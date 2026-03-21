import Foundation

final class TodoFileStore: TodoStore {
    static let shared = TodoFileStore()

    private let defaultFileName = "todo.txt"
    private let providerNameKey = "TodoExternalProviderName"
    private var loadedEntries: [LoadedEntry] = []
    private var cachedExternalURL: URL?
    private var cachedExternalArchiveURL: URL?
    private var hasCachedExternal = false
    private var hasCachedExternalArchive = false

    private init() {}

    /// The display name of the file provider (e.g. "Dropbox", "iCloud Drive")
    /// for the current external file, or nil when using app storage.
    var externalProviderName: String? {
        UserDefaults.standard.string(forKey: providerNameKey)
    }

    enum StoreError: LocalizedError {
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud is unavailable. Enable iCloud Drive for this app in Signing & Capabilities."
            }
        }
    }

    private enum LoadedEntry {
        case task(UUID)
        case raw(String)
    }

    private var internalURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(defaultFileName)
    }

    private var externalURL: URL? {
        if hasCachedExternal {
            return cachedExternalURL
        }
        cachedExternalURL = BookmarkStore.shared.restore()
        hasCachedExternal = true
        return cachedExternalURL
    }

    private var externalArchiveURL: URL? {
        if hasCachedExternalArchive {
            return cachedExternalArchiveURL
        }
        cachedExternalArchiveURL = BookmarkStore.shared.restoreArchive()
        hasCachedExternalArchive = true
        return cachedExternalArchiveURL
    }

    /// Whether the user needs to grant access to a done.txt file.
    /// True when an external todo.txt is set but no archive bookmark exists.
    var needsArchiveBookmark: Bool {
        externalURL != nil && externalArchiveURL == nil && !isICloudURL(effectiveURL())
    }

    func setExternalArchiveURL(_ url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        try? BookmarkStore.shared.saveArchive(url: url)
        cachedExternalArchiveURL = url
        hasCachedExternalArchive = true
    }

    private func isICloudURL(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("ubiquity") || path.contains("iCloud")
    }

    /// Whether the URL points to a location inside the app's own sandbox.
    private func isAppInternalURL(_ url: URL) -> Bool {
        guard let appDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        return url.path.hasPrefix(appDocuments.path)
    }

    func setExternalURL(_ url: URL?) {
        // Read the old done.txt before switching so we can merge it forward.
        let oldArchiveText = readCurrentArchive()

        if let url {
            // The URL from fileImporter is security-scoped. We must access
            // the resource before creating the bookmark so the system can
            // persist the grant.
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            try? BookmarkStore.shared.save(url: url)

            // Try to capture the file provider's display name (e.g. "Dropbox").
            let providerName = (try? url.resourceValues(forKeys: [.ubiquitousItemContainerDisplayNameKey]))?.ubiquitousItemContainerDisplayName
            if let providerName {
                UserDefaults.standard.set(providerName, forKey: providerNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: providerNameKey)
            }
        } else {
            BookmarkStore.shared.clear()
            BookmarkStore.shared.clearArchive()
            UserDefaults.standard.removeObject(forKey: providerNameKey)
        }

        cachedExternalURL = url
        hasCachedExternal = true
        // Clear the archive bookmark — the user will be prompted to pick done.txt
        // for the new location if needed.
        BookmarkStore.shared.clearArchive()
        cachedExternalArchiveURL = nil
        hasCachedExternalArchive = true

        // Merge the old archive into the new location's done.txt.
        if let oldText = oldArchiveText, !oldText.isEmpty {
            mergeArchiveForward(oldText)
        }
    }

    func ensureFileExistsForUI() {
        ensureFileExists()
    }

    func load() throws -> [TodoTask] {
        ensureFileExists()
        let url = effectiveURL()
        let content: String = try withSecurityScope(url: url) {
            try String(contentsOf: url, encoding: .utf8)
        }

        var tasks: [TodoTask] = []
        loadedEntries = []

        for line in content.split(whereSeparator: \.isNewline) {
            let rawLine = String(line)
            if let task = try? TodoParser.parse(line: rawLine) {
                tasks.append(task)
                loadedEntries.append(.task(task.id))
            } else {
                loadedEntries.append(.raw(rawLine))
            }
        }

        return tasks
    }

    func save(_ tasks: [TodoTask]) throws {
        let url = effectiveURL()
        var remainingByID: [UUID: TodoTask] = [:]

        for task in tasks {
            remainingByID[task.id] = task
        }

        var lines: [String] = []
        var newLoadedEntries: [LoadedEntry] = []

        for entry in loadedEntries {
            switch entry {
            case .raw(let line):
                lines.append(line)
                newLoadedEntries.append(.raw(line))
            case .task(let id):
                if let task = remainingByID.removeValue(forKey: id) {
                    lines.append(TodoParser.serialize(task))
                    newLoadedEntries.append(.task(task.id))
                }
            }
        }

        for task in tasks where remainingByID[task.id] != nil {
            lines.append(TodoParser.serialize(task))
            newLoadedEntries.append(.task(task.id))
            remainingByID.removeValue(forKey: task.id)
        }

        let text = lines.joined(separator: "\n").appending("\n")
        let atomic = isAppInternalURL(url)
        try withSecurityScope(url: url) {
            try text.write(to: url, atomically: atomic, encoding: .utf8)
        }
        loadedEntries = newLoadedEntries
    }

    func archive(_ completedTasks: [TodoTask], removing remainingTasks: [TodoTask]) throws {
        guard !completedTasks.isEmpty else { return }

        let todoURL = effectiveURL()
        let archiveURL = archiveURL(relativeTo: todoURL)
        let archiveChunk = completedTasks.map(TodoParser.serialize).joined(separator: "\n").appending("\n")
        let previousArchiveText: String? = try withSecurityScope(url: archiveURL) {
            guard FileManager.default.fileExists(atPath: archiveURL.path) else { return nil }
            return try String(contentsOf: archiveURL, encoding: .utf8)
        }

        let atomicArchive = isAppInternalURL(archiveURL)
        do {
            try withSecurityScope(url: archiveURL) {
                let updatedArchiveText = (previousArchiveText ?? "") + archiveChunk
                try updatedArchiveText.write(to: archiveURL, atomically: atomicArchive, encoding: .utf8)
            }
            try save(remainingTasks)
        } catch {
            try? withSecurityScope(url: archiveURL) {
                if let previousArchiveText {
                    try previousArchiveText.write(to: archiveURL, atomically: atomicArchive, encoding: .utf8)
                } else if FileManager.default.fileExists(atPath: archiveURL.path) {
                    try FileManager.default.removeItem(at: archiveURL)
                }
            }
            throw error
        }
    }

    @discardableResult
    func configureICloudTodoFile() throws -> URL {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw StoreError.iCloudUnavailable
        }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        let todoURL = documentsURL.appendingPathComponent(defaultFileName)
        if !FileManager.default.fileExists(atPath: todoURL.path) {
            try "".write(to: todoURL, atomically: true, encoding: .utf8)
        }

        setExternalURL(todoURL)
        return todoURL
    }

    func fileURL() -> URL {
        effectiveURL()
    }

    private func effectiveURL() -> URL {
        externalURL ?? internalURL
    }

    private func ensureFileExists() {
        // Only create the internal file. Never overwrite an external file —
        // it may appear missing simply because the security scope isn't active yet.
        guard externalURL == nil else { return }
        let url = internalURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    private var internalArchiveURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("done.txt")
    }

    private func archiveURL(relativeTo todoURL: URL) -> URL {
        let path = todoURL.path

        // App-internal files — done.txt lives alongside todo.txt in app storage.
        if let appDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           path.hasPrefix(appDocuments.path) {
            return internalArchiveURL
        }

        // iCloud files — we have directory access.
        if isICloudURL(todoURL) {
            return todoURL.deletingLastPathComponent().appendingPathComponent("done.txt")
        }

        // External files (Dropbox, etc.) — use the user-granted archive bookmark
        // if available, otherwise fall back to app storage.
        if let archiveURL = externalArchiveURL {
            return archiveURL
        }

        return internalArchiveURL
    }

    /// Reads the done.txt that sits next to the *current* effective todo.txt.
    private func readCurrentArchive() -> String? {
        let url = archiveURL(relativeTo: effectiveURL())
        return withSecurityScope(url: url) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Appends old archive text to the done.txt at the *new* effective location.
    /// Avoids duplicating lines that already exist in the destination.
    private func mergeArchiveForward(_ oldText: String) {
        let newTodoURL = effectiveURL()
        let newArchiveURL = archiveURL(relativeTo: newTodoURL)

        let existingText: String? = withSecurityScope(url: newArchiveURL) {
            guard FileManager.default.fileExists(atPath: newArchiveURL.path) else { return nil }
            return try? String(contentsOf: newArchiveURL, encoding: .utf8)
        }

        let existingLines = Set(
            (existingText ?? "").split(whereSeparator: \.isNewline).map(String.init)
        )

        let newLines = oldText.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !existingLines.contains($0) }

        guard !newLines.isEmpty else { return }

        let chunk = newLines.joined(separator: "\n").appending("\n")
        let merged = (existingText ?? "") + chunk

        let atomic = isAppInternalURL(newArchiveURL)
        _ = withSecurityScope(url: newArchiveURL) {
            try? merged.write(to: newArchiveURL, atomically: atomic, encoding: .utf8)
        }
    }
}

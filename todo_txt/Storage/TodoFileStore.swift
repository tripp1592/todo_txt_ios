import Foundation

final class TodoFileStore: TodoStore {
    static let shared = TodoFileStore()

    private let defaultFileName = "todo.txt"
    private var loadedEntries: [LoadedEntry] = []
    private var cachedExternalURL: URL?
    private var hasCachedExternal = false

    private init() {}

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

    func setExternalURL(_ url: URL?) {
        if let url {
            try? BookmarkStore.shared.save(url: url)
        } else {
            BookmarkStore.shared.clear()
        }

        cachedExternalURL = url
        hasCachedExternal = true
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

        loadedEntries = newLoadedEntries

        let text = lines.joined(separator: "\n").appending("\n")
        try withSecurityScope(url: url) {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func appendToArchive(_ tasks: [TodoTask]) throws {
        guard !tasks.isEmpty else { return }

        let archiveURL = effectiveURL()
            .deletingLastPathComponent()
            .appendingPathComponent("done.txt")
        let chunk = tasks.map(TodoParser.serialize).joined(separator: "\n").appending("\n")

        try withSecurityScope(url: archiveURL) {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                let handle = try FileHandle(forWritingTo: archiveURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = chunk.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try chunk.write(to: archiveURL, atomically: true, encoding: .utf8)
            }
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
        let url = effectiveURL()
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        _ = withSecurityScope(url: url) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

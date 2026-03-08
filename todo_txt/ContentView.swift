//  ContentView.swift
//  todo_txt
//  Lightweight todo.txt client (single-file store) with user-chosen path support
//  Updated on 8/11/25.

import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Model
struct TodoTask: Identifiable, Equatable {
    let id: UUID
    var completed: Bool
    var completionDate: Date?
    var priority: Character?
    var creationDate: Date?
    var baseDescription: String // description without +projects/@contexts/extras
    var projects: [String]
    var contexts: [String]
    var extras: [String: String] // key:value metadata

    init(id: UUID = UUID(), completed: Bool, completionDate: Date? = nil,
         priority: Character? = nil, creationDate: Date? = nil,
         baseDescription: String, projects: [String] = [], contexts: [String] = [], extras: [String: String] = [:]) {
        self.id = id
        self.completed = completed
        self.completionDate = completionDate
        self.priority = priority
        self.creationDate = creationDate
        self.baseDescription = baseDescription
        self.projects = projects
        self.contexts = contexts
        self.extras = extras
    }
}

// MARK: - Parser (strict todo.txt rules)
enum TodoParseError: Error, LocalizedError {
    case emptyLine
    case invalidCompletedPrefix
    case invalidDate
    case invalidPriority
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .emptyLine: return "Empty line"
        case .invalidCompletedPrefix: return "Completed tasks must start with 'x '"
        case .invalidDate: return "Invalid YYYY-MM-DD date"
        case .invalidPriority: return "Priority must be (A)-(Z) and appear first"
        case .invalidFormat: return "Line does not match todo.txt strict format"
        }
    }
}

struct TodoParser {
    static let posix: Locale = Locale(identifier: "en_US_POSIX")
    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = posix
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    // Completed:  x <compDate> [<creationDate>] <rest>
    private static let completedRegex = try! NSRegularExpression(
        pattern: "^x (\\d{4}-\\d{2}-\\d{2})(?: (\\d{4}-\\d{2}-\\d{2}))? (.+)$"
    )

    // Incomplete: [(P)] [<creationDate>] <rest>   (priority if present must be first)
    private static let incompleteRegex = try! NSRegularExpression(
        pattern: "^(?:\\(([A-Z])\\) )?(?:(\\d{4}-\\d{2}-\\d{2}) )?(.+)$"
    )

    static func parse(line: String) throws -> TodoTask {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TodoParseError.emptyLine }

        if trimmed.hasPrefix("x ") {
            let m = completedRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count))
            guard let match = m else { throw TodoParseError.invalidCompletedPrefix }

            let compDate = try date(from: trimmed, match: match, at: 1)
            let creationDate = try dateOptional(from: trimmed, match: match, at: 2)
            let rest = substring(trimmed, match.range(at: 3))
            let (base, projects, contexts, extras) = splitRest(rest)
            return TodoTask(completed: true, completionDate: compDate, priority: nil, creationDate: creationDate, baseDescription: base, projects: projects, contexts: contexts, extras: extras)
        } else {
            let m = incompleteRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count))
            guard let match = m else { throw TodoParseError.invalidFormat }

            let priStr = substringOptional(trimmed, match.range(at: 1))
            let priority: Character? = priStr?.first

            let creationDate = try dateOptional(from: trimmed, match: match, at: 2)
            let rest = substring(trimmed, match.range(at: 3))
            let (base, projects, contexts, extras) = splitRest(rest)
            return TodoTask(completed: false, completionDate: nil, priority: priority, creationDate: creationDate, baseDescription: base, projects: projects, contexts: contexts, extras: extras)
        }
    }

    static func serialize(_ task: TodoTask) -> String {
        var parts: [String] = []
        if task.completed {
            parts.append("x")
            parts.append(dateFormatter.string(from: task.completionDate ?? Date()))
            if let cd = task.creationDate { parts.append(dateFormatter.string(from: cd)) }
            parts.append(restString(task))
        } else {
            if let p = task.priority { parts.append("(\(p))") }
            if let cd = task.creationDate { parts.append(dateFormatter.string(from: cd)) }
            parts.append(restString(task))
        }
        return parts.joined(separator: " ")
    }

    static func restString(_ task: TodoTask) -> String {
        var out = task.baseDescription
        if !task.projects.isEmpty { out += " " + task.projects.map { "+\($0)" }.joined(separator: " ") }
        if !task.contexts.isEmpty { out += " " + task.contexts.map { "@\($0)" }.joined(separator: " ") }
        if !task.extras.isEmpty { out += " " + task.extras.sorted { $0.key < $1.key }.map { "\($0):\($1)" }.joined(separator: " ") }
        return out
    }

    private static func splitRest(_ rest: String) -> (String, [String], [String], [String:String]) {
        var baseTokens: [String] = []
        var projects: [String] = []
        var contexts: [String] = []
        var extras: [String:String] = [:]

        for tok in rest.split(separator: " ") {
            if tok.hasPrefix("+") && tok.count > 1 {
                projects.append(String(tok.dropFirst()))
            } else if tok.hasPrefix("@") && tok.count > 1 {
                contexts.append(String(tok.dropFirst()))
            } else if let colon = tok.firstIndex(of: ":"), colon != tok.startIndex, colon != tok.index(before: tok.endIndex) {
                let key = String(tok[..<colon])
                let value = String(tok[tok.index(after: colon)...])
                if !key.isEmpty && !value.isEmpty && !key.contains(":") && !value.contains(":") {
                    extras[key] = value
                } else {
                    baseTokens.append(String(tok))
                }
            } else {
                baseTokens.append(String(tok))
            }
        }
        return (baseTokens.joined(separator: " "), projects, contexts, extras)
    }

    private static func date(from s: String, match: NSTextCheckingResult, at idx: Int) throws -> Date {
        let str = substring(s, match.range(at: idx))
        guard let d = dateFormatter.date(from: str) else { throw TodoParseError.invalidDate }
        return d
    }
    private static func dateOptional(from s: String, match: NSTextCheckingResult, at idx: Int) throws -> Date? {
        let str = substringOptional(s, match.range(at: idx))
        if let str, let d = dateFormatter.date(from: str) { return d }
        if str == nil { return nil }
        throw TodoParseError.invalidDate
    }
    private static func substring(_ s: String, _ range: NSRange) -> String {
        guard let r = Range(range, in: s) else { return "" }
        return String(s[r])
    }
    private static func substringOptional(_ s: String, _ range: NSRange) -> String? {
        if range.location == NSNotFound { return nil }
        guard let r = Range(range, in: s) else { return nil }
        return String(s[r])
    }
}

// MARK: - Security‑scoped bookmark storage
final class BookmarkStore {
    static let shared = BookmarkStore()
    private init() {}
    private let key = "TodoExternalBookmarkData"

    func save(url: URL) throws {
#if os(iOS)
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
#else
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
#endif
        UserDefaults.standard.set(data, forKey: key)
    }

    func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        do {
#if os(iOS)
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
#else
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
#endif
            if stale {
                try? save(url: url)
            }
            return url
        } catch {
            return nil
        }
    }

    func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

@discardableResult
private func withSecurityScope<T>(url: URL, _ body: () throws -> T) rethrows -> T {
    let needsScope = url.startAccessingSecurityScopedResource()
    defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
    return try body()
}

// MARK: - Storage (single file in Documents/todo.txt, or user-chosen external file)
final class TodoFileStore {
    static let shared = TodoFileStore()
    private init() {}

    private let defaultFileName = "todo.txt"
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
    private var loadedEntries: [LoadedEntry] = []
    private var cachedExternalURL: URL?
    private var hasCachedExternal = false

    private var internalURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(defaultFileName)
    }

    private var externalURL: URL? {
        if hasCachedExternal { return cachedExternalURL }
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

    private func effectiveURL() -> URL { externalURL ?? internalURL }

    func ensureFileExists() {
        let url = effectiveURL()
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            _ = withSecurityScope(url: url) {
                try? "".write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func load() throws -> [TodoTask] {
        ensureFileExists()
        let url = effectiveURL()
        let content: String = try withSecurityScope(url: url) {
            try String(contentsOf: url, encoding: .utf8)
        }
        var tasks: [TodoTask] = []
        loadedEntries = []
        for line in content.split(whereSeparator: { $0.isNewline }) {
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
        var remainingById: [UUID: TodoTask] = [:]
        for task in tasks { remainingById[task.id] = task }

        var lines: [String] = []
        var newLoadedEntries: [LoadedEntry] = []
        for entry in loadedEntries {
            switch entry {
            case .raw(let line):
                lines.append(line)
                newLoadedEntries.append(.raw(line))
            case .task(let id):
                if let task = remainingById.removeValue(forKey: id) {
                    let serialized = TodoParser.serialize(task)
                    lines.append(serialized)
                    newLoadedEntries.append(.task(task.id))
                }
            }
        }

        for task in tasks where remainingById[task.id] != nil {
            let serialized = TodoParser.serialize(task)
            lines.append(serialized)
            newLoadedEntries.append(.task(task.id))
            remainingById.removeValue(forKey: task.id)
        }

        loadedEntries = newLoadedEntries

        let text = lines.joined(separator: "\n").appending("\n")
        try withSecurityScope(url: url) {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func appendToArchive(_ tasks: [TodoTask]) throws {
        guard !tasks.isEmpty else { return }
        let archiveURL = effectiveURL().deletingLastPathComponent().appendingPathComponent("done.txt")
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

    func fileURL() -> URL { effectiveURL() }
}

// MARK: - ViewModel
@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = []
    @Published var filter: Filter = .open
    @Published var sort: Sort = .priority
    @Published var lastError: String?

    enum Filter: String, CaseIterable, Identifiable { case open, done, all; var id: String { rawValue } }
    enum Sort: String, CaseIterable, Identifiable {
        case priority
        case newestDate
        case text
        var id: String { rawValue }
    }

    init() { load() }

    func load() {
        do { tasks = try TodoFileStore.shared.load() } catch { tasks = [] }
    }

    private func save() {
        do {
            try TodoFileStore.shared.save(tasks)
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }

    /// Returns an error message on failure, nil on success.
    func add(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do {
            let task = try TodoParser.parse(line: text)
            tasks.append(task)
            save()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        save()
    }

    func deleteVisible(at offsets: IndexSet) {
        let visible = visibleTasks
        let idsToDelete: Set<UUID> = Set(offsets.compactMap { index in
            guard visible.indices.contains(index) else { return nil }
            return visible[index].id
        })
        tasks.removeAll { idsToDelete.contains($0.id) }
        save()
    }

    func deleteTask(_ task: TodoTask) {
        if let idx = tasks.firstIndex(of: task) {
            tasks.remove(at: idx)
            save()
        }
    }

    @discardableResult
    func toggle(_ task: TodoTask) -> Bool {
        guard let idx = tasks.firstIndex(of: task) else { return false }
        var t = tasks[idx]
        var justCompleted = false
        if t.completed {
            t.completed = false
            t.completionDate = nil
        } else {
            t.completed = true
            t.completionDate = Date()
            t.priority = nil
            justCompleted = true
        }
        tasks[idx] = t
        save()
        return justCompleted
    }

    func setExternalURL(_ url: URL) {
        TodoFileStore.shared.setExternalURL(url)
        load()
    }

    func clearExternalURL() {
        TodoFileStore.shared.setExternalURL(nil)
        load()
    }

    func enableICloudSync() throws {
        _ = try TodoFileStore.shared.configureICloudTodoFile()
        load()
    }

    func seedStarterTasksIfNeeded() {
        guard tasks.isEmpty else { return }
        let now = Date()
        let today = TodoParser.dateFormatter.string(from: now)
        let yesterday = TodoParser.dateFormatter.string(
            from: Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: now) ?? now
        )
        let samples = [
            "(B) \(today) Review your priorities +planning",
            "Capture one quick task +inbox @phone",
            "x \(today) \(yesterday) Archive old note +cleanup"
        ]

        var seeded: [TodoTask] = []
        for line in samples {
            if let task = try? TodoParser.parse(line: line) {
                seeded.append(task)
            }
        }
        guard !seeded.isEmpty else { return }
        tasks.append(contentsOf: seeded)
        save()
    }

    func update(_ task: TodoTask, with rawLine: String) -> Bool {
        guard let idx = tasks.firstIndex(of: task) else { return false }
        guard let parsed = try? TodoParser.parse(line: rawLine) else { return false }
        let updated = TodoTask(
            id: task.id,
            completed: parsed.completed,
            completionDate: parsed.completionDate,
            priority: parsed.priority,
            creationDate: parsed.creationDate,
            baseDescription: parsed.baseDescription,
            projects: parsed.projects,
            contexts: parsed.contexts,
            extras: parsed.extras
        )
        tasks[idx] = updated
        save()
        return true
    }

    @discardableResult
    func archiveCompleted() -> Int {
        let completed = tasks.filter { $0.completed }
        guard !completed.isEmpty else { return 0 }
        do {
            try TodoFileStore.shared.appendToArchive(completed)
            tasks.removeAll { $0.completed }
            save()
            return completed.count
        } catch {
            lastError = "Failed to archive: \(error.localizedDescription)"
            return 0
        }
    }

    var visibleTasks: [TodoTask] {
        let filtered: [TodoTask]
        switch filter {
        case .open: filtered = tasks.filter { !$0.completed }
        case .done: filtered = tasks.filter { $0.completed }
        case .all: filtered = tasks
        }

        switch sort {
        case .priority:
            return filtered.sorted { lhs, rhs in
                if lhs.completed != rhs.completed { return !lhs.completed }
                let leftPriority = lhs.priority.map { Int($0.asciiValue ?? 91) } ?? 999
                let rightPriority = rhs.priority.map { Int($0.asciiValue ?? 91) } ?? 999
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                return TodoParser.restString(lhs).localizedCaseInsensitiveCompare(TodoParser.restString(rhs)) == .orderedAscending
            }
        case .newestDate:
            return filtered.sorted { lhs, rhs in
                let leftDate = lhs.completionDate ?? lhs.creationDate ?? Date.distantPast
                let rightDate = rhs.completionDate ?? rhs.creationDate ?? Date.distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return TodoParser.restString(lhs).localizedCaseInsensitiveCompare(TodoParser.restString(rhs)) == .orderedAscending
            }
        case .text:
            return filtered.sorted {
                TodoParser.restString($0).localizedCaseInsensitiveCompare(TodoParser.restString($1)) == .orderedAscending
            }
        }
    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var vm = TodoListViewModel()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("defaultPriority") private var defaultPriorityRaw = ""
    @AppStorage("autoArchiveOnComplete") private var autoArchiveOnComplete = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var newLine: String = ""
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var openImporterAfterOnboarding = false
    @State private var didRunInitialSetup = false
    @State private var alertText: String?
    @State private var editingTask: TodoTask?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $vm.filter) {
                    Text("Open").tag(TodoListViewModel.Filter.open)
                    Text("Done").tag(TodoListViewModel.Filter.done)
                    Text("All").tag(TodoListViewModel.Filter.all)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

                HStack {
                    Text("Sort")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Sort", selection: $vm.sort) {
                        Text("Priority").tag(TodoListViewModel.Sort.priority)
                        Text("Newest").tag(TodoListViewModel.Sort.newestDate)
                        Text("Text").tag(TodoListViewModel.Sort.text)
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                HStack(spacing: 10) {
                    Text("Done")
                        .frame(width: 44, alignment: .leading)
                    Text("Pri")
                        .frame(width: 34, alignment: .leading)
                    Text("Task")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Date")
                        .frame(width: 92, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))

                List {
                    ForEach(vm.visibleTasks) { task in
                        HStack(spacing: 10) {
                            Button(action: { handleToggle(task) }) {
                                Image(systemName: task.completed ? "checkmark.square.fill" : "square")
                                    .frame(width: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .tint(task.completed ? .green : .secondary)

                            Text(priorityLabel(for: task))
                                .frame(width: 34, alignment: .leading)
                                .foregroundStyle(.secondary)

                            Text(TodoParser.restString(task))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(task.completed ? .secondary : .primary)

                            Text(dateLabel(for: task))
                                .frame(width: 92, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                        .font(.body.monospaced())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.deleteTask(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingTask = task
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                editingTask = task
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                vm.deleteTask(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: vm.deleteVisible)
                }
                .listStyle(.plain)

                HStack(spacing: 10) {
                    TextField("(A) 2025-08-11 Your task +Project @context due:2025-09-01", text: $newLine)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.body.monospaced())
                        .onSubmit(commitNew)

                    Button(action: { commitNew() }) {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .font(.title3.weight(.bold))
                    }
                    .accessibilityLabel("Add task")
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Text("File: \(TodoFileStore.shared.fileURL().lastPathComponent) • \(vm.visibleTasks.count) / \(vm.tasks.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showImporter = true } label: {
                        Label("Choose File", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: TodoFileStore.shared.fileURL()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                EditTaskSheet(
                    task: task,
                    onSave: { newRaw in
                        if vm.update(task, with: newRaw) { return nil }
                        return "Invalid todo.txt line. Check priority/date/order."
                    },
                    onDismiss: { editingTask = nil }
                )
            }
            .sheet(isPresented: $showOnboarding) {
                FirstLaunchSheet(
                    onUseLocal: {
                        vm.clearExternalURL()
                        vm.seedStarterTasksIfNeeded()
                        hasSeenOnboarding = true
                        showOnboarding = false
                    },
                    onImportExistingFile: {
                        openImporterAfterOnboarding = true
                        hasSeenOnboarding = true
                        showOnboarding = false
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    currentFileName: TodoFileStore.shared.fileURL().lastPathComponent,
                    onChooseFile: {
                        iCloudSyncEnabled = false
                        showSettings = false
                        showImporter = true
                    },
                    onUseLocalFile: {
                        iCloudSyncEnabled = false
                        vm.clearExternalURL()
                        showSettings = false
                    },
                    onArchiveNow: {
                        archiveNow()
                    },
                    onICloudSyncChanged: { enabled in
                        setICloudSync(enabled)
                    }
                )
            }
        }
        .onAppear { runInitialSetupIfNeeded() }
        .onChange(of: showOnboarding) { _, isShowing in
            guard !isShowing, openImporterAfterOnboarding else { return }
            openImporterAfterOnboarding = false
            showImporter = true
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.plainText],
            allowsMultipleSelection: false
        ) { (result: Result<[URL], Error>) in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.pathExtension.lowercased() == "txt" else {
                    alertText = "Please choose a .txt file."
                    return
                }
                iCloudSyncEnabled = false
                vm.setExternalURL(url)
            case .failure(let error):
                alertText = error.localizedDescription
            }
        }
        .alert("Notice", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
        .alert("Error", isPresented: Binding(get: { vm.lastError != nil }, set: { if !$0 { vm.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.lastError ?? "")
        }
    }

    private func priorityLabel(for task: TodoTask) -> String {
        if let priority = task.priority {
            return String(priority)
        }
        return "-"
    }

    private func dateLabel(for task: TodoTask) -> String {
        if task.completed, let completionDate = task.completionDate {
            return relativeDateLabel(for: completionDate)
        }
        if let creationDate = task.creationDate {
            return relativeDateLabel(for: creationDate)
        }
        return "-"
    }

    private func runInitialSetupIfNeeded() {
        guard !didRunInitialSetup else { return }
        didRunInitialSetup = true
        if iCloudSyncEnabled {
            setICloudSync(true)
        } else {
            TodoFileStore.shared.ensureFileExists()
        }
        if !hasSeenOnboarding {
            showOnboarding = true
        }
    }

    private func relativeDateLabel(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: targetDay, to: today).day ?? 0

        if dayDiff == 0 { return "today" }
        if dayDiff == 1 { return "1 day ago" }
        if dayDiff > 1 && dayDiff < 30 { return "\(dayDiff) days ago" }
        if dayDiff >= 30 && dayDiff < 365 {
            let months = dayDiff / 30
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        return TodoParser.dateFormatter.string(from: date)
    }

    private func handleToggle(_ task: TodoTask) {
        let justCompleted = vm.toggle(task)
        if autoArchiveOnComplete && justCompleted {
            _ = vm.archiveCompleted()
        }
    }

    private func archiveNow() {
        let count = vm.archiveCompleted()
        if count > 0 {
            alertText = "Archived \(count) completed task\(count == 1 ? "" : "s") to done.txt."
        } else if vm.lastError == nil {
            alertText = "No completed tasks to archive."
        }
    }

    private func setICloudSync(_ enabled: Bool) {
        if enabled {
            do {
                try vm.enableICloudSync()
                iCloudSyncEnabled = true
            } catch {
                iCloudSyncEnabled = false
                alertText = error.localizedDescription
            }
        } else {
            iCloudSyncEnabled = false
            vm.clearExternalURL()
        }
    }

    private func commitNew() {
        let line = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let lineToAdd = lineWithDefaultPriorityIfNeeded(line)
        if let errorMsg = vm.add(lineToAdd) {
            alertText = errorMsg
        } else {
            newLine = ""
        }
    }

    private func lineWithDefaultPriorityIfNeeded(_ line: String) -> String {
        guard let parsed = try? TodoParser.parse(line: line) else { return line }
        guard !parsed.completed, parsed.priority == nil else { return line }
        guard defaultPriorityRaw.count == 1 else { return line }
        return "(\(defaultPriorityRaw)) \(line)"
    }
}

struct SettingsSheet: View {
    @AppStorage("defaultPriority") private var defaultPriorityRaw = ""
    @AppStorage("autoArchiveOnComplete") private var autoArchiveOnComplete = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    let currentFileName: String
    let onChooseFile: () -> Void
    let onUseLocalFile: () -> Void
    let onArchiveNow: () -> Void
    let onICloudSyncChanged: (Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    LabeledContent("Current", value: currentFileName)
                    Toggle("Sync with iCloud Drive", isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) { _, enabled in
                            onICloudSyncChanged(enabled)
                        }
                    Button("Choose .txt File", action: onChooseFile)
                    Button("Use App Documents/todo.txt", action: onUseLocalFile)
                }
                Section("Tasks") {
                    Picker("Default Priority", selection: $defaultPriorityRaw) {
                        Text("None").tag("")
                        ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), id: \.self) { priority in
                            Text(String(priority)).tag(String(priority))
                        }
                    }
                    Toggle("Auto Archive Completed", isOn: $autoArchiveOnComplete)
                    Button("Archive Now", action: onArchiveNow)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FirstLaunchSheet: View {
    let onUseLocal: () -> Void
    let onImportExistingFile: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how to start")
                    .font(.headline)
                Text("You can start with a local `todo.txt` in this app, or import your existing file.")
                    .foregroundStyle(.secondary)
                Button(action: onUseLocal) {
                    Label("Start with local todo.txt", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onImportExistingFile) {
                    Label("Import existing .txt file", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct EditTaskSheet: View {
    private enum DateField: Identifiable {
        case due
        case threshold

        var id: String {
            switch self {
            case .due: return "due"
            case .threshold: return "threshold"
            }
        }
    }

    let task: TodoTask
    /// Return nil on success, or an error message string to display
    let onSave: (String) -> String?
    let onDismiss: () -> Void

    @State private var priorityRaw: String = ""
    @State private var taskText: String = ""
    @State private var dueDateText: String = ""
    @State private var thresholdDateText: String = ""
    @State private var activeDateField: DateField?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task", text: $taskText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priorityRaw) {
                        Text("None").tag("")
                        ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), id: \.self) { priority in
                            Text(String(priority)).tag(String(priority))
                        }
                    }
                }
                Section("Dates") {
                    Button {
                        activeDateField = .due
                    } label: {
                        LabeledContent("Due", value: dueDateText.isEmpty ? "Not set" : dueDateText)
                    }
                    .foregroundStyle(.primary)

                    Button {
                        activeDateField = .threshold
                    } label: {
                        LabeledContent("Threshold", value: thresholdDateText.isEmpty ? "Not set" : thresholdDateText)
                    }
                    .foregroundStyle(.primary)
                }
                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let msg = validateDates() {
                            error = msg
                            return
                        }
                        let rawLine = composedRawLine()
                        if let msg = onSave(rawLine) {
                            error = msg
                        } else {
                            onDismiss()
                        }
                    }
                }
            }
            .onAppear {
                if taskText.isEmpty {
                    taskText = task.baseDescription
                    priorityRaw = task.priority.map(String.init) ?? ""
                    dueDateText = task.extras["due"] ?? ""
                    thresholdDateText = task.extras["t"] ?? ""
                }
            }
            .sheet(item: $activeDateField) { field in
                switch field {
                case .due:
                    DateSelectionSheet(
                        title: "Due Date",
                        initialDateText: dueDateText,
                        onSave: { selected in
                            dueDateText = selected
                        },
                        onClear: {
                            dueDateText = ""
                        }
                    )
                case .threshold:
                    DateSelectionSheet(
                        title: "Threshold Date",
                        initialDateText: thresholdDateText,
                        onSave: { selected in
                            thresholdDateText = selected
                        },
                        onClear: {
                            thresholdDateText = ""
                        }
                    )
                }
            }
        }
    }

    private func validateDates() -> String? {
        let due = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let threshold = thresholdDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !due.isEmpty && TodoParser.dateFormatter.date(from: due) == nil {
            return "Due date must use YYYY-MM-DD."
        }
        if !threshold.isEmpty && TodoParser.dateFormatter.date(from: threshold) == nil {
            return "Threshold date must use YYYY-MM-DD."
        }
        return nil
    }

    private func composedRawLine() -> String {
        let desc = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []

        if task.completed {
            parts.append("x")
            parts.append(TodoParser.dateFormatter.string(from: task.completionDate ?? Date()))
            if let creationDate = task.creationDate {
                parts.append(TodoParser.dateFormatter.string(from: creationDate))
            }
        } else {
            if priorityRaw.count == 1 {
                parts.append("(\(priorityRaw))")
            }
            if let creationDate = task.creationDate {
                parts.append(TodoParser.dateFormatter.string(from: creationDate))
            }
        }

        var bodyTokens: [String] = []
        if !desc.isEmpty {
            bodyTokens.append(desc)
        }
        bodyTokens.append(contentsOf: task.projects.map { "+\($0)" })
        bodyTokens.append(contentsOf: task.contexts.map { "@\($0)" })

        var extras = task.extras
        extras.removeValue(forKey: "due")
        extras.removeValue(forKey: "t")

        let due = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let threshold = thresholdDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !due.isEmpty { extras["due"] = due }
        if !threshold.isEmpty { extras["t"] = threshold }

        bodyTokens.append(contentsOf: extras.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })
        parts.append(bodyTokens.joined(separator: " "))
        return parts.joined(separator: " ")
    }
}

struct DateSelectionSheet: View {
    let title: String
    let initialDateText: String
    let onSave: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        onClear()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(TodoParser.dateFormatter.string(from: selectedDate))
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let parsed = TodoParser.dateFormatter.date(from: initialDateText) {
                    selectedDate = parsed
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

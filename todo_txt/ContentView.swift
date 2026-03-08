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

    func fileURL() -> URL { effectiveURL() }
}

// MARK: - ViewModel
@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = []
    @Published var filter: Filter = .open
    @Published var lastError: String?

    enum Filter: String, CaseIterable, Identifiable { case open, done, all; var id: String { rawValue } }

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

    func toggle(_ task: TodoTask) {
        guard let idx = tasks.firstIndex(of: task) else { return }
        var t = tasks[idx]
        if t.completed {
            t.completed = false
            t.completionDate = nil
        } else {
            t.completed = true
            t.completionDate = Date()
            t.priority = nil
        }
        tasks[idx] = t
        save()
    }

    func setExternalURL(_ url: URL) {
        TodoFileStore.shared.setExternalURL(url)
        load()
    }

    func clearExternalURL() {
        TodoFileStore.shared.setExternalURL(nil)
        load()
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

    var visibleTasks: [TodoTask] {
        switch filter {
        case .open: return tasks.filter { !$0.completed }
        case .done: return tasks.filter { $0.completed }
        case .all: return tasks
        }
    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var vm = TodoListViewModel()
    @State private var newLine: String = ""
    @State private var showImporter = false
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
                .padding(.bottom, 10)

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
                            Button(action: { vm.toggle(task) }) {
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
                    Menu {
                        Button("Use App Documents/todo.txt") { vm.clearExternalURL() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                EditTaskSheet(
                    task: task,
                    initialText: TodoParser.serialize(task),
                    onSave: { newRaw in
                        if vm.update(task, with: newRaw) { return nil }
                        return "Invalid todo.txt line. Check priority/date/order."
                    },
                    onDismiss: { editingTask = nil }
                )
            }
        }
        .onAppear { TodoFileStore.shared.ensureFileExists() }
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
            return TodoParser.dateFormatter.string(from: completionDate)
        }
        if let creationDate = task.creationDate {
            return TodoParser.dateFormatter.string(from: creationDate)
        }
        return "-"
    }

    private func commitNew() {
        let line = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if let errorMsg = vm.add(line) {
            alertText = errorMsg
        } else {
            newLine = ""
        }
    }
}

struct EditTaskSheet: View {
    let task: TodoTask
    let initialText: String
    /// Return nil on success, or an error message string to display
    let onSave: (String) -> String?
    let onDismiss: () -> Void

    @State private var text: String = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit raw todo.txt line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.body.monospaced())
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            error = "Line cannot be empty."
                        } else if let msg = onSave(trimmed) {
                            error = msg
                        } else {
                            onDismiss()
                        }
                    }
                }
            }
            .onAppear { if text.isEmpty { text = initialText } }
        }
    }
}

#Preview {
    ContentView()
}

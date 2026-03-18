import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = [] {
        didSet { updateVisibleTasks() }
    }
    
    @Published var filter: Filter = .all {
        didSet { updateVisibleTasks() }
    }
    
    @Published var sort: Sort = .priority {
        didSet { updateVisibleTasks() }
    }
    
    @Published var grouping: Grouping = .none {
        didSet { updateVisibleTasks() }
    }
    
    @Published var lastError: String?
    
    // Using a @Published property prevents sorting and string allocation
    // on every single SwiftUI view render.
    @Published private(set) var visibleTasks: [TodoTask] = []
    @Published private(set) var groupedTasks: [(key: String, tasks: [TodoTask])] = []

    enum Filter: String, CaseIterable, Identifiable {
        case open
        case done
        case all

        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case priority
        case dueDate

        var id: String { rawValue }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case none
        case priority
        case dueDate

        var id: String { rawValue }
    }

    private let store: TodoStore

    init(store: TodoStore = TodoFileStore.shared) {
        self.store = store
        load()
    }

    func load() {
        do {
            tasks = try store.load()
            lastError = nil
            updateBadgeCount()
        } catch {
            lastError = "Failed to load: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try store.save(tasks)
            lastError = nil
            return true
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func commit(_ newTasks: [TodoTask]) -> Bool {
        let previousTasks = tasks
        tasks = newTasks

        guard save() else {
            tasks = previousTasks
            return false
        }

        updateBadgeCount()
        return true
    }

    func add(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        do {
            let task = try TodoParser.parse(line: text)
            var newTasks = tasks
            newTasks.append(task)
            _ = commit(newTasks)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        var newTasks = tasks
        newTasks.remove(atOffsets: offsets)
        _ = commit(newTasks)
    }

    func deleteVisible(at offsets: IndexSet) {
        let visible = visibleTasks
        let idsToDelete: Set<UUID> = Set(offsets.compactMap { index in
            guard visible.indices.contains(index) else { return nil }
            return visible[index].id
        })

        let newTasks = tasks.filter { !idsToDelete.contains($0.id) }
        _ = commit(newTasks)
    }

    func deleteTask(_ task: TodoTask) {
        if let index = tasks.firstIndex(of: task) {
            var newTasks = tasks
            newTasks.remove(at: index)
            _ = commit(newTasks)
        }
    }

    @discardableResult
    func toggle(_ task: TodoTask) -> Bool {
        guard let index = tasks.firstIndex(of: task) else { return false }

        var updatedTask = tasks[index]
        var justCompleted = false

        if updatedTask.completed {
            updatedTask.completed = false
            updatedTask.completionDate = nil
        } else {
            updatedTask.completed = true
            updatedTask.completionDate = Date()
            updatedTask.priority = nil
            justCompleted = true
        }

        var newTasks = tasks
        newTasks[index] = updatedTask
        guard commit(newTasks) else { return false }
        return justCompleted
    }

    func setExternalURL(_ url: URL) {
        store.setExternalURL(url)
        load()
    }

    func clearExternalURL() {
        store.setExternalURL(nil)
        load()
    }

    func enableICloudSync() throws {
        _ = try store.configureICloudTodoFile()
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

        let seededTasks = samples.compactMap { try? TodoParser.parse(line: $0) }
        guard !seededTasks.isEmpty else { return }

        var newTasks = tasks
        newTasks.append(contentsOf: seededTasks)
        _ = commit(newTasks)
    }

    func update(_ task: TodoTask, with rawLine: String) -> Bool {
        guard let index = tasks.firstIndex(of: task) else { return false }
        guard let parsed = try? TodoParser.parse(line: rawLine) else { return false }

        var newTasks = tasks
        newTasks[index] = TodoTask(
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
        return commit(newTasks)
    }

    @discardableResult
    func archiveCompleted() -> Int {
        let completedTasks = tasks.filter(\.completed)
        guard !completedTasks.isEmpty else { return 0 }
        let remainingTasks = tasks.filter { !$0.completed }

        do {
            try store.archive(completedTasks, removing: remainingTasks)
            tasks = remainingTasks
            lastError = nil
            updateBadgeCount()
            return completedTasks.count
        } catch {
            lastError = "Failed to archive: \(error.localizedDescription)"
            return 0
        }
    }

    private func updateVisibleTasks() {
        let filteredTasks: [TodoTask]

        switch filter {
        case .open:
            filteredTasks = tasks.filter { !$0.completed }
        case .done:
            filteredTasks = tasks.filter(\.completed)
        case .all:
            filteredTasks = tasks
        }

        switch sort {
        case .priority:
            visibleTasks = filteredTasks.sorted { lhs, rhs in
                if lhs.completed != rhs.completed {
                    return !lhs.completed
                }
                let leftPriority = lhs.priority.map { Int($0.asciiValue ?? 91) } ?? 999
                let rightPriority = rhs.priority.map { Int($0.asciiValue ?? 91) } ?? 999
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return TodoParser.restString(lhs)
                    .localizedCaseInsensitiveCompare(TodoParser.restString(rhs)) == .orderedAscending
            }
        case .dueDate:
            visibleTasks = filteredTasks.sorted { lhs, rhs in
                let leftDue = lhs.extras["due"].flatMap { TodoParser.dateFormatter.date(from: $0) }
                let rightDue = rhs.extras["due"].flatMap { TodoParser.dateFormatter.date(from: $0) }
                switch (leftDue, rightDue) {
                case let (l?, r?) where l != r:
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return TodoParser.restString(lhs)
                        .localizedCaseInsensitiveCompare(TodoParser.restString(rhs)) == .orderedAscending
                }
            }
        }

        updateGroupedTasks()
    }

    private func updateGroupedTasks() {
        switch grouping {
        case .none:
            groupedTasks = []
        case .priority:
            var buckets: [String: [TodoTask]] = [:]
            for task in visibleTasks {
                let key: String
                if task.completed {
                    key = "Completed"
                } else if let p = task.priority {
                    key = "(\(p))"
                } else {
                    key = "No Priority"
                }
                buckets[key, default: []].append(task)
            }
            let order = ["(A)", "(B)", "(C)", "(D)", "(E)", "No Priority", "Completed"]
            let known = Set(order)
            var result = order.compactMap { key in
                buckets[key].map { (key: key, tasks: $0) }
            }
            // Append any F-Z priorities that may exist
            let extras = buckets.keys
                .filter { !known.contains($0) }
                .sorted()
            for key in extras {
                if let tasks = buckets[key] {
                    result.insert((key: key, tasks: tasks), at: result.count - (buckets["Completed"] != nil ? 1 : 0))
                }
            }
            groupedTasks = result
        case .dueDate:
            var buckets: [String: [TodoTask]] = [:]
            for task in visibleTasks {
                let key: String
                if let due = task.extras["due"], !due.isEmpty {
                    key = due
                } else {
                    key = "No Due Date"
                }
                buckets[key, default: []].append(task)
            }
            let sortedKeys = buckets.keys.sorted { lhs, rhs in
                if lhs == "No Due Date" { return false }
                if rhs == "No Due Date" { return true }
                return lhs < rhs
            }
            groupedTasks = sortedKeys.compactMap { key in
                buckets[key].map { (key: key, tasks: $0) }
            }
        }
    }

    var allProjects: [String] {
        Array(Set(tasks.flatMap(\.projects))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var allContexts: [String] {
        Array(Set(tasks.flatMap(\.contexts))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func updateBadgeCount() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let todayStart = calendar.startOfDay(for: Date())

        let count = tasks.filter { task in
            guard !task.completed,
                  let dueString = task.extras["due"],
                  let dueDate = TodoParser.dateFormatter.date(from: dueString)
            else { return false }
            return dueDate <= todayStart
        }.count

        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}

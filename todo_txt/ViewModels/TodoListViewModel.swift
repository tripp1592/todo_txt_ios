import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = []
    @Published var filter: Filter = .all
    @Published var sort: Sort = .priority
    @Published var lastError: String?

    enum Filter: String, CaseIterable, Identifiable {
        case open
        case done
        case all

        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case priority
        case newestDate
        case text

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

    var visibleTasks: [TodoTask] {
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
            return filteredTasks.sorted { lhs, rhs in
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
        case .newestDate:
            return filteredTasks.sorted { lhs, rhs in
                let leftDate = lhs.completionDate ?? lhs.creationDate ?? .distantPast
                let rightDate = rhs.completionDate ?? rhs.creationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return TodoParser.restString(lhs)
                    .localizedCaseInsensitiveCompare(TodoParser.restString(rhs)) == .orderedAscending
            }
        case .text:
            return filteredTasks.sorted {
                TodoParser.restString($0)
                    .localizedCaseInsensitiveCompare(TodoParser.restString($1)) == .orderedAscending
            }
        }
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

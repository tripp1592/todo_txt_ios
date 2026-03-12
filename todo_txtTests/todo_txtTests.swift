//
//  todo_txtTests.swift
//  todo_txtTests
//
//  Created by Tripp Moore on 8/11/25.
//

import Foundation
import Testing
@testable import todo_txt

@Suite(.serialized)
struct todo_txtTests {

    @Test
    @MainActor
    func deleteVisibleRemovesCorrectFilteredTask() throws {
        let fileURL = try makeTempTodoFile(contents: """
        (A) 2026-03-01 first open
        x 2026-03-02 2026-03-01 finished task
        (B) 2026-03-03 second open
        """)
        defer { cleanupTempFile(at: fileURL) }

        let vm = TodoListViewModel()
        vm.setExternalURL(fileURL)
        vm.filter = .open

        #expect(vm.visibleTasks.count == 2)
        vm.deleteVisible(at: IndexSet(integer: 0))

        #expect(vm.tasks.count == 2)
        #expect(vm.tasks.contains(where: { $0.baseDescription == "finished task" && $0.completed }))
        #expect(vm.tasks.contains(where: { $0.baseDescription == "second open" && !$0.completed }))
    }

    @Test
    func savePreservesUnparseableLines() throws {
        let fileURL = try makeTempTodoFile(contents: """
        (A) 2026-03-01 valid task
        x 2026-03-02
        """)
        defer { cleanupTempFile(at: fileURL) }

        let store = TodoFileStore.shared
        store.setExternalURL(fileURL)
        defer { store.setExternalURL(nil) }

        var tasks = try store.load()
        #expect(tasks.count == 1)
        tasks.append(try TodoParser.parse(line: "(B) 2026-03-03 new task"))
        try store.save(tasks)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("x 2026-03-02"))
        #expect(content.contains("(B) 2026-03-03 new task"))
    }

    @Test
    @MainActor
    func archiveCompletedRestoresTasksWhenSaveFails() throws {
        let fileURL = try makeTempTodoFile(contents: """
        x 2026-03-02 2026-03-01 finished task +Archive
        (A) 2026-03-03 keep open
        """)
        defer { cleanupTempFile(at: fileURL) }

        let vm = TodoListViewModel()
        vm.setExternalURL(fileURL)
        #expect(vm.tasks.count == 2)

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        let archivedCount = vm.archiveCompleted()

        #expect(archivedCount == 0)
        #expect(vm.lastError != nil)
        #expect(vm.tasks.count == 2)
        #expect(vm.tasks.contains(where: { $0.baseDescription == "finished task" && $0.completed }))

        let doneURL = fileURL.deletingLastPathComponent().appendingPathComponent("done.txt")
        #expect(!FileManager.default.fileExists(atPath: doneURL.path))
    }

    @Test
    @MainActor
    func addRollsBackTasksWhenSaveFails() throws {
        let fileURL = try makeTempTodoFile(contents: """
        (A) 2026-03-01 keep task
        """)
        defer { cleanupTempFile(at: fileURL) }

        let vm = TodoListViewModel()
        vm.setExternalURL(fileURL)
        #expect(vm.tasks.count == 1)

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        let parseError = vm.add("(B) 2026-03-02 should not persist")

        #expect(parseError == nil)
        #expect(vm.lastError != nil)
        #expect(vm.tasks.count == 1)
        #expect(vm.tasks.contains(where: { $0.baseDescription == "keep task" }))
    }

    @Test
    @MainActor
    func loadFailurePreservesExistingTasksAndSetsError() throws {
        let fileURL = try makeTempTodoFile(contents: """
        (A) 2026-03-01 keep task
        """)
        defer { cleanupTempFile(at: fileURL) }

        let vm = TodoListViewModel()
        vm.setExternalURL(fileURL)
        #expect(vm.tasks.count == 1)

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        vm.load()

        #expect(vm.lastError != nil)
        #expect(vm.tasks.count == 1)
        #expect(vm.tasks.first?.baseDescription == "keep task")
    }

    // MARK: - Parser tests

    @Test
    func parseSimpleIncompleteTask() throws {
        let task = try TodoParser.parse(line: "Buy milk")
        #expect(!task.completed)
        #expect(task.priority == nil)
        #expect(task.creationDate == nil)
        #expect(task.baseDescription == "Buy milk")
    }

    @Test
    func parseIncompleteWithPriority() throws {
        let task = try TodoParser.parse(line: "(A) Buy milk")
        #expect(!task.completed)
        #expect(task.priority == "A")
        #expect(task.baseDescription == "Buy milk")
    }

    @Test
    func parseIncompleteWithPriorityAndDate() throws {
        let task = try TodoParser.parse(line: "(B) 2026-03-01 Buy milk")
        #expect(!task.completed)
        #expect(task.priority == "B")
        #expect(task.creationDate != nil)
        #expect(task.baseDescription == "Buy milk")
    }

    @Test
    func parseIncompleteWithDateOnly() throws {
        let task = try TodoParser.parse(line: "2026-03-01 Buy milk")
        #expect(!task.completed)
        #expect(task.priority == nil)
        #expect(task.creationDate != nil)
        #expect(task.baseDescription == "Buy milk")
    }

    @Test
    func parseCompletedTask() throws {
        let task = try TodoParser.parse(line: "x 2026-03-02 2026-03-01 Buy milk")
        #expect(task.completed)
        #expect(task.completionDate != nil)
        #expect(task.creationDate != nil)
        #expect(task.priority == nil)
        #expect(task.baseDescription == "Buy milk")
    }

    @Test
    func parseCompletedWithoutCreationDate() throws {
        let task = try TodoParser.parse(line: "x 2026-03-02 Buy milk")
        #expect(task.completed)
        #expect(task.completionDate != nil)
        #expect(task.creationDate == nil)
        #expect(task.baseDescription == "Buy milk")
    }

    @Test
    func parseProjectsAndContexts() throws {
        let task = try TodoParser.parse(line: "Buy milk +Groceries @Store")
        #expect(task.baseDescription == "Buy milk")
        #expect(task.projects == ["Groceries"])
        #expect(task.contexts == ["Store"])
    }

    @Test
    func parseMultipleProjectsAndContexts() throws {
        let task = try TodoParser.parse(line: "Deploy app +Backend +Frontend @Work @Server")
        #expect(task.projects == ["Backend", "Frontend"])
        #expect(task.contexts == ["Work", "Server"])
    }

    @Test
    func parseExtras() throws {
        let task = try TodoParser.parse(line: "Buy milk due:2026-04-01 tag:urgent")
        #expect(task.extras["due"] == "2026-04-01")
        #expect(task.extras["tag"] == "urgent")
    }

    @Test
    func parseEmptyLineThrows() {
        #expect(throws: TodoParseError.emptyLine) {
            try TodoParser.parse(line: "")
        }
    }

    @Test
    func parseWhitespaceOnlyThrows() {
        #expect(throws: TodoParseError.emptyLine) {
            try TodoParser.parse(line: "   ")
        }
    }

    @Test
    func parseCompletedWithoutDateThrows() {
        #expect(throws: TodoParseError.invalidCompletedPrefix) {
            try TodoParser.parse(line: "x missing date")
        }
    }

    @Test
    func parseBareAtOrPlusNotTreatedAsTag() throws {
        let task = try TodoParser.parse(line: "Email @ home + work")
        #expect(task.projects.isEmpty)
        #expect(task.contexts.isEmpty)
        #expect(task.baseDescription == "Email @ home + work")
    }

    // MARK: - Serialization round-trip tests

    @Test
    func roundTripSimpleTask() throws {
        let line = "Buy milk"
        let task = try TodoParser.parse(line: line)
        let serialized = TodoParser.serialize(task)
        #expect(serialized == line)
    }

    @Test
    func roundTripWithPriority() throws {
        let line = "(A) Buy milk"
        let task = try TodoParser.parse(line: line)
        let serialized = TodoParser.serialize(task)
        #expect(serialized == line)
    }

    @Test
    func roundTripWithPriorityAndDate() throws {
        let line = "(B) 2026-03-01 Buy milk"
        let task = try TodoParser.parse(line: line)
        let serialized = TodoParser.serialize(task)
        #expect(serialized == line)
    }

    @Test
    func roundTripCompleted() throws {
        let line = "x 2026-03-02 2026-03-01 Buy milk"
        let task = try TodoParser.parse(line: line)
        let serialized = TodoParser.serialize(task)
        #expect(serialized == line)
    }

    @Test
    func roundTripWithAllMetadata() throws {
        let line = "(A) 2026-03-01 Deploy app +Backend @Work due:2026-04-01"
        let task = try TodoParser.parse(line: line)
        let serialized = TodoParser.serialize(task)
        #expect(serialized == line)
    }

    @Test
    func roundTripCompletedWithAllMetadata() throws {
        let line = "x 2026-03-02 2026-03-01 Deploy app +Backend @Work due:2026-04-01"
        let task = try TodoParser.parse(line: line)
        let serialized = TodoParser.serialize(task)
        #expect(serialized == line)
    }

    @Test
    func editableTaskTextIncludesProjectsContextsAndNonDateExtras() throws {
        let task = try TodoParser.parse(
            line: "(A) 2026-03-01 Call Mom +Family @phone due:2026-04-01 t:2026-03-20 note:important"
        )

        let editableText = TaskEditFormatter.editableTaskText(for: task)

        #expect(editableText.contains("Call Mom"))
        #expect(editableText.contains("+Family"))
        #expect(editableText.contains("@phone"))
        #expect(editableText.contains("note:important"))
        #expect(!editableText.contains("due:2026-04-01"))
        #expect(!editableText.contains("t:2026-03-20"))
    }

    @Test
    func composedRawLineUsesEditedProjectsContextsAndMergedExtras() throws {
        let originalTask = try TodoParser.parse(
            line: "(A) 2026-03-01 Call Mom +Family @phone due:2026-04-01 t:2026-03-20 note:old"
        )

        let rawLine = TaskEditFormatter.composedRawLine(
            task: originalTask,
            taskText: "Email Dad +Admin @email note:new",
            priorityRaw: "B",
            dueDateText: "2026-04-02",
            thresholdDateText: ""
        )
        let editedTask = try TodoParser.parse(line: rawLine)

        #expect(editedTask.priority == "B")
        #expect(editedTask.creationDate == originalTask.creationDate)
        #expect(editedTask.baseDescription == "Email Dad")
        #expect(editedTask.projects == ["Admin"])
        #expect(editedTask.contexts == ["email"])
        #expect(editedTask.extras["note"] == "new")
        #expect(editedTask.extras["due"] == "2026-04-02")
        #expect(editedTask.extras["t"] == nil)
    }

    // MARK: - Toggle tests

    @Test
    func toggleClearsPriority() throws {
        let task = try TodoParser.parse(line: "(A) 2026-03-01 Important task")
        #expect(task.priority == "A")

        var toggled = task
        toggled.completed = true
        toggled.completionDate = Date()
        toggled.priority = nil // matches what toggle() now does

        #expect(toggled.priority == nil)
        let serialized = TodoParser.serialize(toggled)
        #expect(serialized.hasPrefix("x "))
        #expect(!serialized.contains("(A)"))
    }

    // MARK: - Helpers

    private func makeTempTodoFile(contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("todo.txt")
        try contents.appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func cleanupTempFile(at fileURL: URL) {
        TodoFileStore.shared.setExternalURL(nil)
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
}

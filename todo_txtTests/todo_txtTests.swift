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

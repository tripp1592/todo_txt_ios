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

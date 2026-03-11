import Foundation

struct TodoTask: Identifiable, Equatable {
    let id: UUID
    var completed: Bool
    var completionDate: Date?
    var priority: Character?
    var creationDate: Date?
    var baseDescription: String
    var projects: [String]
    var contexts: [String]
    var extras: [String: String]

    init(
        id: UUID = UUID(),
        completed: Bool,
        completionDate: Date? = nil,
        priority: Character? = nil,
        creationDate: Date? = nil,
        baseDescription: String,
        projects: [String] = [],
        contexts: [String] = [],
        extras: [String: String] = [:]
    ) {
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

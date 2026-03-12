import Foundation

protocol TodoStore: AnyObject {
    func load() throws -> [TodoTask]
    func save(_ tasks: [TodoTask]) throws
    func archive(_ completedTasks: [TodoTask], removing remainingTasks: [TodoTask]) throws
    func configureICloudTodoFile() throws -> URL
    func fileURL() -> URL
    func setExternalURL(_ url: URL?)
}

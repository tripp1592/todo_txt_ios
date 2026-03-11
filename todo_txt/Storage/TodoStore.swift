import Foundation

protocol TodoStore: AnyObject {
    func load() throws -> [TodoTask]
    func save(_ tasks: [TodoTask]) throws
    func appendToArchive(_ tasks: [TodoTask]) throws
    func configureICloudTodoFile() throws -> URL
    func fileURL() -> URL
    func setExternalURL(_ url: URL?)
}

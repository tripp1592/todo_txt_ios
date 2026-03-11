import Foundation

@discardableResult
func withSecurityScope<T>(url: URL, _ body: () throws -> T) rethrows -> T {
    let needsScope = url.startAccessingSecurityScopedResource()
    defer {
        if needsScope {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try body()
}

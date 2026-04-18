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

/// Reads a file using NSFileCoordinator to avoid conflicts with cloud sync providers (e.g. Dropbox).
@discardableResult
func coordinatedRead<T>(url: URL, _ body: (URL) throws -> T) throws -> T {
    let needsScope = url.startAccessingSecurityScopedResource()
    defer {
        if needsScope {
            url.stopAccessingSecurityScopedResource()
        }
    }

    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?
    var result: Result<T, Error>?

    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
        do {
            result = .success(try body(readURL))
        } catch {
            result = .failure(error)
        }
    }

    if let coordinatorError {
        throw coordinatorError
    }
    return try result!.get()
}

/// Writes a file using NSFileCoordinator to avoid conflicts with cloud sync providers (e.g. Dropbox).
@discardableResult
func coordinatedWrite<T>(url: URL, _ body: (URL) throws -> T) throws -> T {
    let needsScope = url.startAccessingSecurityScopedResource()
    defer {
        if needsScope {
            url.stopAccessingSecurityScopedResource()
        }
    }

    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?
    var result: Result<T, Error>?

    coordinator.coordinate(writingItemAt: url, options: [], error: &coordinatorError) { writeURL in
        do {
            result = .success(try body(writeURL))
        } catch {
            result = .failure(error)
        }
    }

    if let coordinatorError {
        throw coordinatorError
    }
    return try result!.get()
}

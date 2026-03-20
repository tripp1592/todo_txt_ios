import Foundation

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let todoKey = "TodoExternalBookmarkData"
    private let archiveKey = "ArchiveExternalBookmarkData"

    private init() {}

    func save(url: URL, forKey key: String? = nil) throws {
        let storageKey = key ?? todoKey
#if os(iOS)
        let data = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
#else
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
#endif
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func restore(forKey key: String? = nil) -> URL? {
        let storageKey = key ?? todoKey
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        var stale = false

        do {
#if os(iOS)
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
#else
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
#endif
            if stale {
                try? save(url: url, forKey: storageKey)
            }
            return url
        } catch {
            return nil
        }
    }

    func clear(forKey key: String? = nil) {
        let storageKey = key ?? todoKey
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Convenience for archive bookmark

    func saveArchive(url: URL) throws {
        try save(url: url, forKey: archiveKey)
    }

    func restoreArchive() -> URL? {
        restore(forKey: archiveKey)
    }

    func clearArchive() {
        clear(forKey: archiveKey)
    }
}

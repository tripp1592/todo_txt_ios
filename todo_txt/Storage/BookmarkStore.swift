import Foundation

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let key = "TodoExternalBookmarkData"

    private init() {}

    func save(url: URL) throws {
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
        UserDefaults.standard.set(data, forKey: key)
    }

    func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
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
                try? save(url: url)
            }
            return url
        } catch {
            return nil
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

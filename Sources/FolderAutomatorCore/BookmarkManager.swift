import Foundation

public final class BookmarkManager: @unchecked Sendable {
    public static let shared = BookmarkManager()

    public init() {}

    public func makeBookmark(for path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return data.base64EncodedString()
    }

    public func resolvePath(path: String, bookmarkData: String?) -> String {
        guard let bookmarkData,
              let data = Data(base64Encoded: bookmarkData)
        else {
            return path
        }

        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                return path
            }
            _ = url.startAccessingSecurityScopedResource()
            return url.path
        } catch {
            return path
        }
    }
}

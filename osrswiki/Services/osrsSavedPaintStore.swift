import Foundation

struct osrsSavedPaintStore {
    static func paintFileURL(pageId: String, cacheDirectory: URL) -> URL {
        cacheDirectory.appendingPathComponent("\(pageId).paint.html")
    }

    static func write(pageId: String, html: String, cacheDirectory: URL) throws {
        let url = paintFileURL(pageId: pageId, cacheDirectory: cacheDirectory)
        try html.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func read(pageId: String, cacheDirectory: URL) -> String? {
        let url = paintFileURL(pageId: pageId, cacheDirectory: cacheDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func remove(pageId: String, cacheDirectory: URL) {
        let url = paintFileURL(pageId: pageId, cacheDirectory: cacheDirectory)
        try? FileManager.default.removeItem(at: url)
    }
}

struct osrsSavedPageAssetReuse {
    struct Partition: Equatable {
        let reusedUrls: [URL]
        let fetchUrls: [URL]
    }

    static func partition(requiredUrls: [URL], priorUrls: Set<URL>) -> Partition {
        var reused: [URL] = []
        var fetch: [URL] = []
        var seen = Set<URL>()
        for url in requiredUrls where seen.insert(url).inserted {
            if priorUrls.contains(url) {
                reused.append(url)
            } else {
                fetch.append(url)
            }
        }
        return Partition(reusedUrls: reused, fetchUrls: fetch)
    }
}

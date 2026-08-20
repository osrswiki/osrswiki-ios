import Foundation

struct osrsSavedPageRevisionProbe: Sendable {
    struct RemoteRevision: Equatable, Sendable {
        let pageTitle: String
        let revisionId: Int
    }

    static let wikiQueryURL = URL(string: "https://oldschool.runescape.wiki/api.php")!

    static func queryURL(forPageTitle title: String) -> URL {
        var components = URLComponents(url: wikiQueryURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "prop", value: "revisions"),
            URLQueryItem(name: "rvprop", value: "ids"),
            URLQueryItem(name: "rvlimit", value: "1"),
            URLQueryItem(name: "titles", value: title)
        ]
        return components.url ?? wikiQueryURL
    }

    static func remoteRevision(
        in data: Data,
        requestedTitle: String
    ) -> RemoteRevision? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let query = root["query"] as? [String: Any],
            let pages = query["pages"] as? [[String: Any]],
            let page = pages.first,
            page["missing"] == nil,
            let revisions = page["revisions"] as? [[String: Any]],
            let revision = revisions.first,
            let revisionId = revision["revid"] as? Int
        else {
            return nil
        }
        let resolvedTitle = (page["title"] as? String) ?? requestedTitle
        return RemoteRevision(pageTitle: resolvedTitle, revisionId: revisionId)
    }

    static func snapshotNeedsRefresh(
        localRevisionId: Int?,
        remoteRevisionId: Int
    ) -> Bool {
        guard let localRevisionId, localRevisionId > 0 else {
            return true
        }
        return remoteRevisionId != localRevisionId
    }
}

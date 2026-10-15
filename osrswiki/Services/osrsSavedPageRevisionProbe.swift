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
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "maxlag", value: String(osrsWikiApiStewardship.backgroundMaxLagSeconds))
        ]
        return components.url ?? wikiQueryURL
    }

    static func fetchRemoteRevision(forPageTitle title: String) async -> RemoteRevision? {
        var request = URLRequest(url: queryURL(forPageTitle: title))
        request.setValue(
            osrsWikiApiStewardship.appUserAgent("revision-probe"),
            forHTTPHeaderField: "User-Agent"
        )
        var attempt = 0
        while attempt <= 2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let retryable = osrsWikiApiStewardship.shouldRetry(
                    statusCode: http?.statusCode ?? 0,
                    body: data
                )
                if retryable && attempt < 2 {
                    let delay = (http.flatMap { osrsWikiApiStewardship.retryAfterInterval(from: $0) }) ?? 1
                    try await Task.sleep(
                        nanoseconds: UInt64(min(delay, osrsWikiApiStewardship.maxRetryAfter) * 1_000_000_000)
                    )
                    attempt += 1
                    continue
                }
                return remoteRevision(in: data, requestedTitle: title)
            } catch {
                return nil
            }
        }
        return nil
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

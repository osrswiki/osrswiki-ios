import Foundation

/// Identified User-Agent and Retry-After policy for wiki / prices HTTP.
///
/// The OSRS Wiki asks automated clients to send a descriptive User-Agent with
/// contact details, honor HTTP caching, use prices API v2, and back off on
/// 429/503. See https://oldschool.runescape.wiki/w/RuneScape:Real-time_Prices
enum osrsWikiApiStewardship {
    static let contactEmail = "osamu+osrswiki@mail.grokbot.com"
    static let iosSource = "https://github.com/osrswiki/osrswiki-ios"
    static let maxRetryAfter: TimeInterval = 30
    static let backgroundMaxLagSeconds = 5
    static let geChartCacheTTL: TimeInterval = 30 * 60
    static let searchQueryCacheSize = 16
    static let mediaWikiErrorMaxlag = "maxlag"
    static let mediaWikiErrorRatelimited = "ratelimited"

    static func marketingVersion(
        bundle: Bundle = .main
    ) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "dev"
    }

    static func userAgent(
        version: String,
        component: String = "app"
    ) -> String {
        let label = component.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? "app" : label
        let resolvedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionToken = resolvedVersion.isEmpty ? "dev" : resolvedVersion
        return "OSRSWikiApp/\(versionToken) (iOS; \(resolvedLabel); \(contactEmail); +\(iosSource))"
    }

    static func appUserAgent(_ component: String = "app") -> String {
        userAgent(version: marketingVersion(), component: component)
    }

    static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 429 || statusCode == 503
    }

    static func shouldRetryMediaWikiError(_ code: String?) -> Bool {
        code == mediaWikiErrorMaxlag || code == mediaWikiErrorRatelimited
    }

    static func mediaWikiRetryableErrorCode(in body: String?) -> String? {
        let text = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text.contains("\"error\"") else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "\"code\"\\s*:\\s*\"([^\"]+)\"") else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let codeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let code = String(text[codeRange])
        return shouldRetryMediaWikiError(code) ? code : nil
    }

    static func mediaWikiRetryableErrorCode(in data: Data) -> String? {
        let prefix = data.prefix(2048)
        return mediaWikiRetryableErrorCode(in: String(data: prefix, encoding: .utf8))
    }

    static func shouldRetry(statusCode: Int, body: Data?) -> Bool {
        shouldRetry(statusCode: statusCode) || shouldRetryMediaWikiError(mediaWikiRetryableErrorCode(in: body ?? Data()))
    }

    static func withBackgroundMaxLag(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        if items.contains(where: { $0.name == "maxlag" }) {
            return url
        }
        items.append(URLQueryItem(name: "maxlag", value: String(backgroundMaxLagSeconds)))
        components.queryItems = items
        return components.url ?? url
    }

    static func retryAfterInterval(
        header: String?,
        now: Date = Date()
    ) -> TimeInterval? {
        let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return min(seconds, maxRetryAfter)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let when = formatter.date(from: raw) else { return nil }
        return min(max(0, when.timeIntervalSince(now)), maxRetryAfter)
    }

    static func retryAfterInterval(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        let header = response.value(forHTTPHeaderField: "Retry-After")
        return retryAfterInterval(header: header, now: now)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

//
//  NewsRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import Foundation

@MainActor
class NewsRepository: ObservableObject {
    static let shared = NewsRepository()
    
    // MARK: - Cache Management
    private let cacheKey = "osrs_wiki_feed_cache"
    private let cacheTimestampKey = "osrs_wiki_feed_timestamp"
    private let lastRefreshAttemptKey = "osrs_wiki_feed_last_attempt"
    private let cacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours
    
    @Published private var cachedFeed: WikiFeed?
    private var cacheTimestamp: Date?
    private var lastRefreshAttemptTimestamp: Date?
    
    private init() {
        loadCachedData()
    }
    private let baseURL = "https://oldschool.runescape.wiki"
    private let wikiURL = "https://oldschool.runescape.wiki/"
    private let networkManager = NetworkManager.shared
    
    func fetchWikiFeed(forceRefresh: Bool = false) async throws -> WikiFeed {
        // Check cache first unless forced refresh
        if !forceRefresh, let cached = getCachedFeedIfValid() {
            print("📦 NewsRepository: Using cached feed data")
            return cached
        }
        
        print("🌐 NewsRepository: Fetching fresh feed data...")
        let feed = try await fetchFreshWikiFeed()
        
        // Cache the fresh data
        cacheFeed(feed)
        
        return feed
    }
    
    private func fetchFreshWikiFeed() async throws -> WikiFeed {
        guard let url = URL(string: wikiURL) else {
            throw NetworkError.invalidResponse
        }
        
        // Use NetworkManager for resilient network handling
        do {
            let (data, _) = try await networkManager.performDataRequest(url: url, retryCount: 2, bypassCache: true)
            guard let html = String(data: data, encoding: .utf8) else {
                throw NetworkError.invalidData
            }
            
            return parseWikiFeed(from: html)
        } catch let networkError as NetworkError {
            print("❌ NewsRepository: Network error fetching wiki feed: \(networkError.localizedDescription)")
            throw networkError
        } catch {
            print("❌ NewsRepository: Unexpected error fetching wiki feed: \(error)")
            throw NetworkError.unknown(error)
        }
    }
    
    // For backwards compatibility with existing NewsViewModel
    func fetchLatestNews(forceRefresh: Bool = false) async throws -> [NewsItem] {
        let wikiFeed = try await fetchWikiFeed(forceRefresh: forceRefresh)
        return transformFeedToNewsItems(wikiFeed)
    }
    
    // MARK: - Cache Management Methods
    
    private func getCachedFeedIfValid() -> WikiFeed? {
        // Check if we have cached data and it's still valid
        guard let cached = cachedFeed,
              let timestamp = cacheTimestamp,
              Date().timeIntervalSince(timestamp) < cacheTTL else {
            print("📦 NewsRepository: Cache invalid or expired")
            return nil
        }
        
        let age = Date().timeIntervalSince(timestamp)
        print("📦 NewsRepository: Cache valid, age: \(Int(age))s")
        return cached
    }
    
    private func cacheFeed(_ feed: WikiFeed) {
        cachedFeed = feed
        cacheTimestamp = Date()
        
        // Persist to UserDefaults
        saveCacheToUserDefaults(feed)
        
        print("💾 NewsRepository: Cached feed data")
    }
    
    private func loadCachedData() {
        // Load from UserDefaults on initialization
        if let feed = loadCacheFromUserDefaults() {
            cachedFeed = feed
            print("📦 NewsRepository: Loaded cached data from UserDefaults")
        }
        
        // Load last refresh attempt timestamp
        if let lastAttempt = UserDefaults.standard.object(forKey: lastRefreshAttemptKey) as? Date {
            lastRefreshAttemptTimestamp = lastAttempt
        }
    }
    
    private func saveCacheToUserDefaults(_ feed: WikiFeed) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(CachedWikiFeed(from: feed))
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        } catch {
            print("❌ NewsRepository: Failed to save cache: \(error)")
        }
    }
    
    private func loadCacheFromUserDefaults() -> WikiFeed? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return nil
        }
        
        // Check if cache is still valid
        guard Date().timeIntervalSince(timestamp) < cacheTTL else {
            print("📦 NewsRepository: Persisted cache expired")
            clearCache()
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedFeed = try decoder.decode(CachedWikiFeed.self, from: data)
            cacheTimestamp = timestamp
            return cachedFeed.toWikiFeed()
        } catch {
            print("❌ NewsRepository: Failed to decode cache: \(error)")
            clearCache()
            return nil
        }
    }
    
    func clearCache() {
        cachedFeed = nil
        cacheTimestamp = nil
        lastRefreshAttemptTimestamp = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        UserDefaults.standard.removeObject(forKey: lastRefreshAttemptKey)
        print("🗑️ NewsRepository: Cache cleared")
    }

#if DEBUG
    func seedHomeFeedForSpecConformanceTests() {
        clearCache()
        cacheFeed(osrsSpecConformanceFixtures.homeFeed)
        print("UITest: seeded Home feed for spec conformance")
    }
#endif
    
    var isCacheValid: Bool {
        return getCachedFeedIfValid() != nil
    }
    
    /// Synchronous cache access for instant display in ViewModel initialization
    func getCachedFeedSynchronously() -> WikiFeed? {
        return getCachedFeedIfValid()
    }
    
    /// Get last updated timestamp for UI display
    var lastUpdatedTimestamp: Date? {
        return cacheTimestamp
    }
    
    /// Format last updated time for user display
    /// Shows "Just now" for recent refresh attempts (even if cancelled) or actual cache age
    var lastUpdatedString: String {
        let now = Date()
        
        // If there was a recent refresh attempt (within 2 minutes), show "Just now"
        if let lastAttempt = lastRefreshAttemptTimestamp,
           now.timeIntervalSince(lastAttempt) < 120 {
            return "Just now"
        }
        
        // Otherwise show actual cache age
        guard let timestamp = cacheTimestamp else {
            return "Never updated"
        }
        
        let interval = now.timeIntervalSince(timestamp)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    /// Mark that a refresh attempt was made (regardless of success)
    func markRefreshAttempt() {
        lastRefreshAttemptTimestamp = Date()
        UserDefaults.standard.set(lastRefreshAttemptTimestamp, forKey: lastRefreshAttemptKey)
        print("🔄 NewsRepository: Marked refresh attempt at \(Date())")
    }

    private func parseWikiFeed(from html: String) -> WikiFeed {
        return WikiFeed(
            recentUpdates: parseRecentUpdates(html),
            announcements: parseAnnouncements(html),
            onThisDay: parseOnThisDay(html),
            popularPages: parsePopularPages(html)
        )
    }

#if DEBUG
    func parseWikiFeedForTesting(_ html: String) -> WikiFeed {
        return parseWikiFeed(from: html)
    }
#endif
    
    private func parseRecentUpdates(_ html: String) -> [UpdateItem] {
        var updates: [UpdateItem] = []
        
        // Find the start of mainpage-recent-updates section
        guard let startRange = html.range(of: #"<div[^>]*class="[^"]*mainpage-recent-updates"#, options: .regularExpression) else {
            print("📰 mainpage-recent-updates section not found")
            return updates
        }
        
        // Find the end marker (next major section)
        let searchAfterStart = html[startRange.upperBound...]
        let endPattern = #"<div[^>]*class="[^"]*mainpage-contents"#
        let endRange = searchAfterStart.range(of: endPattern, options: .regularExpression)
        
        // Extract the content section
        let containerContent: String
        if let endRange = endRange {
            containerContent = String(html[startRange.lowerBound..<endRange.lowerBound])
        } else {
            // Fallback: take everything after start
            containerContent = String(html[startRange.lowerBound...])
        }
        
        print("📰 Extracted container content, length: \(containerContent.count)")
        
        // Find all tile-halves within this content
        let tilePattern = #"<div[^>]*class="[^"]*tile-halves[^"]*"[^>]*>(.*?)</div>\s*</div>"#
        
        do {
            let tileRegex = try NSRegularExpression(pattern: tilePattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let tileMatches = tileRegex.matches(in: containerContent, options: [], range: NSRange(containerContent.startIndex..., in: containerContent))
            
            print("📰 Found \(tileMatches.count) tile-halves in recent updates")
            
            for (index, match) in tileMatches.prefix(5).enumerated() {
                guard let tileRange = Range(match.range(at: 1), in: containerContent) else { continue }
                let tileContent = String(containerContent[tileRange])
                
                print("📰 Processing tile \(index + 1):")
                print("   First 200 chars: \(String(tileContent.prefix(200)))")
                
                // Extract title from h2 within tile-bottom a tag
                let titlePattern = #"<div[^>]*class="[^"]*tile-bottom[^"]*"[^>]*>.*?<a[^>]*>.*?<h2[^>]*>(.*?)</h2>"#
                let title = extractFirst(pattern: titlePattern, from: tileContent) ?? "Recent Update"
                
                // Extract snippet from last p tag within tile-bottom a tag (matching Android approach)
                let pTagPattern = #"<p[^>]*>(.*?)</p>"#
                let allPTagsInTile = extractAll(pattern: pTagPattern, from: tileContent)
                let snippet = allPTagsInTile.last.map { cleanHTML($0) } ?? ""
                
                // Extract href from tile-bottom a tag
                let hrefPattern = #"<div[^>]*class="[^"]*tile-bottom[^"]*"[^>]*>.*?<a[^>]*href="([^"]+)""#
                let href = extractFirst(pattern: hrefPattern, from: tileContent) ?? ""
                let articleUrl = href.starts(with: "/") ? "\(baseURL)\(href)" : href
                
                // Extract image from tile-top
                let imgSrcPattern = #"<div[^>]*class="[^"]*tile-top[^"]*"[^>]*>.*?<img[^>]*src="([^"]+)""#
                let imgSrc = extractFirst(pattern: imgSrcPattern, from: tileContent) ?? ""
                let imageUrl = imgSrc.starts(with: "/") ? "\(baseURL)\(imgSrc)" : imgSrc
                
                let cleanTitle = cleanHTML(title)
                let cleanSnippet = snippet // Already cleaned above
                
                print("   Extracted title: '\(cleanTitle)'")
                print("   Extracted snippet: '\(cleanSnippet)'")
                print("   Article URL: '\(articleUrl)'")
                print("   Image URL: '\(imageUrl)'")
                
                if !cleanTitle.isEmpty && cleanTitle != "Recent Update" {
                    updates.append(UpdateItem(
                        title: cleanTitle,
                        snippet: cleanSnippet,
                        imageUrl: imageUrl,
                        articleUrl: articleUrl
                    ))
                }
            }
        } catch {
            print("Error parsing recent updates: \(error)")
        }
        
        print("📰 Total updates parsed: \(updates.count)")
        return updates
    }
    
    private func parseAnnouncements(_ html: String) -> [AnnouncementItem] {
        var announcements: [AnnouncementItem] = []
        
        let dtPattern = #"<dt[^>]*>(.*?)</dt>"#
        let ddPattern = #"<dd[^>]*>(.*?)</dd>"#
        
        if let wikinewsContent = extractDivElementHTML(containingClass: "mainpage-wikinews", from: html) {
            let dates = extractAll(pattern: dtPattern, from: wikinewsContent)
            let contents = extractAll(pattern: ddPattern, from: wikinewsContent)
            
            for (date, content) in zip(dates, contents) {
                announcements.append(AnnouncementItem(
                    date: cleanHTML(date),
                    content: content
                ))
            }
        }
        
        return announcements
    }
    
    private func parseOnThisDay(_ html: String) -> OnThisDayItem? {
        let h2Pattern = #"<h2[^>]*>(.*?)</h2>"#
        let liPattern = #"<li[^>]*>(.*?)</li>"#
        
        if let onThisDayContent = extractDivElementHTML(containingClass: "mainpage-onthisday", from: html) {
            let title = extractFirst(pattern: h2Pattern, from: onThisDayContent) ?? "On this day..."
            let events = extractAll(pattern: liPattern, from: onThisDayContent)
            
            if !events.isEmpty {
                return OnThisDayItem(title: cleanHTML(title), events: events)
            }
        }
        
        return nil
    }
    
    private func parsePopularPages(_ html: String) -> [PopularPageItem] {
        var popularPages: [PopularPageItem] = []
        
        let linkPattern = #"<li[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        
        do {
            if let popularContent = extractDivElementHTML(containingClass: "mainpage-popular", from: html) {
                let linkRegex = try NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive])
                let linkMatches = linkRegex.matches(in: popularContent, options: [], range: NSRange(popularContent.startIndex..., in: popularContent))
                
                for linkMatch in linkMatches {
                    guard let hrefRange = Range(linkMatch.range(at: 1), in: popularContent),
                          let titleRange = Range(linkMatch.range(at: 2), in: popularContent) else { continue }
                    
                    let href = String(popularContent[hrefRange])
                    let title = String(popularContent[titleRange])
                    let pageUrl = href.starts(with: "/") ? "\(baseURL)\(href)" : href
                    
                    popularPages.append(PopularPageItem(
                        title: cleanHTML(title),
                        pageUrl: pageUrl
                    ))
                }
            }
        } catch {
            print("Error parsing popular pages: \(error)")
        }
        
        return popularPages
    }
    
    func transformFeedToNewsItems(_ feed: WikiFeed) -> [NewsItem] {
        var items: [NewsItem] = []
        
        // Convert recent updates to news items
        for (index, update) in feed.recentUpdates.enumerated() {
            items.append(NewsItem(
                id: "update_\(index)",
                title: update.title,
                summary: update.snippet,
                content: nil,
                imageUrl: URL(string: update.imageUrl),
                publishedDate: Date(), // We don't have publish dates from scraping
                category: .update,
                url: URL(string: update.articleUrl)
            ))
        }
        
        // Convert announcements to news items
        for (index, announcement) in feed.announcements.enumerated() {
            items.append(NewsItem(
                id: "announcement_\(index)",
                title: "Wiki News: \(announcement.date)",
                summary: announcement.content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                content: nil,
                imageUrl: nil,
                publishedDate: Date(),
                category: .announcement,
                url: nil
            ))
        }
        
        return items
    }
    
    // MARK: - Helper Methods
    
    private func extractFirst(pattern: String, from text: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            
            if let match = matches.first,
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        } catch {
            print("Error extracting with pattern \(pattern): \(error)")
        }
        
        return nil
    }
    
    private func extractLast(pattern: String, from text: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            
            if let match = matches.last,
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        } catch {
            print("Error extracting with pattern \(pattern): \(error)")
        }
        
        return nil
    }
    
    private func extractAll(pattern: String, from text: String) -> [String] {
        var results: [String] = []
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    results.append(String(text[range]))
                }
            }
        } catch {
            print("Error extracting all with pattern \(pattern): \(error)")
        }
        
        return results
    }

    private func extractDivElementHTML(containingClass className: String, from html: String) -> String? {
        let escapedClassName = NSRegularExpression.escapedPattern(for: className)
        let startPattern = #"<div\b[^>]*class\s*=\s*"[^"]*\#(escapedClassName)[^"]*"[^>]*>"#

        do {
            let startRegex = try NSRegularExpression(pattern: startPattern, options: [.caseInsensitive])
            guard let startMatch = startRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                  let startRange = Range(startMatch.range, in: html) else {
                return nil
            }

            let divRegex = try NSRegularExpression(pattern: #"</?div\b[^>]*>"#, options: [.caseInsensitive])
            let matches = divRegex.matches(in: html, options: [], range: NSRange(startRange.lowerBound..., in: html))
            var depth = 0

            for match in matches {
                guard let tagRange = Range(match.range, in: html) else { continue }
                let tag = html[tagRange].lowercased()

                if tag.hasPrefix("</div") {
                    depth -= 1
                    if depth == 0 {
                        return String(html[startRange.lowerBound..<tagRange.upperBound])
                    }
                } else {
                    depth += 1
                }
            }
        } catch {
            print("Error extracting div for class \(className): \(error)")
        }

        return nil
    }
    
    private func cleanHTML(_ html: String) -> String {
        return html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#8226;", with: "•")
            .replacingOccurrences(of: "&bull;", with: "•")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Legacy NewsError (deprecated - use NetworkError instead)
enum NewsError: Error {
    case invalidURL
    case invalidData
    case parseError(String)
    
    // Convert to NetworkError for consistency
    var asNetworkError: NetworkError {
        switch self {
        case .invalidURL:
            return .invalidResponse
        case .invalidData:
            return .invalidData
        case .parseError(let message):
            return .unknown(NSError(domain: "NewsError", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}

// MARK: - Cache Models (Codable versions for persistence)

private struct CachedWikiFeed: Codable {
    let recentUpdates: [CachedUpdateItem]
    let announcements: [CachedAnnouncementItem]
    let onThisDay: CachedOnThisDayItem?
    let popularPages: [CachedPopularPageItem]
    
    init(from wikiFeed: WikiFeed) {
        self.recentUpdates = wikiFeed.recentUpdates.map { CachedUpdateItem(from: $0) }
        self.announcements = wikiFeed.announcements.map { CachedAnnouncementItem(from: $0) }
        self.onThisDay = wikiFeed.onThisDay.map { CachedOnThisDayItem(from: $0) }
        self.popularPages = wikiFeed.popularPages.map { CachedPopularPageItem(from: $0) }
    }
    
    func toWikiFeed() -> WikiFeed {
        return WikiFeed(
            recentUpdates: recentUpdates.map { $0.toUpdateItem() },
            announcements: announcements.map { $0.toAnnouncementItem() },
            onThisDay: onThisDay?.toOnThisDayItem(),
            popularPages: popularPages.map { $0.toPopularPageItem() }
        )
    }
}

private struct CachedUpdateItem: Codable {
    let title: String
    let snippet: String
    let imageUrl: String
    let articleUrl: String
    
    init(from item: UpdateItem) {
        self.title = item.title
        self.snippet = item.snippet
        self.imageUrl = item.imageUrl
        self.articleUrl = item.articleUrl
    }
    
    func toUpdateItem() -> UpdateItem {
        return UpdateItem(title: title, snippet: snippet, imageUrl: imageUrl, articleUrl: articleUrl)
    }
}

private struct CachedAnnouncementItem: Codable {
    let date: String
    let content: String
    
    init(from item: AnnouncementItem) {
        self.date = item.date
        self.content = item.content
    }
    
    func toAnnouncementItem() -> AnnouncementItem {
        return AnnouncementItem(date: date, content: content)
    }
}

private struct CachedOnThisDayItem: Codable {
    let title: String
    let events: [String]
    
    init(from item: OnThisDayItem) {
        self.title = item.title
        self.events = item.events
    }
    
    func toOnThisDayItem() -> OnThisDayItem {
        return OnThisDayItem(title: title, events: events)
    }
}

private struct CachedPopularPageItem: Codable {
    let title: String
    let pageUrl: String
    
    init(from item: PopularPageItem) {
        self.title = item.title
        self.pageUrl = item.pageUrl
    }
    
    func toPopularPageItem() -> PopularPageItem {
        return PopularPageItem(title: title, pageUrl: pageUrl)
    }
}

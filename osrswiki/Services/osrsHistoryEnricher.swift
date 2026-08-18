//
//  osrsHistoryEnricher.swift
//  OSRS Wiki
//
//  Created on iOS history list consistency session
//

import Foundation

struct osrsHistoryMetadataSnapshot: Sendable, Equatable {
    let thumbnailUrl: URL?
    let description: String?
}

/// Resolves rich update-card metadata already cached by Home. Wiki update pages often omit a
/// `pageimages` thumbnail even though the feed carries the canonical card image, so History and
/// Saved must share this deterministic fallback instead of independently losing that image.
enum osrsHistoryUpdateMetadataResolver {
    static func cachedMetadata(for item: HistoryItem, in feed: WikiFeed?) -> osrsHistoryMetadataSnapshot? {
        cachedMetadata(forTitle: item.displayTitle, in: feed)
    }

    static func cachedMetadata(forTitle title: String, in feed: WikiFeed?) -> osrsHistoryMetadataSnapshot? {
        guard let update = feed?.recentUpdates.first(where: {
            normalizedTitle($0.title) == normalizedTitle(title)
        }) else {
            return nil
        }

        return osrsHistoryMetadataSnapshot(
            thumbnailUrl: update.imageUrl.isEmpty ? nil : URL(string: update.imageUrl),
            description: update.snippet.isEmpty ? nil : update.snippet
        )
    }

    private static func normalizedTitle(_ title: String) -> String {
        osrsStringUtils.extractMainTitle(title)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}

/// Service to enrich history entries with thumbnails and snippets, matching Android functionality
final class osrsHistoryEnricher: @unchecked Sendable {
    private let session: URLSession
    private let baseURL = "https://oldschool.runescape.wiki/api.php"
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 20.0
        self.session = URLSession(configuration: config)
    }
    
    /// Enriches a history entry with thumbnail and description metadata
    /// Matches Android's PageHistoryManager.logPageVisit() functionality
    /// - Parameters:
    ///   - pageTitle: The page title to enrich
    ///   - pageUrl: The page URL
    /// - Returns: Enriched history data with thumbnail and snippet
    func enrichHistoryEntry(pageTitle: String, pageUrl: URL) async -> (thumbnailUrl: URL?, snippet: String?) {
        // Extract the actual page title from URL for API calls
        let cleanTitle = extractTitleFromUrl(pageUrl) ?? pageTitle
        
        async let thumbnailTask = fetchThumbnailUrl(for: cleanTitle)
        async let snippetTask = fetchPageExtract(for: cleanTitle)
        
        // Run both API calls concurrently for efficiency
        let (thumbnailUrl, snippet) = await (thumbnailTask, snippetTask)
        
        return (thumbnailUrl: thumbnailUrl, snippet: snippet)
    }
    
    /// Fetches thumbnail URL for a given page title
    /// Matches Android's PageImages API usage
    private func fetchThumbnailUrl(for title: String) async -> URL? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail|original"),
            URLQueryItem(name: "pithumbsize", value: "240"), // Match Android's thumbnail size
            URLQueryItem(name: "pilicense", value: "any"),
            URLQueryItem(name: "redirects", value: "1")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(HistoryThumbnailResponse.self, from: data)
            
            if let pages = response.query?.pages,
               let page = pages.first,
               let thumbnail = page.thumbnail {
                return URL(string: thumbnail.source)
            }
        } catch {
            print("Failed to fetch thumbnail for '\(title)': \(error)")
        }
        
        return nil
    }
    
    /// Fetches page extract/snippet for a given page title
    /// Matches Android's PageExtracts API usage
    private func fetchPageExtract(for title: String) async -> String? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "exintro", value: "true"), // Only intro section
            URLQueryItem(name: "explaintext", value: "true"), // Plain text, no HTML
            URLQueryItem(name: "exsectionformat", value: "plain"),
            URLQueryItem(name: "exchars", value: "200"), // Limit to ~200 characters
            URLQueryItem(name: "redirects", value: "1")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(WikiExtractResponse.self, from: data)
            
            if let pages = response.query?.pages,
               let page = pages.first,
               let extract = page.extract,
               !extract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return extract.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Failed to fetch extract for '\(title)': \(error)")
        }
        
        return nil
    }
    
    /// Extracts the page title from a Wikipedia URL
    /// - Parameter url: The Wikipedia URL
    /// - Returns: The extracted page title
    private func extractTitleFromUrl(_ url: URL) -> String? {
        // Handle URLs like: https://oldschool.runescape.wiki/w/Page_Title
        guard let path = url.path.components(separatedBy: "/").last,
              !path.isEmpty else {
            return nil
        }
        
        // URL decode and replace underscores with spaces
        let title = path.removingPercentEncoding ?? path
        return title.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Response Models for History Enrichment (reusing existing models from SearchRepository)

/// Response model for thumbnail API calls (reusing existing structure)
private struct HistoryThumbnailResponse: Codable {
    let query: HistoryThumbnailQuery?
}

private struct HistoryThumbnailQuery: Codable {
    let pages: [HistoryThumbnailPage]?
}

private struct HistoryThumbnailPage: Codable {
    let pageid: Int?
    let title: String?
    let thumbnail: HistoryWikiThumbnail?
}

private struct HistoryWikiThumbnail: Codable {
    let source: String
    let width: Int?
    let height: Int?
}

/// Response model for page extract API calls
private struct WikiExtractResponse: Codable {
    let query: WikiExtractQuery?
}

private struct WikiExtractQuery: Codable {
    let pages: [WikiExtractPage]?
}

private struct WikiExtractPage: Codable {
    let pageid: Int?
    let title: String?
    let extract: String?
}

//
//  SearchRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import Foundation

@MainActor
class SearchRepository {
    private let baseURL = "https://oldschool.runescape.wiki/api.php"
    
    func search(query: String, limit: Int = 50, offset: Int = 0) async throws -> SearchResponse {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchResponse(results: [], hasMore: false, totalCount: 0)
        }
        
        // Build MediaWiki API search URL with pagination support and relevance ranking
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"), // Use format version 2 for consistency with Android
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: String(limit)),
            URLQueryItem(name: "sroffset", value: String(offset)),
            URLQueryItem(name: "srprop", value: "snippet|size|wordcount|timestamp"), // Match Android's props
            URLQueryItem(name: "srsort", value: "relevance"), // Critical: explicit relevance sorting
            // Removed srnamespace filter to match Android (includes all namespaces)
            URLQueryItem(name: "srinfo", value: "totalhits") // Get total result count
        ]
        
        guard let url = components.url else {
            throw SearchError.invalidURL
        }

        // Make API request with proper error handling
        do {
            let (data, response) = try await NetworkManager.shared.performDataRequest(url: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SearchError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                break
            case 429:
                throw SearchError.rateLimited
            case 500...599:
                throw SearchError.serverError
            default:
                throw SearchError.invalidResponse
            }
            
            // Parse JSON response
            let searchResponse = try JSONDecoder().decode(WikiSearchResponse.self, from: data)

            // Step 1: Map search results to SearchResult objects with preserved ranking
            var searchResults = searchResponse.query.search.enumerated().map { (index, apiResult) in
                SearchResult(
                    id: String(apiResult.pageid),
                    title: apiResult.title,
                    description: apiResult.snippet?.htmlStripped(), // HTML-stripped for fallback
                    rawSnippet: apiResult.snippet, // Raw HTML with <span class="searchmatch"> tags
                    url: URL(string: "https://oldschool.runescape.wiki/w/\(apiResult.title.replacingOccurrences(of: " ", with: "_"))")!,
                    thumbnailUrl: nil, // Will be set in step 2
                    ns: apiResult.ns, // Include namespace ID to match Android
                    namespace: namespaceDisplayName(for: apiResult.ns), // Convert to readable name
                    score: nil,
                    index: index + 1, // Maintain search ranking order
                    size: apiResult.size,
                    wordcount: apiResult.wordcount,
                    timestamp: apiResult.timestamp
                )
            }
            
            // Step 2: Fetch thumbnails in batch (matching Android's efficient approach)
            if !searchResults.isEmpty {
                let thumbnailMap = await fetchThumbnailsBatch(for: searchResults)
                searchResults = searchResults.map { result in
                    var updatedResult = result
                    updatedResult.thumbnailUrl = thumbnailMap[result.id]
                    return updatedResult
                }
            }
            
            let totalHits = searchResponse.query.searchinfo?.totalhits ?? searchResults.count
            let hasMore = (offset + searchResults.count) < totalHits
            
            return SearchResponse(results: searchResults, hasMore: hasMore, totalCount: totalHits)
            
        } catch let error as SearchError {
            throw error
        } catch let error as NetworkError {
            throw searchError(from: error)
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw SearchError.networkUnavailable
                case .timedOut:
                    throw SearchError.timeout
                default:
                    throw SearchError.networkError(urlError)
                }
            } else {
                throw SearchError.unknown(error)
            }
        }
    }

    private func searchError(from error: NetworkError) -> SearchError {
        switch error {
        case .noConnection, .connectionLost:
            return .networkUnavailable
        case .timeout:
            return .timeout
        case .rateLimited:
            return .rateLimited
        case .serverError:
            return .serverError
        case .pageNotFound:
            return .invalidResponse
        case .invalidResponse:
            return .invalidResponse
        case .invalidData:
            return .invalidResponse
        case .unknown(let underlying):
            if let urlError = underlying as? URLError {
                return .networkError(urlError)
            }
            return .unknown(error)
        }
    }
    
    // Efficient batch thumbnail fetching (matching Android's approach)
    private func fetchThumbnailsBatch(for searchResults: [SearchResult]) async -> [String: URL] {
        // Limit to first 50 results to respect MediaWiki API constraints
        let resultsToFetch = Array(searchResults.prefix(50))
        let pageIds = resultsToFetch.map { $0.id }.joined(separator: "|")
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "pageids", value: pageIds), // Use pageids instead of titles for efficiency
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "pilicense", value: "any"),
            URLQueryItem(name: "pithumbsize", value: "240") // Match Android's thumbnail size
        ]
        
        guard let url = components.url else { return [:] }
        
        do {
            let (data, _) = try await NetworkManager.shared.performDataRequest(url: url)
            let response = try JSONDecoder().decode(WikiBatchThumbnailResponse.self, from: data)
            
            var thumbnailMap: [String: URL] = [:]
            
            if let pages = response.query?.pages {
                for page in pages {
                    if let thumbnail = page.thumbnail,
                       let thumbnailURL = URL(string: thumbnail.source) {
                        thumbnailMap[String(page.pageid)] = thumbnailURL
                    }
                }
            }
            
            return thumbnailMap
        } catch {
            // Silently fail for thumbnail fetching - not critical for functionality
            return [:]
        }
    }
    
    // Legacy method - kept for compatibility but not used in new implementation
    private func fetchThumbnailURL(for title: String) async -> URL? {
        let cleanTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "titles", value: cleanTitle),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "pithumbsize", value: "240") // Updated to match Android
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let (data, _) = try await NetworkManager.shared.performDataRequest(url: url)
            let response = try JSONDecoder().decode(WikiThumbnailResponse.self, from: data)
            
            if let pages = response.query?.pages,
               let page = pages.values.first,
               let thumbnail = page.thumbnail {
                return URL(string: thumbnail.source)
            }
        } catch {
            // Silently fail for thumbnail fetching
        }
        
        return nil
    }
    
    // Convert namespace ID to human readable name (matching Android behavior)
    private func namespaceDisplayName(for namespaceId: Int) -> String {
        switch namespaceId {
        case 0: return "Main"
        case 1: return "Talk"
        case 2: return "User"
        case 3: return "User talk"
        case 4: return "OSRS Wiki"
        case 5: return "OSRS Wiki talk"
        case 6: return "File"
        case 7: return "File talk"
        case 8: return "MediaWiki"
        case 9: return "MediaWiki talk"
        case 10: return "Template"
        case 11: return "Template talk"
        case 12: return "Help"
        case 13: return "Help talk"
        case 14: return "Category"
        case 15: return "Category talk"
        default: return "Namespace \(namespaceId)"
        }
    }
}

// MARK: - Search Response Models
struct SearchResponse {
    let results: [SearchResult]
    let hasMore: Bool
    let totalCount: Int
}

enum SearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case networkUnavailable
    case timeout
    case rateLimited
    case serverError
    case networkError(URLError)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid search URL"
        case .invalidResponse:
            return "Invalid server response"
        case .networkUnavailable:
            return "No internet connection"
        case .timeout:
            return "Search request timed out"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .serverError:
            return "Server error. Please try again."
        case .networkError(let urlError):
            return urlError.localizedDescription
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - MediaWiki API Response Models
struct WikiSearchResponse: Codable {
    let query: WikiQuery
}

struct WikiQuery: Codable {
    let search: [WikiSearchResult]
    let searchinfo: WikiSearchInfo?
}

struct WikiSearchInfo: Codable {
    let totalhits: Int
}

struct WikiSearchResult: Codable {
    let ns: Int // Namespace - added to match Android
    let pageid: Int
    let title: String
    let snippet: String?
    let size: Int?
    let wordcount: Int? // Added to match Android
    let timestamp: String?
}

// Legacy thumbnail response (for single page requests)
struct WikiThumbnailResponse: Codable {
    let query: WikiThumbnailQuery?
}

struct WikiThumbnailQuery: Codable {
    let pages: [String: WikiPage]?
}

struct WikiPage: Codable {
    let thumbnail: WikiThumbnail?
}

// Batch thumbnail response (for multiple pages using pageids)
struct WikiBatchThumbnailResponse: Codable {
    let query: WikiBatchThumbnailQuery?
}

struct WikiBatchThumbnailQuery: Codable {
    let pages: [WikiBatchPage]
}

struct WikiBatchPage: Codable {
    let pageid: Int
    let thumbnail: WikiThumbnail?
}

struct WikiThumbnail: Codable {
    let source: String
    let width: Int?
    let height: Int?
}

// MARK: - Helper Extensions
extension String {
    func htmlStripped() -> String {
        // Remove HTML tags from snippet
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                  .replacingOccurrences(of: "&quot;", with: "\"")
                  .replacingOccurrences(of: "&amp;", with: "&")
                  .replacingOccurrences(of: "&lt;", with: "<")
                  .replacingOccurrences(of: "&gt;", with: ">")
    }
}

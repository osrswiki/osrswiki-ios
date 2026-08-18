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
    
    func search(
        query: String,
        limit: Int = 50,
        offset: Int = 0,
        onPartialResults: ((SearchResponse) -> Void)? = nil
    ) async throws -> SearchResponse {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchResponse(results: [], hasMore: false, totalCount: 0)
        }
        
        // Fulltext search misses title-prefix hits such as "earth ru" → Earth rune
        // (Cirrus ranks popular *rune* pages instead). OpenSearch/prefixsearch is
        // what the website search box uses. Fetch both in parallel on the first
        // page so typeahead ranking matches the web box without dropping
        // descriptive queries like "amulet glo".
        do {
            async let openSearchResult = fetchOpenSearchPagesIfNeeded(
                query: query,
                limit: min(limit, 10),
                offset: offset
            )
            async let prefixResult = offset == 0
                ? fetchGeneratedPages(
                    generator: "prefixsearch",
                    searchItemName: "gpssearch",
                    searchValue: SearchQueryPolicy.apiQuery(query),
                    limitItemName: "gpslimit",
                    limit: min(limit, 10),
                    offsetItemName: nil,
                    offset: 0,
                    extraItems: [],
                    includeExtracts: true
                )
                : SearchGeneratorPageFetch(pages: [], hasMore: false)
            async let fulltextResult = fetchGeneratedPages(
                generator: "search",
                searchItemName: "gsrsearch",
                searchValue: SearchQueryPolicy.networkQuery(query),
                limitItemName: "gsrlimit",
                limit: limit,
                offsetItemName: "gsroffset",
                offset: offset,
                extraItems: [
                    URLQueryItem(name: "gsrprop", value: "snippet|size|wordcount|timestamp"),
                    URLQueryItem(name: "gsrsort", value: "relevance")
                ],
                includeExtracts: false
            )

            let openSearchPages = await openSearchResult
            if offset == 0, let onPartialResults, !openSearchPages.isEmpty {
                onPartialResults(makeSearchResponse(
                    pages: openSearchPages,
                    offset: offset,
                    hasMore: true
                ))
            }
            let fulltextFetch = try await fulltextResult
            if offset == 0, let onPartialResults {
                onPartialResults(makeSearchResponse(
                    pages: SearchQueryPolicy.merge(prefix: [], fulltext: fulltextFetch.pages, for: query),
                    offset: offset,
                    hasMore: fulltextFetch.hasMore
                ))
            }
            let prefixFetch = try await prefixResult
            let rankedPages = SearchQueryPolicy.merge(
                prefix: prefixFetch.pages,
                fulltext: fulltextFetch.pages,
                for: query
            )
            return makeSearchResponse(
                pages: rankedPages,
                offset: offset,
                hasMore: fulltextFetch.hasMore
            )
            
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

    private struct SearchGeneratorPageFetch {
        let pages: [WikiGeneratedSearchPage]
        let hasMore: Bool
    }

    private func makeSearchResponse(
        pages: [WikiGeneratedSearchPage],
        offset: Int,
        hasMore: Bool
    ) -> SearchResponse {
        let searchResults = pages.map { apiResult in
            SearchResult(
                id: apiResult.pageid > 0 ? String(apiResult.pageid) : "title:\(apiResult.title)",
                title: apiResult.title,
                description: apiResult.snippet?.htmlStripped(),
                rawSnippet: apiResult.snippet,
                url: URL(string: "https://oldschool.runescape.wiki/w/\(apiResult.title.replacingOccurrences(of: " ", with: "_"))")!,
                thumbnailUrl: apiResult.thumbnail.flatMap { URL(string: $0.source) },
                ns: apiResult.ns,
                namespace: namespaceDisplayName(for: apiResult.ns),
                score: nil,
                index: apiResult.index,
                size: apiResult.size,
                wordcount: apiResult.wordcount,
                timestamp: apiResult.timestamp
            )
        }
        let totalHits = offset + searchResults.count + (hasMore ? 1 : 0)
        return SearchResponse(results: searchResults, hasMore: hasMore, totalCount: totalHits)
    }

    private func fetchOpenSearchPagesIfNeeded(query: String, limit: Int, offset: Int) async -> [WikiGeneratedSearchPage] {
        guard offset == 0 else { return [] }
        return (try? await fetchOpenSearchPages(query: query, limit: limit)) ?? []
    }

    private func fetchOpenSearchPages(query: String, limit: Int) async throws -> [WikiGeneratedSearchPage] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "redirects", value: "resolve"),
            URLQueryItem(name: "search", value: SearchQueryPolicy.apiQuery(query)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { throw SearchError.invalidURL }
        let (data, response) = try await NetworkManager.shared.performDataRequest(url: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SearchError.invalidResponse
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              root.count >= 3,
              let titles = root[1] as? [String] else {
            return []
        }
        let descriptions = root[2] as? [String] ?? []
        return titles.enumerated().map { index, title in
            let snippet = descriptions.indices.contains(index) ? descriptions[index] : nil
            return WikiGeneratedSearchPage(
                ns: 0,
                pageid: 0,
                title: title,
                index: index + 1,
                snippet: snippet?.isEmpty == false ? snippet : nil,
                size: nil,
                wordcount: nil,
                timestamp: nil,
                thumbnail: nil
            )
        }
    }

    private func fetchGeneratedPages(
        generator: String,
        searchItemName: String,
        searchValue: String,
        limitItemName: String,
        limit: Int,
        offsetItemName: String?,
        offset: Int,
        extraItems: [URLQueryItem],
        includeExtracts: Bool
    ) async throws -> SearchGeneratorPageFetch {
        var components = URLComponents(string: baseURL)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "redirects", value: "true"),
            URLQueryItem(name: "generator", value: generator),
            URLQueryItem(name: searchItemName, value: searchValue),
            URLQueryItem(name: limitItemName, value: String(limit)),
            URLQueryItem(name: "prop", value: includeExtracts ? "pageimages|extracts" : "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pilicense", value: "any"),
            URLQueryItem(name: "pithumbsize", value: "240")
        ]
        if includeExtracts {
            items.append(contentsOf: [
                URLQueryItem(name: "exintro", value: "1"),
                URLQueryItem(name: "explaintext", value: "1"),
                URLQueryItem(name: "exchars", value: "160"),
                URLQueryItem(name: "exlimit", value: "max")
            ])
        }
        if let offsetItemName, offset > 0 {
            items.append(URLQueryItem(name: offsetItemName, value: String(offset)))
        }
        items.append(contentsOf: extraItems)
        components.queryItems = items
        guard let url = components.url else {
            throw SearchError.invalidURL
        }

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

        let decoded = try JSONDecoder().decode(WikiGeneratedSearchResponse.self, from: data)
        return SearchGeneratorPageFetch(
            pages: decoded.query?.pages ?? [],
            hasMore: decoded.continuation?.gsroffset != nil
        )
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
            return "Search is unavailable right now. Please try again."
        case .invalidResponse:
            return "Search is unavailable right now. Please try again."
        case .networkUnavailable:
            return "No internet connection"
        case .timeout:
            return "Search request timed out"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .serverError:
            return "Search is unavailable right now. Please try again."
        case .networkError:
            return "Search is unavailable right now. Please try again."
        case .unknown:
            return "Something went wrong. Please try again."
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

struct WikiGeneratedSearchResponse: Codable {
    let continuation: WikiGeneratedSearchContinuation?
    let query: WikiGeneratedSearchQuery?

    enum CodingKeys: String, CodingKey {
        case continuation = "continue"
        case query
    }
}

struct WikiGeneratedSearchContinuation: Codable {
    let gsroffset: Int?
}

struct WikiGeneratedSearchQuery: Codable {
    let pages: [WikiGeneratedSearchPage]
}

struct WikiGeneratedSearchPage: Codable {
    enum CodingKeys: String, CodingKey {
        case ns, pageid, title, index, snippet, extract, size, wordcount, timestamp, thumbnail
    }

    let ns: Int
    let pageid: Int
    let title: String
    let index: Int
    let snippet: String?
    let extract: String?
    let size: Int?
    let wordcount: Int?
    let timestamp: String?
    let thumbnail: WikiThumbnail?

    init(
        ns: Int,
        pageid: Int,
        title: String,
        index: Int,
        snippet: String?,
        extract: String? = nil,
        size: Int?,
        wordcount: Int?,
        timestamp: String?,
        thumbnail: WikiThumbnail?
    ) {
        self.ns = ns
        self.pageid = pageid
        self.title = title
        self.index = index
        self.snippet = snippet
        self.extract = extract
        self.size = size
        self.wordcount = wordcount
        self.timestamp = timestamp
        self.thumbnail = thumbnail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ns = try container.decodeIfPresent(Int.self, forKey: .ns) ?? 0
        pageid = try container.decode(Int.self, forKey: .pageid)
        title = try container.decode(String.self, forKey: .title)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        extract = try container.decodeIfPresent(String.self, forKey: .extract)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        wordcount = try container.decodeIfPresent(Int.self, forKey: .wordcount)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        thumbnail = try container.decodeIfPresent(WikiThumbnail.self, forKey: .thumbnail)
    }

    func withPreviewFallback() -> WikiGeneratedSearchPage {
        let preview = firstNonBlank(snippet, extract)
        guard preview != snippet else { return self }
        return replacing(snippet: preview, extract: extract, thumbnail: thumbnail, size: size, wordcount: wordcount, timestamp: timestamp)
    }

    func enriched(with other: WikiGeneratedSearchPage) -> WikiGeneratedSearchPage {
        replacing(
            snippet: firstNonBlank(snippet, extract, other.snippet, other.extract),
            extract: firstNonBlank(extract, other.extract),
            thumbnail: thumbnail ?? other.thumbnail,
            size: size ?? other.size,
            wordcount: wordcount ?? other.wordcount,
            timestamp: timestamp ?? other.timestamp
        )
    }

    private func replacing(
        snippet: String?,
        extract: String?,
        thumbnail: WikiThumbnail?,
        size: Int?,
        wordcount: Int?,
        timestamp: String?
    ) -> WikiGeneratedSearchPage {
        WikiGeneratedSearchPage(
            ns: ns,
            pageid: pageid,
            title: title,
            index: index,
            snippet: snippet,
            extract: extract,
            size: size,
            wordcount: wordcount,
            timestamp: timestamp,
            thumbnail: thumbnail
        )
    }
}

private func firstNonBlank(_ values: String?...) -> String? {
    for value in values {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
    }
    return nil
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

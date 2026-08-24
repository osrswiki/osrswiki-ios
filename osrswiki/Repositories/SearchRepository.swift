//
//  SearchRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import Foundation

@MainActor
protocol osrsSearchDataClient: AnyObject {
    func fetchSearchBytes(from url: URL) async throws -> (Data, URLResponse)
}

extension NetworkManager: osrsSearchDataClient {
    func fetchSearchBytes(from url: URL) async throws -> (Data, URLResponse) {
        try await performDataRequest(url: url)
    }
}

@MainActor
class SearchRepository {
    private let baseURL = "https://oldschool.runescape.wiki/api.php"
    private let dataClient: osrsSearchDataClient

    init(dataClient: osrsSearchDataClient? = nil) {
        self.dataClient = dataClient ?? NetworkManager.shared
    }
    
    func search(
        query: String,
        limit: Int = 50,
        offset: Int = 0,
        scope: osrsSearchScope = .all,
        continueToken: String? = nil,
        onPartialResults: ((SearchResponse) -> Void)? = nil
    ) async throws -> SearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if scope.emptyQueryBrowsesNewest, let namespace = scope.namespace {
                return try await browseNewestPages(
                    namespace: namespace,
                    limit: limit,
                    continueToken: continueToken,
                    onPartialResults: onPartialResults
                )
            }
            return SearchResponse(results: [], hasMore: false, totalCount: 0)
        }

        if let namespace = scope.namespace {
            do {
                let fetch = try await fetchGeneratedPages(
                    generator: "search",
                    searchItemName: "gsrsearch",
                    searchValue: SearchQueryPolicy.networkQuery(trimmed),
                    limitItemName: "gsrlimit",
                    limit: limit,
                    offsetItemName: "gsroffset",
                    offset: offset,
                    extraItems: [
                        URLQueryItem(name: "gsrnamespace", value: String(namespace)),
                        URLQueryItem(name: "gsrprop", value: "snippet|size|wordcount|timestamp"),
                        URLQueryItem(name: "gsrsort", value: "relevance")
                    ],
                    includeExtracts: true,
                    followRedirects: false
                )
                return makeSearchResponse(
                    pages: fetch.pages
                        .filter { $0.ns == namespace }
                        .map { $0.withPreviewFallback() },
                    offset: offset,
                    hasMore: fetch.hasMore,
                    continueToken: fetch.continueToken
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
                }
                throw SearchError.unknown(error)
            }
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
                includeExtracts: true
            )

            let openSearchPages = await openSearchResult
            let fulltextFetch = try await fulltextResult
            let prefixFetch = try await prefixResult
            let rankedPages = SearchQueryPolicy.merge(
                prefix: prefixFetch.pages,
                fulltext: fulltextFetch.pages,
                for: query
            )
            return makeSearchResponse(
                pages: fillOpenSearchPreviews(pages: rankedPages, openSearchPages: openSearchPages)
                    .map { $0.withPreviewFallback() },
                offset: offset,
                hasMore: fulltextFetch.hasMore,
                continueToken: fulltextFetch.continueToken
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
        let continueToken: String?

        init(pages: [WikiGeneratedSearchPage], hasMore: Bool, continueToken: String? = nil) {
            self.pages = pages
            self.hasMore = hasMore
            self.continueToken = continueToken
        }
    }

    private func makeSearchResponse(
        pages: [WikiGeneratedSearchPage],
        offset: Int,
        hasMore: Bool,
        continueToken: String? = nil
    ) -> SearchResponse {
        let searchResults = pages.map { apiResult in
            let preview = osrsSearchPreviewText.fromCandidates(apiResult.snippet, apiResult.extract)
            return SearchResult(
                id: apiResult.pageid > 0 ? String(apiResult.pageid) : "title:\(apiResult.title)",
                title: apiResult.title,
                description: preview?.htmlStripped(),
                rawSnippet: preview,
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
        return SearchResponse(
            results: searchResults,
            hasMore: hasMore,
            totalCount: totalHits,
            continueToken: continueToken
        )
    }

    private func fillOpenSearchPreviews(
        pages: [WikiGeneratedSearchPage],
        openSearchPages: [WikiGeneratedSearchPage]
    ) -> [WikiGeneratedSearchPage] {
        guard !openSearchPages.isEmpty else { return pages }
        return pages.map { page in
            if osrsSearchPreviewText.fromCandidates(page.snippet, page.extract) != nil { return page }
            guard let open = openSearchPages.first(where: {
                $0.title.compare(page.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                return page
            }
            return page.enriched(with: open)
        }
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
        let (data, response) = try await dataClient.fetchSearchBytes(from: url)
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
        includeExtracts: Bool,
        followRedirects: Bool = true,
        enrichMissingPreviews: Bool = true
    ) async throws -> SearchGeneratorPageFetch {
        var components = URLComponents(string: baseURL)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: generator),
            URLQueryItem(name: searchItemName, value: searchValue),
            URLQueryItem(name: limitItemName, value: String(limit)),
            URLQueryItem(name: "prop", value: includeExtracts ? "pageimages|extracts" : "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pilicense", value: "any"),
            URLQueryItem(name: "pithumbsize", value: "240")
        ]
        if followRedirects {
            items.append(URLQueryItem(name: "redirects", value: "true"))
        }
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

        let (data, response) = try await dataClient.fetchSearchBytes(from: url)
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
        let continueToken = decoded.continuation?.gsroffset.map(String.init)
            ?? decoded.continuation?.grccontinue
        let pages = decoded.query?.pages ?? []
        let resolved: [WikiGeneratedSearchPage]
        if includeExtracts && enrichMissingPreviews {
            resolved = await self.enrichMissingPreviews(pages.map { $0.withPreviewFallback() })
        } else if includeExtracts {
            resolved = pages.map { $0.withPreviewFallback() }
        } else {
            resolved = pages
        }
        return SearchGeneratorPageFetch(
            pages: resolved,
            hasMore: continueToken != nil,
            continueToken: continueToken
        )
    }

    private func enrichMissingPreviews(_ pages: [WikiGeneratedSearchPage]) async -> [WikiGeneratedSearchPage] {
        let missingIds = pages.compactMap { page -> Int? in
            osrsSearchPreviewText.fromCandidates(page.snippet, page.extract) == nil ? page.pageid : nil
        }.filter { $0 > 0 }
        guard !missingIds.isEmpty else { return pages }

        var byId = Dictionary(uniqueKeysWithValues: pages.map { ($0.pageid, $0) })
        if let extracts = try? await fetchPlainExtracts(pageIds: missingIds) {
            for (pageId, extract) in extracts {
                guard let preview = osrsSearchPreviewText.fromPlainExtract(extract),
                      let existing = byId[pageId] else { continue }
                byId[pageId] = existing.withResolvedPreview(preview)
            }
        }
        let stillMissing = missingIds.filter { pageId in
            osrsSearchPreviewText.fromCandidates(byId[pageId]?.snippet, byId[pageId]?.extract) == nil
        }
        await withTaskGroup(of: (Int, String?).self) { group in
            for pageId in stillMissing {
                group.addTask {
                    let html = try? await self.fetchParseHtml(pageId: pageId)
                    return (pageId, osrsSearchPreviewText.fromHtml(html))
                }
            }
            for await (pageId, preview) in group {
                guard let preview, let existing = byId[pageId] else { continue }
                byId[pageId] = existing.withResolvedPreview(preview)
            }
        }
        return pages.map { byId[$0.pageid] ?? $0 }
    }

    private func fetchPlainExtracts(pageIds: [Int]) async throws -> [Int: String] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exchars", value: "280"),
            URLQueryItem(name: "exlimit", value: "max"),
            URLQueryItem(name: "pageids", value: pageIds.map(String.init).joined(separator: "|"))
        ]
        guard let url = components.url else { throw SearchError.invalidURL }
        let (data, response) = try await dataClient.fetchSearchBytes(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SearchError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(WikiGeneratedSearchResponse.self, from: data)
        var extracts: [Int: String] = [:]
        for page in decoded.query?.pages ?? [] {
            if let extract = page.extract, !extract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extracts[page.pageid] = extract
            }
        }
        return extracts
    }

    private func fetchParseHtml(pageId: Int) async throws -> String? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "prop", value: "text"),
            URLQueryItem(name: "disablelimitreport", value: "1"),
            URLQueryItem(name: "pageid", value: String(pageId))
        ]
        guard let url = components.url else { throw SearchError.invalidURL }
        let (data, response) = try await dataClient.fetchSearchBytes(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SearchError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(WikiParsePreviewResponse.self, from: data)
        return decoded.parse?.text
    }

    private struct WikiParsePreviewResponse: Decodable {
        struct Parse: Decodable {
            let text: String?
        }
        let parse: Parse?
    }

    private func browseNewestPages(
        namespace: Int,
        limit: Int,
        continueToken: String?,
        onPartialResults: ((SearchResponse) -> Void)? = nil
    ) async throws -> SearchResponse {
        do {
            var extraItems = [
                URLQueryItem(name: "grctype", value: "new"),
                URLQueryItem(name: "grcdir", value: "older")
            ]
            if let continueToken, !continueToken.isEmpty {
                extraItems.append(URLQueryItem(name: "grccontinue", value: continueToken))
            }
            let fetch = try await fetchGeneratedPages(
                generator: "recentchanges",
                searchItemName: "grcnamespace",
                searchValue: String(namespace),
                limitItemName: "grclimit",
                limit: limit,
                offsetItemName: nil,
                offset: 0,
                extraItems: extraItems,
                includeExtracts: true,
                followRedirects: false,
                enrichMissingPreviews: false
            )
            let firstPages = fetch.pages
                .filter { $0.ns == namespace }
                .map { $0.withPreviewFallback() }
            let firstResponse = makeSearchResponse(
                pages: firstPages,
                offset: 0,
                hasMore: fetch.hasMore,
                continueToken: fetch.continueToken
            )
            onPartialResults?(firstResponse)
            let enriched = await enrichMissingPreviews(firstPages)
            return makeSearchResponse(
                pages: enriched,
                offset: 0,
                hasMore: fetch.hasMore,
                continueToken: fetch.continueToken
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
        case 112: return "Update"
        default: return "Namespace \(namespaceId)"
        }
    }
}

// MARK: - Search Response Models
struct SearchResponse {
    let results: [SearchResult]
    let hasMore: Bool
    let totalCount: Int
    let continueToken: String?

    init(results: [SearchResult], hasMore: Bool, totalCount: Int, continueToken: String? = nil) {
        self.results = results
        self.hasMore = hasMore
        self.totalCount = totalCount
        self.continueToken = continueToken
    }
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
    let grccontinue: String?
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
        let preview = osrsSearchPreviewText.fromCandidates(snippet, extract)
        guard preview != snippet else { return self }
        return replacing(snippet: preview, extract: extract, thumbnail: thumbnail, size: size, wordcount: wordcount, timestamp: timestamp)
    }

    func withResolvedPreview(_ preview: String) -> WikiGeneratedSearchPage {
        replacing(
            snippet: preview,
            extract: firstNonBlank(extract, preview),
            thumbnail: thumbnail,
            size: size,
            wordcount: wordcount,
            timestamp: timestamp
        )
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

//
//  SearchViewModel.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var themedSearchResults: [ThemedSearchResult] = [] // FREEZE FIX: Pre-processed themed results
    @Published var recentSearches: [String] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    @Published var hasMoreResults: Bool = false
    @Published var totalResultCount: Int = 0
    @Published var currentQuery: String = ""
    
    private let searchRepository = SearchRepository()
    private let historyRepository = HistoryRepository()
    private var cancellables = Set<AnyCancellable>()
    private var currentSearchTask: Task<Void, Never>?
    private var searchOffset = 0
    private let searchLimit = 20
    private let recentSearchesKey = "recent_searches"
    
    // Navigation callback - will be set by the view
    var navigateToArticle: ((String, URL, SearchResult?) -> Void)?
    
    init() {
        PerformanceTimer.shared.start("SearchViewModel.init")
        
        PerformanceTimer.shared.start("loadRecentSearches")
        loadRecentSearches()
        _ = PerformanceTimer.shared.end("loadRecentSearches")
        
        PerformanceTimer.shared.start("setupSearchDebouncing")
        setupSearchDebouncing()
        _ = PerformanceTimer.shared.end("setupSearchDebouncing")
        
        _ = PerformanceTimer.shared.end("SearchViewModel.init")
    }
    
    private func setupSearchDebouncing() {
        // Fixed: Use debounced search to prevent rapid API calls and UI conflicts
        $currentQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main) // Faster than 500ms but prevents conflicts
            .removeDuplicates()
            .sink { [weak self] query in
                Task { @MainActor in
                    await self?.performSearch(query: query, isNewSearch: true)
                }
            }
            .store(in: &cancellables)
    }
    
    func performSearch(query: String, isNewSearch: Bool = true) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearchResults()
            return
        }
        
        // Cancel previous search if it's still running
        currentSearchTask?.cancel()
        
        // CRASH FIX: Atomic state updates to prevent race conditions during list rendering
        if isNewSearch {
            await Task.yield() // Let other UI updates complete
            searchOffset = 0
            searchResults = []
            themedSearchResults = []
            errorMessage = nil
            hasMoreResults = false
            totalResultCount = 0
        }
        
        isSearching = true
        
        currentSearchTask = Task {
            do {
                let response = try await searchRepository.search(
                    query: trimmedQuery,
                    limit: searchLimit,
                    offset: searchOffset
                )
                
                guard !Task.isCancelled else { 
                    // CRASH FIX: Clean up state on cancellation
                    await MainActor.run {
                        isSearching = false
                    }
                    return 
                }
                
                // FREEZE FIX: Process results on background thread, then update UI atomically
                let processedResults = await processSearchResultsInBackground(
                    results: response.results, 
                    searchQuery: trimmedQuery,
                    isNewSearch: isNewSearch
                )
                
                // CRASH FIX: Atomic array updates to prevent list rendering conflicts
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    if isNewSearch {
                        self.searchResults = response.results
                        self.themedSearchResults = processedResults
                    } else {
                        // Use batch update to prevent intermediate states
                        var updatedResults = self.searchResults
                        var updatedThemedResults = self.themedSearchResults
                        updatedResults.append(contentsOf: response.results)
                        updatedThemedResults.append(contentsOf: processedResults)
                        self.searchResults = updatedResults
                        self.themedSearchResults = updatedThemedResults
                    }
                    
                    self.totalResultCount = response.totalCount
                    self.hasMoreResults = response.hasMore
                    self.searchOffset += response.results.count
                }
                
            } catch let error as SearchError {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                if isNewSearch {
                    searchResults = []
                    themedSearchResults = []
                    hasMoreResults = false
                    totalResultCount = 0
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Search failed: \(error.localizedDescription)"
                if isNewSearch {
                    searchResults = []
                    themedSearchResults = []
                    hasMoreResults = false
                    totalResultCount = 0
                }
            }
            
            isSearching = false
        }
    }
    
    func loadMoreResults() async {
        guard hasMoreResults && !isSearching && !currentQuery.isEmpty else { return }
        await performSearch(query: currentQuery, isNewSearch: false)
    }
    
    func selectSearchResult(_ result: SearchResult) {
        // Navigate to article view - history will be tracked by ArticleViewModel
        navigateToArticle?(result.title, result.url, result)
    }
    
    // FREEZE FIX: Helper to find SearchResult by ThemedSearchResult
    func selectThemedSearchResult(_ themedResult: ThemedSearchResult) {
        // Find corresponding SearchResult by matching URL or pageId
        if let matchingResult = searchResults.first(where: { 
            $0.url.absoluteString == themedResult.url || 
            (themedResult.pageId != nil && $0.id == String(themedResult.pageId!))
        }) {
            selectSearchResult(matchingResult)
        }
    }
    
    func addToRecentSearches(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        let queryKey = recentSearchKey(for: trimmedQuery)
        
        // Remove any existing variant so the most recent spelling/casing wins.
        recentSearches = normalizedRecentSearches(recentSearches)
        recentSearches.removeAll { recentSearchKey(for: $0) == queryKey }
        
        // Add to beginning
        recentSearches.insert(trimmedQuery, at: 0)
        
        // Keep only last 10
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        
        saveRecentSearches()
    }
    
    func clearRecentSearches() {
        recentSearches.removeAll()
        saveRecentSearches()
    }
    
    func clearSearchResults() {
        searchResults.removeAll()
        themedSearchResults.removeAll() // FREEZE FIX: Clear themed results too
        hasMoreResults = false
        totalResultCount = 0
        searchOffset = 0
        errorMessage = nil
    }
    
    func navigateToPage(_ pageTitle: String) {
        // Implementation would navigate to the page
        // For now, this is a placeholder
    }
    
    
    private func loadRecentSearches() {
        if let saved = UserDefaults.standard.array(forKey: recentSearchesKey) as? [String] {
            recentSearches = normalizedRecentSearches(saved)
            if recentSearches != saved {
                saveRecentSearches()
            }
        }
    }
    
    private func saveRecentSearches() {
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    private func normalizedRecentSearches(_ searches: [String]) -> [String] {
        var seenKeys = Set<String>()
        var normalized: [String] = []

        for search in searches {
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = recentSearchKey(for: trimmedSearch)
            guard !trimmedSearch.isEmpty, !seenKeys.contains(key) else { continue }

            seenKeys.insert(key)
            normalized.append(trimmedSearch)

            if normalized.count == 10 {
                break
            }
        }

        return normalized
    }

    private func recentSearchKey(for query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    
    // FREEZE FIX: Process search results on background thread to avoid blocking main thread
    private func processSearchResultsInBackground(
        results: [SearchResult],
        searchQuery: String,
        isNewSearch: Bool
    ) async -> [ThemedSearchResult] {
        return await withTaskGroup(of: ThemedSearchResult.self, returning: [ThemedSearchResult].self) { group in
            for result in results {
                group.addTask {
                    // Create ThemedSearchResult on background thread
                    return ThemedSearchResult(
                        title: result.displayTitle,
                        snippet: result.rawSnippet,
                        description: result.namespace,
                        url: result.url.absoluteString,
                        thumbnailUrl: result.thumbnailUrl,
                        pageId: Int(result.id),
                        searchQuery: searchQuery
                    )
                }
            }
            
            var processedResults: [ThemedSearchResult] = []
            for await themedResult in group {
                processedResults.append(themedResult)
            }
            
            // Maintain original order by sorting by pageId if available
            return processedResults.sorted { lhs, rhs in
                guard let lhsPageId = lhs.pageId, let rhsPageId = rhs.pageId else {
                    return false
                }
                return results.firstIndex { $0.id == String(lhsPageId) } ?? 0 <
                       results.firstIndex { $0.id == String(rhsPageId) } ?? 0
            }
        }
    }
}

// MARK: - Models
struct SearchResult: Identifiable, Codable {
    let id: String
    let title: String
    let description: String? // HTML-stripped version for fallback
    let rawSnippet: String? // Raw HTML snippet with <span class="searchmatch"> tags
    let url: URL
    var thumbnailUrl: URL? // Made mutable for batch thumbnail updates
    let ns: Int? // Namespace ID to match Android exactly
    let namespace: String? // Human readable namespace
    let score: Double?
    let index: Int? // Added to preserve search ranking order
    let size: Int? // Added to match Android
    let wordcount: Int? // Added to match Android
    let timestamp: String? // Added to match Android
    
    var displayTitle: String {
        return title.replacingOccurrences(of: "_", with: " ")
    }
}

struct HistoryItem: Identifiable, Codable {
    let id: String
    let pageTitle: String
    let pageUrl: URL
    let visitedDate: Date
    let thumbnailUrl: URL?
    let description: String?
    
    var displayTitle: String {
        return pageTitle.replacingOccurrences(of: "_", with: " ")
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: visitedDate, relativeTo: Date())
    }
}

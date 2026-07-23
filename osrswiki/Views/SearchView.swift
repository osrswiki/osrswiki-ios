//
//  SearchView.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import UIKit

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @StateObject private var viewModel = SearchViewModel()
    // Use shared speech manager from AppState to prevent resource conflicts
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var searchInputMinHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var searchTextFieldMinHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .subheadline) private var recentChipMinHeight: CGFloat = 44
    
    // Unified alert system to handle both search and voice search errors  
    @State private var showingAlert = false
    @State private var currentAlertType: AlertType = .search
    
    enum AlertType {
        case search
        case voiceSearch
    }
    
    var body: some View {
        NavigationStack(path: $appState.searchNavigationStack) {
            ZStack {
                // Full-screen background to prevent white areas
                Color(osrsTheme.background)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    osrsAccessibilityMarker(identifier: "search_screen", label: "Search screen")

                    // Search input section
                    searchInputSection
                    
                    // Content section
                    contentSection
                }

            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Set up navigation callback with weak references to prevent retain cycles
                viewModel.navigateToArticle = { [weak appState] title, url, searchResult in
                    guard let appState = appState else { return }
                    
                    // Dismiss keyboard before navigation to prevent blank area
                    // Note: Cannot use weak reference to @State properties directly in closures
                    // The keyboard dismissal is handled by the SearchResultRowView tap action
                    
                    if let searchResult = searchResult {
                        // Use rich navigation with metadata for search results
                        appState.navigateToArticle(
                            title: title,
                            url: url,
                            snippet: searchResult.description,
                            thumbnailUrl: searchResult.thumbnailUrl
                        )
                    } else {
                        // Fallback to simple navigation
                        appState.navigateToArticle(title: title, url: url)
                    }
                }
                
                // Set up voice search callbacks
                setupVoiceSearch()
                
                #if DEBUG
                if !osrsTestEnvironment.disablesSearchAutofocusForUITests {
                    isSearchFocused = true
                }
                #else
                isSearchFocused = true
                #endif
            }
            .onDisappear {
                // Dismiss keyboard to prevent blank area when navigating back
                isSearchFocused = false
                dismissKeyboardWithLayoutUpdate()
                
                // Clean up speech recognition when leaving the view
                appState.speechManager.cleanup()
                
                // Clear navigation callback to prevent retain cycles
                viewModel.navigateToArticle = nil
            }
            .dismissKeyboardOnDisappear()
            .navigationDestination(for: SearchNavigationDestination.self) { destination in
                switch destination {
                case .article(let articleDestination):
                    ArticleView(
                        pageTitle: articleDestination.title,
                        pageUrl: articleDestination.url,
                        navigationIdentity: articleDestination.navigationIdentity,
                        snippet: articleDestination.snippet,
                        thumbnailUrl: articleDestination.thumbnailUrl,
                        savedPageId: articleDestination.savedPageId
                    )
                    .id(articleDestination.navigationIdentity)
                    .environmentObject(appState)
                    .environmentObject(themeManager)
                    .environment(\.osrsTheme, osrsTheme)
                }
            }
        }
    }

    private var searchInputSection: some View {
        VStack(spacing: 12) {
            // Main search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.osrsPlaceholderColor)
                
                TextField("Search OSRS Wiki", text: $searchText, axis: .vertical)
                    .focused($isSearchFocused)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.body)
                    .dynamicTypeSize(.xSmall ... .xLarge)
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .lineLimit(1...2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: searchTextFieldMinHeight)
                    .accessibilityIdentifier("search_input")
                    .onChange(of: searchText) { _, newValue in
                        viewModel.currentQuery = newValue
                    }
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.osrsSecondaryTextColor)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Clear search")
                }
                
                osrsVoiceSearchButton(
                    action: {
                        appState.speechManager.startVoiceRecognition()
                    },
                    state: appState.speechManager.currentState
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .frame(minHeight: searchInputMinHeight)
            .background(.osrsSearchBoxBackgroundColor)
            .cornerRadius(18)
            .padding(.horizontal)
            
            // Recent searches or suggestions
            if searchText.isEmpty && !viewModel.recentSearches.isEmpty {
                recentSearchesSection
            }
        }
        .background(.osrsBackground)
    }
    
    private var contentSection: some View {
        Group {
            if searchText.isEmpty {
                if dynamicTypeSize.isAccessibilitySize && !viewModel.recentSearches.isEmpty {
                    Color(osrsTheme.background)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Show empty state when no search text (history now belongs in History tab)
                    ScrollView {
                        emptySearchState
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            } else if viewModel.isSearching && viewModel.searchResults.isEmpty {
                // Show loading during initial search
                ProgressView("Searching...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .tint(.osrsPrimaryColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty && !searchText.isEmpty && !viewModel.isSearching {
                // Show no results
                EmptyStateView(
                    iconName: "magnifyingglass",
                    title: "No Results",
                    subtitle: "Try different search terms"
                )
            } else {
                // Show search results with error handling
                searchResultsSection
            }
        }
        .alert(alertTitle, 
               isPresented: $showingAlert) {
            Button("OK") { 
                clearCurrentAlert()
            }
        } message: {
            Text(alertMessage)
        }
        .onReceive(viewModel.$errorMessage) { errorMessage in
            if let _ = errorMessage {
                currentAlertType = .search
                showingAlert = true
            }
        }
        .onReceive(appState.speechManager.$errorMessage) { errorMessage in
            if let _ = errorMessage {
                currentAlertType = .voiceSearch
                showingAlert = true
            }
        }
    }
    
    // MARK: - Alert System
    
    private var alertTitle: String {
        switch currentAlertType {
        case .search:
            return "Search Error"
        case .voiceSearch:
            return "Voice Search Error"
        }
    }
    
    private var alertMessage: String {
        switch currentAlertType {
        case .search:
            return viewModel.errorMessage ?? ""
        case .voiceSearch:
            return appState.speechManager.errorMessage ?? ""
        }
    }
    
    private func clearCurrentAlert() {
        switch currentAlertType {
        case .search:
            viewModel.errorMessage = nil
        case .voiceSearch:
            appState.speechManager.clearError()
        }
        showingAlert = false
    }
    
    // MARK: - View Sections
    
    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Searches")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Button("Clear") {
                    viewModel.clearRecentSearches()
                }
                .font(.subheadline)
                .foregroundStyle(.osrsPrimary)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.recentSearches.prefix(5), id: \.self) { search in
                        Button {
                            searchText = search
                            performSearch()
                        } label: {
                            Text(search)
                                .font(.subheadline)
                                .foregroundStyle(.osrsPrimaryTextColor)
                                .padding(.horizontal, 14)
                                .frame(minHeight: recentChipMinHeight)
                                .background(.osrsSearchBoxBackgroundColor)
                                .cornerRadius(16)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .frame(minHeight: recentChipMinHeight + 12)
        }
    }
    
    private var emptySearchState: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 24) {
            osrsAccessibilityMarker(identifier: "search_empty_state", label: "Search empty state")

            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundStyle(.osrsSecondaryTextColor)
            }
            
            Text("Search OSRS Wiki")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.osrsPrimaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            
            Text("Enter a search term to find articles, items, quests, and more.")
                .font(.body)
                .foregroundStyle(.osrsPrimaryTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 20 : 40)
            
        }
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 20 : 56)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(.osrsBackground)
    }
    
    private var searchResultsSection: some View {
        VStack(spacing: 0) {
            List {
                // FREEZE FIX: Use pre-processed themed results to avoid expensive processing on main thread
                ForEach(viewModel.themedSearchResults, id: \.id) { themedResult in
                    SearchResultRowView(result: themedResult) {
                        // FREEZE DEBUG: Add precise logging for tap flow tracing
                        let timestamp = DateFormatter.timeFormatter.string(from: Date())
                        print("🟡 [\(timestamp)] SEARCHVIEW TAP START: SearchView tap handler called for '\(themedResult.processedTitle)'")
                        
                        // Dismiss keyboard before selecting result
                        isSearchFocused = false
                        dismissKeyboard()
                        
                        print("🟡 [\(timestamp)] SEARCHVIEW: About to call selectThemedSearchResult")
                        
                        // FREEZE FIX: Use themedResult selection to avoid main thread processing
                        viewModel.selectThemedSearchResult(themedResult)
                        viewModel.addToRecentSearches(searchText)
                        
                        let completedTimestamp = DateFormatter.timeFormatter.string(from: Date())
                        print("🟡 [\(completedTimestamp)] SEARCHVIEW TAP END: SearchView tap handler completed")
                    }
                    .id(themedResult.id) // CRASH FIX: Use ThemedSearchResult's stable ID
                }
                
                // FIXED: Load more section with proper state management to prevent cell conflicts
                if viewModel.hasMoreResults && !viewModel.isSearching {
                    // Only show load more when not actively searching to prevent state conflicts
                    HStack {
                        Spacer()
                        Button("Load More Results") {
                            // Prevent multiple simultaneous load operations
                            guard !viewModel.isSearching else { return }
                            Task { @MainActor in
                                await viewModel.loadMoreResults()
                            }
                        }
                        .disabled(viewModel.isSearching) // Prevent conflicts during loading
                        .foregroundStyle(viewModel.isSearching ? Color.gray : Color(osrsTheme.primary))
                        Spacer()
                    }
                    .padding()
                    .listRowBackground(osrsTheme.surface)
                    // FIXED: Use consistent ID that doesn't change during updates
                    .id("load-more-section")
                } else if viewModel.isSearching && viewModel.hasMoreResults {
                    // Show loading indicator in separate section to prevent ID conflicts
                    HStack {
                        Spacer()
                        ProgressView("Loading more results...")
                            .scaleEffect(0.8)
                            .tint(osrsTheme.primary)
                        Spacer()
                    }
                    .padding()
                    .listRowBackground(osrsTheme.surface)
                    .id("loading-more-section")
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(.osrsBackground)
            // FIXED: Remove animation on count changes that can cause cell dequeue issues
            // Animation during rapid updates can cause SwiftUI to lose track of cells
        }
        .accessibilityIdentifier("search_results")
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Add to recent searches when user explicitly submits
        viewModel.addToRecentSearches(searchText)
        
        // FIXED: Add slight delay to ensure UI state is consistent before starting search
        Task {
            // Brief delay to let any pending UI updates complete
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await viewModel.performSearch(query: searchText, isNewSearch: true)
        }
    }
    
    private func clearSearch() {
        searchText = ""
        viewModel.currentQuery = ""
        viewModel.clearSearchResults()
    }
    
    private func setupVoiceSearch() {
        // Use weak references to prevent retain cycles with shared speech manager
        appState.speechManager.configure(
            onResult: { [weak viewModel] result in
                guard let viewModel = viewModel else { return }
                
                // Set the search text and perform search
                // Note: Cannot use weak reference to @State properties directly
                // The view will update through the viewModel
                Task { @MainActor in
                    viewModel.currentQuery = result
                    await viewModel.performSearch(query: result)
                }
            },
            onPartialResult: { [weak viewModel] partialResult in
                guard let viewModel = viewModel else { return }
                
                // Show real-time transcription in search field
                if !partialResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { @MainActor in
                        viewModel.currentQuery = partialResult
                    }
                }
            },
            onError: { errorMessage in
                // Error handling is managed by the speech manager's published errorMessage
                print("Voice search error: \(errorMessage)")
            }
        )
    }
}

#Preview {
    SearchView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

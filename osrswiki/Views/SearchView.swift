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
    @StateObject private var historyViewModel = HistoryViewModel()
    // Use shared speech manager from AppState to prevent resource conflicts
    @State private var searchText = ""
    @State private var isSearchMode = false
    @State private var isSearchFocused = false
    @State private var searchViewAppeared = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var recentRowMinHeight: CGFloat = 44
    
    // Unified alert system to handle both search and voice search errors  
    @State private var showingAlert = false
    @State private var showingClearConfirmation = false
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

                    if isSearchMode {
                        if !searchText.isEmpty {
                            contentSection
                        } else if !viewModel.recentSearches.isEmpty {
                            recentSearchesSection
                        } else {
                            historyContent
                                .accessibilityIdentifier("search_active_canvas")
                        }
                    } else {
                        historyContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .osrsInteractiveBackSwipe(
                enabled: isSearchMode && appState.searchNavigationStack.isEmpty,
                onBack: { exitActiveSearch() }
            )
            .osrsTabGlassAccessoryBar {
                if isSearchMode {
                    activeSearchToolbar
                } else {
                    searchLauncher
                }
            }
            .alert("Clear History", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    historyViewModel.clearAllHistory()
                }
            } message: {
                Text("This will permanently delete all your reading history. This action cannot be undone.")
            }
            .onAppear {
                searchViewAppeared = true
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

                activatePendingSearchIntentIfNeeded()
                
                historyViewModel.loadHistory()
            }
            .onChange(of: appState.pendingSearchActivationIntent) { _, _ in
                activatePendingSearchIntentIfNeeded()
            }
            .onDisappear {
                searchViewAppeared = false
                // A Search-tab layout pass can disappear while an article→search
                // handoff is still pending. Only cancel when leaving Search.
                if appState.selectedTab != .search {
                    appState.cancelSearchActivationIntent()
                    appState.invalidateActiveSearchReturnContext()
                }
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
        .osrsResumedNavigationHost(appState.navigationHostGeneration)
    }

    private var searchLauncher: some View {
        osrsTabSearchWithTrailingControl(
            search: osrsSearchLauncher(
                placeholder: "Search OSRS Wiki",
                accessibilityIdentifier: "search_history_launcher",
                voiceAccessibilityIdentifier: "search_history_voice_search",
                speechState: appState.speechManager.currentState,
                onSearchTap: {
                    isSearchMode = true
                    DispatchQueue.main.async { isSearchFocused = true }
                },
                onVoiceTap: {
                    isSearchMode = true
                    DispatchQueue.main.async {
                        isSearchFocused = true
                        appState.speechManager.startVoiceRecognition()
                    }
                }
            )
        ) {
            osrsGlassIconButton(
                systemImage: "trash",
                accessibilityLabel: "Clear search history",
                accessibilityIdentifier: "search_history_clear_button",
                action: { showingClearConfirmation = true }
            )
            .disabled(historyViewModel.historyItems.isEmpty)
            .opacity(historyViewModel.historyItems.isEmpty ? 0.4 : 1)
        }
    }

    private var activeSearchToolbar: some View {
        osrsActiveSearchToolbar(
            text: $searchText,
            isFocused: $isSearchFocused,
            placeholder: "Search OSRS Wiki",
            backAccessibilityLabel: "Back to search history",
            backAccessibilityIdentifier: "search_back_button",
            inputAccessibilityIdentifier: "search_input",
            clearAccessibilityIdentifier: "search_clear_button",
            voiceAccessibilityIdentifier: "search_voice_search",
            speechState: appState.speechManager.currentState,
            onBack: { exitActiveSearch() },
            onClear: clearSearch,
            onVoiceTap: { appState.speechManager.startVoiceRecognition() },
            onSubmit: performSearch
        )
        .onChange(of: searchText) { _, value in viewModel.currentQuery = value }
    }

    private var historyContent: some View {
        Group {
            if historyViewModel.historyItems.isEmpty {
                EmptyStateView(
                    iconName: "clock",
                    title: "No Search History",
                    subtitle: "Articles you open will appear here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyViewModel.historyItems) { item in
                            switch item {
                            case .dateHeader(let date):
                                HistoryDateHeaderView(dateString: date)
                                    .background(Color(osrsTheme.background))
                            case .entryItem(let entry):
                                HistoryEntryRowView(entry: entry, onTap: {
                                    guard let url = URL(string: entry.wikiUrl) else { return }
                                    appState.navigateToArticle(
                                        title: entry.displayText,
                                        url: url,
                                        snippet: entry.snippet,
                                        thumbnailUrl: entry.thumbnailUrl
                                    )
                                }, onDelete: {
                                    historyViewModel.removeHistoryEntry(entry)
                                })
                                .background(Color(osrsTheme.surface))
                            }
                        }
                    }
                }
                .scrollPosition($appState.searchHistoryScrollPosition)
                .scrollContentBackground(.hidden)
                .background(Color(osrsTheme.background))
            }
        }
        .background(Color(osrsTheme.background))
    }

    private var contentSection: some View {
        Group {
            if searchText.isEmpty {
                if !viewModel.recentSearches.isEmpty {
                    // Match Android: once real history rows are present, let those rows be the
                    // content instead of repeating a large generic empty-state prompt below them.
                    Color(osrsTheme.background)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Show empty state when no search text (history now belongs in History tab)
                    ScrollView {
                        emptySearchState
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            } else if viewModel.searchResults.isEmpty && !viewModel.hasCompletedCurrentQuery {
                // Keep the canvas quiet during the very short live request instead of flashing a
                // spinner between every keystroke.
                Color(osrsTheme.background)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty && !searchText.isEmpty {
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
                Text("Recent")
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
            
            VStack(spacing: 0) {
                ForEach(viewModel.recentSearches.prefix(5), id: \.self) { search in
                    Button {
                        searchText = search
                        performSearch()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body)
                                .foregroundStyle(.osrsSecondaryTextColor)
                                .frame(width: 24, height: 24)
                            Text(search)
                                .font(.body)
                                .foregroundStyle(.osrsPrimaryTextColor)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: recentRowMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(search)

                    // Android recent-query rows have no hairline. Do not add one here.
                }
            }
            .background(.osrsSurface)
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.themedSearchResults, id: \.id) { themedResult in
                        SearchResultRowView(result: themedResult) {
                            let timestamp = DateFormatter.timeFormatter.string(from: Date())
                            print("🟡 [\(timestamp)] SEARCHVIEW TAP START: SearchView tap handler called for '\(themedResult.processedTitle)'")
                            isSearchFocused = false
                            dismissKeyboard()
                            print("🟡 [\(timestamp)] SEARCHVIEW: About to call selectThemedSearchResult")
                            viewModel.selectThemedSearchResult(themedResult)
                            viewModel.addToRecentSearches(searchText)
                            let completedTimestamp = DateFormatter.timeFormatter.string(from: Date())
                            print("🟡 [\(completedTimestamp)] SEARCHVIEW TAP END: SearchView tap handler completed")
                        }
                        .id(themedResult.id)
                    }

                    if viewModel.hasMoreResults && !viewModel.isSearching {
                        HStack {
                            Spacer()
                            Button("Load More Results") {
                                guard !viewModel.isSearching else { return }
                                Task { @MainActor in
                                    await viewModel.loadMoreResults()
                                }
                            }
                            .disabled(viewModel.isSearching)
                            .foregroundStyle(viewModel.isSearching ? Color.gray : Color(osrsTheme.primary))
                            Spacer()
                        }
                        .padding()
                        .id("load-more-section")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.osrsBackground)
        }
        .accessibilityIdentifier("search_results")
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Add to recent searches when user explicitly submits
        viewModel.addToRecentSearches(searchText)
        
        Task {
            await viewModel.performSearch(query: searchText, isNewSearch: true)
        }
    }
    
    private func exitActiveSearch() {
        isSearchFocused = false
        clearSearch()
        isSearchMode = false
        if appState.returnFromActiveSearchIfNeeded() {
            return
        }
        historyViewModel.loadHistory()
    }

    private func clearSearch() {
        searchText = ""
        viewModel.currentQuery = ""
        viewModel.clearSearchResults()
    }
    
    private func setupVoiceSearch() {
        appState.speechManager.configure(
            onResult: { result in
                isSearchMode = true
                searchText = result
                viewModel.currentQuery = result
                viewModel.addToRecentSearches(result)
            },
            onPartialResult: { partialResult in
                if !partialResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isSearchMode = true
                    searchText = partialResult
                    viewModel.currentQuery = partialResult
                }
            },
            onError: { errorMessage in
                // Error handling is managed by the speech manager's published errorMessage
                print("Voice search error: \(errorMessage)")
            }
        )
    }

    /// Consumes the article toolbar's one-shot search request only after this canonical Search
    /// surface is mounted. The UI enters active-search mode before yielding a render turn; voice
    /// recognition then starts against the callbacks installed above, without a guessed delay.
    private func activatePendingSearchIntentIfNeeded() {
        guard searchViewAppeared,
              let intent = appState.pendingSearchActivationIntent,
              appState.consumeSearchActivationIntent(generation: intent.generation) else {
            return
        }

        isSearchMode = true
        if let query = appState.pendingSearchQuery {
            searchText = query
            viewModel.currentQuery = query
            appState.pendingSearchQuery = nil
            Task { await viewModel.performSearch(query: query, isNewSearch: true) }
        }

        // Focus after the accessory chrome has a layout turn so article→search
        // never lands on a keyboard-only empty canvas.
        Task { @MainActor in
            await Task.yield()
            guard searchViewAppeared,
                  appState.selectedTab == .search,
                  appState.searchNavigationStack.isEmpty,
                  isSearchMode else {
                return
            }
            isSearchFocused = true
            guard intent.startsVoiceRecognition else { return }
            appState.speechManager.startVoiceRecognition()
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

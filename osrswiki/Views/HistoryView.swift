//
//  HistoryView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI
import Foundation
import UIKit

// MARK: - Data Models (Matching Android Structure)

/// iOS equivalent of Android's sealed HistoryItem class
enum HistoryListItem: Identifiable {
    case dateHeader(String)  // Date string for section header
    case entryItem(ReadingHistoryEntry)  // Individual history entry
    
    var id: String {
        switch self {
        case .dateHeader(let dateString):
            return "header_\(dateString)"
        case .entryItem(let entry):
            return "entry_\(entry.id)"
        }
    }
}

struct HistoryView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @StateObject private var viewModel = HistoryViewModel()
    @State private var showingClearConfirmation = false
    
    var body: some View {
        NavigationStack(path: $appState.historyNavigationStack) {
            VStack(spacing: 0) {
                // Custom header matching NewsView layout
                HistoryHeaderView(
                    onClearHistory: { showingClearConfirmation = true }
                )
                
                osrsSearchLauncher(
                    placeholder: "Search OSRS Wiki",
                    accessibilityIdentifier: "history_search",
                    voiceAccessibilityIdentifier: "history_voice_search",
                    speechState: appState.speechManager.currentState,
                    onSearchTap: { appState.navigateToActiveSearch(startsVoiceRecognition: false) },
                    onVoiceTap: {
                        appState.navigateToActiveSearch(startsVoiceRecognition: true)
                    }
                )
                .osrsTabSearchLauncherLayout()
                
                if viewModel.historyItems.isEmpty {
                    emptyStateView
                } else {
                    historyList
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .background(.osrsBackground)
            .ignoresSafeArea(.keyboard) // Prevent layout adjustment during keyboard appearance in child views
            .onAppear {
                viewModel.loadHistory()
            }
            .alert("Clear History", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    viewModel.clearAllHistory()
                }
            } message: {
                Text("This will permanently delete all your reading history. This action cannot be undone.")
            }
            .navigationDestination(for: HistoryNavigationDestination.self) { destination in
                switch destination {
                case .search:
                    ImmediateStyledSearchView(
                        appState: appState,
                        themeManager: themeManager,
                        theme: osrsTheme,
                        customNavigationClosure: { title, url, snippet, thumbnailUrl in
                            // Use history-specific navigation to avoid NavigationStack context mismatch
                            appState.navigateToArticleInHistory(
                                title: title,
                                url: url,
                                snippet: snippet,
                                thumbnailUrl: thumbnailUrl
                            )
                        }
                    )
                case .article(let articleDestination):
                    ArticleView(
                        pageTitle: articleDestination.title, 
                        pageUrl: articleDestination.url,
                        navigationIdentity: articleDestination.navigationIdentity,
                        snippet: articleDestination.snippet,
                        thumbnailUrl: articleDestination.thumbnailUrl
                    )
                    .id(articleDestination.navigationIdentity)
                    .environmentObject(appState)
                    .environment(\.osrsTheme, osrsTheme)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.osrsSecondaryTextColor)
            
            Text("No History Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            Text("Pages you visit will appear here for easy access later.")
                .font(.body)
                .foregroundStyle(.osrsSecondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.osrsBackground)
    }
    
    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.historyItems) { item in
                    switch item {
                    case .dateHeader(let dateString):
                        HistoryDateHeaderView(dateString: dateString)
                            .background(osrsTheme.background)
                    case .entryItem(let entry):
                        HistoryEntryRowView(entry: entry, onTap: {
                            navigateToHistoryEntry(entry)
                        }) {
                            viewModel.removeHistoryEntry(entry)
                        }
                        .background(osrsTheme.surface)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                viewModel.removeHistoryEntry(entry)
                            }
                        }
                    }
                }
            }
        }
        .scrollPosition($appState.historyListScrollPosition)
        .scrollContentBackground(.hidden)
        .background(osrsTheme.background)
        .refreshable {
            viewModel.loadHistory()
        }
    }
    
    private func navigateToHistoryEntry(_ entry: ReadingHistoryEntry) {
        // Build the article URL from the history entry - matches Android navigation
        if let url = URL(string: entry.wikiUrl) {
            appState.navigateToArticleInHistory(title: entry.displayText, url: url, snippet: entry.snippet, thumbnailUrl: entry.thumbnailUrl)
        }
    }
}

struct HistoryHeaderView: View {
    let onClearHistory: () -> Void
    
    var body: some View {
        osrsThemedTabHeader("History", accessibilityIdentifier: "history_header") {
            Button(action: onClearHistory) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(.osrsSecondaryTextColor)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Clear history")
            .accessibilityIdentifier("history_clear_button")
        }
    }
}

struct HistoryEntryRowView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: ReadingHistoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Main content section (title and description) - matches saved pages
                VStack(alignment: .leading, spacing: 4) {
                    Text(osrsStringUtils.extractMainTitle(entry.displayText))
                        .font(.osrsListTitle)
                        .lineLimit(1)
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .multilineTextAlignment(.leading)
                    
                    if let snippet = entry.snippet, !snippet.isEmpty {
                        Text(osrsStringUtils.decodeHTMLEntitiesFixedPoint(snippet))
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(.osrsPrimaryTextColor) // Use primary color to match title
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                // Match search rows: entries without media use the full text width instead of
                // reserving a decorative placeholder block.
                if let thumbnailUrl = entry.thumbnailUrl, !dynamicTypeSize.isAccessibilitySize {
                    osrsAnimatedThumbnailView(
                        url: thumbnailUrl,
                        refreshToken: entry.metadataUpdatedAt.map { String($0.timeIntervalSince1970) }
                    )
                    .frame(width: 60, height: 60)
                    .background(.osrsSearchBoxBackgroundColor)
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(osrsTheme.surface)
        .listRowSeparator(.hidden, edges: .all)
        .overlay(alignment: .bottom) {
            Color(osrsTheme.surface).frame(height: 3)
        }
        .osrsPrewarmArticleWhenVisible(
            pageURL: URL(string: entry.wikiUrl),
            pageTitle: entry.displayText
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - ReadingHistoryEntry Model
struct ReadingHistoryEntry: Identifiable, Hashable {
    let id: String
    let wikiUrl: String
    let displayText: String
    let pageId: Int?
    let apiPath: String
    let timestamp: Date
    let source: Int
    let snippet: String?
    let thumbnailUrl: URL?
    let metadataUpdatedAt: Date?
    
    var sourceDescription: String {
        switch source {
        case 1: return "Search"
        case 2: return "Link"
        case 3: return "External"
        case 4: return "History"
        case 5: return "Saved"
        case 6: return "Main"
        case 7: return "Random"
        case 8: return "News"
        default: return "Unknown"
        }
    }
}

// MARK: - Date Header View (Matches Android DateHeaderViewHolder)

struct HistoryDateHeaderView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @ScaledMetric(relativeTo: .title3) private var dateFontSize: CGFloat = 24
    let dateString: String
    
    var body: some View {
        HStack {
            Text(dateString)
                .font(dateFont)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(.osrsSecondaryTextColor)
                .padding(.vertical, 8)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(osrsTheme.background)
    }

    private var dateFont: Font {
        for name in ["AlegreyaSC-Bold", "alegreya_sc_bold", "Alegreya SC Bold", "alegreya_sc_medium", "AlegreyaSC-Medium"] where UIFont(name: name, size: dateFontSize) != nil {
            return .custom(name, size: dateFontSize)
        }
        return .system(size: dateFontSize, weight: .bold, design: .serif)
    }
}

// MARK: - HistoryViewModel
@MainActor
class HistoryViewModel: ObservableObject {
    private static var activeMetadataRefreshURLs = Set<URL>()
    @Published var historyItems: [HistoryListItem] = []  // Changed to grouped items
    @Published var isLoading = false
    
    private let historyRepository: HistoryRepository
    private let historyEnricher: osrsHistoryEnricher
    private var metadataRefreshTask: Task<Void, Never>?
    private let metadataFreshnessInterval: TimeInterval = 7 * 24 * 60 * 60

    init(
        historyRepository: HistoryRepository = HistoryRepository(),
        historyEnricher: osrsHistoryEnricher = osrsHistoryEnricher()
    ) {
        self.historyRepository = historyRepository
        self.historyEnricher = historyEnricher
    }
    
    func loadHistory() {
        isLoading = true
        
        // Load real history data from HistoryRepository
        let rawHistoryItems = historyRepository.getHistory()
        
        publishHistory(rawHistoryItems)
        isLoading = false
        scheduleMetadataRefresh(for: rawHistoryItems)
    }

    private func publishHistory(_ rawHistoryItems: [HistoryItem]) {
        let entries = rawHistoryItems.map { item in
            ReadingHistoryEntry(
                id: item.id,
                wikiUrl: item.pageUrl.absoluteString,
                displayText: osrsStringUtils.extractMainTitle(item.displayTitle),
                pageId: nil,
                apiPath: item.pageTitle,
                timestamp: item.visitedDate,
                source: 1,
                snippet: item.description.map(osrsStringUtils.decodeHTMLEntitiesFixedPoint),
                thumbnailUrl: item.thumbnailUrl,
                metadataUpdatedAt: item.metadataUpdatedAt
            )
        }
        historyItems = groupByDate(entries)
    }

    private func scheduleMetadataRefresh(for rawHistoryItems: [HistoryItem]) {
        guard metadataRefreshTask == nil else { return }
        let cutoff = Date().addingTimeInterval(-metadataFreshnessInterval)
        let candidates = rawHistoryItems.filter { item in
            guard let updatedAt = item.metadataUpdatedAt else { return true }
            return updatedAt < cutoff
        }
        .filter { !Self.activeMetadataRefreshURLs.contains($0.pageUrl) }
        .prefix(24)
        guard !candidates.isEmpty else { return }
        let claimedURLs = Set(candidates.map(\.pageUrl))
        Self.activeMetadataRefreshURLs.formUnion(claimedURLs)
        let repository = historyRepository
        let enricher = historyEnricher
        let cachedFeed = NewsRepository.shared.getCachedFeedSynchronously()
        let refreshCandidates = candidates.map { item in
            (item, osrsHistoryUpdateMetadataResolver.cachedMetadata(for: item, in: cachedFeed))
        }

        metadataRefreshTask = Task { [weak self] in
            defer {
                Self.activeMetadataRefreshURLs.subtract(claimedURLs)
                self?.metadataRefreshTask = nil
            }
            for batchStart in stride(from: 0, to: refreshCandidates.count, by: 4) {
                guard !Task.isCancelled else { return }
                let batchEnd = min(batchStart + 4, refreshCandidates.count)
                let batch = Array(refreshCandidates[batchStart..<batchEnd])
                let refreshResults = await withTaskGroup(
                    of: (URL, URL?, String?).self,
                    returning: [(URL, URL?, String?)].self
                ) { group in
                    for (item, cachedMetadata) in batch {
                        group.addTask { [enricher] in
                            let metadata = await enricher.enrichHistoryEntry(
                                pageTitle: item.displayTitle,
                                pageUrl: item.pageUrl
                            )
                            return (
                                item.pageUrl,
                                metadata.thumbnailUrl ?? cachedMetadata?.thumbnailUrl,
                                metadata.snippet ?? cachedMetadata?.description
                            )
                        }
                    }
                    var results: [(URL, URL?, String?)] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }
                guard !Task.isCancelled else { return }
                for (pageURL, thumbnailURL, snippet) in refreshResults {
                    repository.updateMetadata(
                        for: pageURL,
                        thumbnailUrl: thumbnailURL,
                        description: snippet
                    )
                }
                self?.publishHistory(repository.getHistory())
            }
        }
    }
    
    /// Groups history entries by date, inserting date headers (matches Android implementation)
    private func groupByDate(_ entries: [ReadingHistoryEntry]) -> [HistoryListItem] {
        var result: [HistoryListItem] = []
        
        guard !entries.isEmpty else { return result }
        
        let calendar = Calendar.current
        var prevDay = 0
        
        // Sort by timestamp descending (newest first)
        let sortedEntries = entries.sorted { $0.timestamp > $1.timestamp }
        
        for entry in sortedEntries {
            let components = calendar.dateComponents([.year, .dayOfYear], from: entry.timestamp)
            let curDay = (components.year ?? 0) + (components.dayOfYear ?? 0)
            
            // Add date header if it's a new day
            if prevDay == 0 || curDay != prevDay {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let dateString = dateFormatter.string(from: entry.timestamp)
                result.append(.dateHeader(dateString))
            }
            
            prevDay = curDay
            result.append(.entryItem(entry))
        }
        
        return result
    }
    
    func removeHistoryEntry(_ entry: ReadingHistoryEntry) {
        // Find corresponding HistoryItem by URL and remove it
        let rawHistoryItems = historyRepository.getHistory()
        if let historyItem = rawHistoryItems.first(where: { $0.pageUrl.absoluteString == entry.wikiUrl }) {
            historyRepository.removeFromHistory(historyItem.id)
            loadHistory() // Reload to update UI
        }
    }
    
    func clearAllHistory() {
        metadataRefreshTask?.cancel()
        historyRepository.clearHistory()
        historyItems.removeAll()
    }
    
}

#Preview {
    HistoryView()
        .environment(\.osrsTheme, osrsLightTheme())
}

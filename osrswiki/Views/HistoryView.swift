//
//  HistoryView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI
import Foundation

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
                
                // Search bar at top (matches Android and home page)
                SearchBarView(placeholder: "Search OSRS Wiki") {
                    // Navigate to search using dedicated HistoryView navigation stack
                    appState.navigateToSearchFromHistory()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
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
        List {
            ForEach(viewModel.historyItems) { item in
                switch item {
                case .dateHeader(let dateString):
                    // Date header section (matches Android DateHeaderViewHolder)
                    HistoryDateHeaderView(dateString: dateString)
                        .listRowBackground(osrsTheme.surface)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        
                case .entryItem(let entry):
                    // History entry (matches Android EntryViewHolder) 
                    HistoryEntryRowView(entry: entry, onTap: {
                        navigateToHistoryEntry(entry)
                    }) {
                        viewModel.removeHistoryEntry(entry)
                    }
                    .listRowBackground(osrsTheme.surface)
                }
            }
        }
        .listStyle(PlainListStyle())
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
        HStack {
            // Left-aligned "History" title matching NewsView HeaderView
            Text("History")
                .font(.osrsDisplay)
                .foregroundStyle(.osrsPrimaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right-aligned clear all button (matches Android design)
            Button(action: onClearHistory) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(.osrsSecondaryTextColor)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.osrsBackground)
    }
}

struct HistoryEntryRowView: View {
    @Environment(\.osrsTheme) var osrsTheme
    let entry: ReadingHistoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Main content section (title and description) - matches saved pages
                VStack(alignment: .leading, spacing: 4) {
                    Text(osrsStringUtils.extractMainTitle(entry.displayText))
                        .font(.osrsListTitle)  // Use same font as saved pages
                        .lineLimit(1)
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .multilineTextAlignment(.leading)
                    
                    if let snippet = entry.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(.osrsPrimaryTextColor) // Use primary color to match title
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                // Thumbnail positioned on the right (matching saved pages layout)
                AsyncImage(url: entry.thumbnailUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } placeholder: {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.osrsPlaceholderColor)
                        .font(.title2)
                }
                .frame(width: 60, height: 60)  // Match saved pages size
                .background(.osrsSearchBoxBackgroundColor)  // Match saved pages background
                .cornerRadius(8)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(osrsTheme.surface)  // Proper theme background
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(osrsTheme.divider)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - ReadingHistoryEntry Model
struct ReadingHistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let wikiUrl: String
    let displayText: String
    let pageId: Int?
    let apiPath: String
    let timestamp: Date
    let source: Int
    let snippet: String?
    let thumbnailUrl: URL?
    
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
    let dateString: String
    
    var body: some View {
        HStack {
            Text(dateString)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.osrsPrimaryTextColor)
                .padding(.top, 8)
                .padding(.bottom, 0)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(.osrsBackground)
    }
}

// MARK: - HistoryViewModel
class HistoryViewModel: ObservableObject {
    @Published var historyItems: [HistoryListItem] = []  // Changed to grouped items
    @Published var isLoading = false
    
    private let historyRepository = HistoryRepository()
    
    func loadHistory() {
        isLoading = true
        
        // Load real history data from HistoryRepository
        let rawHistoryItems = historyRepository.getHistory()
        
        // Convert to ReadingHistoryEntry and group by date (like Android)
        var entries = rawHistoryItems.map { item in
            ReadingHistoryEntry(
                wikiUrl: item.pageUrl.absoluteString,
                displayText: osrsStringUtils.extractMainTitle(item.displayTitle),
                pageId: nil,
                apiPath: item.pageTitle,
                timestamp: item.visitedDate,
                source: 1,
                snippet: item.description,
                thumbnailUrl: item.thumbnailUrl
            )
        }
        
        
        // Group by date (matching Android's groupByDate function)
        self.historyItems = groupByDate(entries)
        
        isLoading = false
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
        historyRepository.clearHistory()
        historyItems.removeAll()
    }
    
}

#Preview {
    HistoryView()
        .environment(\.osrsTheme, osrsLightTheme())
}

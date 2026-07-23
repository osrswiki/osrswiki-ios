//
//  SavedPagesView.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI

struct SavedPagesView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SavedPagesViewModel()
    
    var body: some View {
        return NavigationStack(path: $appState.savedNavigationStack) {
            VStack(spacing: 0) {
                osrsAccessibilityMarker(identifier: "saved_pages_screen", label: "Saved pages screen")

                // Custom header matching Home and History layout
                SavedPagesHeaderView(
                    hasSavedPages: !viewModel.savedPages.isEmpty,
                    usesCompactLayout: usesCompactAccessibilityLayout,
                    onSortByDate: { viewModel.sortBy(.date) },
                    onSortByTitle: { viewModel.sortBy(.title) },
                    onClearAllSavedPages: { viewModel.clearAllSavedPages() },
                    onExportReadingList: { viewModel.exportReadingList() }
                )
                
                // Search bar at top (matches NewsView and HistoryView layout)
                SearchBarView(placeholder: "Search saved pages") {
                    // Navigate to search using NavigationStack
                    appState.navigateToSearchFromSaved()
                }
                .accessibilityIdentifier("saved_search")
                .padding(.horizontal)
                .padding(.top, usesCompactAccessibilityLayout ? 4 : 8)
                .padding(.bottom, usesCompactAccessibilityLayout ? 6 : 12)
                
                if viewModel.savedPages.isEmpty {
                    emptyStateView
                } else {
                    savedPagesListView
                }
            }
            .dynamicTypeSize(contentDynamicTypeSize)
            .navigationTitle("")
            .navigationBarHidden(true)
            .background(.osrsBackground)
            .onReceive(appState.$savedNavigationStack) { stack in
                print("🔍 SAVEDPAGES: NavigationStack path changed - new count: \(stack.count)")
                if stack.isEmpty {
                    print("🔍 SAVEDPAGES: savedNavigationStack is EMPTY")
                } else {
                    print("🔍 SAVEDPAGES: savedNavigationStack contents: \(stack)")
                    print("🔍 SAVEDPAGES: Latest navigation destination: \(stack.last!)")
                }
            }
            .onAppear {
                print("🔍 SAVEDPAGES: SavedPagesView.onAppear - Initial NavigationStack count: \(appState.savedNavigationStack.count)")
            }
            .navigationDestination(for: SavedNavigationDestination.self) { destination in
                switch destination {
                case .search:
                    SavedPagesSearchView(viewModel: viewModel)
                        .onAppear {
                            print("🎯 SAVEDPAGES: navigationDestination TRIGGERED! Processing: \(destination)")
                            print("🎯 SAVEDPAGES: Creating SavedPagesSearchView")
                            print("✅ SAVEDPAGES: SavedPagesSearchView.onAppear - Search view successfully created!")
                        }
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
                    .environment(\.osrsTheme, osrsTheme)
                    .onAppear {
                        print("🎯 SAVEDPAGES: navigationDestination TRIGGERED! Processing: \(destination)")
                        print("🎯 SAVEDPAGES: Creating ArticleView with:")
                        print("  - title: \(articleDestination.title ?? "nil")")
                        print("  - url: \(articleDestination.url)")
                        print("  - snippet: \(articleDestination.snippet ?? "nil")")
                        print("  - thumbnailUrl: \(articleDestination.thumbnailUrl?.absoluteString ?? "nil")")
                        print("  - savedPageId: \(articleDestination.savedPageId ?? "nil")")
                        print("✅ SAVEDPAGES: ArticleView.onAppear - ArticleView successfully created and appeared!")
                    }
                    .onDisappear {
                        print("❌ SAVEDPAGES: ArticleView.onDisappear - ArticleView disappeared")
                        
                        // Clean up proxy configuration when leaving saved page
                        if let savedPageId = articleDestination.savedPageId {
                            print("🧹 SAVEDPAGES: Cleaning up proxy configuration for: \(savedPageId)")
                            if #available(iOS 17.0, *) {
                                ProxyInterceptorService.shared.disableOfflineSaveMode()
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadSavedPages()
        }
        .sheet(item: $viewModel.sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
#if DEBUG
        .overlay(alignment: .bottomLeading) {
            if let record = viewModel.shareRequestRecordForUITests {
                Text(record.label)
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier(record.identifier)
                    .accessibilityLabel(record.label)
            }
        }
#endif
    }

    private var contentDynamicTypeSize: DynamicTypeSize {
        verticalSizeClass == .compact && dynamicTypeSize.isAccessibilitySize ? .medium : dynamicTypeSize
    }

    private var usesCompactAccessibilityLayout: Bool {
        verticalSizeClass == .compact && dynamicTypeSize.isAccessibilitySize
    }
    
    private var emptyStateView: some View {
        VStack(spacing: usesCompactAccessibilityLayout ? 8 : 24) {
            osrsAccessibilityMarker(identifier: "saved_empty_state", label: "Saved pages empty state")

            if !usesCompactAccessibilityLayout {
                Image(systemName: "bookmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.osrsPlaceholderColor)
                    .accessibilityIdentifier("saved_empty_bookmark_icon")
            }
            
            VStack(spacing: usesCompactAccessibilityLayout ? 4 : 12) {
                Text("No Saved Pages")
                    .font(usesCompactAccessibilityLayout ? .headline : .title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text("Save pages while browsing to build your personal reading list")
                    .font(usesCompactAccessibilityLayout ? .subheadline : .body)
                    .foregroundStyle(.osrsSecondaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(usesCompactAccessibilityLayout ? 2 : nil)
                    .padding(.horizontal, usesCompactAccessibilityLayout ? 16 : 32)
            }
            
        }
        .padding(.top, usesCompactAccessibilityLayout ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: usesCompactAccessibilityLayout ? .top : .center)
        .background(.osrsBackground)
    }
    
    private var savedPagesListView: some View {
        List {
            ForEach(viewModel.savedPages) { savedPage in
                SavedPageRowView(savedPage: savedPage) {
                    viewModel.navigateToPage(savedPage, appState: appState)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        viewModel.removeSavedPage(savedPage)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Share") {
                        viewModel.sharePage(savedPage)
                    }
                    .tint(.blue)
                }
            }
            .onMove { from, to in
                viewModel.moveSavedPages(from: from, to: to)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(.osrsBackground)
        .refreshable {
            await viewModel.refresh()
        }
    }
}

struct SavedPageRowView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let savedPage: SavedPage
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 12) {
                // Main content section (title and description) - matches search results
                VStack(alignment: .leading, spacing: 4) {
                    Text(osrsStringUtils.extractMainTitle(savedPage.title))
                        .font(.osrsListTitle)  // Use same font as search results
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .multilineTextAlignment(.leading)
                    
                    if let description = savedPage.description {
                        Text(description)
                            .font(.subheadline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.osrsPrimaryTextColor) // Use primary color to match title
                            .multilineTextAlignment(.leading)
                    }
                    
                    HStack {
                        Text(savedPage.savedDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        
                        if savedPage.isOfflineAvailable {
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Thumbnail positioned on the right (matching search results layout)
                if !dynamicTypeSize.isAccessibilitySize {
                    AsyncImage(url: savedPage.thumbnailUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.osrsPlaceholderColor)
                            .font(.title2)
                    }
                    .frame(width: 60, height: 60)  // Match search results size
                    .background(.clear)  // Transparent background
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(osrsTheme.surface)  // Proper theme background
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(osrsTheme.divider)
    }
}

struct SavedPagesSearchView: View {
    @ObservedObject var viewModel: SavedPagesViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.osrsPlaceholderColor)
                
                TextField("Search saved pages", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFieldFocused)
            }
            .padding()
            .background(.osrsSearchBoxBackgroundColor)
            .cornerRadius(10)
            .padding()
            
            // Filtered results
            List(viewModel.filteredSavedPages(searchText: searchText)) { savedPage in
                SavedPageRowView(savedPage: savedPage) {
                    viewModel.navigateToPage(savedPage, appState: appState)
                    dismiss()
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("Search Saved Pages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isSearchFieldFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

struct SavedPagesHeaderView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let hasSavedPages: Bool
    let usesCompactLayout: Bool
    let onSortByDate: () -> Void
    let onSortByTitle: () -> Void
    let onClearAllSavedPages: () -> Void
    let onExportReadingList: () -> Void
    
    var body: some View {
        HStack {
            // Left-aligned "Saved Pages" title matching Home and History
            Text("Saved")
                .font(headerTitleFont)
                .dynamicTypeSize(headerTitleDynamicTypeSize)
                .foregroundStyle(.osrsPrimaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right-aligned menu button (matches History and Home ellipsis menu)
            Menu {
                Button("Sort by Date") {
                    onSortByDate()
                }
                
                Button("Sort by Title") {
                    onSortByTitle()
                }
                
                Divider()
                
                Button("Clear All Saved Pages", role: .destructive) {
                    onClearAllSavedPages()
                }
                .disabled(!hasSavedPages)
                
                Button("Export Reading List") {
                    onExportReadingList()
                }
                .disabled(!hasSavedPages)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.osrsPlaceholderColor)
                    .frame(width: 48, height: 48)
            }
            .accessibilityIdentifier("saved_header_menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, usesCompactLayout || dynamicTypeSize.isAccessibilitySize ? 4 : 8)
        .frame(minHeight: usesCompactLayout ? 40 : 48)
        .background(.osrsBackground)
    }

    private var headerTitleFont: Font {
        usesCompactLayout || dynamicTypeSize.isAccessibilitySize ? .osrsTitleBold : .osrsDisplay
    }

    private var headerTitleDynamicTypeSize: DynamicTypeSize {
        dynamicTypeSize.isAccessibilitySize ? .large : dynamicTypeSize
    }
}

#Preview {
    SavedPagesView()
        .environment(\.osrsTheme, osrsLightTheme())
        .environmentObject(AppState())
}

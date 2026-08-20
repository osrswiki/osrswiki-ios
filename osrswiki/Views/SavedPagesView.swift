//
//  SavedPagesView.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import Combine

struct SavedPagesView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SavedPagesViewModel()
    @State private var repositoryRefreshTask: Task<Void, Never>?

    static func shouldRefreshRepository(
        after oldPath: [SavedNavigationDestination],
        before newPath: [SavedNavigationDestination]
    ) -> Bool {
        guard newPath.count < oldPath.count,
              let oldTop = oldPath.last,
              case .article = oldTop else {
            return false
        }
        return true
    }
    
    var body: some View {
        return NavigationStack(path: $appState.savedNavigationStack) {
            VStack(spacing: 0) {
                osrsAccessibilityMarker(identifier: "saved_pages_screen", label: "Saved pages screen")

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
            .osrsTabGlassAccessoryBar {
                osrsTabSearchWithTrailingControl(
                    search: osrsSearchLauncher(
                        placeholder: "Search saved pages",
                        accessibilityIdentifier: "saved_search",
                        voiceAccessibilityIdentifier: "saved_voice_search",
                        speechState: appState.speechManager.currentState,
                        onSearchTap: { appState.navigateToSearchFromSaved() },
                        onVoiceTap: {
                            appState.navigateToActiveSearch(startsVoiceRecognition: true)
                        }
                    )
                ) {
                    osrsGlassOverflowMenu(accessibilityIdentifier: "saved_header_menu") {
                        Button("Sort by Date") {
                            viewModel.sortBy(.date)
                        }
                        Button("Sort by Title") {
                            viewModel.sortBy(.title)
                        }
                        Divider()
                        Button("Clear All Saved Pages", role: .destructive) {
                            viewModel.clearAllSavedPages()
                        }
                        .disabled(viewModel.savedPages.isEmpty)
                        Button("Export Reading List") {
                            viewModel.exportReadingList()
                        }
                        .disabled(viewModel.savedPages.isEmpty)
                    }
                }
            }
            .onReceive(appState.$savedNavigationStack) { stack in
                print("🔍 SAVEDPAGES: NavigationStack path changed - new count: \(stack.count)")
                if stack.isEmpty {
                    print("🔍 SAVEDPAGES: savedNavigationStack is EMPTY")
                } else {
                    print("🔍 SAVEDPAGES: savedNavigationStack contents: \(stack)")
                    print("🔍 SAVEDPAGES: Latest navigation destination: \(stack.last!)")
                }
            }
            .onChange(of: appState.savedNavigationStack) { oldPath, newPath in
                guard Self.shouldRefreshRepository(after: oldPath, before: newPath) else {
                    return
                }
                // ArticleView owns a separate repository-backed model. Refresh the shared Saved
                // root/search model after any article pop so Retry→Saved and unsave are visible
                // immediately, including [.search, .article] → [.search].
                scheduleRepositoryRefresh()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .osrsSavedPagesRepositoryDidChange)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                // ArticleView uses another repository-backed model and its explicit save may
                // finish after the user pops. Coalesce cross-instance terminal mutations so the
                // retained Saved root/search never remains UPDATING, RETRY, or removed-stale.
                scheduleRepositoryRefresh()
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
                        // ArticleView owns and tears down its exact proxy session token. A
                        // retained Saved destination must never disable a newer article owner.
                        print("❌ SAVEDPAGES: ArticleView.onDisappear - ArticleView disappeared")
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

    private func scheduleRepositoryRefresh() {
        repositoryRefreshTask?.cancel()
        repositoryRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await viewModel.loadSavedPages()
            guard !Task.isCancelled else { return }
            repositoryRefreshTask = nil
        }
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.savedPages) { savedPage in
                    SavedPageRowView(savedPage: savedPage) {
                        viewModel.navigateToPage(savedPage, appState: appState)
                    }
                    .background(Color(osrsTheme.surface))
                    .contextMenu {
                        Button("Update") {
                            osrsDownloadSettings.markPendingManualUpdate(id: savedPage.offlineCachePageId)
                            viewModel.navigateToPage(savedPage, appState: appState)
                        }
                        Button("Share") { viewModel.sharePage(savedPage) }
                        Button("Delete", role: .destructive) {
                            viewModel.removeSavedPage(savedPage)
                        }
                    }
                }
            }
        }
        .scrollPosition($appState.savedPagesScrollPosition)
        .scrollContentBackground(.hidden)
        .background(.osrsBackground)
        .refreshable {
            await viewModel.refresh()
        }
        .osrsPrewarmArticlesWhenVisible(
            pageURLs: Array(viewModel.savedPages.prefix(8).map(\.url)),
            isOfflineContentAvailable: true
        )
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
                // Match Android's information hierarchy: title, one concise preview, then
                // durable save metadata. Accessibility sizes may give the preview a second line.
                VStack(alignment: .leading, spacing: 4) {
                    Text(osrsStringUtils.extractMainTitle(savedPage.title))
                        .font(.osrsListTitle)  // Use same font as search results
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("saved_row_title")

                    if let description = savedPage.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.osrsSecondaryTextColor)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("saved_row_preview")
                    }
                    
                    HStack(spacing: 4) {
                        Text(savedMetadata)
                            .font(.caption)
                            .foregroundStyle(.osrsPrimaryTextColor)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("saved_row_metadata")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Thumbnail positioned on the right (matching search results layout)
                if let thumbnailUrl = savedPage.thumbnailUrl, !dynamicTypeSize.isAccessibilitySize {
                    osrsAnimatedThumbnailView(url: thumbnailUrl)
                    .frame(width: 60, height: 60)  // Match search results size
                    .background(.clear)  // Transparent background
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(minHeight: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("saved_page_row")
        .accessibilityValue(savedAccessibilityMetadata)
        .accessibilityHint(savedPage.description ?? "")
        .listRowBackground(osrsTheme.surface)  // Proper theme background
        .listRowSeparator(.hidden, edges: .all)
        .overlay(alignment: .bottom) {
            Color(osrsTheme.surface).frame(height: 3)
        }
        .osrsPrewarmArticleWhenVisible(
            pageURL: savedPage.url,
            pageTitle: savedPage.title,
            isOfflineContentAvailable: savedPage.isOfflineAvailable
        )
    }

    private var savedMetadata: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let size = savedPage.offlineFileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [savedPage.savedLibraryStatusLabel, size, formatter.string(from: savedPage.savedDate)]
            .compactMap { $0 }
            .joined(separator: " • ")
    }

    private var savedAccessibilityMetadata: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let size = savedPage.offlineFileSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        return [
            savedPage.savedLibraryStatusLabel,
            size,
            "Last updated \(formatter.string(from: savedPage.savedDate))"
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

struct SavedPagesSearchView: View {
    @ObservedObject var viewModel: SavedPagesViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.osrsTheme) private var osrsTheme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isSearchFieldFocused = false
    
    var body: some View {
        ZStack {
            Color(osrsTheme.background)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                osrsAccessibilityMarker(identifier: "saved_search_screen", label: "Saved pages search screen")

                osrsActiveSearchToolbar(
                    text: $searchText,
                    isFocused: $isSearchFieldFocused,
                    placeholder: "Search saved pages",
                    backAccessibilityLabel: "Back to saved pages",
                    backAccessibilityIdentifier: "saved_search_back_button",
                    inputAccessibilityIdentifier: "saved_search_input",
                    clearAccessibilityIdentifier: "saved_search_clear_button",
                    voiceAccessibilityIdentifier: "saved_search_voice_search",
                    speechState: appState.speechManager.currentState,
                    onBack: {
                        isSearchFieldFocused = false
                        dismiss()
                    },
                    onClear: { searchText = "" },
                    onVoiceTap: { appState.speechManager.startVoiceRecognition() },
                    onSubmit: {}
                )

                List(viewModel.filteredSavedPages(searchText: searchText)) { savedPage in
                    SavedPageRowView(savedPage: savedPage) {
                        isSearchFieldFocused = false
                        viewModel.navigateToPage(savedPage, appState: appState)
                        dismiss()
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color(osrsTheme.surface))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(osrsTheme.background))
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .onAppear {
            configureVoiceSearch()
            isSearchFieldFocused = true
        }
        .onDisappear {
            appState.speechManager.cleanup()
        }
        .alert(
            "Voice Search Error",
            isPresented: Binding(
                get: { appState.speechManager.errorMessage != nil },
                set: { if !$0 { appState.speechManager.clearError() } }
            )
        ) {
            Button("OK") { appState.speechManager.clearError() }
        } message: {
            Text(appState.speechManager.errorMessage ?? "")
        }
    }

    private func configureVoiceSearch() {
        appState.speechManager.configure(
            onResult: { result in searchText = result },
            onPartialResult: { partialResult in searchText = partialResult },
            onError: { _ in }
        )
    }
}

#Preview {
    SavedPagesView()
        .environment(\.osrsTheme, osrsLightTheme())
        .environmentObject(AppState())
}

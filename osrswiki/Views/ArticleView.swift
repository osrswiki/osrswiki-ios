//
//  ArticleView.swift
//  OSRS Wiki
//
//  Created on iOS webviewer implementation session
//

import SwiftUI
import UIKit
import WebKit

struct ArticleView: View {
    enum SavedCacheRoutingMode: Equatable {
        case cacheOnly
        case cacheFirst
        case saveWhileServing
    }

    /// The saved-page record's settlement status controls the save button, not readability.
    /// Navigation probes the exact main response in the preserved page namespace so a legacy
    /// record marked `.outdated` can still be read best-effort while its refresh remains honest.
    static func savedCacheRoutingMode(
        hasPersistedMainResponse: Bool,
        isOffline: Bool
    ) -> SavedCacheRoutingMode {
        if hasPersistedMainResponse {
            return .cacheOnly
        }
        return isOffline ? .cacheOnly : .saveWhileServing
    }

    let pageTitle: String?
    let pageUrl: URL
    let navigationIdentity: String?
    let snippet: String?
    let thumbnailUrl: URL?
    let savedPageId: String?
    let collapseTablesEnabled: Bool
    let excludeFromHistory: Bool
    let navigationDelegate: WKNavigationDelegate?
    let onLoadingComplete: ((ArticleViewModel) -> Void)?
    let showProgressBar: Bool
    let managesMainTabBarVisibility: Bool

    init(pageTitle: String?, pageUrl: URL, navigationIdentity: String? = nil, snippet: String? = nil, thumbnailUrl: URL? = nil, savedPageId: String? = nil, collapseTablesEnabled: Bool = true, excludeFromHistory: Bool = false, navigationDelegate: WKNavigationDelegate? = nil, onLoadingComplete: ((ArticleViewModel) -> Void)? = nil, showProgressBar: Bool = true, managesMainTabBarVisibility: Bool = true) {
        self.pageTitle = pageTitle
        self.pageUrl = pageUrl
        self.navigationIdentity = navigationIdentity
        self.snippet = snippet
        self.thumbnailUrl = thumbnailUrl
        self.savedPageId = savedPageId
        self.collapseTablesEnabled = collapseTablesEnabled
        self.excludeFromHistory = excludeFromHistory
        self.navigationDelegate = navigationDelegate
        self.onLoadingComplete = onLoadingComplete
        self.showProgressBar = showProgressBar
        self.managesMainTabBarVisibility = managesMainTabBarVisibility
    }

    var body: some View {
        ArticleViewContent(
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            navigationIdentity: navigationIdentity,
            snippet: snippet,
            thumbnailUrl: thumbnailUrl,
            savedPageId: savedPageId,
            collapseTablesEnabled: collapseTablesEnabled,
            excludeFromHistory: excludeFromHistory,
            navigationDelegate: navigationDelegate,
            onLoadingComplete: onLoadingComplete,
            showProgressBar: showProgressBar,
            managesMainTabBarVisibility: managesMainTabBarVisibility
        )
        .id(articleIdentity)
    }

    private var articleIdentity: String {
        navigationIdentity ?? "\(pageUrl.absoluteString)|savedPageId=\(savedPageId ?? "")"
    }
}

private struct ArticleViewContent: View {
    @Environment(\.osrsTheme) var osrsTheme
    @EnvironmentObject var themeManager: osrsThemeManager
    @EnvironmentObject var appState: AppState
    // Make overlayManager optional to handle preview rendering
    @Environment(\.overlayManager) var overlayManager: GlobalOverlayManager?
    @StateObject private var viewModel: ArticleViewModel
    @State private var isShowingShareSheet = false
    @State private var isShowingTableOfContents = false
    @State private var contentsRevealProgress: CGFloat = 0
    @State private var isShowingFindInPage = false
    @State private var findSession = 0
    @State private var isShowingAppearanceSettings = false
    @State private var highlightFloorNumberingOnAppearance = false
    @State private var isShowingFeedback = false
    @State private var isShowingOfflineCacheBanner = false
    @State private var hasLoadedBefore = false
    @State private var movedOffTopOfArticleStack = false
    @State private var isArticleVisible = false
    @State private var savedCacheSessionToken: ProxyCacheSessionToken?
    @State private var savedCachePreparationTask: Task<Void, Never>?
#if DEBUG
    @State private var hasStartedFindInPageForTests = false
#endif

    let pageTitle: String?
    let pageUrl: URL
    let navigationIdentity: String?
    let snippet: String?
    let thumbnailUrl: URL?
    let savedPageId: String? // For proxy configuration when loading saved pages
    let collapseTablesEnabled: Bool
    let navigationDelegate: WKNavigationDelegate?
    let onLoadingComplete: ((ArticleViewModel) -> Void)? // Optional callback for preview generation
    let showProgressBar: Bool
    let managesMainTabBarVisibility: Bool

    init(pageTitle: String?, pageUrl: URL, navigationIdentity: String? = nil, snippet: String? = nil, thumbnailUrl: URL? = nil, savedPageId: String? = nil, collapseTablesEnabled: Bool = true, excludeFromHistory: Bool = false, navigationDelegate: WKNavigationDelegate? = nil, onLoadingComplete: ((ArticleViewModel) -> Void)? = nil, showProgressBar: Bool = true, managesMainTabBarVisibility: Bool = true) {
        self.pageTitle = pageTitle
        self.pageUrl = pageUrl
        self.navigationIdentity = navigationIdentity
        self.snippet = snippet
        self.thumbnailUrl = thumbnailUrl
        self.savedPageId = savedPageId
        self.collapseTablesEnabled = collapseTablesEnabled
        self.navigationDelegate = navigationDelegate
        self.onLoadingComplete = onLoadingComplete
        self.showProgressBar = showProgressBar
        self.managesMainTabBarVisibility = managesMainTabBarVisibility
        self._viewModel = StateObject(wrappedValue: ArticleViewModel(pageUrl: pageUrl, pageTitle: pageTitle, pageId: nil, snippet: snippet, thumbnailUrl: thumbnailUrl, collapseTablesEnabled: collapseTablesEnabled, excludeFromHistory: excludeFromHistory))
        print("🏗️ ArticleView: Created with title='\(pageTitle ?? "nil")' url=\(pageUrl), snippet='\(snippet ?? "nil")', thumbnail='\(thumbnailUrl?.absoluteString ?? "nil")', collapseTables=\(collapseTablesEnabled), excludeFromHistory=\(excludeFromHistory)")
    }

    var body: some View {
        articleSessionChrome
    }

    private var articleNavigationChrome: some View {
        articleLayout
            .background {
                osrsTheme.background.ignoresSafeArea()
            }
            .navigationBarHidden(true)
            .onAppear {
                isArticleVisible = true
                beginAppearanceLoad()
            }
            .onChange(of: appState.activeArticleDestination?.navigationIdentity) { _, activeIdentity in
                if activeIdentity == articleIdentity {
                    updateArticleBottomBar()
                } else if activeIdentity == nil {
                    overlayManager?.hideArticleBottomBar(owner: articleIdentity)
                }
                guard hasLoadedBefore else { return }

                if activeIdentity == articleIdentity {
                    guard movedOffTopOfArticleStack else { return }
                    movedOffTopOfArticleStack = false
                    restoreCapturedArticleScrollIfNeeded()
                    updateArticleBottomBar()
                } else {
                    captureCurrentArticleScroll()
                    movedOffTopOfArticleStack = true
                }
            }
            .onChange(of: viewModel.hasTableOfContents) { _, _ in
                updateArticleBottomBar()
            }
            .onChange(of: viewModel.isBookmarked) { _, _ in
                updateArticleBottomBar()
            }
            .onChange(of: viewModel.saveState) { _, _ in
                updateArticleBottomBar()
            }
            .onChange(of: themeManager.articleTextScale) { _, newScale in
                viewModel.setArticleTextScale(CGFloat(newScale))
            }
            .onChange(of: themeManager.floorNumberingMode) { _, _ in
                viewModel.applyFloorNumberingConvention(osrsArticleFloorConvention.current())
            }
            .onChange(of: themeManager.wrapTableCells) { _, enabled in
                viewModel.applyWrapTableCells(enabled)
            }
            .onChange(of: themeManager.collapseTables) { _, shouldCollapse in
                guard collapseTablesEnabled else { return }
                viewModel.setCollapseTablesEnabled(shouldCollapse)
                if hasLoadedBefore {
                    viewModel.loadArticle(theme: osrsTheme, isReload: true)
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if !isLoading, let onLoadingComplete {
                    print("📊 ArticleView: Loading completed - calling preview generation callback with viewModel")
                    onLoadingComplete(viewModel)
                }
                if !isLoading {
                    consumePendingArticleScrollIfNeeded()
                    restoreCapturedArticleScrollIfNeeded()
#if DEBUG
                    dumpArticleTableMetricsIfRequested()
#endif
                }
#if DEBUG
                if !isLoading,
                   !hasStartedFindInPageForTests,
                   ProcessInfo.processInfo.arguments.contains("-startFindInPage") {
                    hasStartedFindInPageForTests = true
                    startFindInPage()
                }
#endif
            }
            .onDisappear {
                overlayManager?.setArticleBottomBarCovered(false)
                savedCachePreparationTask?.cancel()
                savedCachePreparationTask = nil
                isArticleVisible = false
                captureCurrentArticleScroll()
                findSession += 1
                viewModel.hideFindInPageAction()
                viewModel.cancelActiveWorkForNavigation()
                if #available(iOS 17.0, *), let savedCacheSessionToken {
                    ProxyInterceptorService.shared.disableMode(owner: savedCacheSessionToken)
                    self.savedCacheSessionToken = nil
                }
                let stillShowingArticle = appState.activeArticleDestination != nil
                if !stillShowingArticle {
                    overlayManager?.hideArticleBottomBar(owner: articleIdentity)
                    showMainTabBar()
                }
            }
    }

    private var articlePresentedChrome: some View {
        articleNavigationChrome
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(items: [pageUrl])
            }
            .osrsYouTubePlayerSheet(url: $viewModel.pendingYouTubeEmbedURL)
            .overlay {
                osrsContentsDrawerSimple(
                    isPresented: $isShowingTableOfContents,
                    interactiveProgress: $contentsRevealProgress,
                    sections: viewModel.tableOfContents,
                    onSectionSelected: { sectionId in
                        viewModel.scrollToSection(sectionId)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingAppearanceSettings, onDismiss: {
                highlightFloorNumberingOnAppearance = false
            }) {
                NavigationStack {
                    AppearanceSettingsView(
                        highlightFloorNumbering: highlightFloorNumberingOnAppearance,
                        usesLargeTitle: false
                    )
                        .environmentObject(themeManager)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    isShowingAppearanceSettings = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingFeedback) {
                NavigationStack {
                    FeedbackView()
                        .environmentObject(themeManager)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    isShowingFeedback = false
                                }
                            }
                        }
                }
            }
            .alert("Voice Search Error",
                   isPresented: Binding<Bool>(
                       get: { appState.speechManager.errorMessage != nil },
                       set: { _ in appState.speechManager.clearError() }
                   )) {
                Button("OK") { }
            } message: {
                if let errorMessage = appState.speechManager.errorMessage {
                    Text(errorMessage)
                }
            }
    }

    private var articleSessionChrome: some View {
        articlePresentedChrome
            .onChange(of: osrsTheme as? osrsLightTheme != nil) { _, _ in
                viewModel.applyLiveTheme(osrsTheme, themeManager: themeManager)
                UIApplication.refreshFloatingTabBarMaterial()
            }
            .osrsArticleSceneRestore(
                needsRecovery: $viewModel.needsContentProcessRecovery,
                onLeaveForeground: captureCurrentArticleScroll,
                onEnterForeground: {
                    restoreCapturedArticleScrollIfNeeded()
                },
                onRecover: {
                    viewModel.needsContentProcessRecovery = false
                    viewModel.loadArticle(theme: osrsTheme, isReload: true)
                }
            )
            .onReceive(NotificationCenter.default.publisher(for: .osrsPlayYouTubeRequested)) { notification in
                if let videoId = notification.userInfo?["videoId"] as? String {
                    viewModel.playYouTubeVideo(id: videoId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAppearanceSettings)) { notification in
                highlightFloorNumberingOnAppearance =
                    (notification.userInfo?["highlightFloorNumbering"] as? Bool) == true
                isShowingAppearanceSettings = true
            }
            .onAppear {
                viewModel.navigateToInternalArticle = { url in
                    appState.routeInternalArticleLink(url, sourceArticleURL: pageUrl)
                }
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-startArticleShowAppearance") {
                    highlightFloorNumberingOnAppearance =
                        ProcessInfo.processInfo.arguments.contains("-highlightFloorNumberingOnAppearance")
                    isShowingAppearanceSettings = true
                }
#endif
            }
            .onDisappear {
                viewModel.navigateToInternalArticle = nil
                appState.speechManager.cleanup()
            }
    }

    /// Saved-page cache inspection and listener binding are disk/network preparation, so they
    /// suspend without occupying MainActor. The article request starts only after its selected
    /// routing mode is fully installed; a disappeared view cannot resume a stale load or owner.
    private func beginAppearanceLoad() {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🟢 [\(timestamp)] ARTICLEVIEW: onAppear called - hasLoadedBefore: \(hasLoadedBefore)")
        hideMainTabBar()
        isArticleVisible = true
        viewModel.setArticleVisibility(true, allowsPassiveCaching: savedPageId == nil)

        if hasLoadedBefore {
            if viewModel.shouldReloadArticleOnReappear {
                print("🔄 ARTICLEVIEW: Reloading terminated or empty article document")
                viewModel.loadArticle(theme: osrsTheme, isReload: true)
            } else {
                restoreCapturedArticleScrollIfNeeded()
            }
            updateArticleBottomBar()
            return
        }

        isShowingOfflineCacheBanner = false
        savedCachePreparationTask?.cancel()
        savedCachePreparationTask = nil

        if #available(iOS 17.0, *), let savedCacheSessionToken {
            ProxyInterceptorService.shared.disableMode(owner: savedCacheSessionToken)
            self.savedCacheSessionToken = nil
        }

        let isReload = false
        print("🆕 [\(timestamp)] ARTICLEVIEW: First load - using normal loading")
        hasLoadedBefore = true

        guard #available(iOS 17.0, *) else {
            startPreparedArticleLoad(isReload: isReload)
            return
        }

        guard let savedPageId else {
            startPreparedArticleLoad(isReload: isReload)
            return
        }

        print("🚀 [\(timestamp)] ARTICLEVIEW: Preparing proxy system for saved page: \(savedPageId)")
        savedCachePreparationTask = Task { @MainActor in
            let requestedTitle = osrsArticleDocumentIdentity.requestedTitle(
                pageURL: pageUrl,
                fallbackTitle: pageTitle
            )
            let parseURL = ArticleViewModel.makeParseRequestURL(pageTitle: requestedTitle)
            let hasCache: Bool
            if let parseURL {
                hasCache = await ProxyInterceptorService.shared.hasPersistedMainResponseAsync(
                    pageId: savedPageId,
                    url: parseURL
                )
            } else {
                hasCache = false
            }
            guard !Task.isCancelled else { return }

            let isOffline: Bool
#if DEBUG
            // NWPath is advisory and may be stale during launch/handoff. Only the explicit UI
            // test override selects cache-only; normal cache-first misses reach URLSession.
            isOffline = NetworkManager.shared.isForcedOfflineForTests
#else
            isOffline = false
#endif
            let routingMode = ArticleView.savedCacheRoutingMode(
                hasPersistedMainResponse: hasCache,
                isOffline: isOffline
            )
            let preparedToken: ProxyCacheSessionToken?
            switch routingMode {
            case .cacheOnly:
                if hasCache {
                    print("📦 [\(timestamp)] ARTICLEVIEW: Offline + persisted main response = CACHE-ONLY mode")
                    isShowingOfflineCacheBanner = true
                } else {
                    print("⚠️ [\(timestamp)] ARTICLEVIEW: Offline + no persisted main response; using cache-only failure path")
                }
                preparedToken = await ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: savedPageId)
            case .cacheFirst:
                print("🌐 [\(timestamp)] ARTICLEVIEW: Online + persisted main response = CACHE-FIRST mode")
                preparedToken = await ProxyInterceptorService.shared.enableCacheFirstMode(pageId: savedPageId)
            case .saveWhileServing:
                print("📡 [\(timestamp)] ARTICLEVIEW: Online + no persisted main response = SAVE-WHILE-SERVING mode")
                preparedToken = await ProxyInterceptorService.shared.enableOfflineSaveMode(pageId: savedPageId)
            }

            guard !Task.isCancelled else {
                if let preparedToken {
                    ProxyInterceptorService.shared.disableMode(owner: preparedToken)
                }
                return
            }

            savedCacheSessionToken = preparedToken
            savedCachePreparationTask = nil
            startPreparedArticleLoad(isReload: isReload)
        }
    }

    private func startPreparedArticleLoad(isReload: Bool) {
        viewModel.bindSavedCachePageId(savedPageId)
        viewModel.setCollapseTablesEnabled(collapseTablesEnabled && themeManager.collapseTables)
        viewModel.setArticleTextScale(CGFloat(themeManager.articleTextScale))
        viewModel.applyWrapTableCells(themeManager.wrapTableCells)
        viewModel.loadArticle(theme: osrsTheme, isReload: isReload)
        movedOffTopOfArticleStack = false
        updateArticleBottomBar()
        scheduleSavedSnapshotRefreshIfNeeded()
    }

    private func scheduleSavedSnapshotRefreshIfNeeded() {
        guard let savedPageId else { return }
        let settings = osrsDownloadSettings.load()
        let network = NetworkManager.shared
        let isUnmetered = network.connectionType == .wifi || network.connectionType == .wiredEthernet
        let pendingManual = osrsDownloadSettings.consumePendingManualUpdate(id: savedPageId)
        let trigger: osrsSavedPageUpdateTrigger = pendingManual ? .manual : .access
        guard settings.shouldRefreshSnapshot(
            trigger: trigger,
            isOnline: network.isConnected,
            isUnmetered: isUnmetered
        ) else {
            return
        }
        Task { @MainActor in
            await refreshSavedSnapshotIfRemoteRevisionChanged()
        }
    }

    private func refreshSavedSnapshotIfRemoteRevisionChanged() async {
        let requestedTitle = osrsArticleDocumentIdentity.requestedTitle(
            pageURL: pageUrl,
            fallbackTitle: pageTitle
        )
        let probeURL = osrsSavedPageRevisionProbe.queryURL(forPageTitle: requestedTitle)
        do {
            let (data, _) = try await URLSession.shared.data(from: probeURL)
            guard let remote = osrsSavedPageRevisionProbe.remoteRevision(
                in: data,
                requestedTitle: requestedTitle
            ) else {
                return
            }
            let localRevision = SavedPagesRepository().getSavedPages().first {
                $0.offlineCachePageId == savedPageId || $0.url == pageUrl
            }?.revisionId
            guard osrsSavedPageRevisionProbe.snapshotNeedsRefresh(
                localRevisionId: localRevision,
                remoteRevisionId: remote.revisionId
            ) else {
                return
            }
            await viewModel.performSaveAction(refreshExistingSnapshot: true)
        } catch {
            return
        }
    }

    @ViewBuilder
    private var articleLayout: some View {
        if #available(iOS 26.0, *) {
            articleCanvas
                .ignoresSafeArea()
                .osrsPairedEdgeChrome(edge: .top) {
                    articleTopChrome
                }
        } else {
            VStack(spacing: 0) {
                articleDebugMarker
                articleTopChrome
                articleContentCanvas
            }
        }
    }

    private var articleCanvas: some View {
        ZStack(alignment: .top) {
            articleContentCanvas
                .ignoresSafeArea()
            articleDebugMarker
        }
    }

    @ViewBuilder
    private var articleDebugMarker: some View {
#if DEBUG
        osrsAccessibilityMarker(
            identifier: "article_navigation_stack_state",
            label: appState.osrsNavigationStackDebugLabel
        )
#else
        EmptyView()
#endif
    }

    private var articleTopChrome: some View {
        VStack(spacing: 0) {
            osrsArticleSearchBar(
                onBackAction: { navigateBackFromArticle() },
                onSearchAction: { appState.navigateToActiveSearch() },
                onMenuAction: { action in
                    switch action {
                    case .share: isShowingShareSheet = true
                    case .goToTop: scrollToTop()
                    case .copyLink: copyPageLink()
                    case .refresh: refreshPage()
                    case .openInBrowser: openInBrowser()
                    case .pageHistory: viewPageHistory()
                    case .reportIssue: reportIssue()
                    }
                },
                onVoiceSearchAction: {
                    appState.navigateToActiveSearch(startsVoiceRecognition: true)
                }
            )

            if isShowingOfflineCacheBanner {
                offlineCacheBanner
            }
        }
    }

    private var articleContentCanvas: some View {
        ZStack {
            contentView
            progressOverlay
            errorOverlay
        }
    }

    // MARK: - Overlay Management

    private var articleIdentity: String {
        navigationIdentity ?? "\(pageUrl.absoluteString)|savedPageId=\(savedPageId ?? "")"
    }

    private func setContentsRevealProgress(_ progress: CGFloat, animated: Bool = false) {
        if animated {
            settleContents(to: progress, velocity: 0)
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            contentsRevealProgress = progress
        }
    }

    private func settleContents(to progress: CGFloat, velocity: CGFloat) {
        let target = min(1, max(0, progress))
        let from = contentsRevealProgress
        let animation = osrsContentsReveal.settleAnimation(
            from: from,
            to: target,
            velocity: velocity
        )
        withAnimation(animation) {
            contentsRevealProgress = target
            if target >= 1 {
                isShowingTableOfContents = true
            }
        } completion: {
            if target < 1 {
                isShowingTableOfContents = false
            } else {
                isShowingTableOfContents = true
            }
            contentsRevealProgress = target
        }
    }

    private func captureCurrentArticleScroll() {
        guard let scrollView = viewModel.webView?.scrollView else { return }
        guard scrollView.contentSize.height >= 64 else { return }
        appState.captureArticleScrollOffset(articleIdentity, offsetY: scrollView.contentOffset.y)
    }

    private func restoreCapturedArticleScrollIfNeeded(attempt: Int = 0) {
        guard let offsetY = appState.capturedArticleScrollOffset(articleIdentity),
              offsetY > 1,
              let webView = viewModel.webView else { return }
        let scrollView = webView.scrollView
        scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        webView.evaluateJavaScript("window.scrollTo(0, \(offsetY));")
        let maxOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        if abs(scrollView.contentOffset.y - offsetY) <= 8 ||
            maxOffset + 24 >= offsetY ||
            attempt >= 80 {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.032) {
            self.restoreCapturedArticleScrollIfNeeded(attempt: attempt + 1)
        }
    }

    private func navigateBackFromArticle(animated: Bool = true) {
        let transitionIdentity = "\(articleIdentity)|\(viewModel.articleBackTransitionIdentity)"
        guard appState.beginArticleBackAction(
            articleIdentity: articleIdentity,
            transitionIdentity: transitionIdentity
        ) else {
            hideMainTabBar()
            overlayManager?.setArticleBottomBarExitProgress(0)
            return
        }

        var accepted = false
        var leftArticleStack = false
        defer {
            appState.completeArticleBackAction(
                transitionIdentity: transitionIdentity,
                accepted: accepted
            )
            if accepted && leftArticleStack {
                overlayManager?.hideArticleBottomBar(owner: articleIdentity)
            }
            if accepted {
                overlayManager?.setArticleBottomBarExitProgress(0)
            }
        }

#if DEBUG
        appState.articleBackActionDebugCount += 1
#endif

        if appState.navigateBackWithinActiveArticleStack(animated: animated) {
            accepted = true
            return
        }

        showMainTabBar()
        leftArticleStack = true

        if appState.navigateBackFromActiveRootArticle(animated: animated) {
            accepted = true
            return
        }

        if viewModel.goBackToPreviousWebViewArticleIfNeeded() {
            accepted = true
            return
        }

        if viewModel.recoverRenderedArticleMismatchIfNeeded(theme: osrsTheme, fallbackToNativeBack: {
            appState.navigateBack(animated: animated)
        }) {
            accepted = true
            return
        }

        appState.navigateBack(animated: animated)
        accepted = true
    }

    private var offlineCacheBanner: some View {
        Label("Available offline", systemImage: "wifi.slash")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.osrsPrimaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.osrsSurfaceVariant)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.osrsBorder)
                    .frame(height: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("article_offline_cache_banner")
    }

    private func updateArticleBottomBar() {
        // Only update overlay if manager is available (not in preview rendering)
        guard let overlayManager = overlayManager else { return }
        guard isArticleVisible,
              appState.activeArticleDestination?.navigationIdentity == articleIdentity else {
            overlayManager.hideArticleBottomBar(owner: articleIdentity)
            return
        }
        guard !isShowingFindInPage else {
            overlayManager.hideArticleBottomBar(owner: articleIdentity)
            return
        }

        overlayManager.showArticleBottomBar(owner: articleIdentity) {
            osrsArticleBottomBar(
                onSaveAction: {
                    Task {
                        await performArticleSaveAction()
                    }
                },
                onFindInPageAction: {
                    if isShowingFindInPage {
                        stopFindInPage()
                    } else {
                        startFindInPage()
                    }
                },
                onAppearanceAction: {
                    viewModel.performAppearanceAction()
                },
                onContentsAction: {
                    if osrsContentsReveal.isVisuallyOpen(
                        isPresented: isShowingTableOfContents,
                        interactiveProgress: contentsRevealProgress
                    ) {
                        settleContents(to: 0, velocity: 0)
                    } else {
                        settleContents(to: 1, velocity: 0)
                    }
                },
                isBookmarked: viewModel.isBookmarked,
                saveState: viewModel.saveState,
                saveProgress: viewModel.saveProgress,
                hasTableOfContents: viewModel.hasTableOfContents
            )
        }
    }

    private func hideMainTabBar() {
        guard managesMainTabBarVisibility else { return }
        overlayManager?.hideMainTabBar(owner: articleIdentity)
    }

    @MainActor
    private func performArticleSaveAction() async {
        guard savedPageId != nil, !viewModel.isBookmarked else {
            await viewModel.performSaveAction()
            return
        }

#if DEBUG
        // Forced-offline is a deterministic test policy, not a production reachability guess.
        // Preserve the readable cache owner and expose retry state instead of tearing it down for
        // a refresh that the test transport is explicitly forbidden to perform.
        if NetworkManager.shared.isForcedOfflineForTests {
            viewModel.markOfflineSaveRetryUnavailable()
            return
        }
#endif

        savedCachePreparationTask?.cancel()
        savedCachePreparationTask = nil

        if #available(iOS 17.0, *), let savedCacheSessionToken {
            guard let reservation = ProxyInterceptorService.shared.reserveExplicitSaveLease(
                replacingPresentationOwner: savedCacheSessionToken
            ) else {
                viewModel.markOfflineSaveRetryUnavailable()
                return
            }
            self.savedCacheSessionToken = nil
            scheduleSavedCacheRoutingResumeAfterExplicitSave()
            await viewModel.performSaveAction(explicitSaveReservation: reservation)
            return
        }

        // A saved route with no installed owner (for example after an origin load) can use the
        // view model's ordinary reservation path. Reinstall routing only if this exact article
        // is still visible after the operation finishes.
        await viewModel.performSaveAction()
        scheduleSavedCacheRoutingResumeAfterExplicitSave()
    }

    @MainActor
    private func scheduleSavedCacheRoutingResumeAfterExplicitSave() {
        guard #available(iOS 17.0, *), let initialSavedPageId = savedPageId else { return }
        savedCachePreparationTask?.cancel()
        savedCachePreparationTask = Task { @MainActor in
            do {
                try await ProxyInterceptorService.shared.waitForExplicitSaveRelease()
            } catch {
                return
            }
            guard !Task.isCancelled,
                  isArticleVisible,
                  appState.activeArticleDestination?.navigationIdentity == articleIdentity else {
                return
            }

            let pageId = viewModel.currentSavedCachePageIdForArticle() ?? initialSavedPageId
            let requestedTitle = osrsArticleDocumentIdentity.requestedTitle(
                pageURL: pageUrl,
                fallbackTitle: pageTitle
            )
            let parseURL = ArticleViewModel.makeParseRequestURL(pageTitle: requestedTitle)
            let hasCache: Bool
            if let parseURL {
                hasCache = await ProxyInterceptorService.shared.hasPersistedMainResponseAsync(
                    pageId: pageId,
                    url: parseURL
                )
            } else {
                hasCache = false
            }
            guard !Task.isCancelled,
                  isArticleVisible,
                  appState.activeArticleDestination?.navigationIdentity == articleIdentity else {
                return
            }

            let forceCacheOnly: Bool
#if DEBUG
            forceCacheOnly = NetworkManager.shared.isForcedOfflineForTests
#else
            forceCacheOnly = false
#endif
            let routingMode = ArticleView.savedCacheRoutingMode(
                hasPersistedMainResponse: hasCache,
                isOffline: forceCacheOnly
            )
            let preparedToken: ProxyCacheSessionToken?
            switch routingMode {
            case .cacheOnly:
                preparedToken = await ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: pageId)
            case .cacheFirst:
                preparedToken = await ProxyInterceptorService.shared.enableCacheFirstMode(pageId: pageId)
            case .saveWhileServing:
                preparedToken = await ProxyInterceptorService.shared.enableOfflineSaveMode(pageId: pageId)
            }

            guard !Task.isCancelled,
                  isArticleVisible,
                  appState.activeArticleDestination?.navigationIdentity == articleIdentity else {
                if let preparedToken {
                    ProxyInterceptorService.shared.disableMode(owner: preparedToken)
                }
                return
            }
            savedCacheSessionToken = preparedToken
            savedCachePreparationTask = nil
        }
    }

    private func showMainTabBar() {
        guard managesMainTabBarVisibility else { return }
        overlayManager?.showMainTabBar(owner: articleIdentity)
    }

    private func startFindInPage() {
        findSession += 1
        let session = findSession
        isShowingFindInPage = true
        overlayManager?.hideArticleBottomBar(owner: articleIdentity)
        viewModel.performFindInPageAction {
            monitorFindNavigatorVisibility(session: session)
        }
    }

    private func stopFindInPage() {
        findSession += 1
        viewModel.hideFindInPageAction()
        isShowingFindInPage = false
        updateArticleBottomBar()
    }

    private func monitorFindNavigatorVisibility(session: Int, hasAppeared: Bool = false, attempts: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard isShowingFindInPage, session == findSession else { return }

            if viewModel.isNativeFindNavigatorVisible() {
                overlayManager?.hideArticleBottomBar(owner: articleIdentity)
                monitorFindNavigatorVisibility(session: session, hasAppeared: true, attempts: attempts + 1)
            } else if !hasAppeared && attempts < 20 {
                // WKFindInteraction reports false while the navigator is still presenting. Do
                // not resurrect the article bar into the keyboard during that launch window.
                monitorFindNavigatorVisibility(session: session, hasAppeared: false, attempts: attempts + 1)
            } else {
                isShowingFindInPage = false
                updateArticleBottomBar()
            }
        }
    }

    // MARK: - Menu Action Helpers

#if DEBUG
    private func dumpArticleTableMetricsIfRequested(attempt: Int = 0) {
        guard ProcessInfo.processInfo.arguments.contains("-osrsDumpTableMetrics") else { return }
        let delay = attempt == 0 ? 1.2 : 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [viewModel] in
            viewModel.webView?.evaluateJavaScript(
                "JSON.stringify(window.__osrsDumpArticleTableMetrics && window.__osrsDumpArticleTableMetrics())"
            ) { result, _ in
                guard let json = result as? String, json != "null" else {
                    if attempt < 8 { self.dumpArticleTableMetricsIfRequested(attempt: attempt + 1) }
                    return
                }
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("osrs-table-metrics.json")
                try? json.write(to: url, atomically: true, encoding: .utf8)
                print("📊 TABLE METRICS \(url.path)")
                print("📊 TABLE METRICS \(json)")
            }
        }
    }
#endif

    private func consumePendingArticleScrollIfNeeded(attempt: Int = 0) {
        guard let section = appState.pendingArticleScrollSection, !section.isEmpty else { return }
        let delay = attempt == 0 ? 0.6 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [viewModel, appState] in
            viewModel.scrollToSection(section)
            if attempt < 16 {
                self.consumePendingArticleScrollIfNeeded(attempt: attempt + 1)
            } else {
                appState.pendingArticleScrollSection = nil
            }
        }
    }

    private func scrollToTop() {
        viewModel.webView?.evaluateJavaScript("window.scrollTo(0, 0);") { _, _ in
            // Could add haptic feedback or visual confirmation here
        }
    }

    private func copyPageLink() {
        let pasteboard = UIPasteboard.general
        pasteboard.string = pageUrl.absoluteString
        // Could show a toast or alert here to confirm the copy action
    }

    private func refreshPage() {
        viewModel.refreshPage(theme: osrsTheme)
    }

    private func openInBrowser() {
        UIApplication.shared.open(pageUrl)
    }

    private func viewPageHistory() {
        if let pageTitle = pageTitle?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            let historyUrl = URL(string: "https://oldschool.runescape.wiki/w/Special:History/\(pageTitle)")!
            UIApplication.shared.open(historyUrl)
        }
    }

    private func reportIssue() {
        isShowingFeedback = true
    }

    // MARK: - Computed Views for Refresh Logic

    @ViewBuilder
    private var contentView: some View {
        // WebView always present to allow loading completion
        ArticleWebView(
            viewModel: viewModel,
            navigationDelegate: navigationDelegate,
            onBackGesture: themeManager.swipeRightToGoBackEnabled ? {
                print("[ArticleView] Horizontal back gesture triggered")
                setContentsRevealProgress(0)
                navigateBackFromArticle(animated: false)
            } : nil,
            onSidebarGesture: themeManager.swipeLeftToShowContentsEnabled ? {
                print("[ArticleView] Horizontal sidebar gesture triggered")
                settleContents(to: 1, velocity: 0)
            } : nil,
            onSidebarProgress: { progress in
                setContentsRevealProgress(progress)
                if progress >= 1 {
                    isShowingTableOfContents = true
                } else if progress <= 0 {
                    isShowingTableOfContents = false
                }
            },
            onSidebarSettle: { target, velocity in
                settleContents(to: target, velocity: velocity)
            },
            onBackProgress: { progress in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    // Keep the live overlay bar visible and translate it with the
                    // article. Liquid Glass is not captured by window snapshots, so
                    // covering the bar made it vanish at the first pixel of a swipe.
                    overlayManager?.setArticleBottomBarCovered(false)
                    overlayManager?.setArticleBottomBarExitProgress(progress)
                }
            },
            isContentsOpen: {
                osrsContentsReveal.isVisuallyOpen(
                    isPresented: isShowingTableOfContents,
                    interactiveProgress: contentsRevealProgress
                )
            }
        )
            .background(Color.osrsBackground)
    }

    @ViewBuilder
    private var progressOverlay: some View {
        EmptyView()
    }

    @ViewBuilder
    private var errorOverlay: some View {
        // ERROR STATE: Show visible error message when loading fails
        if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)

                Text("Failed to Load Page")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(errorMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Button("Retry") {
                    viewModel.loadArticle(theme: osrsTheme, isReload: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.osrsBackground)
            .osrsInteractiveBackSwipe(
                enabled: themeManager.swipeRightToGoBackEnabled,
                onBack: { navigateBackFromArticle(animated: false) }
            )
            .transition(.opacity)
            .zIndex(3)  // Highest priority over progress and content
        }
    }
}

// Share Sheet implementation
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: applicationActivitiesForCurrentEnvironment()
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    private func applicationActivitiesForCurrentEnvironment() -> [UIActivity]? {
#if DEBUG
        if osrsTestEnvironment.usesTestShareReceiverActivityForUITests {
            return [osrsTestShareReceiverActivity()]
        }
#endif
        return nil
    }
}

#if DEBUG
private final class osrsTestShareReceiverActivity: UIActivity {
    private var activityItems: [Any] = []

    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.omiyawaki.osrswiki.tests.share-receiver")
    }

    override var activityTitle: String? {
        "OSRS Test Receiver"
    }

    override var activityImage: UIImage? {
        UIImage(systemName: "tray.and.arrow.down")
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        !activityItems.isEmpty
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        self.activityItems = activityItems
    }

    override func perform() {
        activityDidFinish(true)
    }

    override var activityViewController: UIViewController? {
        osrsTestShareReceiverViewController(payload: payloadRecord()) { [weak self] in
            self?.activityDidFinish(true)
        }
    }

    private func payloadRecord() -> String {
        let renderedItems = activityItems.map { item in
            if let string = item as? String {
                return string
            }

            if let url = item as? URL {
                if url.isFileURL, let fileText = try? String(contentsOf: url, encoding: .utf8) {
                    return fileText
                }
                return url.absoluteString
            }

            return String(describing: item)
        }

        return (["osrs_test_share_receiver_completed"] + renderedItems).joined(separator: "\n")
    }
}

private final class osrsTestShareReceiverViewController: UIViewController {
    private let payload: String
    private let onComplete: () -> Void

    init(payload: String, onComplete: @escaping () -> Void) {
        self.payload = payload
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "osrs_test_share_receiver_completed"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityIdentifier = "osrs_test_share_receiver_completed"

        let payloadLabel = UILabel()
        payloadLabel.text = payload
        payloadLabel.numberOfLines = 0
        payloadLabel.font = .preferredFont(forTextStyle: .body)
        payloadLabel.adjustsFontForContentSizeCategory = true
        payloadLabel.accessibilityIdentifier = "osrs_test_share_receiver_payload"

        let completeButton = UIButton(type: .system)
        completeButton.setTitle("Complete", for: .normal)
        completeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        completeButton.titleLabel?.adjustsFontForContentSizeCategory = true
        completeButton.accessibilityIdentifier = "osrs_test_share_receiver_complete"
        completeButton.addTarget(self, action: #selector(complete), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [titleLabel, payloadLabel, completeButton])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    @objc private func complete() {
        onComplete()
    }
}
#endif

// Table of Contents Sheet
struct TableOfContentsView: View {
    let sections: [TableOfContentsSection]
    let onSectionSelected: (String) -> Void

    var body: some View {
        NavigationStack {
            List(sections) { section in
                Button(action: {
                    onSectionSelected(section.id)
                }) {
                    HStack {
                        Text(section.title)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.osrsSecondaryTextColor)
                            .font(.caption)
                    }
                }
                .padding(.leading, CGFloat(section.level * 16))
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        ArticleView(
            pageTitle: "Sample Article",
            pageUrl: URL(string: "about:blank")!
        )
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
    }
}

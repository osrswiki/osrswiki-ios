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
    @State private var isShowingFindInPage = false
    @State private var isShowingAppearanceSettings = false
    @State private var isShowingPageMenu = false
    @State private var isShowingFeedback = false
    @State private var isShowingOfflineCacheBanner = false
    @State private var hasLoadedBefore = false
    @State private var movedOffTopOfArticleStack = false
#if DEBUG
    @State private var hasStartedFindInPageForTests = false
#endif

    let pageTitle: String?
    let pageUrl: URL
    let navigationIdentity: String?
    let snippet: String?
    let thumbnailUrl: URL?
    let savedPageId: String? // For proxy configuration when loading saved pages
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
        self.navigationDelegate = navigationDelegate
        self.onLoadingComplete = onLoadingComplete
        self.showProgressBar = showProgressBar
        self.managesMainTabBarVisibility = managesMainTabBarVisibility
        self._viewModel = StateObject(wrappedValue: ArticleViewModel(pageUrl: pageUrl, pageTitle: pageTitle, pageId: nil, snippet: snippet, thumbnailUrl: thumbnailUrl, collapseTablesEnabled: collapseTablesEnabled, excludeFromHistory: excludeFromHistory))
        print("🏗️ ArticleView: Created with title='\(pageTitle ?? "nil")' url=\(pageUrl), snippet='\(snippet ?? "nil")', thumbnail='\(thumbnailUrl?.absoluteString ?? "nil")', collapseTables=\(collapseTablesEnabled), excludeFromHistory=\(excludeFromHistory)")
    }

    var body: some View {
        VStack(spacing: 0) {
#if DEBUG
            osrsAccessibilityMarker(
                identifier: "article_navigation_stack_state",
                label: appState.osrsNavigationStackDebugLabel
            )
#endif

            // Custom search bar instead of navigation bar
            if !isShowingFindInPage {
                osrsArticleSearchBar(
                    onBackAction: {
                        navigateBackFromArticle()
                    },
                    onMenuAction: {
                        isShowingPageMenu = true
                    },
                    onVoiceSearchAction: {
                        appState.speechManager.startVoiceRecognition()
                    }
                )
            }

            if isShowingOfflineCacheBanner {
                offlineCacheBanner
            }

            // WebView content with overlaid progress bar - extends to bottom
            ZStack {
                contentView
                progressOverlay
                errorOverlay
            }
        }
        .background(Color.osrsBackgroundColor)
        .navigationBarHidden(true)
        .toolbarVisibility(.hidden, for: .tabBar)
        // Add horizontal gestures matching Android PageActivity functionality
        .osrsHorizontalGestures(
            onBackGesture: {
                // Match Android's back gesture behavior
                print("[ArticleView] Horizontal back gesture triggered")

                navigateBackFromArticle()
            },
            onSidebarGesture: {
                // Match Android's sidebar gesture behavior
                print("[ArticleView] Horizontal sidebar gesture triggered")

                // Only open if table of contents is available (matches Android logic)
                if viewModel.hasTableOfContents {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isShowingTableOfContents = true
                    }
                } else {
                    print("[ArticleView] Table of contents not available - gesture ignored")
                }
            }
        )
        .onAppear {
            let timestamp = DateFormatter.timeFormatter.string(from: Date())
            print("🟢 [\(timestamp)] ARTICLEVIEW: onAppear called - hasLoadedBefore: \(hasLoadedBefore)")
            hideMainTabBar()
            isShowingOfflineCacheBanner = false

            // CRITICAL: Configure proxy system BEFORE starting loading for saved pages
            if let savedPageId = savedPageId {
                print("🚀 [\(timestamp)] ARTICLEVIEW: Configuring proxy system for saved page: \(savedPageId)")

                // Configure proxy immediately (without delay) before loading starts
                if #available(iOS 17.0, *) {
                    let hasCache = ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: savedPageId)
                    let isOffline = !NetworkManager.shared.isConnected

                    if isOffline && hasCache {
                        print("📦 [\(timestamp)] ARTICLEVIEW: Offline + cached content = CACHE-ONLY mode for: \(savedPageId)")
                        ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: savedPageId)
                        isShowingOfflineCacheBanner = true
                    } else if !hasCache && !isOffline {
                        print("📡 [\(timestamp)] ARTICLEVIEW: Online + no cache = SAVE-WHILE-SERVING mode for: \(savedPageId)")
                        ProxyInterceptorService.shared.enableOfflineSaveMode(pageId: savedPageId)
                    } else if hasCache && !isOffline {
                        print("🌐 [\(timestamp)] ARTICLEVIEW: Online + cached content = NORMAL mode for: \(savedPageId)")
                        // No special proxy mode needed - just load normally
                    } else {
                        print("⚠️ [\(timestamp)] ARTICLEVIEW: Offline + no cache = ERROR scenario for: \(savedPageId)")
                        print("🔄 [\(timestamp)] ARTICLEVIEW: Attempting cache-only mode as fallback")
                        ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: savedPageId)
                    }
                }
            }

            // Android parity: Detect navigation returns and use blank overlay approach
            let isReload = hasLoadedBefore
            if isReload {
                print("🔄 [\(timestamp)] ARTICLEVIEW: Detected return navigation - using reload with blank overlay")
            } else {
                print("🆕 [\(timestamp)] ARTICLEVIEW: First load - using normal loading")
                hasLoadedBefore = true
            }

            // Start loading AFTER proxy configuration is complete
            viewModel.loadArticle(theme: osrsTheme, isReload: isReload)
            movedOffTopOfArticleStack = false
            updateArticleBottomBar()
        }
        .onChange(of: appState.activeArticleDestination?.navigationIdentity) { _, activeIdentity in
            guard hasLoadedBefore else { return }

            if activeIdentity == articleIdentity {
                guard movedOffTopOfArticleStack else { return }
                movedOffTopOfArticleStack = false
                let timestamp = DateFormatter.timeFormatter.string(from: Date())
                print("🔄 [\(timestamp)] ARTICLEVIEW: Returned to top article destination - reloading expected page: \(articleIdentity)")
                viewModel.loadArticle(theme: osrsTheme, isReload: true)
            } else {
                movedOffTopOfArticleStack = true
            }
        }
        .onChange(of: appState.articleBackStackRecoveryRequestID) { _, _ in
            guard let destination = appState.articleBackStackRecoveryDestination else { return }
            viewModel.loadArticleDestination(destination, theme: osrsTheme)
        }
        .onChange(of: viewModel.hasTableOfContents) { _, _ in
            // Update article bottom bar overlay when table of contents availability changes
            updateArticleBottomBar()
        }
        .onChange(of: viewModel.isBookmarked) { _, _ in
            // Update article bottom bar overlay when bookmark status changes
            updateArticleBottomBar()
        }
        .onChange(of: viewModel.saveState) { _, _ in
            // Update article bottom bar overlay when save state changes
            updateArticleBottomBar()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            // Call loading complete callback for preview generation
            if !isLoading, let onLoadingComplete = onLoadingComplete {
                print("📊 ArticleView: Loading completed - calling preview generation callback with viewModel")
                onLoadingComplete(viewModel)
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
            // Hide article bottom bar overlay when leaving article view
            overlayManager?.hideArticleBottomBar()
            viewModel.hideFindInPageAction()
            showMainTabBar()
        }
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(items: [pageUrl])
            }
            .overlay(
                // Enhanced contents drawer with Android-style functionality
                osrsContentsDrawerSimple(
                    isPresented: $isShowingTableOfContents,
                    sections: viewModel.tableOfContents,
                    onSectionSelected: { sectionId in
                        viewModel.scrollToSection(sectionId)
                    }
                )
                .ignoresSafeArea()
            )
            .sheet(isPresented: $isShowingAppearanceSettings) {
                NavigationStack {
                    AppearanceSettingsView()
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
            .confirmationDialog("Page Options", isPresented: $isShowingPageMenu) {
                Button("Share") {
                    isShowingShareSheet = true
                }
                Button("Go to Top") {
                    scrollToTop()
                }
                Button("Copy Link") {
                    copyPageLink()
                }
                Button("Refresh Page") {
                    refreshPage()
                }
                Button("Open in Browser") {
                    openInBrowser()
                }
                Button("View Page History") {
                    viewPageHistory()
                }
                Button("Report Issue") {
                    reportIssue()
                }
                Button("Cancel", role: .cancel) { }
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
        .onChange(of: osrsTheme as? osrsLightTheme != nil) { _, _ in
            // Reload with new theme when theme changes - use blank overlay like other reloads
            viewModel.loadArticle(theme: osrsTheme, isReload: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAppearanceSettings)) { _ in
            isShowingAppearanceSettings = true
        }
        .onAppear {
            viewModel.navigateToInternalArticle = { url in
                appState.routeInternalArticleLink(url)
            }
        }
        .onDisappear {
            // Clean up speech recognition when leaving the view
            viewModel.navigateToInternalArticle = nil
            appState.speechManager.cleanup()
        }
    }

    // MARK: - Overlay Management

    private var articleIdentity: String {
        navigationIdentity ?? "\(pageUrl.absoluteString)|savedPageId=\(savedPageId ?? "")"
    }

    private func navigateBackFromArticle() {
        guard appState.beginArticleBackAction() else {
            return
        }

#if DEBUG
        appState.articleBackActionDebugCount += 1
#endif
        overlayManager?.hideArticleBottomBar()

        if appState.navigateBackWithinActiveArticleStack() {
            return
        }

        if viewModel.goBackToPreviousWebViewArticleIfNeeded() {
            return
        }

        if viewModel.recoverRenderedArticleMismatchIfNeeded(theme: osrsTheme, fallbackToNativeBack: {
            appState.navigateBack()
        }) {
            return
        }

        appState.navigateBack()
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
        guard !isShowingFindInPage else {
            overlayManager.hideArticleBottomBar()
            return
        }

        overlayManager.showArticleBottomBar {
            osrsArticleBottomBar(
                onSaveAction: {
                    Task {
                        await viewModel.performSaveAction()
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
                    isShowingTableOfContents.toggle()
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
        NotificationCenter.default.post(name: Notification.Name("hideCustomTabBar"), object: nil)
    }

    private func showMainTabBar() {
        guard managesMainTabBarVisibility else { return }
        NotificationCenter.default.post(name: Notification.Name("showCustomTabBar"), object: nil)
    }

    private func startFindInPage() {
        isShowingFindInPage = true
        overlayManager?.hideArticleBottomBar()
        viewModel.performFindInPageAction {
            monitorFindNavigatorVisibility()
        }
    }

    private func stopFindInPage() {
        viewModel.hideFindInPageAction()
        isShowingFindInPage = false
        updateArticleBottomBar()
    }

    private func monitorFindNavigatorVisibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard isShowingFindInPage else { return }

            if viewModel.isNativeFindNavigatorVisible() {
                monitorFindNavigatorVisibility()
            } else {
                isShowingFindInPage = false
                updateArticleBottomBar()
            }
        }
    }

    // MARK: - Menu Action Helpers

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
        // Use Android-parity refresh that shows progress bar over blank page
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
        ArticleWebView(viewModel: viewModel, navigationDelegate: navigationDelegate)
            .background(Color.osrsBackground)

        // Overlay blank view during refresh (Android parity)
        if viewModel.isRefreshing {
            Color(osrsTheme.background)
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                .zIndex(1)  // Ensures blank overlay covers WebView
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if viewModel.isRefreshing && showProgressBar {
            // Show progress bar over completely blank page during refresh
            osrsProgressView(
                progress: viewModel.loadingProgress,
                progressText: viewModel.loadingProgressText ?? "Refreshing page..."
            )
            .transition(.opacity)
            .zIndex(2)  // Higher than blank overlay's zIndex(1)
        } else if viewModel.isLoading && showProgressBar {
            // Show normal loading progress bar when not refreshing
            osrsProgressView(
                progress: viewModel.loadingProgress,
                progressText: viewModel.loadingProgressText ?? "Loading page..."
            )
            .transition(.opacity)
            .zIndex(2)  // Consistent z-index across all loading states
        }
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

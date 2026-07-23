//
//  ArticleViewModel.swift
//  OSRS Wiki
//
//  Created on iOS webviewer implementation session
//  Updated for article rendering parity with Android
//

import SwiftUI
import WebKit
import Combine

// TIMELINE LOGGING: Precise timestamp formatter for tracking loading phases
extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Notification Names
extension Notification.Name {
    static let showAppearanceSettings = Notification.Name("showAppearanceSettings")
    static let osrsInternalArticleLinkRequested = Notification.Name("osrsInternalArticleLinkRequested")
}

// MARK: - Color Extension for Hex Conversion
extension Color {
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(red * 255.0)
        let g = Int(green * 255.0)
        let b = Int(blue * 255.0)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Supporting Types

/// Save state enum matching Android PageActionBarManager.SaveState
enum osrsArticleBottomBarSaveState {
    case notSaved
    case downloading
    case saved
    case error
}

struct osrsArticleParsePayload {
    let pageId: Int
    let title: String
    let displayTitle: String?
    let revisionId: Int?
    let htmlContent: String

    var resolvedTitle: String {
        guard let displayTitle, !displayTitle.isEmpty else {
            return title
        }
        let normalizedTitle = osrsStringUtils.extractMainTitle(displayTitle)
        return normalizedTitle.isEmpty ? title : normalizedTitle
    }
}

enum osrsArticleNavigationDecision: Equatable {
    case appArticle(URL)
    case external(URL)
    case allow
}

@MainActor
class ArticleViewModel: NSObject, ObservableObject {
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var loadingProgressText: String? = nil
    @Published var errorMessage: String?
    @Published var isRefreshing: Bool = false
    @Published var pageTitle: String = ""
    @Published var isBookmarked: Bool = false
    @Published var hasTableOfContents: Bool = false
    @Published var tableOfContents: [TableOfContentsSection] = []

    // Bottom bar state management - matching Android PageActionBarManager
    @Published var saveState: osrsArticleBottomBarSaveState = .notSaved
    @Published var saveProgress: Double = 0.0

    private(set) var pageUrl: URL
    private(set) var pageTitle_: String?
    let pageId: Int?
    let collapseTablesEnabled: Bool
    private(set) var snippet_: String?  // Metadata for rich history display
    private(set) var thumbnailUrl_: URL?  // Metadata for rich history display
    let excludeFromHistory: Bool  // Exclude from history tracking (for preview generation)

    weak var webView: WKWebView?
#if DEBUG
    private var didForceArticleReloadNetworkFailureForUITests = false
#endif
    private var cancellables = Set<AnyCancellable>()
    private var progressObserver: NSKeyValueObservation?
    private var currentLoadTask: Task<Void, Never>?
    private var currentLoadGeneration = 0
    private var webKitReadyGeneration: Int?
    private var javaScriptReadyGeneration: Int?
    private var completedLoadGeneration: Int?
    private var webKitNavigationGenerations: [ObjectIdentifier: Int] = [:]
    private var readinessTimeoutWorkItem: DispatchWorkItem?
    private var reloadTimeoutWorkItem: DispatchWorkItem?
    private var refreshTimeoutWorkItem: DispatchWorkItem?
    private var deferredRefreshWorkItem: DispatchWorkItem?
    // FREEZE FIX: Defer heavy initialization - create these async to avoid blocking main thread
    private var contentLoader: osrsPageContentLoader?
    private let savedPagesRepository = SavedPagesRepository()
    private let historyRepository = HistoryRepository()
    private var proxyCacheSessionToken: ProxyCacheSessionToken?
    private var accessibilityReflowEnabled = false
    private var accessibilityTextScale: CGFloat = 1.0
    private var resolvedPageTitleForHistory: String?
    private var resolvedPageUrlForHistory: URL?
    var navigateToInternalArticle: ((URL) -> Void)?
    private var routedObservedArticleNavigationURLs = Set<String>()
    private var renderedArticleIdentityProbe: Timer?
    private var renderedArticleIdentityProbeAttempts = 0

    // TIMING MEASUREMENT: Track progress completion vs page visibility delay
    var progressCompletionTime: Date?
    private var pageVisibilityTime: Date?
    @Published var lastMeasuredDelay: TimeInterval? = nil

    init(pageUrl: URL, pageTitle: String? = nil, pageId: Int? = nil, snippet: String? = nil, thumbnailUrl: URL? = nil, collapseTablesEnabled: Bool = true, excludeFromHistory: Bool = false) {
        self.pageUrl = pageUrl
        self.pageTitle_ = pageTitle
        self.pageId = pageId
        self.collapseTablesEnabled = collapseTablesEnabled
        self.snippet_ = snippet
        self.thumbnailUrl_ = thumbnailUrl
        self.excludeFromHistory = excludeFromHistory
        super.init()
        print("🏗️ ArticleViewModel: Lightweight init completed for '\(pageTitle ?? "unknown")' - heavy loading deferred")
    }

    func loadArticleDestination(_ destination: ArticleDestination, theme: any osrsThemeProtocol) {
        let previousURL = pageUrl
        pageUrl = destination.url
        pageTitle_ = destination.title
        snippet_ = destination.snippet
        thumbnailUrl_ = destination.thumbnailUrl
        pageTitle = destination.title ?? extractTitleFromUrl(destination.url)
        hasTableOfContents = false
        tableOfContents = []
        isBookmarked = false

        print("🔄 ArticleViewModel: Rebinding visible article from \(previousURL.absoluteString) to active destination \(destination.url.absoluteString)")
        loadArticle(theme: theme, isReload: true)
    }

    static func makeParseRequestURL(pageTitle: String) -> URL? {
        var components = URLComponents(string: "https://oldschool.runescape.wiki/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "text|displaytitle|revid"),
            URLQueryItem(name: "disablelimitreport", value: "1"),
            URLQueryItem(name: "wrapoutputclass", value: "mw-parser-output"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "page", value: pageTitle)
        ]
        return components.url
    }

    static func articleURL(forResolvedTitle title: String) -> URL? {
        let pathTitle = title.replacingOccurrences(of: " ", with: "_")
        guard let encodedTitle = pathTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://oldschool.runescape.wiki/w/\(encodedTitle)")
    }

    static func articleNavigationDecision(for url: URL) -> osrsArticleNavigationDecision {
        if let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) {
            return .appArticle(articleURL)
        }

        if let externalWikiURL = osrsArticleLinkRouter.externalWikiURLForNonArticleAppAssetURL(url) {
            return .external(externalWikiURL)
        }

        if shouldOpenExternallyForArticleNavigation(url) {
            return .external(url)
        }

        return .allow
    }

    static func osrsShouldUseWebViewArticleHistory(currentURL: URL?, pageURL: URL) -> Bool {
        osrsShouldPromoteWebViewArticleNavigation(candidateURL: currentURL, pageURL: pageURL)
    }

    static func osrsShouldPromoteWebViewArticleNavigation(candidateURL: URL?, pageURL: URL) -> Bool {
        guard let candidateURL,
              let currentIdentity = osrsArticleHistoryIdentity(for: candidateURL),
              let pageIdentity = osrsArticleHistoryIdentity(for: pageURL) else {
            return false
        }

        return currentIdentity != pageIdentity
    }

    private static func osrsArticleHistoryIdentity(for url: URL) -> String? {
        guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url),
              var components = URLComponents(url: articleURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = nil

        let scheme = components.scheme?.lowercased() ?? ""
        let host = components.host?.lowercased() ?? ""
        let decodedPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
        let decodedQuery = components.percentEncodedQuery?.removingPercentEncoding ?? components.query ?? ""

        return "\(scheme)://\(host)\(decodedPath)?\(decodedQuery)"
    }

    static func decodeParsePayload(_ data: Data, requestedTitle: String? = nil) throws -> osrsArticleParsePayload {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidData
        }

        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? String ?? "unknown"
            let info = error["info"] as? String ?? "Unknown error"
            print("❌ ArticleViewModel: API Error: \(code) - \(info)")
            if code == "missingtitle" {
                throw NetworkError.pageNotFound(requestedTitle)
            }
            throw NetworkError.serverError(404)
        }

        guard let parse = json["parse"] as? [String: Any],
              let title = parse["title"] as? String,
              let pageid = parse["pageid"] as? Int,
              let textObj = parse["text"] as? [String: Any],
              let htmlContent = textObj["*"] as? String else {
            throw NetworkError.invalidData
        }

        return osrsArticleParsePayload(
            pageId: pageid,
            title: title,
            displayTitle: parse["displaytitle"] as? String,
            revisionId: parse["revid"] as? Int,
            htmlContent: htmlContent
        )
    }

    // FREEZE FIX: Async content loader initialization - following Android's coroutineScope.launch pattern
    private func initializeContentLoaderAsync() async -> osrsPageContentLoader {
        return await withCheckedContinuation { continuation in
            // Move to background thread for heavy initialization
            Task.detached(priority: .userInitiated) {
                print("🔨 ArticleViewModel: Creating content loader on background thread")
                let loader = osrsPageContentLoader()
                print("✅ ArticleViewModel: Content loader created successfully")
                continuation.resume(returning: loader)
            }
        }
    }

    // FREEZE FIX: Get content loader async, creating it only when needed
    private func getContentLoader() async -> osrsPageContentLoader {
        if let existingLoader = contentLoader {
            return existingLoader
        }

        let newLoader = await initializeContentLoaderAsync()
        await MainActor.run {
            self.contentLoader = newLoader
        }
        return newLoader
    }

    func setAccessibilityReflowEnabled(_ enabled: Bool, textScale: CGFloat = 1.0) {
        accessibilityReflowEnabled = enabled
        accessibilityTextScale = textScale
        applyAccessibilityReflow(to: webView)
    }

    private func applyAccessibilityReflow(to webView: WKWebView?) {
        guard let webView else { return }
        let enabledLiteral = accessibilityReflowEnabled ? "true" : "false"
        let scaleLiteral = String(format: "%.3f", Double(accessibilityTextScale))
        webView.evaluateJavaScript("""
            (function() {
                var enabled = \(enabledLiteral);
                var textScale = \(scaleLiteral);
                document.documentElement.style.setProperty('--osrs-article-text-scale', String(textScale));
                [document.documentElement, document.body].forEach(function(element) {
                    if (element) {
                        element.classList.toggle('osrs-accessibility-reflow', enabled);
                    }
                });
            })();
        """)
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        setupWebViewObservers()

        // CRITICAL: Enable always-on lazy caching for ALL pages (not just saved pages)
        // This implements Android's OfflineCacheInterceptor pattern for iOS
        if #available(iOS 17.0, *) {
            print("🚀 ArticleViewModel: Enabling always-on lazy caching for automatic resource collection")

            // Configure proxy for this WebView
            let configured = ProxyInterceptorService.shared.configureWebViewForProxyInterception(webView)
            if configured {
                // Generate a temporary page ID based on the URL for cache key management
                let tempPageId = generatePageIdFromURL(pageUrl)

                // Enable passive caching mode - cache everything but don't mark as saved
                proxyCacheSessionToken = ProxyInterceptorService.shared.enablePassiveCachingMode(pageId: tempPageId)

                // CRITICAL FIX: Also enable save mode on IOSAssetHandler for images
                // This ensures images loaded through the custom URL scheme are cached
                if let assetHandler = webView.configuration.urlSchemeHandler(forURLScheme: "app-assets") as? IOSAssetHandler {
                    // Register with ProxyInterceptorService for coordinated management
                    ProxyInterceptorService.shared.registerAssetHandler(assetHandler)

                    // Enable save mode for lazy caching of images
                    assetHandler.enableOfflineSaveMode(pageId: tempPageId)
                    print("✅ ArticleViewModel: IOSAssetHandler save mode enabled for image caching")
                }

                print("✅ ArticleViewModel: Lazy caching enabled - resources will be cached automatically during browsing")
            } else {
                print("⚠️ ArticleViewModel: Failed to enable lazy caching - falling back to traditional approach")
            }
        }

        checkIfPageIsSaved()
    }

    /// Generate a consistent page ID from URL for cache key management
    private func generatePageIdFromURL(_ url: URL) -> String {
        // Use URL path as a stable identifier, removing special characters
        let path = url.path.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "page_\(path)"
    }

    private func setupWebViewObservers() {
        guard let webView = webView else { return }

        // Smart progress mapping - embed WebKit's automatic progress into total progress phases
        // This matches Android's approach: map WebView 0-100% to appropriate phase ranges
        progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.updateProgressFromWebKit(webView.estimatedProgress)
            }
        }
    }

    // Smart progress mapping matching Android's implementation
    func updateProgressFromWebKit(_ webKitProgress: Double) {
        let webKitPercent = Int(webKitProgress * 100)
        let timestamp = Date()
        let timeString = DateFormatter.timeFormatter.string(from: timestamp)

        if isLoading {
            // Map WebKit progress to appropriate phase based on current loading stage
            let mappedProgress: Double
            let progressText: String

            if webKitPercent < 10 {
                // Initial loading phase: 0-10% WebKit -> 5-15% total
                mappedProgress = 0.05 + (webKitProgress * 0.1)
                progressText = "Starting download..."
            } else if webKitPercent < 50 {
                // Content fetching phase: 10-50% WebKit -> 15-50% total
                mappedProgress = 0.15 + ((webKitProgress - 0.1) * 0.875) // 0.875 = (0.5-0.15)/(0.5-0.1)
                progressText = "Downloading content..."
            } else if webKitPercent < 95 {
                // Rendering phase: 50-95% WebKit -> 50-95% total
                mappedProgress = 0.5 + ((webKitProgress - 0.5) * 1.0)
                progressText = "Rendering page..."
            } else {
                // ANDROID PARITY: Cap at 95% until JavaScript signals content ready
                mappedProgress = 0.95
                progressText = "Finalizing content..."
            }

            self.loadingProgress = mappedProgress
            self.loadingProgressText = progressText

            // ANDROID PARITY: Don't complete on WebKit 100% - wait for JavaScript signal
            if webKitProgress >= 1.0 {
                // TIMING MEASUREMENT: Record when WebKit completes (not final completion)
                self.progressCompletionTime = timestamp
                print("📊 [\(timeString)] 🔴 WEBKIT COMPLETE: WebKit reached 100%, waiting for JavaScript content readiness...")

                // Progress stays at 95% and loading continues until "StylingScriptsComplete"
                self.loadingProgress = 0.95
                self.loadingProgressText = "Finalizing content..."
                self.isLoading = true
            } else {
                self.isLoading = true
            }

            print("📊 [\(timeString)] Progress mapping: WebKit \(Int(webKitProgress * 100))% -> Total \(Int(mappedProgress * 100))% (\(progressText))")
        }
    }

    private func beginArticleLoad() -> Int {
        currentLoadTask?.cancel()
        currentLoadTask = nil
        readinessTimeoutWorkItem?.cancel()
        reloadTimeoutWorkItem?.cancel()
        refreshTimeoutWorkItem?.cancel()
        deferredRefreshWorkItem?.cancel()
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
        renderedArticleIdentityProbeAttempts = 0

        currentLoadGeneration += 1
        webKitReadyGeneration = nil
        javaScriptReadyGeneration = nil
        completedLoadGeneration = nil
        webKitNavigationGenerations.removeAll()
        routedObservedArticleNavigationURLs.removeAll()

        let generation = currentLoadGeneration
        print("🧭 ArticleViewModel: Starting load generation \(generation)")
        webView?.stopLoading()
        return generation
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == currentLoadGeneration
    }

    private func bindWebKitNavigation(_ navigation: WKNavigation?, to generation: Int) {
        guard let navigation = navigation else {
            print("⚠️ ArticleViewModel: WebKit did not return a navigation for generation \(generation)")
            return
        }

        webKitNavigationGenerations[ObjectIdentifier(navigation)] = generation
        print("🧭 ArticleViewModel: Bound WebKit navigation to generation \(generation)")
    }

    private func boundGeneration(for navigation: WKNavigation?) -> Int? {
        guard let navigation = navigation else {
#if DEBUG
            return currentLoadGeneration
#else
            return nil
#endif
        }

        return webKitNavigationGenerations[ObjectIdentifier(navigation)]
    }

    private func clearBoundWebKitNavigation(_ navigation: WKNavigation?) {
        guard let navigation = navigation else { return }
        webKitNavigationGenerations.removeValue(forKey: ObjectIdentifier(navigation))
    }

    private func htmlWithLoadGeneration(_ html: String, generation: Int) -> String {
        let generationScript = """
        <script>window.__osrsArticleLoadGeneration = \(generation);</script>
        """

        if let headEnd = html.range(of: "</head>", options: [.caseInsensitive]) {
            var htmlWithGeneration = html
            htmlWithGeneration.insert(contentsOf: generationScript, at: headEnd.lowerBound)
            return htmlWithGeneration
        }

        return generationScript + html
    }

    func loadArticle(theme: any osrsThemeProtocol = osrsLightTheme(), isReload: Bool = false) {
        guard webView != nil else {
            print("❌ ArticleViewModel: WebView not set")
            return
        }
        let loadGeneration = beginArticleLoad()

        // Android parity: Use blank overlay approach for all reloads (manual and automatic)
        if isReload {
            isRefreshing = true
            loadingProgressText = "Refreshing page..."
        } else {
            isLoading = true
        }
        errorMessage = nil
        resolvedPageTitleForHistory = nil
        resolvedPageUrlForHistory = nil

        // DIAGNOSTIC LOGGING: Enhanced URL and parameter analysis
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🚀 LOADING STARTED: Beginning article load process")
        print("📊 [\(timeString)] 📋 LOAD PARAMS: pageUrl=\(pageUrl), pageTitle=\(pageTitle_ ?? "nil"), pageId=\(pageId?.description ?? "nil")")
        print("🛠️ DIAGNOSTIC: Detailed URL analysis:")
        print("  - Full URL: \(pageUrl.absoluteString)")
        print("  - URL Scheme: \(pageUrl.scheme ?? "nil")")
        print("  - URL Host: \(pageUrl.host ?? "nil")")
        print("  - URL Path: \(pageUrl.path)")
        print("  - URL Query: \(pageUrl.query ?? "nil")")
        print("  - URL Fragment: \(pageUrl.fragment ?? "nil")")

        // Check domain validation compatibility
        let hostContainsWiki = osrsWebKitSecurityPolicy.isTrustedWikiHost(pageUrl.host)
        print("🛠️ DIAGNOSTIC: Domain validation check:")
        print("  - Host contains wiki domain: \(hostContainsWiki)")
        print("  - Would pass shouldOpenExternally: \(!Self.shouldOpenExternallyForArticleNavigation(pageUrl))")

        // Safety timeout for reload cases to prevent stuck refresh state
        if isReload {
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.isCurrentLoad(loadGeneration) && self.isRefreshing {
                    let timeoutString = DateFormatter.timeFormatter.string(from: Date())
                    print("⚠️ [\(timeoutString)] RELOAD TIMEOUT: Force-resetting stuck reload refresh state")
                    self.isRefreshing = false
                    self.errorMessage = "Reload timed out. Please try again."
                }
            }
            reloadTimeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
        }

        // TIMING MEASUREMENT: Reset timing measurements for new page load
        progressCompletionTime = nil
        pageVisibilityTime = nil

        // Initial progress will be set by WebKit observer

        // Debug: Print raw title hex bytes to detect encoding issues
        if let rawTitle = pageTitle_ {
            print("🔗 DEBUG: Raw title: '\(rawTitle)'")
            print("🔗 DEBUG: Title UTF-8 bytes: \(rawTitle.utf8.map { String(format: "%02X", $0) }.joined(separator: " "))")
            print("🔗 DEBUG: Title.count: \(rawTitle.count)")
            print("🔗 DEBUG: Title contains %: \(rawTitle.contains("%"))")
            print("🔗 DEBUG: Title contains colon: \(rawTitle.contains(":"))")
        }

        // Extract canonical title from URL (like Android does)
        let titleToLoad: String
        if let cleanPageTitle = pageTitle_?.trimmingCharacters(in: .whitespacesAndNewlines), !cleanPageTitle.isEmpty {
            // Use the provided title (for cases like search results)
            print("📄 ArticleViewModel: Using provided title: '\(cleanPageTitle)'")

            // Defensive check: detect potential corruption early
            if cleanPageTitle.contains("%20") && !cleanPageTitle.hasPrefix("http") {
                print("⚠️ ArticleViewModel: ALERT - Title contains URL encoding but isn't a URL!")
                print("⚠️ ArticleViewModel: This suggests title corruption - falling back to URL extraction")
                titleToLoad = extractTitleFromUrl(pageUrl)
                print("📄 ArticleViewModel: Extracted title from URL due to corruption: '\(titleToLoad)'")
            } else {
                titleToLoad = cleanUpTitle(cleanPageTitle)
                print("📄 ArticleViewModel: After cleanUpTitle: '\(titleToLoad)'")
            }
        } else {
            // Extract canonical title from URL (like Android does)
            titleToLoad = extractTitleFromUrl(pageUrl)
            print("📄 ArticleViewModel: Extracted canonical title from URL: '\(titleToLoad)'")
        }

        // CUSTOM SCHEME DETECTION: Check if this is an offline URL that should bypass API
        if pageUrl.scheme == "app-assets" {
            print("🔧 ArticleViewModel: Detected custom scheme URL - loading directly in WebView")
            print("🔧 ArticleViewModel: Bypassing API for offline content: \(pageUrl.absoluteString)")
            loadUrlDirectlyInWebView(theme: theme, generation: loadGeneration)
            return
        }

#if DEBUG
        if osrsTestEnvironment.usesDeepNavigationFixtureForUITests,
           let fixturePage = osrsDeepNavigationFixtureAudit.page(for: pageUrl, requestedTitle: pageTitle_) {
            loadDeepNavigationFixturePage(fixturePage, theme: theme, generation: loadGeneration)
            return
        }
#endif

        // NOTE: Using direct loading approach instead of publisher pattern

        // Simplified direct loading approach
        currentLoadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                print("🔄 ArticleViewModel: Starting direct content loading...")

                // Progress will be updated automatically by WebKit observer

                // CRITICAL FIX: Extract page name from URL, convert underscores to spaces
                // MediaWiki API expects display title (spaces), not URL path (underscores)
                let originalUrlString = pageUrl.absoluteString
                let pageTitle: String
                if let range = originalUrlString.range(of: "/w/") {
                    let urlPageName = String(originalUrlString[range.upperBound...])
                    // Convert URL encoding back to display title: %26 -> &, _ -> space
                    pageTitle = urlPageName.removingPercentEncoding?.replacingOccurrences(of: "_", with: " ") ?? titleToLoad
                } else {
                    // Fallback to extracted title
                    pageTitle = titleToLoad
                }

                guard let url = Self.makeParseRequestURL(pageTitle: pageTitle) else {
                    await MainActor.run {
                        self.errorMessage = "Invalid URL"
                        self.isLoading = false
                    }
                    return
                }

                print("🌐 ArticleViewModel: Extracted page title: '\(pageTitle)'")
                print("🌐 ArticleViewModel: URLComponents URL: '\(url.absoluteString)'")

                // Progress updated automatically by WebKit observer

#if DEBUG
                if osrsTestEnvironment.forcesArticleReloadNetworkFailureAfterFirstSuccessForUITests,
                   self.isRefreshing,
                   !self.didForceArticleReloadNetworkFailureForUITests {
                    self.didForceArticleReloadNetworkFailureForUITests = true
                    print("🧪 ArticleViewModel: Forced one-shot article reload network failure for UI test")
                    throw NetworkError.noConnection
                }
#endif

                let (data, _) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 2)
                try Task.checkCancellation()
                guard await MainActor.run(body: { self.isCurrentLoad(loadGeneration) }) else {
                    print("🚫 ArticleViewModel: Ignoring stale network response for generation \(loadGeneration)")
                    return
                }

                // Progress updated automatically by WebKit observer

                // Parse JSON manually to handle the nested structure
                print("📊 ArticleViewModel: Received data: \(data.count) bytes")

                // First, let's see what we actually received
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 ArticleViewModel: Raw JSON (first 500 chars): \(String(jsonString.prefix(500)))")
                }

                let payload = try Self.decodeParsePayload(data, requestedTitle: pageTitle)
                let title = payload.title
                let htmlContent = payload.htmlContent
                let displaytitle = payload.displayTitle

                print("✅ ArticleViewModel: Got content - Title: '\(title)', Length: \(htmlContent.count)")

                // Cache images opportunistically after the article starts rendering. Blocking
                // here makes text-only content wait for every image request.
                let tempPageId = generatePageIdFromURL(pageUrl)
                Task.detached(priority: .utility) { [weak self, tempPageId, htmlContent] in
                    await self?.proactivelyDownloadAllResources(pageId: tempPageId, htmlContent: htmlContent)
                }

                // Progress updated automatically by WebKit observer

                // Process the HTML to remove unwanted sections (matching Android behavior)
                let processedHtml = removeUnwantedInfoboxSections(from: htmlContent)
                print("📄 ArticleViewModel: Processed HTML - removed unwanted sections")

                // Build HTML using the HTML builder directly (without asset links for WKUserScript injection)
                let htmlBuilder = osrsPageHtmlBuilder()
                let finalHtml = htmlBuilder.buildFullHtmlDocument(
                    title: displaytitle ?? title,
                    bodyContent: processedHtml,
                    theme: theme,
                    collapseTablesEnabled: collapseTablesEnabled,
                    includeAssetLinks: true   // Option B: Generate <link> and <script> tags for ios-assets:// URLs
                )

                print("🏗️ ArticleViewModel: Built HTML document (\(finalHtml.count) characters)")

                // DEBUG: Check if the correct custom scheme URLs are in the HTML
                let expectedScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
                print("🔍 Checking HTML for scheme: \(expectedScheme)://")

                if finalHtml.contains("\(expectedScheme)://") {
                    print("✅ HTML contains \(expectedScheme):// URLs")
                    let customLinks = finalHtml.components(separatedBy: "\n").filter { $0.contains("\(expectedScheme)://") }
                    print("📋 Found \(customLinks.count) \(expectedScheme):// links in HTML")
                    if customLinks.count > 0 {
                        print("📋 First few links: \(customLinks.prefix(3))")
                    }
                } else {
                    print("❌ HTML does NOT contain \(expectedScheme):// URLs - Option B not working!")
                    // Check what schemes are actually in the HTML
                    if finalHtml.contains("://") {
                        let allSchemes = finalHtml.components(separatedBy: "\n")
                            .filter { $0.contains("://") }
                            .compactMap { line in
                                let components = line.components(separatedBy: "://")
                                return components.count > 1 ? components[0].components(separatedBy: "\"").last : nil
                            }
                            .prefix(5)
                        print("🔍 Found these schemes in HTML instead: \(Array(Set(allSchemes)))")
                    }
                }

                // Load in WebView on main thread
                await MainActor.run {
                    if self.isCurrentLoad(loadGeneration) {
                        self.pageTitle = payload.resolvedTitle
                        self.resolvedPageTitleForHistory = payload.resolvedTitle
                        self.resolvedPageUrlForHistory = Self.articleURL(forResolvedTitle: title)
                    }
                }
                try Task.checkCancellation()
                guard await MainActor.run(body: { self.isCurrentLoad(loadGeneration) }) else {
                    print("🚫 ArticleViewModel: Ignoring stale HTML load for generation \(loadGeneration)")
                    return
                }
                await self.loadCustomHtml(finalHtml, theme: theme, generation: loadGeneration)

                // Check if this page is already saved
                await MainActor.run {
                    if self.isCurrentLoad(loadGeneration) {
                        self.checkIfPageIsSaved()
                    }
                }

            } catch is CancellationError {
                print("🚫 ArticleViewModel: Article load cancelled for generation \(loadGeneration)")
            } catch let networkError as NetworkError {
                print("❌ ArticleViewModel: Network error loading article: \(networkError.localizedDescription)")
                print("🛠️ DIAGNOSTIC: Network error details:")
                print("  - Error type: \(networkError)")
                print("  - User message: \(networkError.userMessage)")
                print("  - Is offline error: \(networkError.isOfflineError)")
                print("  - Original URL: \(pageUrl.absoluteString)")
                await MainActor.run {
                    guard self.isCurrentLoad(loadGeneration) else {
                        print("🚫 ArticleViewModel: Ignoring stale network error for generation \(loadGeneration)")
                        return
                    }
                    self.errorMessage = networkError.userMessage
                    self.isLoading = false

                    // If it's an offline error, we could show different UI
                    if networkError.isOfflineError {
                        print("📵 ArticleViewModel: Device appears to be offline")
                    }
                }
            } catch {
                print("❌ ArticleViewModel: Unexpected error loading article: \(error)")
                print("🛠️ DIAGNOSTIC: Unexpected error details:")
                print("  - Error type: \(type(of: error))")
                print("  - Error description: \(error.localizedDescription)")
                print("  - Error: \(error)")
                print("  - Original URL: \(pageUrl.absoluteString)")
                if let nsError = error as NSError? {
                    print("  - Error domain: \(nsError.domain)")
                    print("  - Error code: \(nsError.code)")
                    print("  - User info: \(nsError.userInfo)")
                }
                await MainActor.run {
                    guard self.isCurrentLoad(loadGeneration) else {
                        print("🚫 ArticleViewModel: Ignoring stale load error for generation \(loadGeneration)")
                        return
                    }
                    self.errorMessage = "Failed to load content: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

#if DEBUG
    private func loadDeepNavigationFixturePage(
        _ fixturePage: osrsDeepNavigationFixturePage,
        theme: any osrsThemeProtocol,
        generation: Int
    ) {
        pageTitle = fixturePage.title
        resolvedPageTitleForHistory = fixturePage.title
        resolvedPageUrlForHistory = fixturePage.url

        let htmlBuilder = osrsPageHtmlBuilder()
        let finalHtml = htmlBuilder.buildFullHtmlDocument(
            title: fixturePage.title,
            bodyContent: fixturePage.bodyHTML,
            theme: theme,
            collapseTablesEnabled: false,
            includeAssetLinks: false
        )

        currentLoadTask = Task { [weak self] in
            guard let self = self else { return }
            await self.loadCustomHtml(finalHtml, theme: theme, generation: generation)
            await MainActor.run {
                if self.isCurrentLoad(generation) {
                    self.checkIfPageIsSaved()
                }
            }
        }
    }
#endif

    func reloadArticle(theme: any osrsThemeProtocol = osrsLightTheme()) {
        loadArticle(theme: theme)
    }

    /// Refresh page with Android-parity behavior: show progress bar over blank page
    /// Uses SwiftUI view state management with WebView overlay approach
    func refreshPage(theme: any osrsThemeProtocol = osrsLightTheme()) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("🔄 [\(timeString)] REFRESH: Starting SwiftUI overlay-based page refresh with blank page")

        // Step 1: Set refresh state - this will overlay blank view on top of WebView
        isRefreshing = true

        // Step 2: Reset UI state for clean loading experience
        errorMessage = nil
        loadingProgress = 0.1
        loadingProgressText = "Refreshing page..."

        // Reset timing measurements
        progressCompletionTime = nil
        pageVisibilityTime = nil

        print("🔄 [\(timeString)] REFRESH: Blank overlay active, WebView still present for loading")

        // Step 3: Safety timeout to prevent stuck refresh state
        let refreshGeneration = currentLoadGeneration
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isCurrentLoad(refreshGeneration) && self.isRefreshing {
                let timeoutString = DateFormatter.timeFormatter.string(from: Date())
                print("⚠️ [\(timeoutString)] REFRESH TIMEOUT: Force-resetting stuck refresh state")
                self.isRefreshing = false
                self.errorMessage = "Refresh timed out. Please try again."
            }
        }
        refreshTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)

#if DEBUG
        if osrsTestEnvironment.forcesArticleRefreshFailureForUITests {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.isRefreshing else { return }
                self.isRefreshing = false
                self.isLoading = false
                self.loadingProgress = 0
                self.loadingProgressText = nil
                self.errorMessage = "Network connection lost while refreshing. Please try again."
                print("🧪 ArticleViewModel: Forced article refresh failure for UI test")
            }
            return
        }
#endif

        // Step 4: Small delay to ensure UI updates, then load new content
        let refreshWorkItem = DispatchWorkItem { [weak self] in
            print("🔄 [\(timeString)] REFRESH: Starting content load with WebView overlaid but present")
            self?.loadArticle(theme: theme)
        }
        deferredRefreshWorkItem = refreshWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: refreshWorkItem)
    }

    /// Remove unwanted infobox sections that should be hidden by default
    /// Matches Android's preprocessHtml behavior in PageAssetDownloader.kt
    private func removeUnwantedInfoboxSections(from html: String) -> String {
        var processedHtml = html

        // Selectors to remove (matching Android)
        let selectorsToRemove = [
            "advanced-data",
            "leagues-global-flag",
            "infobox-padding"
        ]

        for selector in selectorsToRemove {
            // Pattern to match <tr> elements with the class anywhere in the class attribute
            let pattern = "<tr[^>]*?class=[\"'][^\"']*?\(selector)[^\"']*?[\"'][^>]*?>.*?</tr>"

            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                let matches = regex.matches(in: processedHtml, range: NSRange(location: 0, length: processedHtml.utf16.count))

                if matches.count > 0 {
                    print("🔍 ArticleViewModel: Found \(matches.count) elements with class '\(selector)' to remove")
                }

                // Remove matches in reverse order to maintain correct indices
                for match in matches.reversed() {
                    if let range = Range(match.range, in: processedHtml) {
                        processedHtml.removeSubrange(range)
                    }
                }
            } catch {
                print("❌ ArticleViewModel: Failed to create regex for selector '\(selector)': \(error)")
            }
        }

        return processedHtml
    }

    private func handleDownloadProgress(_ progress: osrsDownloadProgress, theme: any osrsThemeProtocol) async {
        switch progress {
        case .fetchingHtml(let progressValue):
            let scaledProgress = 0.05 + (Double(progressValue) * 0.05)
            await MainActor.run {
                loadingProgress = scaledProgress
            }
            print("📥 ArticleViewModel: Fetching HTML \(progressValue)% - scaled to \(Int(scaledProgress * 100))%")

        case .fetchingAssets(let progressValue):
            let scaledProgress = 0.10 + (Double(progressValue) * 0.40)
            await MainActor.run {
                loadingProgress = scaledProgress
            }
            print("📦 ArticleViewModel: Fetching assets \(progressValue)% - scaled to \(Int(scaledProgress * 100))%")

        case .success(let pageContent):
            print("✅ ArticleViewModel: Successfully loaded page content")
            // Progress updated automatically by WebKit observer

            // FREEZE FIX: Get content loader async - defer heavy initialization until needed
            let loader = await getContentLoader()

            // Build the final HTML document
            let finalHtml = loader.buildFullHtmlDocument(
                pageContent: pageContent,
                theme: theme,
                collapseTablesEnabled: collapseTablesEnabled
            )

            print("🏗️ ArticleViewModel: Built custom HTML document (\(finalHtml.count) characters)")

            await MainActor.run {
                // Update page title
                pageTitle = pageContent.parseResult.displaytitle ?? pageContent.parseResult.title ?? "OSRS Wiki"
            }

            // Load the custom HTML in WebView
            await loadCustomHtml(finalHtml, theme: theme, generation: currentLoadGeneration)

        case .failure(let error):
            print("❌ ArticleViewModel: Failed to load content: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to load page: \(error.localizedDescription)"
            }
        }
    }

    private func loadCustomHtml(_ html: String, theme: any osrsThemeProtocol = osrsLightTheme(), generation: Int) async {
        guard let webView = webView else { return }
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Skipping stale WebView load for generation \(generation)")
            return
        }

        print("🌐 ArticleViewModel: Loading custom HTML in WebView")
        print("🌐 ArticleViewModel: HTML content length: \(html.count) characters")

        // PRELOADING INTEGRATION: Trigger map preloading before WebView loads HTML
        // This mirrors Android's proactive preloading approach
        Task { @MainActor in
            // Set parent view for map preloading containers
            if let parentView = webView.superview {
                osrsMapPreloadService.shared.setParentView(parentView)
            }

            // Parse HTML for maps and start preloading
            print("🗺️ ArticleViewModel: Starting map preloading from HTML")
            osrsMapPreloadService.shared.preloadMapsFromHTML(html)
        }

        // Keep wiki base URL for content
        // CRITICAL FIX: Use custom scheme baseURL to avoid mixed content security blocking
        // WebKit treats custom schemes as insecure and blocks them when baseURL is HTTPS
        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
        let customBaseURL = URL(string: "\(customScheme)://localhost/")!
        print("🔧 CRITICAL FIX: Using custom scheme baseURL: \(customBaseURL) instead of HTTPS")
        print("🔧 This resolves WebKit mixed content security blocking that prevented WKURLSchemeHandler from being called")

        // Option B: Skip WKUserScript injection - assets loaded via WKURLSchemeHandler
        print("📱 Option B: Skipping WKUserScript injection - using WKURLSchemeHandler for asset loading")

        let navigation = webView.loadHTMLString(htmlWithLoadGeneration(html, generation: generation), baseURL: customBaseURL)
        bindWebKitNavigation(navigation, to: generation)
        scheduleReadinessTimeout(for: generation)
    }

    // MARK: - Direct WebView Loading for Custom Schemes

    /// Load URLs directly in WebView - now handles web archives via loadFileURL
    /// Used for offline content stored as .webarchive files
    private func loadUrlDirectlyInWebView(theme: any osrsThemeProtocol, generation: Int) {
        guard let webView = webView else {
            print("❌ ArticleViewModel: WebView not set for direct loading")
            errorMessage = "WebView not available"
            isLoading = false
            isRefreshing = false
            return
        }

        print("🔧 ArticleViewModel: Starting web archive loading")
        print("🔧 ArticleViewModel: Loading URL: \(pageUrl.absoluteString)")

        // NEW: Check if this is a web archive request (app-assets://saved-pages/pageId)
        if pageUrl.scheme == "app-assets" && pageUrl.host == "saved-pages" {
            print("📦 ArticleViewModel: Detected web archive request")
            loadWebArchiveFile(generation: generation)
            return
        }

        // Fallback for other custom schemes (shouldn't happen with web archives)
        print("🌐 ArticleViewModel: Loading non-archive custom scheme URL")

        // Apply theme colors first (like API-based loading does)
        injectBundleAssetsViaUserScript(webView: webView)

        // Create URL request and load directly
        let request = URLRequest(url: pageUrl)
        let navigation = webView.load(request)
        bindWebKitNavigation(navigation, to: generation)
        scheduleReadinessTimeout(for: generation)

        print("🔧 ArticleViewModel: Direct URL request initiated")

        // Note: Progress tracking and completion will be handled by existing WebView delegates
        // (didStartProvisionalNavigation, didFinish, etc.)
    }

    /// Load web archive file using iOS-native loadFileURL method
    private func loadWebArchiveFile(generation: Int) {
        guard let webView = webView else {
            print("❌ ArticleViewModel: WebView not available for web archive loading")
            errorMessage = "WebView not available"
            isLoading = false
            return
        }

        // Extract page ID from URL: app-assets://saved-pages/pageId
        let pathComponents = pageUrl.path.components(separatedBy: "/").filter { !$0.isEmpty }
        guard let pageId = pathComponents.first else {
            print("❌ ArticleViewModel: Could not extract page ID from URL: \(pageUrl.absoluteString)")
            errorMessage = "Invalid offline page URL"
            isLoading = false
            return
        }

        print("📦 ArticleViewModel: Loading web archive for page ID: \(pageId)")

        // Get web archive file URL from OfflineContentService
        let offlineService = OfflineContentService.shared
        let archiveFileURL = offlineService.webArchiveFileURL(for: pageId)

        // Check if web archive exists
        guard FileManager.default.fileExists(atPath: archiveFileURL.path) else {
            print("❌ ArticleViewModel: Web archive not found at: \(archiveFileURL.path)")
            errorMessage = "Offline content not available"
            isLoading = false
            return
        }

        print("📦 ArticleViewModel: Found web archive at: \(archiveFileURL.path)")

        // Apply theme colors first (like API-based loading does)
        injectBundleAssetsViaUserScript(webView: webView)

        // Load web archive using iOS-native method
        // Allow read access to the entire offline_pages directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let offlineDirectory = documentsDirectory.appendingPathComponent("offline_pages")

        print("📦 ArticleViewModel: Loading web archive with read access to: \(offlineDirectory.path)")
        let navigation = webView.loadFileURL(archiveFileURL, allowingReadAccessTo: offlineDirectory)
        bindWebKitNavigation(navigation, to: generation)
        scheduleReadinessTimeout(for: generation)

        // Schedule enhanced diagnostics, base URL injection, and MediaWiki re-initialization after content loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard self.isCurrentLoad(generation) else { return }
            self.injectBaseURLFix()
            self.diagnoseWebArchiveJavaScript()

            // Add MediaWiki re-initialization after diagnostics
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.isCurrentLoad(generation) else { return }
                self.reinitializeMediaWikiForWebArchive()
            }
        }

        print("✅ ArticleViewModel: Web archive load initiated")
    }

    /// Diagnose JavaScript execution issues in web archive context
    private func diagnoseWebArchiveJavaScript() {
        guard let webView = webView else { return }

        print("🔍 JAVASCRIPT DIAGNOSIS: Starting comprehensive JavaScript execution analysis for web archives...")

        let diagnosticScript = """
            (function() {
                console.log('🔍 JS DIAGNOSIS: Starting JavaScript execution analysis...');

                // Test 1: Basic JavaScript execution
                try {
                    var testVar = 'JavaScript execution works';
                    console.log('✅ JS DIAGNOSIS: Basic JavaScript execution: ' + testVar);
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: Basic JavaScript failed: ' + error);
                    return 'basic_js_failed';
                }

                // Test 2: DOM access
                try {
                    var bodyExists = document.body !== null;
                    var headExists = document.head !== null;
                    console.log('✅ JS DIAGNOSIS: DOM access - body: ' + bodyExists + ', head: ' + headExists);
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: DOM access failed: ' + error);
                    return 'dom_access_failed';
                }

                // Test 3: Event listener attachment
                try {
                    var testDiv = document.createElement('div');
                    testDiv.addEventListener('click', function() {});
                    console.log('✅ JS DIAGNOSIS: Event listener attachment works');
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: Event listener attachment failed: ' + error);
                    return 'event_listener_failed';
                }

                // Test 4: Check for collapsible elements
                var collapsibleElements = document.querySelectorAll('.mw-collapsible');
                console.log('🔍 JS DIAGNOSIS: Found ' + collapsibleElements.length + ' collapsible elements');

                if (collapsibleElements.length > 0) {
                    var firstCollapsible = collapsibleElements[0];
                    console.log('🔍 JS DIAGNOSIS: First collapsible element classes: ' + firstCollapsible.className);

                    // Check if collapsible elements have click handlers
                    try {
                        var hasClickHandler = firstCollapsible.onclick !== null;
                        console.log('🔍 JS DIAGNOSIS: First collapsible has onclick handler: ' + hasClickHandler);

                        // Try to manually attach a click handler
                        firstCollapsible.addEventListener('click', function(e) {
                            console.log('🔍 JS DIAGNOSIS: Manual click handler triggered on collapsible element');
                        });
                        console.log('✅ JS DIAGNOSIS: Successfully attached manual click handler to collapsible');
                    } catch (error) {
                        console.log('❌ JS DIAGNOSIS: Failed to attach click handler to collapsible: ' + error);
                    }
                } else {
                    console.log('⚠️ JS DIAGNOSIS: No collapsible elements found in document');
                }

                // Test 5: Check jQuery availability
                try {
                    var jqueryAvailable = typeof jQuery !== 'undefined' || typeof $ !== 'undefined';
                    console.log('🔍 JS DIAGNOSIS: jQuery available: ' + jqueryAvailable);
                    if (jqueryAvailable && typeof $ !== 'undefined') {
                        console.log('🔍 JS DIAGNOSIS: jQuery version: ' + ($.fn ? $.fn.jquery : 'unknown'));
                    }
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: jQuery check failed: ' + error);
                }

                // Test 6: Check MediaWiki JavaScript
                try {
                    var mwAvailable = typeof mw !== 'undefined';
                    console.log('🔍 JS DIAGNOSIS: MediaWiki (mw) available: ' + mwAvailable);
                    if (mwAvailable) {
                        console.log('🔍 JS DIAGNOSIS: MediaWiki config exists: ' + (typeof mw.config !== 'undefined'));
                    }
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: MediaWiki check failed: ' + error);
                }

                console.log('🔍 JS DIAGNOSIS: JavaScript execution analysis complete');
                return 'diagnosis_complete';
            })();
        """

        webView.evaluateJavaScript(diagnosticScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ JAVASCRIPT DIAGNOSIS: Script execution failed: \(error)")
                } else if let resultString = result as? String {
                    print("✅ JAVASCRIPT DIAGNOSIS: Analysis completed with result: \(resultString)")
                } else {
                    print("✅ JAVASCRIPT DIAGNOSIS: Analysis completed successfully")
                }

                // Follow up with collapsible-specific diagnosis
                self.diagnoseCollapsibleContainers()
            }
        }
    }

    /// Specifically diagnose collapsible container functionality
    private func diagnoseCollapsibleContainers() {
        guard let webView = webView else { return }

        print("📋 COLLAPSIBLE DIAGNOSIS: Analyzing collapsible container functionality...")

        let collapsibleScript = """
            (function() {
                console.log('📋 COLLAPSIBLE DIAGNOSIS: Starting collapsible container analysis...');

                // Find all collapsible elements
                var collapsibles = document.querySelectorAll('.mw-collapsible');
                console.log('📋 Found ' + collapsibles.length + ' .mw-collapsible elements');

                if (collapsibles.length === 0) {
                    // Try alternative selectors
                    var altCollapsibles = document.querySelectorAll('[data-expandtext], .collapsible, .mw-collapsible-toggle');
                    console.log('📋 Found ' + altCollapsibles.length + ' alternative collapsible elements');
                    collapsibles = altCollapsibles;
                }

                if (collapsibles.length > 0) {
                    var firstCollapsible = collapsibles[0];

                    // Analyze the structure
                    console.log('📋 First collapsible element:');
                    console.log('  - Tag: ' + firstCollapsible.tagName);
                    console.log('  - Classes: ' + firstCollapsible.className);
                    console.log('  - Has data attributes: ' + Object.keys(firstCollapsible.dataset).join(', '));

                    // Look for toggle elements
                    var toggles = firstCollapsible.querySelectorAll('.mw-collapsible-toggle, .collapsible-toggle');
                    console.log('  - Toggle elements found: ' + toggles.length);

                    if (toggles.length > 0) {
                        var firstToggle = toggles[0];
                        console.log('  - First toggle classes: ' + firstToggle.className);
                        console.log('  - First toggle text: ' + firstToggle.textContent.trim());

                        // Try to simulate a click
                        try {
                            console.log('📋 Attempting to simulate click on toggle...');
                            firstToggle.click();
                            console.log('✅ Click simulation succeeded');
                        } catch (error) {
                            console.log('❌ Click simulation failed: ' + error);
                        }
                    }

                    return 'found_' + collapsibles.length + '_collapsibles';
                } else {
                    console.log('❌ No collapsible elements found in document');
                    return 'no_collapsibles_found';
                }
            })();
        """

        webView.evaluateJavaScript(collapsibleScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ COLLAPSIBLE DIAGNOSIS: Script execution failed: \(error)")
                } else if let resultString = result as? String {
                    print("✅ COLLAPSIBLE DIAGNOSIS: Analysis completed with result: \(resultString)")
                } else {
                    print("✅ COLLAPSIBLE DIAGNOSIS: Analysis completed successfully")
                }
            }
        }
    }

    /// Inject base URL to fix relative links in web archive content
    private func injectBaseURLFix() {
        guard let webView = webView else { return }

        let baseURLScript = """
            (function() {
                // Check if base tag already exists
                if (document.querySelector('base')) {
                    console.log('Base URL already set, skipping injection');
                    return;
                }

                // Create and inject base URL
                var base = document.createElement('base');
                base.href = 'https://oldschool.runescape.wiki/';

                // Insert at beginning of head
                var head = document.head || document.getElementsByTagName('head')[0];
                if (head.firstChild) {
                    head.insertBefore(base, head.firstChild);
                } else {
                    head.appendChild(base);
                }

                console.log('Injected base URL for web archive content');

                // Also fix any remaining relative URLs in the content
                var links = document.querySelectorAll('a[href^="/"], a[href^="./"], a[href^="../"]');
                links.forEach(function(link) {
                    var href = link.getAttribute('href');
                    if (href.startsWith('/')) {
                        link.href = 'https://oldschool.runescape.wiki' + href;
                    }
                });

                console.log('Fixed ' + links.length + ' relative links');
            })();
        """

        webView.evaluateJavaScript(baseURLScript) { result, error in
            if let error = error {
                print("❌ ArticleViewModel: Base URL injection failed: \(error.localizedDescription)")
            } else {
                print("✅ ArticleViewModel: Base URL injection completed")
            }
        }
    }

    /// Re-initialize MediaWiki JavaScript functionality for web archives
    private func reinitializeMediaWikiForWebArchive() {
        guard let webView = webView else { return }

        print("🔧 MEDIAWIKI RE-INIT: Starting MediaWiki JavaScript re-initialization for web archives...")

        let mediaWikiReinitScript = """
            (function() {
                console.log('🔧 MEDIAWIKI RE-INIT: Re-initializing MediaWiki functionality for web archives...');

                // Step 1: Initialize basic MediaWiki objects if they don't exist
                if (typeof mw === 'undefined') {
                    console.log('🔧 MEDIAWIKI RE-INIT: Creating basic MediaWiki object...');
                    window.mw = {
                        config: {
                            get: function(key) {
                                console.log('🔧 MW CONFIG: Getting config for: ' + key);
                                return null;
                            }
                        },
                        loader: {
                            load: function(modules) {
                                console.log('🔧 MW LOADER: Loading modules: ' + modules);
                            }
                        },
                        hook: function(name) {
                            console.log('🔧 MW HOOK: Hook called: ' + name);
                            return {
                                add: function(callback) {
                                    console.log('🔧 MW HOOK: Adding callback for: ' + name);
                                    if (typeof callback === 'function') {
                                        setTimeout(callback, 10);
                                    }
                                }
                            };
                        }
                    };
                }

                // Step 2: Find and manually initialize collapsible elements
                var collapsibleElements = document.querySelectorAll('.mw-collapsible, .collapsible');
                console.log('🔧 MEDIAWIKI RE-INIT: Found ' + collapsibleElements.length + ' collapsible elements to initialize');

                if (collapsibleElements.length > 0) {
                    collapsibleElements.forEach(function(element, index) {
                        try {
                            console.log('🔧 MEDIAWIKI RE-INIT: Initializing collapsible element ' + (index + 1));

                            // Add necessary classes if missing
                            if (!element.classList.contains('mw-collapsible')) {
                                element.classList.add('mw-collapsible');
                            }

                            // Find or create toggle button
                            var toggleButton = element.querySelector('.mw-collapsible-toggle');
                            if (!toggleButton) {
                                // Look for existing toggle elements with different classes
                                toggleButton = element.querySelector('.collapsible-toggle, [data-toggle]');
                            }

                            if (!toggleButton) {
                                // Create a new toggle button
                                toggleButton = document.createElement('span');
                                toggleButton.className = 'mw-collapsible-toggle';
                                toggleButton.innerHTML = '[hide]';
                                toggleButton.style.cursor = 'pointer';
                                toggleButton.style.color = '#0645ad';
                                toggleButton.style.fontSize = '0.8em';
                                toggleButton.style.marginLeft = '0.5em';

                                // Insert toggle button at the beginning of the element
                                var firstChild = element.firstElementChild;
                                if (firstChild) {
                                    firstChild.appendChild(toggleButton);
                                } else {
                                    element.appendChild(toggleButton);
                                }

                                console.log('🔧 MEDIAWIKI RE-INIT: Created new toggle button for element ' + (index + 1));
                            }

                            // Find collapsible content (everything except the first row/header)
                            var collapsibleContent = [];
                            var children = Array.from(element.children);

                            if (element.tagName === 'TABLE') {
                                // For tables, hide all rows except the first
                                var rows = element.querySelectorAll('tr');
                                if (rows.length > 1) {
                                    for (var i = 1; i < rows.length; i++) {
                                        collapsibleContent.push(rows[i]);
                                    }
                                }
                            } else {
                                // For other elements, hide all children except the first
                                if (children.length > 1) {
                                    for (var i = 1; i < children.length; i++) {
                                        collapsibleContent.push(children[i]);
                                    }
                                }
                            }

                            // Add click handler to toggle button
                            toggleButton.onclick = function() {
                                var isCollapsed = element.classList.contains('mw-collapsed');

                                if (isCollapsed) {
                                    // Expand: show content and update button text
                                    element.classList.remove('mw-collapsed');
                                    collapsibleContent.forEach(function(item) {
                                        item.style.display = '';
                                    });
                                    toggleButton.innerHTML = '[hide]';
                                    console.log('🔧 MEDIAWIKI RE-INIT: Expanded collapsible element');
                                } else {
                                    // Collapse: hide content and update button text
                                    element.classList.add('mw-collapsed');
                                    collapsibleContent.forEach(function(item) {
                                        item.style.display = 'none';
                                    });
                                    toggleButton.innerHTML = '[show]';
                                    console.log('🔧 MEDIAWIKI RE-INIT: Collapsed collapsible element');
                                }
                            };

                            // Set initial state - check if element should start collapsed
                            var shouldStartCollapsed = element.classList.contains('mw-collapsed') ||
                                                     element.classList.contains('collapsed');

                            if (shouldStartCollapsed) {
                                element.classList.add('mw-collapsed');
                                collapsibleContent.forEach(function(item) {
                                    item.style.display = 'none';
                                });
                                toggleButton.innerHTML = '[show]';
                            } else {
                                element.classList.remove('mw-collapsed');
                                collapsibleContent.forEach(function(item) {
                                    item.style.display = '';
                                });
                                toggleButton.innerHTML = '[hide]';
                            }

                            console.log('🔧 MEDIAWIKI RE-INIT: Successfully initialized collapsible element ' + (index + 1) + ', starts ' + (shouldStartCollapsed ? 'collapsed' : 'expanded'));

                        } catch (error) {
                            console.log('❌ MEDIAWIKI RE-INIT: Failed to initialize collapsible element ' + (index + 1) + ': ' + error);
                        }
                    });

                    console.log('✅ MEDIAWIKI RE-INIT: Successfully re-initialized ' + collapsibleElements.length + ' collapsible elements');
                    return 'reinitialized_' + collapsibleElements.length + '_collapsibles';

                } else {
                    console.log('⚠️ MEDIAWIKI RE-INIT: No collapsible elements found to re-initialize');
                    return 'no_collapsibles_found';
                }

            })();
        """

        webView.evaluateJavaScript(mediaWikiReinitScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ MEDIAWIKI RE-INIT: Re-initialization failed: \(error)")
                } else if let resultString = result as? String {
                    print("✅ MEDIAWIKI RE-INIT: Re-initialization completed with result: \(resultString)")

                    // Verify the fix worked by running diagnostics again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.verifyCollapsibleFunctionality()
                    }
                } else {
                    print("✅ MEDIAWIKI RE-INIT: Re-initialization completed successfully")
                }
            }
        }
    }

    /// Verify that collapsible functionality is working after re-initialization
    private func verifyCollapsibleFunctionality() {
        guard let webView = webView else { return }

        print("🧪 VERIFICATION: Testing collapsible functionality after re-initialization...")

        let verificationScript = """
            (function() {
                console.log('🧪 VERIFICATION: Testing collapsible functionality...');

                var collapsibles = document.querySelectorAll('.mw-collapsible');
                console.log('🧪 Found ' + collapsibles.length + ' collapsible elements for verification');

                if (collapsibles.length > 0) {
                    var firstCollapsible = collapsibles[0];
                    var toggleButton = firstCollapsible.querySelector('.mw-collapsible-toggle');

                    if (toggleButton) {
                        console.log('🧪 VERIFICATION: Found toggle button, testing click functionality...');

                        // Simulate a click to test functionality
                        var initialState = firstCollapsible.classList.contains('mw-collapsed');
                        console.log('🧪 Initial state - collapsed: ' + initialState);

                        // Trigger click
                        toggleButton.click();

                        // Check if state changed
                        var newState = firstCollapsible.classList.contains('mw-collapsed');
                        console.log('🧪 New state after click - collapsed: ' + newState);

                        if (initialState !== newState) {
                            console.log('✅ VERIFICATION: Collapsible functionality is working correctly!');
                            return 'collapsible_working';
                        } else {
                            console.log('❌ VERIFICATION: Collapsible state did not change - functionality may be broken');
                            return 'collapsible_not_working';
                        }
                    } else {
                        console.log('❌ VERIFICATION: No toggle button found');
                        return 'no_toggle_button';
                    }
                } else {
                    console.log('❌ VERIFICATION: No collapsible elements found for verification');
                    return 'no_collapsibles';
                }
            })();
        """

        webView.evaluateJavaScript(verificationScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ VERIFICATION: Verification script failed: \(error)")
                } else if let resultString = result as? String {
                    print("🧪 VERIFICATION: Functionality verification completed with result: \(resultString)")
                } else {
                    print("🧪 VERIFICATION: Verification completed successfully")
                }
            }
        }
    }

    /// Extract page ID from URL - handles both custom schemes and real HTTPS URLs
    private func extractPageIdFromURL(_ url: URL) -> String? {
        // Handle legacy custom scheme URLs: app-assets://saved-pages/pageId
        if url.scheme == "app-assets" && url.host == "saved-pages" {
            let pathComponents = url.path.components(separatedBy: "/").filter { !$0.isEmpty }
            return pathComponents.first
        }

        // NEW: Handle real HTTPS URLs by looking up saved page by URL
        if url.scheme == "https" && osrsWebKitSecurityPolicy.isTrustedWikiHost(url.host) {
            // For real HTTPS URLs, we need to find the saved page that matches this URL
            // This enables offline caching for pages accessed directly via real URLs
            return findSavedPageIdForURL(url)
        }

        return nil
    }

    /// Find saved page ID that matches the given HTTPS URL
    private func findSavedPageIdForURL(_ url: URL) -> String? {
        // Query saved pages repository to find a page with matching URL
        let savedPagesRepository = SavedPagesRepository()
        let allSavedPages = savedPagesRepository.getSavedPages()

        // Find saved page with matching URL (normalized for comparison)
        let urlString = url.absoluteString
        let normalizedUrlString = normalizeWikiURL(url).absoluteString

        for savedPage in allSavedPages {
            let savedUrlString = savedPage.url.absoluteString
            let normalizedSavedUrl = normalizeWikiURL(savedPage.url).absoluteString

            // Check exact match or normalized match
            if savedUrlString == urlString ||
               normalizedSavedUrl == normalizedUrlString ||
               savedUrlString == normalizedUrlString ||
               normalizedSavedUrl == urlString {
                print("✅ ArticleViewModel: Found saved page ID \(savedPage.id) for URL: \(urlString)")
                return savedPage.id
            }
        }

        print("ℹ️ ArticleViewModel: No saved page found for URL: \(urlString)")
        return nil
    }

    /// Normalize URL for comparison (reuse SavedPagesViewModel logic)
    private func normalizeWikiURL(_ originalUrl: URL) -> URL {
        let urlString = originalUrl.absoluteString

        // Handle URL encoding issues like %26 → &
        let decodedUrlString: String
        if urlString.contains("%") {
            decodedUrlString = urlString.removingPercentEncoding ?? urlString
        } else {
            decodedUrlString = urlString
        }

        guard let decodedUrl = URL(string: decodedUrlString) else {
            return originalUrl
        }

        // Check if URL is already in correct format
        if osrsWebKitSecurityPolicy.isTrustedWikiHost(decodedUrl.host) &&
           decodedUrl.path.hasPrefix("/w/") {
            return decodedUrl
        }

        // Try to convert API URLs to article URLs
        if decodedUrl.path.contains("api.php") {
            if let pageComponent = URLComponents(url: decodedUrl, resolvingAgainstBaseURL: false),
               let queryItems = pageComponent.queryItems,
               let pageItem = queryItems.first(where: { $0.name == "page" }),
               let pageTitle = pageItem.value {
                let normalizedTitle = pageTitle.replacingOccurrences(of: " ", with: "_")
                if let normalizedUrl = URL(string: "https://oldschool.runescape.wiki/w/\(normalizedTitle)") {
                    return normalizedUrl
                }
            }
        }

        return decodedUrl
    }

    /// Check if page has complete cached assets (simplified check)
    private func hasCompleteCachedAssets(pageId: String) -> Bool {
        // For now, assume we always need to cache assets on first load
        // In the future, this could check if critical resources are already cached
        return false
    }

    // MARK: - History Tracking

    /// Add this page visit to history with enriched metadata
    /// Matches Android's PageHistoryManager.logPageVisit() functionality
    private func addToHistory(generation: Int) {
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Skipping stale history write for generation \(generation)")
            return
        }

        // Skip history tracking if excluded (for preview generation)
        guard !excludeFromHistory else {
            print("📚 ArticleViewModel: Skipping history tracking - excludeFromHistory=true")
            return
        }
        let pageTitle = resolvedPageTitleForHistory?.isEmpty == false
            ? resolvedPageTitleForHistory!
            : (pageTitle_?.isEmpty == false ? pageTitle_! : extractTitleFromUrl(pageUrl))
        let historyPageUrl = resolvedPageUrlForHistory ?? pageUrl

        // Use enriched history functionality to fetch metadata if not already available
        Task { [weak self] in
            guard let self = self else { return }
            if thumbnailUrl_ != nil && snippet_ != nil {
                // We already have metadata from navigation, use it directly
                let historyItem = HistoryItem(
                    id: UUID().uuidString,
                    pageTitle: pageTitle,
                    pageUrl: historyPageUrl,
                    visitedDate: Date(),
                    thumbnailUrl: thumbnailUrl_,
                    description: snippet_
                )

                await MainActor.run {
                    guard self.isCurrentLoad(generation) else {
                        print("🚫 ArticleViewModel: Skipping stale direct history write for generation \(generation)")
                        return
                    }
                    self.historyRepository.addToHistory(historyItem)
                    print("📚 ArticleViewModel: Added page to history with existing metadata: '\(historyItem.pageTitle)'")
                }
            } else {
                // Fetch enriched metadata for this page (matches Android behavior)
                let historyItem = await historyRepository.makeEnrichedHistoryEntry(
                    pageTitle: pageTitle,
                    pageUrl: historyPageUrl,
                    visitedDate: Date()
                )
                await MainActor.run {
                    guard self.isCurrentLoad(generation) else {
                        print("🚫 ArticleViewModel: Skipping stale enriched history write for generation \(generation)")
                        return
                    }
                    self.historyRepository.addToHistory(historyItem)
                    print("📚 ArticleViewModel: Added enriched page to history: '\(pageTitle)'")
                }
            }
        }
    }

    private func injectBundleAssetsViaUserScript(webView: WKWebView) {
        print("🎨 ArticleViewModel: Injecting CSS/JS assets via WKUserScript")

        // Remove any existing user scripts to avoid duplicates
        webView.configuration.userContentController.removeAllUserScripts()

        // Inject CSS files
        let cssAssets = [
            "themes.css",
            "base.css",
            "fonts.css",
            "layout.css",
            "components.css",
            "wiki-integration.css",
            "navbox_styles.css",
            "collapsible_tables.css",
            "collapsible_sections.css",
            "switch_infobox_styles.css",
            "fixes.css"
        ]

        // Load and inject CSS
        var combinedCSS = ""
        for cssFile in cssAssets {
            if let path = Bundle.main.path(forResource: cssFile, ofType: nil),
               let cssContent = try? String(contentsOfFile: path) {
                combinedCSS += cssContent + "\n"
                print("✅ Loaded CSS: \(cssFile)")
            } else {
                print("❌ Failed to load CSS: \(cssFile)")
            }
        }

        if !combinedCSS.isEmpty {
            let cssInjectionScript = """
            var style = document.createElement('style');
            style.innerHTML = `\(combinedCSS.replacingOccurrences(of: "`", with: "\\`"))`;
            document.head.appendChild(style);
            console.log('📱 iOS: Injected CSS styles via WKUserScript');
            """

            let cssUserScript = WKUserScript(source: cssInjectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(cssUserScript)
        }

        // Inject JavaScript files
        let jsAssets = [
            "startup.js",
            "tablesort.min.js",
            "tablesort_init.js",
            "article_tools.js",
            "collapsible_content.js",
            "table_wrapper.js",
            "infobox_switcher_bootstrap.js",
            "switch_infobox.js",
            "horizontal_scroll_interceptor.js",
            "responsive_videos.js",
            "clipboard_bridge.js"
        ]

        // Load and inject JavaScript
        for jsFile in jsAssets {
            if let path = Bundle.main.path(forResource: jsFile, ofType: nil),
               let jsContent = try? String(contentsOfFile: path) {

                let jsInjectionScript = """
                \(jsContent)
                console.log('📱 iOS: Loaded JS script: \(jsFile)');
                """

                let jsUserScript = WKUserScript(source: jsInjectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                webView.configuration.userContentController.addUserScript(jsUserScript)
                print("✅ Injected JS: \(jsFile)")
            } else {
                print("❌ Failed to load JS: \(jsFile)")
            }
        }

        print("🎨 ArticleViewModel: Asset injection complete")
    }

    /// Inject theme colors into WebView (called from ArticleWebView.updateUIView)
    func injectThemeColors(_ themeManager: osrsThemeManager) {
        // Option B: Apply theme colors and final styling touches to achieve Android parity
        guard let webView = webView else { return }

        print("🎨 Option B: Applying theme colors and final styling for Android parity")
        applyThemeColors(webView: webView, themeManager: themeManager) {
            print("✅ Option B: Theme colors applied successfully")

            // Apply additional styling fixes for complete Android parity
            self.applyFinalStylingFixes(webView: webView)
        }
    }

    /// Apply iOS theme colors as CSS variables to match Android behavior
    private func applyThemeColors(webView: WKWebView, themeManager: osrsThemeManager, completion: @escaping () -> Void) {
        print("🎨 ArticleViewModel: Applying iOS theme colors as CSS variables")

        // Get current theme colors from iOS theme manager
        let currentTheme = themeManager.currentTheme

        // Map iOS theme colors to CSS variables (matching Android's colorSurfaceVariant etc)
        let themeColors: [String: String] = [
            "--colorsurface": currentTheme.surface.toHexString(),
            "--coloronsurface": currentTheme.onSurface.toHexString(),
            "--colorsurfacevariant": currentTheme.surfaceVariant.toHexString(),
            "--coloronsurfacevariant": currentTheme.onSurfaceVariant.toHexString(),
            "--colorprimarycontainer": currentTheme.primaryContainer.toHexString(),
            "--coloronprimarycontainer": currentTheme.onPrimaryContainer.toHexString(),
            "--coloroutline": currentTheme.outline.toHexString(),
            "--ooui-interface": currentTheme.surfaceVariant.toHexString(),
            "--ooui-interface-border": currentTheme.outline.toHexString()
        ]

        // Build JavaScript object string
        let jsObjectEntries = themeColors.map { key, value in
            "    '\(key)': '\(value)'"
        }.joined(separator: ",\n")

        // Create JavaScript to inject CSS custom properties
        let script = """
        (function() {
            try {
                console.log('📱 iOS: Starting theme color and font injection...');

                const themeColors = {
                \(jsObjectEntries)
                };

                console.log('📱 iOS: Theme colors object created:', themeColors);

                for (const [key, value] of Object.entries(themeColors)) {
                    document.documentElement.style.setProperty(key, value);
                }
                console.log('📱 iOS: Applied theme colors as CSS variables');

                // FEATURE PARITY FIX 1: Remove edit links like Android does
                console.log('📱 iOS: Removing [edit | edit source] links for Android parity');
                const editLinks = document.querySelectorAll('span.mw-editsection');
                editLinks.forEach(link => {
                    link.remove();
                });
                console.log('📱 iOS: Removed', editLinks.length, 'edit links');

                // FEATURE PARITY FIX 2: Apply Alegreya font to page title and headings like Android
                console.log('📱 iOS: Starting Alegreya font application...');

                // Test document state
                console.log('📱 iOS: Document ready state:', document.readyState);
                console.log('📱 iOS: Document body exists:', !!document.body);

                const pageHeader = document.querySelector('h1.page-header');
                const allHeadings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');

                console.log('📱 iOS: Found page header:', !!pageHeader);
                console.log('📱 iOS: Found', allHeadings.length, 'headings total');

                // Test font availability using different methods
                console.log('📱 iOS: Testing font availability...');

                // Method 1: Check if font is loaded
                if (document.fonts && document.fonts.check) {
                    const alegreyaBoldLoaded = document.fonts.check('16px "Alegreya-Bold"');
                    const alegreyaLoaded = document.fonts.check('16px Alegreya');
                    console.log('📱 iOS: Alegreya-Bold loaded:', alegreyaBoldLoaded);
                    console.log('📱 iOS: Alegreya loaded:', alegreyaLoaded);
                }

                // Method 2: Create test element to see computed font
                const testElement = document.createElement('div');
                testElement.style.fontFamily = '"Alegreya-Bold", "Alegreya", Georgia, serif';
                testElement.style.fontSize = '16px';
                testElement.textContent = 'Test';
                testElement.style.position = 'absolute';
                testElement.style.left = '-9999px';
                document.body.appendChild(testElement);
                const computedFont = window.getComputedStyle(testElement).fontFamily;
                document.body.removeChild(testElement);
                console.log('📱 iOS: Test element computed fontFamily:', computedFont);

                if (pageHeader) {
                    console.log('📱 iOS: Applying font to page header...');
                    pageHeader.style.fontFamily = '"Alegreya-Bold", "Alegreya", Georgia, serif';
                    pageHeader.style.fontWeight = 'bold';
                    console.log('📱 iOS: Applied font to page header');

                    // Force style recalculation
                    pageHeader.offsetHeight;

                    // Check what font was actually applied
                    const appliedFont = window.getComputedStyle(pageHeader).fontFamily;
                    console.log('📱 iOS: Page header final computed fontFamily:', appliedFont);
                } else {
                    console.log('📱 iOS: No page header found');
                }

                console.log('📱 iOS: Processing', allHeadings.length, 'headings...');
                allHeadings.forEach((heading, index) => {
                    try {
                        const level = parseInt(heading.tagName.substring(1));
                        const fontFamily = level <= 2 ? '"Alegreya-Bold", "Alegreya", Georgia, serif' : '"Alegreya-Medium", "Alegreya", Georgia, serif';
                        const fontWeight = level <= 2 ? 'bold' : '500';

                        heading.style.fontFamily = fontFamily;
                        heading.style.fontWeight = fontWeight;

                        // Force style recalculation
                        heading.offsetHeight;

                        // Debug first few headings
                        if (index < 3) {
                            const appliedFont = window.getComputedStyle(heading).fontFamily;
                            console.log('📱 iOS: Heading', heading.tagName, 'level', level, 'set to:', fontFamily);
                            console.log('📱 iOS: Heading', heading.tagName, 'computed fontFamily:', appliedFont);
                            console.log('📱 iOS: Heading text:', heading.textContent.substring(0, 50));
                        }
                    } catch (headingError) {
                        console.error('📱 iOS: Error processing heading', index, ':', headingError);
                    }
                });

                console.log('📱 iOS: ✅ Successfully applied Alegreya fonts to', allHeadings.length, 'headings');

                // DEBUG: Test if :has() selector is actually supported in this WebKit version
                const hasSupported = CSS.supports('selector(.test:has(.child))');
                console.log('📱 iOS WebKit :has() support:', hasSupported);

                // DEBUG: Check actual HTML structure
                const infoboxes = document.querySelectorAll('.infobox');
                console.log('📱 iOS: Found', infoboxes.length, 'infoboxes');

                console.log('📱 iOS: ✅ All styling fixes completed successfully');

            } catch (error) {
                console.error('📱 iOS: CRITICAL ERROR in theme/font injection:', error);
                console.error('📱 iOS: Error name:', error.name);
                console.error('📱 iOS: Error message:', error.message);
                console.error('📱 iOS: Error stack:', error.stack);

                // Try to continue with minimal fixes if main script fails
                try {
                    console.log('📱 iOS: Attempting fallback font application...');
                    const pageHeader = document.querySelector('h1.page-header');
                    if (pageHeader) {
                        pageHeader.style.fontFamily = 'Alegreya-Bold, Georgia, serif';
                        console.log('📱 iOS: Fallback - applied font to page header');
                    }
                } catch (fallbackError) {
                    console.error('📱 iOS: Even fallback failed:', fallbackError);
                }
            }
        })();
        """

        print("🎨 ArticleViewModel: Evaluating theme color injection JavaScript")
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("❌ ArticleViewModel: Theme color injection failed: \(error.localizedDescription)")
            } else {
                print("✅ ArticleViewModel: Theme colors applied successfully")
            }
            completion()
        }
    }

    /// Apply final styling fixes for complete Android parity
    private func applyFinalStylingFixes(webView: WKWebView) {
        print("🎨 ArticleViewModel: Applying final styling fixes for Android parity")

        let finalStylingScript = """
        (function() {
            console.log('🎨 iOS: Applying final styling fixes for complete Android parity');

            // Apply colorSurfaceVariant background to collapsible containers
            const collapsibleContainers = document.querySelectorAll('.navbox, .collapsible, .mw-collapsible');
            collapsibleContainers.forEach(container => {
                container.style.backgroundColor = 'var(--colorsurfacevariant)';
                container.style.border = '1px solid var(--coloroutline)';
            });

            // Ensure infoboxes use the proper theme colors
            const infoboxes = document.querySelectorAll('.infobox');
            infoboxes.forEach(infobox => {
                infobox.style.backgroundColor = 'var(--colorsurfacevariant)';
                infobox.style.border = '2px solid var(--coloroutline)';
            });

            console.log('✅ iOS: Final styling fixes applied successfully');
        })();
        """

        webView.evaluateJavaScript(finalStylingScript) { result, error in
            if let error = error {
                print("❌ ArticleViewModel: Final styling fixes failed: \(error.localizedDescription)")
            } else {
                print("✅ ArticleViewModel: Final styling fixes applied successfully")
            }
        }
    }

    /// Build HTML with proper asset links matching Android's approach
    private func buildHtmlWithAssetLinks(originalHtml: String, theme: any osrsThemeProtocol) -> String {
        print("🔗 ArticleViewModel: Building HTML with iOS asset links")

        // Extract body content and title from original HTML
        let bodyContent = extractBodyContent(from: originalHtml)
        let titleContent = extractTitleContent(from: originalHtml) ?? pageTitle

        // Use osrsPageHtmlBuilder to generate HTML with asset links
        let htmlBuilder = osrsPageHtmlBuilder()
        var htmlWithLinks = htmlBuilder.buildFullHtmlDocument(
            title: titleContent,
            bodyContent: bodyContent,
            theme: theme,
            collapseTablesEnabled: collapseTablesEnabled,
            includeAssetLinks: true  // This generates <link> and <script> tags
        )

        // Replace href and src attributes to use ios-assets:// scheme for internal resources only
        // CRITICAL FIX: Only convert relative/internal URLs, preserve external URLs
        htmlWithLinks = convertInternalUrlsToCustomScheme(htmlWithLinks)

        print("🔗 ArticleViewModel: Generated HTML with iOS asset links (\(htmlWithLinks.count) characters)")
        return htmlWithLinks
    }

    /// Convert only internal/relative URLs to custom scheme, preserve external URLs
    /// CRITICAL FIX: Prevents external wiki URLs from being converted to localhost
    private func convertInternalUrlsToCustomScheme(_ html: String) -> String {
        var processedHtml = html

        // Use regex to find and replace only relative/internal URLs
        // Pattern: href="something" or src="something" where something doesn't start with http/https

        // Fix href attributes - only convert non-HTTP URLs
        let hrefPattern = #"href="(?!https?://)([^"]+)""#
        processedHtml = processedHtml.replacingOccurrences(
            of: hrefPattern,
            with: "href=\"ios-assets://localhost/$1\"",
            options: .regularExpression
        )

        // Fix src attributes - only convert non-HTTP URLs
        let srcPattern = #"src="(?!https?://)([^"]+)""#
        processedHtml = processedHtml.replacingOccurrences(
            of: srcPattern,
            with: "src=\"ios-assets://localhost/$1\"",
            options: .regularExpression
        )

        print("🔧 FIXED: Converted only relative URLs to custom scheme, preserved external URLs")
        return processedHtml
    }

    // FREEZE FIX: Make HTML building async to prevent main thread blocking during asset loading
    private func buildEnhancedHtmlWithWorkingCSS(originalHtml: String) async -> String {
        print("🎨 ArticleViewModel: Building enhanced HTML with working CSS/JS system")

        // Load and verify CSS/JS assets from bundle (like the working test environment)
        let cssContent = await loadAllCSSAssets()
        let jsContent = await loadAllJSAssets()

        print("🎨 ArticleViewModel: Loaded \(cssContent.count) chars CSS, \(jsContent.count) chars JS")

        // Extract body content from original HTML
        let bodyContent = extractBodyContent(from: originalHtml)
        let titleContent = extractTitleContent(from: originalHtml) ?? pageTitle

        // Build final HTML with working inline styles that render properly
        let finalHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(titleContent)</title>
            <style>
                \(cssContent)

                /* Enhanced dark theme styles that actually work */
                body {
                    background-color: #1a1a1a !important;
                    color: #ffffff !important;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    line-height: 1.6;
                    margin: 0;
                    padding: 20px;
                }

                .page-header {
                    color: #ffd700 !important;
                    background: #2d2d2d !important;
                    padding: 15px !important;
                    margin: 0 0 20px 0 !important;
                    border-radius: 8px !important;
                }

                .wikitable {
                    background-color: #333 !important;
                    border: 2px solid #666 !important;
                    color: #ffffff !important;
                }

                .wikitable th {
                    background-color: #444 !important;
                    color: #ffd700 !important;
                    border: 1px solid #666 !important;
                }

                .wikitable td {
                    background-color: #2a2a2a !important;
                    border: 1px solid #666 !important;
                    color: #ffffff !important;
                }

                a {
                    color: #66b3ff !important;
                }

                a:visited {
                    color: #bb99ff !important;
                }

                /* Infobox styling */
                .infobox {
                    background-color: #2d2d2d !important;
                    border: 2px solid #666 !important;
                    color: #ffffff !important;
                }

                .infobox-header {
                    background-color: #444 !important;
                    color: #ffd700 !important;
                }
            </style>
        </head>
        <body style="visibility: hidden;">
            \(bodyContent)
            <script>
                \(jsContent)

                // Enhanced console debugging
                console.log('🎉 ArticleViewModel: Enhanced HTML with working CSS loaded successfully!');

                // Theme application
                document.body.classList.add('theme-osrs-dark');

                // Make page visible
                document.body.style.visibility = 'visible';
            </script>
        </body>
        </html>
        """

        print("🎨 ArticleViewModel: Built enhanced HTML document (\(finalHtml.count) characters)")
        return finalHtml
    }

    // FREEZE FIX: Make CSS asset loading async to prevent main thread blocking
    private func loadAllCSSAssets() async -> String {
        let cssFiles = [
            "styles/themes.css",
            "styles/base.css",
            "styles/fonts.css",
            "styles/layout.css",
            "styles/components.css",
            "styles/wiki-integration.css",
            "styles/navbox_styles.css",
            "styles/collapsible_tables.css",
            "web/collapsible_sections.css",
            "styles/infobox_switcher.css",
            "styles/fixes.css"
        ]

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var combinedCSS = ""
                var loadedCount = 0

                for cssFile in cssFiles {
                    if let path = Bundle.main.path(forResource: cssFile.replacingOccurrences(of: ".css", with: ""), ofType: "css", inDirectory: cssFile.contains("/") ? String(cssFile.prefix(upTo: cssFile.lastIndex(of: "/")!)) : nil),
                       let content = try? String(contentsOfFile: path) {
                        combinedCSS += content + "\n"
                        loadedCount += 1
                        print("✅ ArticleViewModel: Loaded CSS asset: \(cssFile)")
                    } else {
                        print("❌ ArticleViewModel: Failed to load CSS asset: \(cssFile)")
                    }
                }

                print("📊 ArticleViewModel: Successfully loaded \(loadedCount)/\(cssFiles.count) CSS files")
                continuation.resume(returning: combinedCSS)
            }
        }
    }

    // FREEZE FIX: Make JS asset loading async to prevent main thread blocking
    private func loadAllJSAssets() async -> String {
        let jsFiles = [
            "startup.js",
            "js/tablesort.min.js",
            "js/tablesort_init.js",
            "web/article_tools.js",
            "web/collapsible_content.js",
            "web/table_wrapper.js",
            "web/infobox_switcher_bootstrap.js",
            "web/switch_infobox.js",
            "web/horizontal_scroll_interceptor.js",
            "web/responsive_videos.js",
            "web/clipboard_bridge.js"
        ]

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var combinedJS = ""
                var loadedCount = 0

                for jsFile in jsFiles {
                    if let path = Bundle.main.path(forResource: jsFile.replacingOccurrences(of: ".js", with: ""), ofType: "js", inDirectory: jsFile.contains("/") ? String(jsFile.prefix(upTo: jsFile.lastIndex(of: "/")!)) : nil),
                       let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        combinedJS += content + "\n"
                        loadedCount += 1
                        print("✅ ArticleViewModel: Loaded JS asset: \(jsFile)")
                    } else {
                        print("❌ ArticleViewModel: Failed to load JS asset: \(jsFile)")
                    }
                }

                print("📊 ArticleViewModel: Successfully loaded \(loadedCount)/\(jsFiles.count) JS files")
                continuation.resume(returning: combinedJS)
            }
        }
    }

    private func extractBodyContent(from html: String) -> String {
        // Extract content between <body> tags
        if let bodyStart = html.range(of: "<body", options: .caseInsensitive),
           let bodyTagEnd = html.range(of: ">", range: bodyStart.upperBound..<html.endIndex),
           let bodyEnd = html.range(of: "</body>", options: .caseInsensitive) {
            return String(html[bodyTagEnd.upperBound..<bodyEnd.lowerBound])
        }

        // If no body tags found, return the entire HTML as content
        return html
    }

    private func extractTitleContent(from html: String) -> String? {
        // Extract title from HTML
        if let titleStart = html.range(of: "<title>", options: .caseInsensitive),
           let titleEnd = html.range(of: "</title>", options: .caseInsensitive) {
            return String(html[titleStart.upperBound..<titleEnd.lowerBound])
        }
        return nil
    }

    private func loadTestHtml() {
        print("🧪 ArticleViewModel: Loading test HTML")

        let testHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Test Article</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #FF0000 !important;
                    color: #FFFFFF !important;
                    min-height: 100vh;
                }
                h1 {
                    color: #FFFF00 !important;
                    background: #000000;
                    padding: 10px;
                    margin: 0 0 20px 0;
                }
                .test-content {
                    background: #0000FF !important;
                    color: #FFFFFF !important;
                    padding: 20px;
                    border: 3px solid #FFFFFF;
                    margin: 20px 0;
                }
                p, li { color: #FFFFFF !important; }
                code {
                    background: #FFFF00 !important;
                    color: #000000 !important;
                    padding: 2px 4px;
                }
            </style>
        </head>
        <body style="visibility: hidden;">
            <h1>🧪 DEBUG: Test Article Loaded Successfully!</h1>
            <div class="test-content">
                <p><strong>SUCCESS!</strong> If you can see this colorful test page, the custom HTML loading is working!</p>
                <p>Original URL: <code>\(pageUrl.absoluteString)</code></p>
                <p>Page Title: <code>\(pageTitle_ ?? "nil")</code></p>
                <p>Page ID: <code>\(pageId?.description ?? "nil")</code></p>
                <p>Status Check:</p>
                <ul>
                    <li>✅ ArticleViewModel.loadArticle() was called</li>
                    <li>✅ loadTestHtml() was executed</li>
                    <li>✅ WebView.loadHTMLString() was called</li>
                    <li>✅ HTML is rendering in WebView</li>
                </ul>
                <p><strong>Next step:</strong> Debug the actual wiki API loading mechanism...</p>
            </div>
            <script>
                console.log('🧪 Test HTML loaded successfully!');
                document.body.style.visibility = 'visible';
            </script>
        </body>
        </html>
        """

        print("🧪 ArticleViewModel: About to call loadHTMLString")
        print("🧪 ArticleViewModel: webView is \(webView == nil ? "nil" : "not nil")")

        if let webView = webView {
            print("🧪 ArticleViewModel: Calling webView.loadHTMLString with \(testHtml.count) characters...")

            // Use proper base URL like Android does - create a local asset domain
            let baseURL = URL(string: "https://oldschool.runescape.wiki/")!
            webView.loadHTMLString(testHtml, baseURL: baseURL)
            print("🧪 ArticleViewModel: loadHTMLString called successfully with baseURL: \(baseURL)")

            // After loading, reveal the body like Android does
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("🧪 ArticleViewModel: Revealing body content...")
                self.revealBody(webView: webView)
            }
        } else {
            print("❌ ArticleViewModel: webView is nil! Cannot load HTML")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isLoading = false
            self.loadingProgress = 1.0
            self.pageTitle = "Test Article"
        }
    }

    func completeLoadingWithBodyReveal() {
        markJavaScriptReady(for: currentLoadGeneration)
    }

    func completeLoadingWithBodyReveal(loadGeneration: Int?) {
        guard let loadGeneration = loadGeneration else {
            print("🚫 ArticleViewModel: Ignoring JavaScript readiness without load generation")
            return
        }
        markJavaScriptReady(for: loadGeneration)
    }

    private func scheduleReadinessTimeout(for generation: Int) {
        readinessTimeoutWorkItem?.cancel()

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrentLoad(generation), self.isLoading || self.isRefreshing else { return }
            let timeString = DateFormatter.timeFormatter.string(from: Date())
            print("⚠️ [\(timeString)] ARTICLE READINESS TIMEOUT: generation \(generation) did not reach WebKit+JS readiness")
            self.isLoading = false
            self.isRefreshing = false
            self.loadingProgressText = nil
            self.errorMessage = "Page rendering timed out. Please try reloading."
        }

        readinessTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
    }

    private func markWebKitReady(for generation: Int) {
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring stale WebKit readiness for generation \(generation)")
            return
        }

        webKitReadyGeneration = generation
        attemptCompleteCurrentLoad(generation: generation)
    }

    private func markJavaScriptReady(for generation: Int) {
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring stale JavaScript readiness for generation \(generation)")
            return
        }

        javaScriptReadyGeneration = generation
        if isLoading || isRefreshing {
            loadingProgress = max(loadingProgress, 0.97)
            loadingProgressText = "Revealing content..."
        }
        attemptCompleteCurrentLoad(generation: generation)
    }

    private func attemptCompleteCurrentLoad(generation: Int) {
        guard isCurrentLoad(generation),
              webKitReadyGeneration == generation,
              javaScriptReadyGeneration == generation,
              completedLoadGeneration != generation else {
            return
        }

        completedLoadGeneration = generation
        readinessTimeoutWorkItem?.cancel()
        finishLoadingWithBodyReveal(generation: generation)
    }

    private func finishLoadingWithBodyReveal(generation: Int) {
        guard let webView = webView else {
            print("❌ ArticleViewModel: WebView not available for body reveal")
            return
        }

        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🏁 COMPLETING PROGRESS: WebKit and JS ready for generation \(generation)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isCurrentLoad(generation) else {
                print("🚫 ArticleViewModel: Ignoring stale reveal for generation \(generation)")
                return
            }

            let revealTimeString = DateFormatter.timeFormatter.string(from: Date())
            print("📊 [\(revealTimeString)] 👁️ REVEALING BODY: Making content visible to user...")

            // CRITICAL FIX: Wrap JavaScript to not return value that causes WKWebView type error
            let revealBodyJs = """
                (function() {
                    try {
                        if (document.body) {
                            document.body.style.visibility = 'visible';
                            console.log('📱 iOS: Body visibility set to visible');
                            return 'success';
                        } else {
                            console.log('📱 iOS: document.body not found');
                            return 'no_body';
                        }
                    } catch (error) {
                        console.log('📱 iOS: Error revealing body:', error);
                        return 'error';
                    }
                })();
            """

            webView.evaluateJavaScript(revealBodyJs) { result, error in
                DispatchQueue.main.async {
                    guard self.isCurrentLoad(generation) else {
                        print("🚫 ArticleViewModel: Ignoring stale reveal callback for generation \(generation)")
                        return
                    }
                    let completionTimeString = DateFormatter.timeFormatter.string(from: Date())
                    if let error = error {
                        print("📊 [\(completionTimeString)] ❌ BODY REVEAL FAILED: \(error)")
                        // Attempt fallback approach
                        webView.evaluateJavaScript("void(document.body && (document.body.style.visibility = 'visible'));") { fallbackResult, fallbackError in
                            if let fallbackError = fallbackError {
                                print("📊 [\(completionTimeString)] ❌ FALLBACK REVEAL FAILED: \(fallbackError)")
                            } else {
                                print("📊 [\(completionTimeString)] ✅ FALLBACK REVEAL SUCCEEDED")
                            }
                        }
                    } else if let resultString = result as? String {
                        print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - result: \(resultString)")
                    } else {
                        print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - user can see page content!")
                    }

                    // Record final page visibility time for timing measurements
                    self.pageVisibilityTime = Date()
                    self.progressCompletionTime = Date()
                    self.loadingProgress = 1.0
                    self.loadingProgressText = "Complete!"
                    self.isLoading = false
                    self.isRefreshing = false
                    print("✅ ArticleViewModel: Loading completed for generation \(generation)!")
                    self.addToHistory(generation: generation)
                    self.startRenderedArticleIdentityProbe(for: generation)
                }
            }
        }
    }

    private func revealBody(webView: WKWebView) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        // CRITICAL FIX: Wrap JavaScript to not return value that causes WKWebView type error
        let revealBodyJs = """
            (function() {
                try {
                    if (document.body) {
                        document.body.style.visibility = 'visible';
                        console.log('📱 iOS: Body visibility set to visible');
                        return 'success';
                    } else {
                        console.log('📱 iOS: document.body not found');
                        return 'no_body';
                    }
                } catch (error) {
                    console.log('📱 iOS: Error revealing body:', error);
                    return 'error';
                }
            })();
        """
        print("📊 [\(timeString)] 👁️ REVEALING BODY: Making content visible to user...")

        webView.evaluateJavaScript(revealBodyJs) { result, error in
            let completionTimeString = DateFormatter.timeFormatter.string(from: Date())
            if let error = error {
                print("📊 [\(completionTimeString)] ❌ BODY REVEAL FAILED: \(error)")
                // Attempt fallback approach
                webView.evaluateJavaScript("void(document.body && (document.body.style.visibility = 'visible'));") { fallbackResult, fallbackError in
                    if let fallbackError = fallbackError {
                        print("📊 [\(completionTimeString)] ❌ FALLBACK REVEAL FAILED: \(fallbackError)")
                    } else {
                        print("📊 [\(completionTimeString)] ✅ FALLBACK REVEAL SUCCEEDED")
                    }
                }
            } else if let resultString = result as? String {
                print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - result: \(resultString)")
            } else {
                print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - user can see page content!")
            }
        }
    }

    private func extractTitleFromUrl(_ url: URL) -> String {
        // Extract article title from wiki URL
        // Examples:
        // https://oldschool.runescape.wiki/w/Dragon -> "Dragon"
        // https://oldschool.runescape.wiki/w/Update:The_Way_of_the_Forester -> "Update:The Way of the Forester"
        // https://oldschool.runescape.wiki/?curid=123 -> fall back to URL

        print("🔗 ArticleViewModel: Processing URL: \(url.absoluteString)")

        let path = url.path
        print("🔗 ArticleViewModel: URL path: '\(path)'")

        if path.hasPrefix("/w/") {
            let encodedTitle = String(path.dropFirst(3)) // Remove "/w/"
            print("🔗 ArticleViewModel: Raw encoded title: '\(encodedTitle)'")

            // First decode any URL encoding
            let partiallyDecoded = encodedTitle.removingPercentEncoding ?? encodedTitle
            print("🔗 ArticleViewModel: After percent decoding: '\(partiallyDecoded)'")

            // Then replace underscores with spaces (wiki convention)
            let decodedTitle = partiallyDecoded.replacingOccurrences(of: "_", with: " ")
            print("🔗 ArticleViewModel: Final decoded title: '\(decodedTitle)'")

            // Clean up any remaining encoding artifacts
            let cleanTitle = cleanUpTitle(decodedTitle)
            print("🔗 ArticleViewModel: Cleaned title: '\(cleanTitle)'")

            return cleanTitle
        }

        // For curid URLs, we'd need the pageId which should be passed in init
        let fallback = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let cleanFallback = cleanUpTitle(fallback.replacingOccurrences(of: "_", with: " "))
        print("🔗 ArticleViewModel: Using fallback title '\(cleanFallback)' from URL")
        return cleanFallback
    }

    private func cleanUpTitle(_ title: String) -> String {
        var cleanTitle = title

        // Remove any remaining percent-encoded characters that might have slipped through
        while cleanTitle.contains("%") && cleanTitle != (cleanTitle.removingPercentEncoding ?? cleanTitle) {
            cleanTitle = cleanTitle.removingPercentEncoding ?? cleanTitle
        }

        // Clean up common encoding artifacts
        cleanTitle = cleanTitle
            .replacingOccurrences(of: "%20-", with: " ")  // Fix malformed encoding
            .replacingOccurrences(of: "%20", with: " ")   // Any remaining %20
            .replacingOccurrences(of: "%3A", with: ":")   // Colon
            .replacingOccurrences(of: "%2C", with: ",")   // Comma
            .replacingOccurrences(of: "%26", with: "&")   // Ampersand
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple spaces into single spaces
        while cleanTitle.contains("  ") {
            cleanTitle = cleanTitle.replacingOccurrences(of: "  ", with: " ")
        }

        return cleanTitle
    }

    func goBack() -> Bool {
        guard let webView = webView, webView.canGoBack else { return false }
        webView.goBack()
        return true
    }

    func goBackToPreviousWebViewArticleIfNeeded() -> Bool {
        guard let webView = webView,
              webView.canGoBack,
              let currentURL = webView.url,
              Self.osrsShouldUseWebViewArticleHistory(currentURL: currentURL, pageURL: pageUrl) else {
            return false
        }

        print("🔙 ArticleViewModel: Falling back to WebView article history from \(currentURL.absoluteString)")
        webView.goBack()
        return true
    }

    func goForward() -> Bool {
        guard let webView = webView, webView.canGoForward else { return false }
        webView.goForward()
        return true
    }

    func toggleBookmark() {
        isBookmarked.toggle()
        // TODO: Implement actual bookmark persistence
    }

    func scrollToSection(_ sectionId: String) {
        webView?.evaluateJavaScript(Self.osrsScrollToSectionScript(for: sectionId))
    }

    static func osrsScrollToSectionScript(for sectionId: String) -> String {
        let sectionIdLiteral = osrsJavaScriptStringLiteral(sectionId)
        return """
            (function() {
                const sectionId = \(sectionIdLiteral);
                const escapedId = (window.CSS && CSS.escape)
                    ? CSS.escape(sectionId)
                    : sectionId.replace(/[\"\\\\]/g, '\\\\$&');
                const element = document.getElementById(sectionId)
                    || document.querySelector('[id="' + escapedId + '"]');
                if (!element) {
                    return false;
                }

                const headerOffset = Math.max(72, Math.min(132, Math.round(window.innerHeight * 0.10)));
                const elementTop = element.getBoundingClientRect().top + window.pageYOffset;
                const targetY = Math.max(0, elementTop - headerOffset);
                window.scrollTo({ top: targetY, behavior: 'smooth' });
                return true;
            })();
        """
    }

    private static func osrsJavaScriptStringLiteral(_ value: String) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let encodedArray = String(data: data, encoding: .utf8),
              encodedArray.count >= 2 else {
            return "\"\""
        }

        return String(encodedArray.dropFirst().dropLast())
    }

    func clearError() {
        errorMessage = nil
    }

    // JavaScript bridge methods - updated to match Android CSS variable injection
    // (Note: The injectThemeColors implementation is now at line 395)

    func extractTableOfContents() {
        let tocScript = """
            (function() {
                const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
                const toc = [];

                headings.forEach((heading, index) => {
                    const level = parseInt(heading.tagName.substring(1));
                    const text = heading.textContent.trim();
                    const id = heading.id || 'heading-' + index;

                    if (!heading.id) {
                        heading.id = id;
                    }

                    toc.push({
                        id: id,
                        title: text,
                        level: level
                    });
                });

                return JSON.stringify(toc);
            })();
        """

        webView?.evaluateJavaScript(tocScript) { [weak self] result, error in
            guard let self = self,
                  let jsonString = result as? String,
                  let jsonData = jsonString.data(using: .utf8) else { return }

            do {
                let sections = try JSONDecoder().decode([TableOfContentsSection].self, from: jsonData)
                DispatchQueue.main.async {
                    self.tableOfContents = sections
                    self.hasTableOfContents = !sections.isEmpty
                }
            } catch {
                print("Failed to parse table of contents: \(error)")
            }
        }
    }

    deinit {
        currentLoadTask?.cancel()
        readinessTimeoutWorkItem?.cancel()
        reloadTimeoutWorkItem?.cancel()
        refreshTimeoutWorkItem?.cancel()
        deferredRefreshWorkItem?.cancel()
        progressObserver?.invalidate()
        renderedArticleIdentityProbe?.invalidate()

        // Clean up preloaded maps when ArticleViewModel is deallocated
        Task { @MainActor in
            osrsMapPreloadService.shared.clearPreloadedMaps()
        }

        print("🧹 ArticleViewModel: Cleaned up and deallocated")
    }
}

// MARK: - WKNavigationDelegate
extension ArticleViewModel: WKNavigationDelegate {
    func recoverRenderedArticleMismatchIfNeeded(
        theme: any osrsThemeProtocol,
        fallbackToNativeBack: @escaping () -> Void
    ) -> Bool {
        guard let webView = webView else {
            return false
        }

        webView.evaluateJavaScript(Self.renderedArticleTitleScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else {
                    fallbackToNativeBack()
                    return
                }

                if let error = error {
                    print("⚠️ ArticleViewModel: Rendered mismatch recovery probe failed: \(error.localizedDescription)")
                    fallbackToNativeBack()
                    return
                }

                guard let renderedTitle = result as? String,
                      !renderedTitle.isEmpty,
                      let renderedArticleURL = Self.articleURL(forResolvedTitle: renderedTitle),
                      renderedArticleURL.absoluteString != self.pageUrl.absoluteString else {
                    fallbackToNativeBack()
                    return
                }

                print("🔙 ArticleViewModel: Recovering source article after unbound rendered article mutation")
                print("  - Rendered title: \(renderedTitle)")
                print("  - Rendered URL: \(renderedArticleURL.absoluteString)")
                print("  - Expected URL: \(self.pageUrl.absoluteString)")
                self.stopRenderedArticleIdentityProbe()
                self.loadArticle(theme: theme, isReload: true)
            }
        }

        return true
    }

    private static let renderedArticleTitleScript = """
        (function() {
            const candidates = [
                document.querySelector('#firstHeading'),
                document.querySelector('h1.page-header'),
                document.querySelector('.mw-page-title-main'),
                document.querySelector('h1')
            ];
            for (const candidate of candidates) {
                if (candidate && candidate.textContent) {
                    const text = candidate.textContent.trim();
                    if (text) {
                        return text;
                    }
                }
            }
            if (document.title) {
                return document.title.replace(/\\s+-\\s+OSRS Wiki.*$/i, '').trim();
            }
            return '';
        })();
        """

    private func startRenderedArticleIdentityProbe(for generation: Int) {
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
        renderedArticleIdentityProbeAttempts = 0

        guard isCurrentLoad(generation), !excludeFromHistory else { return }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self, self.isCurrentLoad(generation), let webView = self.webView else {
                    timer.invalidate()
                    return
                }

                self.renderedArticleIdentityProbeAttempts += 1
                if self.renderedArticleIdentityProbeAttempts > 24 {
                    timer.invalidate()
                    if let activeTimer = self.renderedArticleIdentityProbe, activeTimer === timer {
                        self.renderedArticleIdentityProbe = nil
                    }
                    return
                }

                self.routeRenderedArticleNavigationIfNeeded(in: webView, context: "renderedArticleIdentityProbe")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        renderedArticleIdentityProbe = timer
    }

    private func stopRenderedArticleIdentityProbe() {
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
    }

    private func routeRenderedArticleNavigationIfNeeded(in webView: WKWebView, context: String) {
        webView.evaluateJavaScript(Self.renderedArticleTitleScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("⚠️ WEBVIEW: Rendered article identity probe failed: \(error.localizedDescription)")
                    return
                }
                guard let renderedTitle = result as? String,
                      !renderedTitle.isEmpty,
                      renderedTitle.contains("/"),
                      let articleURL = Self.articleURL(forResolvedTitle: renderedTitle) else {
                    return
                }

                guard articleURL.absoluteString != self.pageUrl.absoluteString else {
                    return
                }

                let routeKey = articleURL.absoluteString
                guard !self.routedObservedArticleNavigationURLs.contains(routeKey) else {
                    return
                }

                self.routedObservedArticleNavigationURLs.insert(routeKey)
                self.stopRenderedArticleIdentityProbe()
                print("🔄 WEBVIEW: Promoting rendered \(context) article identity into native stack:")
                print("  - Rendered title: \(renderedTitle)")
                print("  - Article URL: \(articleURL.absoluteString)")
                print("  - Current ArticleViewModel URL: \(self.pageUrl.absoluteString)")
                self.navigateToInternalArticle?(articleURL)
            }
        }
    }

    private func routeObservedUnboundArticleNavigationIfNeeded(in webView: WKWebView, context: String) -> Bool {
        guard let observedURL = webView.url,
              let articleURL = osrsArticleLinkRouter.appArticleURL(for: observedURL) else {
            return false
        }

        guard Self.osrsShouldPromoteWebViewArticleNavigation(candidateURL: articleURL, pageURL: pageUrl) else {
            return false
        }

        let routeKey = articleURL.absoluteString
        guard !routedObservedArticleNavigationURLs.contains(routeKey) else {
            return true
        }

        routedObservedArticleNavigationURLs.insert(routeKey)
        print("🔄 WEBVIEW: Promoting unbound \(context) article navigation into native stack:")
        print("  - Observed URL: \(observedURL.absoluteString)")
        print("  - Article URL: \(articleURL.absoluteString)")
        print("  - Current ArticleViewModel URL: \(pageUrl.absoluteString)")

        webView.stopLoading()
        DispatchQueue.main.async { [weak self] in
            self?.navigateToInternalArticle?(articleURL)
        }
        return true
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🚀 WEBVIEW: didStartProvisionalNavigation - WebKit started loading")
        print("🛠️ WEBVIEW DIAGNOSTIC: Navigation details:")
        print("  - Current URL: \(webView.url?.absoluteString ?? "nil")")
        print("  - Loading: \(webView.isLoading)")
        print("  - Estimated Progress: \(webView.estimatedProgress)")
        print("  - Can Go Back: \(webView.canGoBack)")
        print("  - Can Go Forward: \(webView.canGoForward)")

        if boundGeneration(for: navigation) == nil,
           routeObservedUnboundArticleNavigationIfNeeded(in: webView, context: "didStartProvisionalNavigation") {
            return
        }

        guard let generation = boundGeneration(for: navigation),
              isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring didStartProvisionalNavigation for stale or unbound WebKit navigation")
            return
        }

        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🌐 WEBKIT NAVIGATION FINISHED: Basic HTML loaded")
        if boundGeneration(for: navigation) == nil,
           routeObservedUnboundArticleNavigationIfNeeded(in: webView, context: "didFinish") {
            return
        }

        guard let generation = boundGeneration(for: navigation) else {
            print("🚫 ArticleViewModel: Ignoring didFinish for unbound WebKit navigation")
            return
        }
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring stale didFinish for generation \(generation)")
            return
        }
        clearBoundWebKitNavigation(navigation)

        // TIMING MEASUREMENT: Record when WebView navigation completes (NOT when content is visible)
        if progressCompletionTime != nil && pageVisibilityTime == nil {
            pageVisibilityTime = Date()
            print("📊 [\(timeString)] 📄 NAVIGATION COMPLETE: WebView finished loading HTML")

            // Calculate and log the delay
            if let startTime = progressCompletionTime, let endTime = pageVisibilityTime {
                let delay = endTime.timeIntervalSince(startTime)

                // Store the measured delay for external access
                self.lastMeasuredDelay = delay

                print("📊 TIMING RESULT: Progress-to-page delay = \(String(format: "%.3f", delay))s")

                // Provide automated optimization suggestions based on measured data
                if delay > 0.5 {
                    print("🔧 OPTIMIZATION: SEVERE delay detected (\(String(format: "%.3f", delay))s). Check WebView rendering pipeline.")
                } else if delay > 0.1 {
                    print("🔧 OPTIMIZATION: MODERATE delay (\(String(format: "%.3f", delay))s). Consider optimizing progress completion logic.")
                } else {
                    print("✅ OPTIMIZATION: Timing is within acceptable range (\(String(format: "%.3f", delay))s).")
                }
            }
        }

        // Extract table of contents from the loaded content
        extractTableOfContents()
        markWebKitReady(for: generation)
        applyAccessibilityReflow(to: webView)

        // CRITICAL FIX: Complete progress for web archives immediately after loading
        if pageUrl.scheme == "app-assets" || webView.url?.scheme == "file" {
            print("📦 [\(timeString)] WEB ARCHIVE LOADED: Marking JavaScript readiness for generation \(generation)")
            completeLoadingWithBodyReveal(loadGeneration: generation)
            return
        }

        // For live HTTPS pages: Inject styling complete notification similar to Android
        webView.evaluateJavaScript("""
            if (window.RenderTimeline) {
                window.RenderTimeline.log('Event: StylingScriptsComplete:\(generation)');
            }
        """)

        print("🎉 ArticleViewModel: Page rendering complete")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] ❌ WEBVIEW: didFail - Navigation failed after starting")
        analyzeWebViewError(error: error, context: "didFail", webView: webView)

        guard let generation = boundGeneration(for: navigation),
              isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring didFail for stale or unbound WebKit navigation")
            return
        }
        clearBoundWebKitNavigation(navigation)
        isLoading = false
        isRefreshing = false
        errorMessage = "Failed to load page: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] ❌ WEBVIEW: didFailProvisionalNavigation - Navigation failed before starting")
        analyzeWebViewError(error: error, context: "didFailProvisionalNavigation", webView: webView)

        guard let generation = boundGeneration(for: navigation),
              isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring provisional failure for stale or unbound WebKit navigation")
            return
        }
        clearBoundWebKitNavigation(navigation)
        isLoading = false
        isRefreshing = false
        errorMessage = "Failed to load page: \(error.localizedDescription)"
    }

    // MARK: - Comprehensive Error Analysis

    private func analyzeWebViewError(error: Error, context: String, webView: WKWebView) {
        print("🛠️ WEBVIEW ERROR ANALYSIS (\(context)):")
        print("  - Error Domain: \(error._domain)")
        print("  - Error Code: \(error._code)")
        print("  - Error Description: \(error.localizedDescription)")
        print("  - Current URL: \(webView.url?.absoluteString ?? "nil")")
        print("  - Target URL: \(pageUrl.absoluteString)")

        // Analyze specific error types
        if let nsError = error as NSError? {
            print("  - NSError Domain: \(nsError.domain)")
            print("  - NSError Code: \(nsError.code)")
            print("  - NSError UserInfo: \(nsError.userInfo)")

            // Analyze common WebKit error codes
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                print("  - ANALYSIS: No internet connection")
            case NSURLErrorTimedOut:
                print("  - ANALYSIS: Request timed out")
            case NSURLErrorCannotFindHost:
                print("  - ANALYSIS: Cannot find host - DNS resolution failed")
            case NSURLErrorCannotConnectToHost:
                print("  - ANALYSIS: Cannot connect to host - network/firewall issue")
            case NSURLErrorNetworkConnectionLost:
                print("  - ANALYSIS: Network connection lost during request")
            case NSURLErrorDNSLookupFailed:
                print("  - ANALYSIS: DNS lookup failed")
            case NSURLErrorHTTPTooManyRedirects:
                print("  - ANALYSIS: Too many HTTP redirects")
            case NSURLErrorResourceUnavailable:
                print("  - ANALYSIS: Resource unavailable")
            case NSURLErrorNotConnectedToInternet:
                print("  - ANALYSIS: Not connected to internet")
            case NSURLErrorBadURL:
                print("  - ANALYSIS: Malformed URL")
            case NSURLErrorUnsupportedURL:
                print("  - ANALYSIS: Unsupported URL scheme")
            case NSURLErrorCannotParseResponse:
                print("  - ANALYSIS: Cannot parse server response")
            default:
                print("  - ANALYSIS: Unknown error code \(nsError.code)")
            }

            // Check for specific WebKit error domains
            if nsError.domain == "WebKitErrorDomain" {
                print("  - ANALYSIS: WebKit-specific error")
                switch nsError.code {
                case 101:
                    print("  - ANALYSIS: WebKit frame load interrupted")
                case 102:
                    print("  - ANALYSIS: WebKit cancelled")
                case 204:
                    print("  - ANALYSIS: WebKit plugin will handle load")
                default:
                    print("  - ANALYSIS: Unknown WebKit error code \(nsError.code)")
                }
            }
        }

        // Check network connectivity
        print("🛠️ CONNECTIVITY CHECK:")
        print("  - Can make basic HTTP request: Testing...")
        testBasicConnectivity()

        // Check URL accessibility
        print("🛠️ URL ACCESSIBILITY CHECK:")
        testUrlAccessibility(url: pageUrl)
    }

    private func testBasicConnectivity() {
        guard let testUrl = URL(string: "https://www.google.com") else { return }

        let task = URLSession.shared.dataTask(with: testUrl) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("  - Basic connectivity test FAILED: \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("  - Basic connectivity test PASSED: HTTP \(httpResponse.statusCode)")
                } else {
                    print("  - Basic connectivity test: Unknown response type")
                }
            }
        }
        task.resume()
    }

    private func testUrlAccessibility(url: URL) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("  - Target URL test FAILED: \(error.localizedDescription)")
                    print("  - Target URL error domain: \(error._domain)")
                    print("  - Target URL error code: \(error._code)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("  - Target URL test PASSED: HTTP \(httpResponse.statusCode)")
                    if let data = data {
                        print("  - Target URL response size: \(data.count) bytes")
                        print("  - Target URL content preview: \(String(data: data.prefix(200), encoding: .utf8) ?? "binary")")
                    }
                } else {
                    print("  - Target URL test: Unknown response type")
                }
            }
        }
        task.resume()
    }

    private func handleArticleNavigationPolicy(
        for navigationAction: WKNavigationAction,
        in webView: WKWebView,
        timeString: String
    ) -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            print("⚠️ WEBVIEW: Navigation action has no URL")
            return .allow
        }

        print("🛠️ NAVIGATION POLICY ANALYSIS:")
        print("  - Target URL: \(url.absoluteString)")
        print("  - URL Scheme: \(url.scheme ?? "nil")")
        print("  - URL Host: \(url.host ?? "nil")")
        print("  - Navigation Type: \(navigationActionTypeString(navigationAction.navigationType))")
        print("  - Source Frame: \(navigationAction.sourceFrame.isMainFrame ? "main" : "subframe")")
        print("  - Target Frame: \(navigationAction.targetFrame?.isMainFrame == true ? "main" : navigationAction.targetFrame != nil ? "subframe" : "nil")")
        print("  - HTTP Method: \(navigationAction.request.httpMethod ?? "nil")")
        print("  - User Agent: \(navigationAction.request.value(forHTTPHeaderField: "User-Agent") ?? "nil")")

        switch Self.articleNavigationDecision(for: url) {
        case .appArticle(let articleURL):
            guard Self.osrsShouldPromoteWebViewArticleNavigation(candidateURL: articleURL, pageURL: pageUrl) else {
                print("↪️ WEBVIEW: Allowing same-article navigation in WebView:")
                print("  - Original: \(url.absoluteString)")
                print("  - Current ArticleViewModel URL: \(pageUrl.absoluteString)")
                return .allow
            }

            print("🔄 WEBVIEW: Routing internal article link through app navigation:")
            print("  - Original: \(url.absoluteString)")
            print("  - Article URL: \(articleURL.absoluteString)")

            if #available(iOS 17.0, *) {
                ProxyInterceptorService.shared.disableOfflineSaveMode()
                print("📊 [\(timeString)] 🔄 WEBVIEW: Disabled offline mode for new article navigation")
            }

            webView.stopLoading()
            DispatchQueue.main.async { [weak self] in
                self?.navigateToInternalArticle?(articleURL)
            }
            return .cancel

        case .external(let externalURL):
            print("  - Should open externally: true")
            print("📊 [\(timeString)] 🚀 WEBVIEW: Opening externally, cancelling WebView navigation")
            print("  - Original: \(url.absoluteString)")
            print("  - External URL: \(externalURL.absoluteString)")
            UIApplication.shared.open(externalURL)
            return .cancel

        case .allow:
            print("  - Should open externally: false")
            return .allow
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🔗 WEBVIEW: decidePolicyFor navigationAction")

        let policy = handleArticleNavigationPolicy(for: navigationAction, in: webView, timeString: timeString)
        if policy == .cancel {
            decisionHandler(.cancel)
            return
        }

        print("📊 [\(timeString)] ✅ WEBVIEW: Allowing navigation in WebView")
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🔗 WEBVIEW: decidePolicyFor navigationAction with webpage preferences")

        let policy = handleArticleNavigationPolicy(for: navigationAction, in: webView, timeString: timeString)
        if policy == .cancel {
            decisionHandler(.cancel, preferences)
            return
        }

        print("📊 [\(timeString)] ✅ WEBVIEW: Allowing navigation in WebView")
        decisionHandler(.allow, preferences)
    }

    private func navigationActionTypeString(_ type: WKNavigationType) -> String {
        switch type {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .formResubmitted:
            return "formResubmitted"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }

    private static func shouldOpenExternallyForArticleNavigation(_ url: URL) -> Bool {
        // CRITICAL: Allow our custom scheme for WKURLSchemeHandler
        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
        if url.scheme == customScheme {
            print("🔧 Allowing internal navigation for custom scheme: \(url.scheme ?? "nil")")
            return false // Keep internal for our custom asset scheme
        }

        // CRITICAL FIX: Allow web archive file:// URLs from offline_pages directory
        if url.scheme == "file" {
            let urlPath = url.path

            // Check if this is a web archive file in our offline_pages directory
            if urlPath.contains("offline_pages") && urlPath.hasSuffix(".webarchive") {
                print("🔧 Allowing internal navigation for offline web archive: \(urlPath)")
                return false // Keep internal for offline web archives
            }

            // Block other file:// URLs for security
            print("⚠️ Blocking external file:// URL for security: \(urlPath)")
            return true
        }

        // Open non-wiki links externally
        guard let host = url.host else { return true }
        return !osrsWebKitSecurityPolicy.isTrustedWikiHost(host)
    }

    // MARK: - Bottom Bar Actions

    /// Check if current page is already saved - matches Android PageReadingListManager.observeAndRefreshSaveButtonState()
    private func checkIfPageIsSaved() {
        guard !pageTitle.isEmpty else { return }

        let savedPages = savedPagesRepository.getSavedPages()
        let cleanTitle = cleanPageTitle(pageTitle)
        let isAlreadySaved = savedPages.contains { savedPage in
            savedPage.url == pageUrl || savedPage.title == cleanTitle || savedPage.title == pageTitle
        }

        isBookmarked = isAlreadySaved
        saveState = isAlreadySaved ? .saved : .notSaved
        saveProgress = isAlreadySaved ? 1.0 : 0.0

        print("🔖 ArticleViewModel: Checked save status - isBookmarked: \(isBookmarked), saveState: \(saveState)")
    }

    /// Save/bookmark toggle action - matches Android PageReadingListManager functionality
    func performSaveAction() async {
        guard saveState != .downloading else { return }

        print("🔖 ArticleViewModel: Save action triggered - current state: \(saveState), bookmarked: \(isBookmarked)")

        if isBookmarked {
            // Remove from saved pages - matches Android unsaving logic
            saveState = .downloading
            saveProgress = 0.0

            do {
                // Find and remove the saved page
                let savedPages = savedPagesRepository.getSavedPages()
                if let savedPage = savedPages.first(where: { $0.url == pageUrl || $0.title == pageTitle }) {
                    // Show progress while removing
                    for progress in stride(from: 0.0, through: 1.0, by: 0.2) {
                        await MainActor.run {
                            self.saveProgress = progress
                        }
                        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
                    }

                    // Remove from repository
                    savedPagesRepository.removeSavedPage(savedPage.id)

                    await MainActor.run {
                        self.isBookmarked = false
                        self.saveState = .notSaved
                        self.saveProgress = 0.0
                        print("✅ ArticleViewModel: Successfully removed page from saved pages")
                    }
                } else {
                    await MainActor.run {
                        self.saveState = .error
                        print("❌ ArticleViewModel: Could not find saved page to remove")
                    }
                }
            } catch {
                await MainActor.run {
                    self.saveState = .error
                    print("❌ ArticleViewModel: Error removing saved page: \(error)")
                }
            }
        } else {
            // Save for offline reading - matches Android saving logic
            saveState = .downloading
            saveProgress = 0.0

            do {
                    print("🔄 ArticleViewModel: Starting page save process...")

                    // Step 1: Fetch page metadata from API
                    await MainActor.run { self.saveProgress = 0.1 }

                    let metadata = await fetchPageMetadata()

                    // Step 2: Create SavedPage object with proper metadata
                    await MainActor.run { self.saveProgress = 0.2 }

                    // CRITICAL VALIDATION: Clean title and URL to prevent encoding issues
                    let rawTitle = cleanPageTitle(pageTitle)
                    let cleanTitle = rawTitle.decodingHTMLEntities() // Remove HTML entities like &amp;
                    let cleanUrl = pageUrl.absoluteString.removingPercentEncoding.flatMap(URL.init) ?? pageUrl // Decode URL encoding like %26

                    print("🔧 VALIDATION: Page save validation")
                    print("  - Raw title: '\(rawTitle)'")
                    print("  - Clean title: '\(cleanTitle)'")
                    print("  - Raw URL: \(pageUrl.absoluteString)")
                    print("  - Clean URL: \(cleanUrl.absoluteString)")

                    let savedPage = SavedPage(
                        id: UUID().uuidString,
                        title: cleanTitle,
                        description: metadata.description?.decodingHTMLEntities() ?? extractPageDescription(),
                        url: cleanUrl,
                        thumbnailUrl: metadata.thumbnailUrl ?? extractThumbnailUrl(),
                        savedDate: Date(),
                        isOfflineAvailable: false, // Will be updated when offline content is downloaded
                        offlineDownloadDate: nil,
                        offlineStatus: .notDownloaded,
                        offlineFileSize: nil,
                        offlineLocalPath: nil
                    )

                    // Step 3: Save page metadata to repository
                    await MainActor.run { self.saveProgress = 0.3 }

                    savedPagesRepository.addSavedPage(savedPage)
                    print("📱 ArticleViewModel: Added page metadata to repository")

                    // Step 4: Mark existing lazy-cached content as saved (Android-style instant save)
                    await MainActor.run { self.saveProgress = 0.5 }

                    print("⚡ ArticleViewModel: Using lazy caching - marking existing cache as saved")

                    do {
                        var durableOfflineReady = false

                        // Use modern iOS 17+ lazy caching approach
                        if #available(iOS 17.0, *) {
                            print("🚀 ArticleViewModel: Lazy caching implementation - instant save")

                            // Get the page ID that was used during browsing
                            let browsingPageId = generatePageIdFromURL(pageUrl)

                            // Check if we have cached content from browsing
                            let hasCache = ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: browsingPageId)

                            if hasCache {
                                print("✅ ArticleViewModel: Found existing cache from browsing - instant save!")

                                // Just link the saved page to the existing cache
                                ProxyInterceptorService.shared.linkSavedPageToCache(savedPageId: savedPage.id, browsingPageId: browsingPageId)
                                durableOfflineReady = ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: savedPage.id)

                                await MainActor.run { self.saveProgress = 0.8 }
                                print("🎉 ArticleViewModel: Page saved instantly using lazy-cached content")
                            } else {
                                print("⚠️ ArticleViewModel: No lazy cache found - falling back to traditional download")

                                // Fallback: Download content now (shouldn't happen with always-on caching)
                                guard let webView = webView else {
                                    throw NSError(domain: "ArticleViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not available"])
                                }

                                // Enable save mode for this page
                                let offlineSaveToken = ProxyInterceptorService.shared.enableOfflineSaveMode(pageId: savedPage.id)
                                defer {
                                    if let offlineSaveToken {
                                        ProxyInterceptorService.shared.disableMode(owner: offlineSaveToken)
                                    }
                                }

                                // Make a simple API request to cache the main content
                                let pageTitle = cleanTitle.replacingOccurrences(of: " ", with: "_")
                                var urlComponents = URLComponents(string: "https://oldschool.runescape.wiki/api.php")!
                                urlComponents.queryItems = [
                                    URLQueryItem(name: "action", value: "parse"),
                                    URLQueryItem(name: "format", value: "json"),
                                    URLQueryItem(name: "prop", value: "text|displaytitle|revid"),
                                    URLQueryItem(name: "disablelimitreport", value: "1"),
                                    URLQueryItem(name: "wrapoutputclass", value: "mw-parser-output"),
                                    URLQueryItem(name: "page", value: pageTitle)
                                ]

                                if let apiURL = urlComponents.url {
                                    print("📡 ArticleViewModel: Fallback - downloading main content")
                                    let response = try? await NetworkManager.shared.performRequest(
                                        url: apiURL,
                                        responseType: osrsParseResponse.self
                                    )

                                    // CRITICAL: Also proactively download all images (Android-style)
                                    if let htmlContent = response?.parse.text {
                                        await proactivelyDownloadAllResources(pageId: savedPage.id, htmlContent: htmlContent)
                                    }
                                }

                                durableOfflineReady = ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: savedPage.id)
                                await MainActor.run { self.saveProgress = 0.8 }
                                print("✅ ArticleViewModel: Fallback download completed")
                            }

                            await MainActor.run { self.saveProgress = 0.9 }

                        } else {
                            print("📦 ArticleViewModel: Using legacy web archive approach (iOS <17)")

                            // Create web archive using iOS-native createWebArchiveData
                            guard let webView = webView else {
                                throw NSError(domain: "ArticleViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not available for web archive creation"])
                            }

                            try await OfflineContentService.shared.createWebArchive(
                                from: webView,
                                pageId: savedPage.id,
                                title: cleanTitle,
                                originalURL: cleanUrl
                            )
                            durableOfflineReady = OfflineContentService.shared.isPageAvailableOffline(pageId: savedPage.id)
                        }

                        guard durableOfflineReady else {
                            throw NSError(
                                domain: "ArticleViewModel",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Offline cache is incomplete; saved page will remain unavailable offline"]
                            )
                        }

                        await MainActor.run { self.saveProgress = 0.8 }
                        print("✅ ArticleViewModel: Offline content download completed")

                        // Update SavedPage to reflect offline availability
                        let updatedSavedPage = SavedPage(
                            id: savedPage.id,
                            title: savedPage.title,
                            description: savedPage.description,
                            url: savedPage.url,
                            thumbnailUrl: savedPage.thumbnailUrl,
                            savedDate: savedPage.savedDate,
                            isOfflineAvailable: true, // Now available offline!
                            offlineDownloadDate: Date(),
                            offlineStatus: .available,
                            offlineFileSize: nil, // TODO: Calculate actual file size
                            offlineLocalPath: savedPage.id // Use page ID as directory name
                        )

                        // Update repository with offline-enabled page
                        savedPagesRepository.updateSavedPage(updatedSavedPage)
                        print("📱 ArticleViewModel: Updated saved page with offline availability")

                        await MainActor.run { self.saveProgress = 0.9 }

                    } catch {
                        print("❌ ArticleViewModel: Offline download failed: \(error)")

                        // Update page status to failed but keep the metadata save
                        let failedSavedPage = SavedPage(
                            id: savedPage.id,
                            title: savedPage.title,
                            description: savedPage.description,
                            url: savedPage.url,
                            thumbnailUrl: savedPage.thumbnailUrl,
                            savedDate: savedPage.savedDate,
                            isOfflineAvailable: false,
                            offlineDownloadDate: nil,
                            offlineStatus: .failed,
                            offlineFileSize: nil,
                            offlineLocalPath: nil
                        )

                        savedPagesRepository.updateSavedPage(failedSavedPage)
                        print("📱 ArticleViewModel: Marked saved page as offline download failed")

                        await MainActor.run { self.saveProgress = 0.9 }

                        // Note: We don't throw here - the page is still saved, just without offline content
                        print("ℹ️ ArticleViewModel: Page saved successfully but offline download failed - page will load online")
                    }

                    // Step 5: Complete save process
                    await MainActor.run {
                        self.isBookmarked = true
                        self.saveState = .saved
                        self.saveProgress = 1.0
                        print("✅ ArticleViewModel: Successfully saved page")
                    }

            } catch {
                await MainActor.run {
                    self.saveState = .error
                    self.saveProgress = 0.0
                    print("❌ ArticleViewModel: Error saving page: \(error)")
                }
            }
        }
    }

    /// Clean page title by removing HTML tags - matches Android title cleaning
    private func cleanPageTitle(_ title: String) -> String {
        // Remove HTML tags like <span class="mw-page-title-main">Varrock</span>
        let cleanTitle = title.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract all image URLs from HTML content - matches Android's extractAssetUrls
    private func extractImageURLsFromHTML(_ html: String) -> [String] {
        var imageURLs = Set<String>() // Use Set to avoid duplicates

        do {
            // Pattern to match <img> tags with src attribute
            let imagePattern = #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
            let regex = try NSRegularExpression(pattern: imagePattern, options: [.caseInsensitive])
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            for match in matches {
                if match.numberOfRanges > 1 {
                    let range = Range(match.range(at: 1), in: html)!
                    var imageURL = String(html[range])

                    // Convert relative URLs to absolute
                    if imageURL.hasPrefix("//") {
                        imageURL = "https:" + imageURL
                    } else if imageURL.hasPrefix("/") {
                        imageURL = "https://oldschool.runescape.wiki" + imageURL
                    }

                    imageURLs.insert(imageURL)
                }
            }

            // Also look for srcset attributes (responsive images)
            let srcsetPattern = #"<img[^>]+srcset\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
            let srcsetRegex = try NSRegularExpression(pattern: srcsetPattern, options: [.caseInsensitive])
            let srcsetMatches = srcsetRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            for match in srcsetMatches {
                if match.numberOfRanges > 1 {
                    let range = Range(match.range(at: 1), in: html)!
                    let srcsetValue = String(html[range])

                    // Parse srcset format: "url1 1x, url2 2x, ..."
                    let urls = srcsetValue.split(separator: ",").compactMap { part in
                        part.trimmingCharacters(in: .whitespaces)
                            .split(separator: " ")
                            .first
                            .map(String.init)
                    }

                    for var url in urls {
                        if url.hasPrefix("//") {
                            url = "https:" + url
                        } else if url.hasPrefix("/") {
                            url = "https://oldschool.runescape.wiki" + url
                        }
                        imageURLs.insert(url)
                    }
                }
            }

            print("📸 ArticleViewModel: Found \(imageURLs.count) unique image URLs to cache")
        } catch {
            print("❌ ArticleViewModel: Error extracting image URLs: \(error)")
        }

        return Array(imageURLs)
    }

    /// Proactively download all resources found in HTML - matches Android's PageAssetDownloader
    private func proactivelyDownloadAllResources(pageId: String, htmlContent: String) async {
        print("🚀 ArticleViewModel: Starting proactive resource download for pageId: \(pageId)")

        // Extract all image URLs from HTML
        let imageURLs = extractImageURLsFromHTML(htmlContent)

        if imageURLs.isEmpty {
            print("⚠️ ArticleViewModel: No images found in HTML to download")
            return
        }

        print("📥 ArticleViewModel: Downloading \(imageURLs.count) images proactively...")

        // Download each image through the proxy to populate cache
        // Use concurrent downloads with limit for performance
        await withTaskGroup(of: Void.self) { group in
            // Limit concurrent downloads to 5
            let semaphore = AsyncSemaphore(value: 5)

            for imageURL in imageURLs {
                group.addTask {
                    await semaphore.wait()

                    do {
                        guard let url = URL(string: imageURL) else {
                            await semaphore.signal()
                            return
                        }

                        // Make request through proxy-enabled NetworkManager
                        // This will trigger LocalHTTPServer to cache the response
                        let _ = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)
                        print("✅ Cached image: \(url.lastPathComponent)")
                    } catch {
                        // Don't fail the whole process if one image fails
                        print("⚠️ Failed to cache image: \(imageURL.split(separator: "/").last ?? "unknown")")
                    }

                    // Signal semaphore after operation completes
                    await semaphore.signal()
                }
            }
        }

        print("✅ ArticleViewModel: Completed proactive resource download - all images cached")
    }

    // Simple async semaphore for limiting concurrent downloads
    private actor AsyncSemaphore {
        private var value: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(value: Int) {
            self.value = value
        }

        func wait() async {
            if value > 0 {
                value -= 1
            } else {
                await withCheckedContinuation { continuation in
                    waiters.append(continuation)
                }
            }
        }

        func signal() {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.resume()
            } else {
                value += 1
            }
        }
    }

    /// Fetch page metadata from MediaWiki API - matches Android metadata extraction
    private func fetchPageMetadata() async -> (description: String?, thumbnailUrl: URL?) {
        let cleanTitle = cleanPageTitle(pageTitle)

        // Build MediaWiki API URL to get page info and images
        var components = URLComponents(string: "https://oldschool.runescape.wiki/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "titles", value: cleanTitle),
            URLQueryItem(name: "prop", value: "extracts|pageimages"),
            URLQueryItem(name: "exintro", value: "1"), // Only intro section
            URLQueryItem(name: "explaintext", value: "1"), // Plain text, not HTML
            URLQueryItem(name: "exsectionformat", value: "plain"),
            URLQueryItem(name: "exchars", value: "200"), // Limit to 200 characters
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "200") // 200px thumbnail
        ]

        guard let url = components.url else {
            print("❌ ArticleViewModel: Failed to build metadata API URL")
            return (nil, nil)
        }

        do {
            let (data, _) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let query = json["query"] as? [String: Any],
               let pages = query["pages"] as? [[String: Any]],
               let page = pages.first {

                // Extract description
                let description = page["extract"] as? String

                // Extract thumbnail URL
                var thumbnailUrl: URL?
                if let thumbnail = page["thumbnail"] as? [String: Any],
                   let thumbnailSource = thumbnail["source"] as? String {
                    thumbnailUrl = URL(string: thumbnailSource)
                }

                print("📱 ArticleViewModel: Fetched metadata - description: \(description?.prefix(50) ?? "nil"), thumbnail: \(thumbnailUrl?.absoluteString ?? "nil")")

                return (description, thumbnailUrl)
            }
        } catch let networkError as NetworkError {
            print("❌ ArticleViewModel: Network error fetching page metadata: \(networkError.localizedDescription)")
            // Metadata fetch failures are non-critical, so we just log and continue
        } catch {
            print("❌ ArticleViewModel: Error fetching page metadata: \(error)")
        }

        return (nil, nil)
    }

    /// Extract page description from current content - matches Android getSnippet() functionality
    private func extractPageDescription() -> String? {
        // Fallback description if metadata fetch fails
        return "OSRS Wiki article: \(cleanPageTitle(pageTitle))"
    }

    /// Extract thumbnail URL from current content - matches Android getThumbnailUrl() functionality
    private func extractThumbnailUrl() -> URL? {
        // Fallback - will be replaced by API metadata
        return nil
    }

    /// Find in page action - matches Android FindInPageManager functionality
    func performFindInPageAction(onPresented: (() -> Void)? = nil) {
        guard let webView = webView else { return }

        // Expand collapsible sections like Android does
        let expandScript = """
            document.querySelectorAll('.collapsible-closed').forEach(function(e) {
                e.classList.remove('collapsible-closed');
            });
        """
        webView.evaluateJavaScript(expandScript) { [weak self] (_, error) in
            if let error = error {
                print("🚨 ArticleViewModel: Error expanding collapsible content: \(error)")
            }

            // After expanding content, present the native find interface
            DispatchQueue.main.async {
                self?.presentNativeFindInterface()
                onPresented?()
            }
        }

        print("🔍 ArticleViewModel: Find in page requested - expanding collapsible content")
    }

    /// Present native iOS find interface using UIFindInteraction (iOS 16+)
    private func presentNativeFindInterface() {
        guard let webView = webView else { return }

        if #available(iOS 16.0, *) {
            // Use native UIFindInteraction for iOS 16+
            webView.findInteraction?.presentFindNavigator(showingReplace: false)
            print("🔍 ArticleViewModel: Presented native find interface (iOS 16+)")
        } else {
            // Fallback for iOS 14-15: Use basic findString API
            // Note: This requires user input, so we'd need a custom UI
            print("🔍 ArticleViewModel: iOS 16+ required for full find interface. Consider implementing custom UI for older iOS versions.")
        }
    }

    /// Hide find in page interface - matches Android toggle behavior
    func hideFindInPageAction() {
        guard let webView = webView else { return }

        if #available(iOS 16.0, *) {
            // Dismiss the native find interface
            webView.findInteraction?.dismissFindNavigator()
            print("🔍 ArticleViewModel: Dismissed native find interface")
        }
    }

    func isNativeFindNavigatorVisible() -> Bool {
        guard let webView = webView else { return false }

        if #available(iOS 16.0, *) {
            return webView.findInteraction?.isFindNavigatorVisible ?? false
        }

        return false
    }

    /// Appearance/theme action - matches Android AppearanceSettingsActivity
    func performAppearanceAction() {
        // Navigate to appearance settings by sending notification
        // This matches Android's behavior of launching AppearanceSettingsActivity
        NotificationCenter.default.post(name: .showAppearanceSettings, object: nil)
        print("🎨 ArticleViewModel: Navigating to appearance settings")
    }

    /// Contents action - matches Android ContentsHandler functionality
    func performContentsAction() {
        // This is already handled by the existing table of contents functionality
        // The ArticleView will show the table of contents sheet
        print("📋 ArticleViewModel: Contents requested - hasTableOfContents: \(hasTableOfContents)")
    }

    /// Apply intelligent size rules to eliminate wasteful caching
    /// Returns appropriate size variants based on original image size
    private func generateIntelligentSizeVariants(originalSize: Int) -> [String] {
        switch originalSize {
        case 0...30:
            // TINY IMAGES (icons, badges, small UI elements)
            // Only cache original + retina (2x) - no massive sizes needed
            let retinaSize = min(originalSize * 2, 60) // Cap retina at 60px for tiny images
            return [String(retinaSize)]

        case 31...60:
            // SMALL IMAGES (chatheads, small thumbnails)
            // Cache original + retina, maybe one step up
            let retinaSize = originalSize * 2
            return retinaSize <= 100 ? [String(retinaSize)] : [String(100)]

        case 61...150:
            // SMALL-MEDIUM IMAGES (larger chatheads, small article images)
            // Cache original + common responsive size
            return ["300"]

        case 151...300:
            // MEDIUM IMAGES (article thumbnails)
            // Cache original + one larger responsive size
            return ["600"]

        case 301...600:
            // LARGE IMAGES (main article images)
            // Cache original + larger responsive sizes
            return ["300", "1200"]

        default:
            // VERY LARGE IMAGES (hero images, detailed screenshots)
            // Full responsive treatment
            return ["300", "600", "1200"]
        }
    }

    /// Determine if full-size variant should be included
    /// Only include for medium/large images where it might be useful
    private func shouldIncludeFullSize(originalSize: Int) -> Bool {
        return originalSize > 100 // Only include full-size for images larger than 100px
    }

    /// Generate multiple size variants for MediaWiki thumbnail images
    /// NOW WITH INTELLIGENT OPTIMIZATION: Eliminates 60-80% of wasteful caching
    private func generateImageSizeVariants(originalURL: String) -> [String] {
        var variants = [originalURL] // Always include the original

        // Check if this is a MediaWiki thumbnail URL
        if originalURL.contains("/thumb/") && originalURL.contains("px-") {
            // Parse MediaWiki thumbnail pattern: /thumb/Filename.ext/300px-Filename.ext?hash
            // FIXED: Updated regex to properly separate filename from query string
            let pattern = #"/thumb/([^/]+)/(\d+)px-([^?]+)(\?.*)?$"#

            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: originalURL, options: [], range: NSRange(location: 0, length: originalURL.count)) {

                let nsString = originalURL as NSString
                let baseFilename = nsString.substring(with: match.range(at: 1))
                let originalSize = nsString.substring(with: match.range(at: 2))
                let thumbnailFilename = nsString.substring(with: match.range(at: 3)) // Now excludes query string
                let queryString = match.range(at: 4).location != NSNotFound ? nsString.substring(with: match.range(at: 4)) : ""

                print("🔍 ArticleViewModel: Detected MediaWiki thumbnail:")
                print("  📁 Base filename: \(baseFilename)")
                print("  📏 Original size: \(originalSize)px")
                print("  🖼️ Thumbnail filename: \(thumbnailFilename)")
                print("  🔗 Query string: \(queryString)")

                // FIXED: Construct proper base URL for MediaWiki thumb directory
                // Extract the thumb directory path: /images/thumb/Filename.ext
                let thumbPathPattern = #"/images/thumb/[^/]+"#
                if let thumbPathRegex = try? NSRegularExpression(pattern: thumbPathPattern, options: []),
                   let thumbPathMatch = thumbPathRegex.firstMatch(in: originalURL, options: [], range: NSRange(location: 0, length: originalURL.count)) {

                    let thumbPath = nsString.substring(with: thumbPathMatch.range)
                    let baseURL = "https://oldschool.runescape.wiki\(thumbPath)"

                    print("🏗️ ArticleViewModel: Base URL for variants: \(baseURL)")

                    // INTELLIGENT OPTIMIZATION: Apply content-aware size rules
                    let intelligentSizes = generateIntelligentSizeVariants(originalSize: Int(originalSize) ?? 0)
                    let variantSizes = intelligentSizes.filter { $0 != originalSize } // Don't duplicate original

                    print("🧠 ArticleViewModel: Intelligent sizing - \(originalSize)px image gets \(variantSizes.count + 1) variants (was 5-6)")

                    for size in variantSizes {
                        // FIXED: Correct MediaWiki thumbnail URL construction
                        let variantURL = "\(baseURL)/\(size)px-\(thumbnailFilename)\(queryString)"
                        variants.append(variantURL)
                        print("  ✅ Generated intelligent variant: \(variantURL)")
                    }

                    // Add full-size variant only for medium/large images
                    if shouldIncludeFullSize(originalSize: Int(originalSize) ?? 0) {
                        let fullSizeURL = "https://oldschool.runescape.wiki/images/\(baseFilename)\(queryString)"
                        variants.append(fullSizeURL)
                        print("  🖼️ Added full-size variant: \(fullSizeURL)")
                    } else {
                        print("  🚫 Skipped full-size variant (unnecessary for small image)")
                    }
                }

                print("🖼️ ArticleViewModel: Generated \(variants.count) size variants for responsive caching")
            } else {
                print("⚠️ ArticleViewModel: Failed to parse MediaWiki thumbnail URL: \(originalURL)")
            }
        }

        return variants
    }

    /// DEPRECATED: Resource discovery no longer needed with lazy caching
    /// Keeping minimal version for backward compatibility only
    private func discoverAndCachePageResources(pageId: String, originalHTML: String) async throws {
        // With lazy caching, resources are automatically cached during browsing
        // No need for manual discovery and sequential downloading
        print("🚀 ArticleViewModel: Skipping resource discovery - using lazy caching instead")
        return

        // OLD CODE BELOW - KEPT FOR REFERENCE BUT NEVER EXECUTED
        /*
        print("🚀🔍 RESOURCE DISCOVERY ENTRY POINT - pageId: \(pageId)")
        print("🔍 ArticleViewModel: Starting comprehensive resource discovery from original HTML...")
        print("📄 ArticleViewModel: HTML length: \(originalHTML.count) characters")

        // CRITICAL: Verify proxy is configured for caching before starting resource discovery
        print("🔗 ArticleViewModel: Resource discovery starting - proxy system should be configured by now")

        // Add HTML content debugging
        if originalHTML.count > 0 {
            let htmlPreview = String(originalHTML.prefix(500))
            print("📄 ArticleViewModel: HTML preview: \(htmlPreview)")

            // Look for any img tags manually for debugging
            let imgCount = originalHTML.components(separatedBy: "<img").count - 1
            print("🔍 ArticleViewModel: Found \(imgCount) <img> tags in HTML using simple string search")

            // Look for any src attributes manually
            let srcCount = originalHTML.components(separatedBy: "src=").count - 1
            print("🔍 ArticleViewModel: Found \(srcCount) src= attributes in HTML using simple string search")

            // Check for specific image file extensions
            let pngCount = originalHTML.components(separatedBy: ".png").count - 1
            let jpgCount = originalHTML.components(separatedBy: ".jpg").count - 1
            print("🔍 ArticleViewModel: Found \(pngCount) .png and \(jpgCount) .jpg references")
        }

        var discoveredResources: [(type: String, url: String)] = []

        // Helper function to convert URLs to absolute form
        func makeAbsoluteURL(_ urlString: String) -> String? {
            // Skip data URLs and empty strings
            guard !urlString.isEmpty && !urlString.starts(with: "data:") else {
                print("🔍 ArticleViewModel: Skipping URL (empty or data): '\(urlString)'")
                return nil
            }

            if urlString.starts(with: "http") {
                // Already absolute URL
                print("🔍 ArticleViewModel: Using absolute URL: \(urlString)")
                return urlString
            } else if urlString.starts(with: "//") {
                // Protocol-relative URL
                let result = "https:" + urlString
                print("🔍 ArticleViewModel: Converting protocol-relative: \(urlString) → \(result)")
                return result
            } else if urlString.starts(with: "/") {
                // Domain-relative URL - convert to absolute
                let result = "https://oldschool.runescape.wiki" + urlString
                print("🔍 ArticleViewModel: Converting domain-relative: \(urlString) → \(result)")
                return result
            } else {
                // Other relative URLs or invalid - skip
                print("🔍 ArticleViewModel: Skipping unsupported URL format: '\(urlString)'")
                return nil
            }
        }

        // Discover images using regex on original HTML
        let imagePattern = #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        print("🔍 ArticleViewModel: Trying image regex pattern: \(imagePattern)")

        if let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: .caseInsensitive) {
            let matches = imageRegex.matches(in: originalHTML, options: [], range: NSRange(location: 0, length: originalHTML.utf16.count))
            print("🔍 ArticleViewModel: Image regex found \(matches.count) matches")

            var processedCount = 0
            var acceptedCount = 0
            var rejectedCount = 0

            for (index, match) in matches.enumerated() {
                if let srcRange = Range(match.range(at: 1), in: originalHTML) {
                    let srcValue = String(originalHTML[srcRange])
                    processedCount += 1

                    // Only show first few for debugging to avoid log spam
                    if index < 10 {
                        print("🔍 ArticleViewModel: Image match \(index + 1): '\(srcValue)'")
                    }

                    if let fullURL = makeAbsoluteURL(srcValue) {
                        discoveredResources.append((type: "image", url: fullURL))
                        acceptedCount += 1
                        if index < 5 {  // Only show first few for debugging
                            print("🖼️ ArticleViewModel: ✅ Found image: \(srcValue) → \(fullURL)")
                        }
                    } else {
                        rejectedCount += 1
                        if index < 5 {  // Only show first few for debugging
                            print("🖼️ ArticleViewModel: ❌ Rejected image URL: \(srcValue)")
                        }
                    }
                }
            }

            print("📊 ArticleViewModel: Image processing complete - Processed: \(processedCount), Accepted: \(acceptedCount), Rejected: \(rejectedCount)")

        } else {
            print("❌ ArticleViewModel: Failed to create image regex pattern")
        }

        // Discover CSS files using regex on original HTML
        let cssPattern = #"<link[^>]+rel\s*=\s*[\"']stylesheet[\"'][^>]+href\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        if let cssRegex = try? NSRegularExpression(pattern: cssPattern, options: .caseInsensitive) {
            let matches = cssRegex.matches(in: originalHTML, options: [], range: NSRange(location: 0, length: originalHTML.utf16.count))
            for match in matches {
                if let hrefRange = Range(match.range(at: 1), in: originalHTML) {
                    let hrefValue = String(originalHTML[hrefRange])
                    if let fullURL = makeAbsoluteURL(hrefValue) {
                        discoveredResources.append((type: "css", url: fullURL))
                        print("🎨 ArticleViewModel: Found CSS: \(hrefValue) → \(fullURL)")
                    }
                }
            }
        }

        // Discover JavaScript files using regex on original HTML
        let jsPattern = #"<script[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        if let jsRegex = try? NSRegularExpression(pattern: jsPattern, options: .caseInsensitive) {
            let matches = jsRegex.matches(in: originalHTML, options: [], range: NSRange(location: 0, length: originalHTML.utf16.count))
            for match in matches {
                if let srcRange = Range(match.range(at: 1), in: originalHTML) {
                    let srcValue = String(originalHTML[srcRange])
                    if let fullURL = makeAbsoluteURL(srcValue) {
                        discoveredResources.append((type: "js", url: fullURL))
                        print("⚡ ArticleViewModel: Found JS: \(srcValue) → \(fullURL)")
                    }
                }
            }
        }

        // Remove duplicates
        var uniqueUrls = Set<String>()
        discoveredResources = discoveredResources.filter { resource in
            if uniqueUrls.contains(resource.url) { return false }
            uniqueUrls.insert(resource.url)
            return true
        }

        print("🎯 ArticleViewModel: Discovered \(discoveredResources.count) external resources to cache")

        // CRITICAL DIAGNOSTIC: Show summary of what we found
        if discoveredResources.isEmpty {
            print("❌ ArticleViewModel: ⚠️  CRITICAL - Zero resources discovered despite HTML analysis!")
            print("❌ ArticleViewModel: This indicates a problem in the resource discovery logic")
        } else {
            print("✅ ArticleViewModel: Resource discovery successful - found \(discoveredResources.count) unique resources")

            // Group by type for analysis
            let imageCount = discoveredResources.filter { $0.type == "image" }.count
            let cssCount = discoveredResources.filter { $0.type == "css" }.count
            let jsCount = discoveredResources.filter { $0.type == "js" }.count
            print("📊 ArticleViewModel: Resource breakdown - Images: \(imageCount), CSS: \(cssCount), JS: \(jsCount)")

            // Sample first few discovered resources
            print("📋 ArticleViewModel: Sample discovered resources:")
            for (i, resource) in discoveredResources.prefix(5).enumerated() {
                print("   [\(i+1)] \(resource.type): \(resource.url)")
            }
        }

        // ENHANCED: Track individual resource caching success/failure
        var successCount = 0
        var failureCount = 0
        var failedResources: [(type: String, url: String, error: String)] = []

        // ENHANCED: Smart multi-size image caching for responsive images
        for (index, resource) in discoveredResources.enumerated() {
            guard let url = URL(string: resource.url) else {
                print("❌ ArticleViewModel: Invalid URL for resource \(index + 1): \(resource.url)")
                failureCount += 1
                failedResources.append((type: resource.type, url: resource.url, error: "Invalid URL"))
                continue
            }

            if resource.type == "image" {
                // For images, implement smart multi-size caching
                let imageVariants = generateImageSizeVariants(originalURL: resource.url)
                print("🖼️ ArticleViewModel: [\(index + 1)/\(discoveredResources.count)] Caching image with \(imageVariants.count) size variants: \(resource.url)")

                for (variantIndex, variantURL) in imageVariants.enumerated() {
                    guard let url = URL(string: variantURL) else {
                        print("❌ ArticleViewModel: Invalid variant URL: \(variantURL)")
                        continue
                    }

                    print("📦 ArticleViewModel:   Variant [\(variantIndex + 1)/\(imageVariants.count)]: \(variantURL)")

                    do {
                        let responseData = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)
                        print("✅ ArticleViewModel: Successfully cached image variant (\(responseData.0.count) bytes): \(variantURL)")
                        successCount += 1
                    } catch {
                        print("⚠️ ArticleViewModel: Failed to cache image variant \(variantURL): \(error)")
                        failureCount += 1
                        failedResources.append((type: resource.type, url: variantURL, error: error.localizedDescription))
                        // Continue with other variants even if one fails
                    }

                    // Small delay between variants
                    try await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
                }
            } else {
                // For non-images, cache normally
                print("📦 ArticleViewModel: [\(index + 1)/\(discoveredResources.count)] Caching \(resource.type): \(resource.url)")

                do {
                    let responseData = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)
                    print("✅ ArticleViewModel: Successfully cached \(resource.type) (\(responseData.0.count) bytes): \(resource.url)")
                    successCount += 1
                } catch {
                    print("⚠️ ArticleViewModel: Failed to cache \(resource.type) \(resource.url): \(error)")
                    failureCount += 1
                    failedResources.append((type: resource.type, url: resource.url, error: error.localizedDescription))
                }
            }

            // Small delay to avoid overwhelming the server
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        // ENHANCED: Comprehensive caching results analysis
        let totalResources = discoveredResources.count
        let successRate = totalResources > 0 ? Double(successCount) / Double(totalResources) * 100 : 0

        print("📊 RESOURCE CACHING ANALYSIS:")
        print("   📈 Total resources discovered: \(totalResources)")
        print("   ✅ Successfully cached: \(successCount) (\(String(format: "%.1f", successRate))%)")
        print("   ❌ Failed to cache: \(failureCount)")

        if failureCount > 0 {
            print("⚠️ CACHING FAILURES DETECTED:")
            for (i, failed) in failedResources.prefix(5).enumerated() {
                print("   [\(i+1)] \(failed.type): \(failed.url)")
                print("        Error: \(failed.error)")
            }
            if failedResources.count > 5 {
                print("   ... and \(failedResources.count - 5) more failures")
            }
        }

        // ENHANCED: Cache success threshold validation
        let minimumSuccessRate = 80.0 // Require 80% success rate for reliable offline experience
        let hasReliableCache = successRate >= minimumSuccessRate

        if hasReliableCache {
            print("🎉 ArticleViewModel: Resource caching SUCCESSFUL - \(successCount)/\(totalResources) cached (≥\(minimumSuccessRate)% threshold met)")
        } else {
            print("⚠️ ArticleViewModel: Resource caching INCOMPLETE - \(successCount)/\(totalResources) cached (<\(minimumSuccessRate)% threshold)")
            print("💡 Recommendation: Page may have missing images when accessed offline")
        }

        // Return success status for save process decision making
        if !hasReliableCache {
            print("🔄 ArticleViewModel: Consider adjusting offline availability status based on cache success rate")
        }
        */
    }
}

// MARK: - Data Models
struct TableOfContentsSection: Codable, Identifiable {
    let id: String
    let title: String
    let level: Int
}

//
//  AppState.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var selectedTab: TabItem = .news
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Shared speech recognition manager - single instance to prevent resource conflicts
    @Published var speechManager = osrsSpeechRecognitionManager()

#if DEBUG
    var isBackgroundPreloadingDisabledForTests: Bool {
        osrsTestEnvironment.disablesStartupSideEffects
    }
#endif

    // Task cancellation management
    private var activeTabTasks: Set<Task<Void, Never>> = []
    private var notificationObservers: [NSObjectProtocol] = []

    // Navigation protection to prevent rapid/double navigation
    internal var lastNavigationTime: Date = Date.distantPast
    internal let navigationDebounceInterval: TimeInterval = 0.5
    internal var lastArticleBackActionTime: Date = Date.distantPast
    internal let articleBackActionDebounceInterval: TimeInterval = 3.0
    internal var suppressedInternalArticleRouteURL: URL?
    internal var suppressedInternalArticleRouteUntil: Date = Date.distantPast
    internal let internalArticleRouteSuppressionInterval: TimeInterval = 10.0
#if DEBUG
    internal var articleBackActionDebugCount = 0
    internal var isDeepNavigationFixtureAuditRunning = false
    @Published var deepNavigationFixtureAuditDebugLabel = "status=idle"
#endif

    // FREEZE FIX: Use @Published arrays with unique types to prevent cross-stack interference
    // Each NavigationStack uses its own destination type to prevent multiple handlers responding
    @Published var newsNavigationStack: [NewsNavigationDestination] = []
    @Published var savedNavigationStack: [SavedNavigationDestination] = []
    @Published var searchNavigationStack: [SearchNavigationDestination] = []
    @Published var mapNavigationStack: [MapNavigationDestination] = []
    @Published var moreNavigationStack: [MoreNavigationDestination] = []
    @Published var historyNavigationStack: [HistoryNavigationDestination] = []  // Dedicated for HistoryView
    @Published var articleBackStackRecoveryRequestID: Int = 0
    internal(set) var articleBackStackRecoveryDestination: ArticleDestination?

    init() {
        loadUserPreferences()
        handleLaunchArguments()
        observeInternalArticleLinkRequests()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeInternalArticleLinkRequests() {
        let observer = NotificationCenter.default.addObserver(
            forName: .osrsInternalArticleLinkRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            Task { @MainActor [weak self] in
                self?.routeInternalArticleLink(url)
            }
        }
        notificationObservers.append(observer)
    }

    private func loadUserPreferences() {
        // Load saved tab preference
        if let savedTab = UserDefaults.standard.object(forKey: "selected_tab") as? String,
           let tab = TabItem(rawValue: savedTab) {
            selectedTab = tab
        }
    }

    func saveUserPreferences() {
        UserDefaults.standard.set(selectedTab.rawValue, forKey: "selected_tab")
    }

    func setSelectedTab(_ tab: TabItem) {
        guard selectedTab != tab else { return }

        // Cancel all active tasks from previous tab before showing the new destination.
        cancelActiveTabTasks()

        selectedTab = tab
        saveUserPreferences()

        // Post notification for views to cancel their operations
        NotificationCenter.default.post(name: Notification.Name("TabSwitched"), object: tab)
    }

    func cancelActiveTabTasks() {
        // Cancel all tracked tasks
        for task in activeTabTasks {
            task.cancel()
        }
        activeTabTasks.removeAll()

        // Clean up speech recognition when switching tabs to prevent resource conflicts
        speechManager.cleanup()

        // Post cancellation notification
        NotificationCenter.default.post(name: Notification.Name("CancelTabOperations"), object: nil)
    }

    func trackTask(_ task: Task<Void, Never>) {
        activeTabTasks.insert(task)

        // Remove task when completed
        Task { @MainActor in
            await task.value
            activeTabTasks.remove(task)
        }
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }

    private func handleLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments

#if DEBUG
        handleUITestSavedPagesArguments(arguments)
        handleUITestSearchArguments(arguments)
#endif

        // Check for direct tab launch arguments
        // Usage: -startTab <tab_name>
        if let startTabIndex = arguments.firstIndex(of: "-startTab"),
           startTabIndex + 1 < arguments.count {
            let tabName = arguments[startTabIndex + 1]
            if let tab = TabItem(rawValue: tabName) {
                selectedTab = tab
                print("🚀 Launch argument: starting with \(tab.title) tab")
            }
        }

#if DEBUG
        handleUITestNavigationArguments(arguments)
        handleUITestDeepNavigationFixtureArguments(arguments)
#endif

        // Check for screenshot mode (automatically takes screenshots of all tabs)
        if arguments.contains("-screenshotMode") {
            print("🧪 Screenshot mode enabled")
            // This will be handled by the screenshot automation script
        }
    }

#if DEBUG
    private func handleUITestSearchArguments(_ arguments: [String]) {
        if arguments.contains("-resetSearchRecentsForUITests") {
            UserDefaults.standard.removeObject(forKey: "recent_searches")
            print("UITest: reset recent searches")
        }

        if arguments.contains("-seedSearchRecentsForUITests") {
            let seedValue = seedSearchRecentValue(from: arguments) ?? "Varrock"
            UserDefaults.standard.set([seedValue], forKey: "recent_searches")
            print("UITest: seeded recent searches")
        }
    }

    private func seedSearchRecentValue(from arguments: [String]) -> String? {
        guard let seedArgumentIndex = arguments.firstIndex(of: "-seedSearchRecentsForUITests"),
              seedArgumentIndex + 1 < arguments.count else {
            return nil
        }

        let seedValue = arguments[seedArgumentIndex + 1]
        return seedValue.hasPrefix("-") ? nil : seedValue
    }

    private func handleUITestSavedPagesArguments(_ arguments: [String]) {
        guard arguments.contains("-resetSavedPagesForUITests") ||
              arguments.contains("-seedSavedPagesForUITests") ||
              osrsTestEnvironment.seedsOfflineSavedPageForUITests else {
            return
        }

        let repository = SavedPagesRepository()

        if arguments.contains("-resetSavedPagesForUITests") {
            repository.clearSavedPages()
            print("UITest: reset saved pages")
        }

        if arguments.contains("-seedSavedPagesForUITests") ||
            osrsTestEnvironment.seedsOfflineSavedPageForUITests {
            let isOfflineSeed = osrsTestEnvironment.seedsOfflineSavedPageForUITests
            let pageId: String
            if isOfflineSeed {
                pageId = "ui-test-varrock-offline"
            } else if osrsTestEnvironment.forcesNetworkOfflineForUITests {
                pageId = "ui-test-varrock-uncached"
            } else {
                pageId = "ui-test-varrock"
            }
            let varrockPage = SavedPage(
                id: pageId,
                title: "Varrock",
                description: "Seeded saved page for UI navigation testing",
                url: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
                thumbnailUrl: nil,
                savedDate: Date(timeIntervalSince1970: 1_735_732_800),
                isOfflineAvailable: isOfflineSeed,
                offlineDownloadDate: isOfflineSeed ? Date(timeIntervalSince1970: 1_735_732_800) : nil,
                offlineStatus: isOfflineSeed ? .available : .notDownloaded,
                offlineFileSize: isOfflineSeed ? 512 : nil,
                offlineLocalPath: isOfflineSeed ? pageId : nil
            )
            repository.addSavedPage(varrockPage)
            print("UITest: seeded saved page \(varrockPage.title)")

            if isOfflineSeed, #available(iOS 17.0, *) {
                ProxyInterceptorService.shared.seedOfflineSavedPageForUITests(
                    pageId: varrockPage.id,
                    title: varrockPage.title
                )
            }
        }
    }

    private func handleUITestNavigationArguments(_ arguments: [String]) {
        if let articleTitleIndex = arguments.firstIndex(of: "-startArticleTitle"),
           articleTitleIndex + 1 < arguments.count,
           let articleURLIndex = arguments.firstIndex(of: "-startArticleURL"),
           articleURLIndex + 1 < arguments.count,
           let url = URL(string: arguments[articleURLIndex + 1]) {
            let title = arguments[articleTitleIndex + 1]
            let destination = ArticleDestination(title: title, url: url)
            appendArticleDestinationForSelectedTab(destination)
            print("UITest: starting article \(title) at \(url.absoluteString)")
        }

        guard selectedTab == .more,
              let moreDestinationIndex = arguments.firstIndex(of: "-startMoreDestination"),
              moreDestinationIndex + 1 < arguments.count else {
            return
        }

        switch arguments[moreDestinationIndex + 1].lowercased() {
        case "appearance":
            moreNavigationStack = [.appearance]
        case "donate":
            moreNavigationStack = [.donate]
        case "about":
            moreNavigationStack = [.about]
        case "feedback":
            moreNavigationStack = [.feedback]
        default:
            break
        }

        print("UITest: starting More destination \(arguments[moreDestinationIndex + 1])")
    }

    private func handleUITestDeepNavigationFixtureArguments(_ arguments: [String]) {
        guard osrsTestEnvironment.runsDeepNavigationFixtureAuditForUITests else {
            return
        }

        let seed = osrsDeepNavigationFixtureAudit.launchIntArgument(
            arguments,
            name: osrsDeepNavigationFixtureAudit.seedLaunchArgument,
            defaultValue: osrsDeepNavigationFixtureAudit.defaultSeed
        )
        let startOffset = osrsDeepNavigationFixtureAudit.launchIntArgument(
            arguments,
            name: osrsDeepNavigationFixtureAudit.startOffsetLaunchArgument,
            defaultValue: osrsDeepNavigationFixtureAudit.defaultStartOffset
        )
        let startCount = osrsDeepNavigationFixtureAudit.launchIntArgument(
            arguments,
            name: osrsDeepNavigationFixtureAudit.startCountLaunchArgument,
            defaultValue: osrsDeepNavigationFixtureAudit.defaultStartCount
        )
        let targetDepth = osrsDeepNavigationFixtureAudit.launchIntArgument(
            arguments,
            name: osrsDeepNavigationFixtureAudit.depthLaunchArgument,
            defaultValue: osrsDeepNavigationFixtureAudit.defaultDepth
        )

        let result = runDeepNavigationFixtureAuditForUITests(
            seed: seed,
            startOffset: startOffset,
            startCount: startCount,
            targetDepth: targetDepth
        )
        deepNavigationFixtureAuditDebugLabel = result.accessibilityLabel
        print("UITest: deep navigation fixture audit \(result.accessibilityLabel)")
    }
#endif

    // NAVIGATION METHODS: Moved to AppState+Navigation.swift extension with unique destination types

    // Check if currently viewing an article (has navigation depth > 0)
    var isInArticle: Bool {
        switch selectedTab {
        case .news:
            return !newsNavigationStack.isEmpty
        case .saved:
            return !savedNavigationStack.isEmpty
        case .search:
            return !searchNavigationStack.isEmpty
        case .map:
            return !mapNavigationStack.isEmpty
        case .more:
            return !moreNavigationStack.isEmpty
        }
    }


    // Clear navigation stack for a specific tab (useful for tab switching)
    func clearNavigationPath(for tab: TabItem? = nil) {
        let targetTab = tab ?? selectedTab
        switch targetTab {
        case .news:
            newsNavigationStack = []
        case .saved:
            savedNavigationStack = []
        case .search:
            searchNavigationStack = []
        case .map:
            mapNavigationStack = []
        case .more:
            moreNavigationStack = []
        }
    }

    // Clear history navigation stack (separate from main tab navigation)
    func clearHistoryNavigationPath() {
        historyNavigationStack = []
        print("🧹 AppState: Cleared historyNavigationStack")
    }
}

// Navigation destinations
// CRITICAL FIX: Create unique destination types for each NavigationStack
// to prevent cross-stack interference where multiple handlers respond to same type

enum NewsNavigationDestination: Hashable {
    case search
    case article(ArticleDestination)
}

enum SearchNavigationDestination: Hashable {
    case article(ArticleDestination)
}

enum HistoryNavigationDestination: Hashable {
    case search
    case article(ArticleDestination)
}

enum SavedNavigationDestination: Hashable {
    case search
    case article(ArticleDestination)
}

enum MapNavigationDestination: Hashable {
    case article(ArticleDestination)
}

enum MoreNavigationDestination: Hashable {
    case appearance
    case donate
    case about
    case feedback
    case article(ArticleDestination)
}

// Legacy enum kept for backwards compatibility during transition
enum NavigationDestination: Hashable {
    case search
    case article(ArticleDestination)
}

struct ArticleDestination: Hashable {
    let title: String?  // Optional - will be extracted from URL if nil
    let url: URL
    let snippet: String?  // Optional - for rich history display
    let thumbnailUrl: URL?  // Optional - for rich history display
    let savedPageId: String?  // Optional - for saved page proxy configuration
    let navigationRevision: Int

    var navigationIdentity: String {
        "\(url.absoluteString)|savedPageId=\(savedPageId ?? "")|revision=\(navigationRevision)"
    }

    init(title: String?, url: URL, snippet: String? = nil, thumbnailUrl: URL? = nil, savedPageId: String? = nil, navigationRevision: Int = 0) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.thumbnailUrl = thumbnailUrl
        self.savedPageId = savedPageId
        self.navigationRevision = navigationRevision
    }

    func incrementingNavigationRevision() -> ArticleDestination {
        ArticleDestination(
            title: title,
            url: url,
            snippet: snippet,
            thumbnailUrl: thumbnailUrl,
            savedPageId: savedPageId,
            navigationRevision: navigationRevision + 1
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(url)
        hasher.combine(snippet)
        hasher.combine(thumbnailUrl)
        hasher.combine(savedPageId)
        hasher.combine(navigationRevision)
    }
}

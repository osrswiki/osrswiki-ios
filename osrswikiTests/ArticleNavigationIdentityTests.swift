//
//  ArticleNavigationIdentityTests.swift
//  osrswikiTests
//
//  Regression coverage for stacked article view identity.
//

import XCTest
import SwiftUI
@testable import osrswiki

final class ArticleNavigationIdentityTests: XCTestCase {
    @MainActor
    func testArticleBottomBarLateOwnerCannotHideOrReplaceCurrentOwner() {
        let manager = GlobalOverlayManager()
        manager.showArticleBottomBar(owner: "article-a") { Text("A") }
        manager.showArticleBottomBar(owner: "article-b") { Text("B") }

        manager.hideArticleBottomBar(owner: "article-a")
        XCTAssertEqual(manager.articleBottomBarOwner, "article-b")
        XCTAssertNotNil(manager.articleBottomBar)

        manager.hideArticleBottomBar(owner: "article-b")
        XCTAssertNil(manager.articleBottomBarOwner)
        XCTAssertNil(manager.articleBottomBar)

        manager.hideMainTabBar(owner: "article-a")
        manager.hideMainTabBar(owner: "article-b")
        manager.showMainTabBar(owner: "article-a")
        XCTAssertEqual(manager.mainTabBarHiddenOwner, "article-b", "Late A disappearance must not reveal the tab bar over B")
        manager.showMainTabBar(owner: "article-b")
        XCTAssertNil(manager.mainTabBarHiddenOwner)

        manager.setArticleBottomBarExitProgress(0.4)
        XCTAssertEqual(manager.articleBottomBarExitProgress, 0.4, accuracy: 0.001)
        manager.setArticleBottomBarExitProgress(1.5)
        XCTAssertEqual(manager.articleBottomBarExitProgress, 1, accuracy: 0.001)
        manager.setArticleBottomBarExitProgress(0)
        XCTAssertEqual(manager.articleBottomBarExitProgress, 0, accuracy: 0.001)
    }

    func testArticleTabBarVisibilityCombinesDestinationHidingWithOwnerScopedRestoration() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root
                .appendingPathComponent("platforms/ios/osrswiki")
                .appendingPathComponent("Views")
                .appendingPathComponent("ArticleView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("overlayManager?.hideMainTabBar(owner: articleIdentity)"))
        XCTAssertTrue(source.contains("overlayManager?.showMainTabBar(owner: articleIdentity)"))
        let tabSource = try String(
            contentsOf: root
                .appendingPathComponent("platforms/ios/osrswiki")
                .appendingPathComponent("Views")
                .appendingPathComponent("CustomMainTabView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            tabSource.contains("UIApplication.setFloatingTabBarHidden"),
            "The iOS 26 tab bar must be alpha-hidden under an article so the home capsule cannot show through the article glass, while staying in the hierarchy for an instant restore."
        )
        XCTAssertFalse(
            tabSource.contains(".toolbarVisibility(.hidden, for: .tabBar)"),
            "toolbarVisibility leaves the Liquid Glass capsule composited underneath the article bar on iOS 26."
        )
    }

    @MainActor
    func testActiveArticleDestinationTracksSelectedTabTopArticleWhenPopping() throws {
        let appState = AppState()
        appState.selectedTab = .search

        let bloodMoon = try ArticleDestination(
            title: "The Blood Moon Rises",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))
        )
        let quickGuide = try ArticleDestination(
            title: "The Blood Moon Rises/Quick guide",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))
        )

        appState.searchNavigationStack = [
            .article(bloodMoon),
            .article(quickGuide)
        ]
        XCTAssertEqual(appState.activeArticleDestination, quickGuide)

        appState.searchNavigationStack.removeLast()

        XCTAssertEqual(appState.activeArticleDestination, bloodMoon)
    }

    @MainActor
    func testURLOnlyArticleNavigationPreservesFullWikiSubpageTitle() throws {
        let appState = AppState()
        appState.selectedTab = .search
        let quickGuideURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))

        appState.navigateToArticle(url: quickGuideURL)

        guard case .article(let destination) = appState.searchNavigationStack.last else {
            return XCTFail("Expected URL-only navigation to append an article destination")
        }
        XCTAssertEqual(destination.title, "The Blood Moon Rises/Quick guide")
        XCTAssertEqual(destination.url, quickGuideURL)
    }

    @MainActor
    func testArticleTitleFromURLPreservesFullWikiSubpagePath() throws {
        let quickGuideURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))

        XCTAssertEqual(AppState.articleTitle(from: quickGuideURL), "The Blood Moon Rises/Quick guide")
    }

    func testArticleNavigationDestinationsKeyArticleViewsByDestinationIdentity() throws {
        let root = try repositoryRoot()
        let articleDestinationViews = [
            "platforms/ios/osrswiki/Views/NewsView.swift",
            "platforms/ios/osrswiki/Views/SearchView.swift",
            "platforms/ios/osrswiki/Views/HistoryView.swift",
            "platforms/ios/osrswiki/Views/SavedPagesView.swift",
            "platforms/ios/osrswiki/Views/MoreView.swift"
        ]

        for path in articleDestinationViews {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(
                source.contains(".id(articleDestination.navigationIdentity)"),
                "\(path) must key ArticleView by articleDestination.navigationIdentity so stacked article pages do not reuse the wrong StateObject when popping back."
            )
            XCTAssertTrue(
                source.contains("navigationIdentity: articleDestination.navigationIdentity"),
                "\(path) must pass articleDestination.navigationIdentity into ArticleView so the active destination and visible ArticleView compare the same identity when popping back."
            )
        }
    }

    func testArticleDestinationProvidesStableNavigationIdentity() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/AppState.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("var navigationIdentity: String"))
        XCTAssertTrue(source.contains("url.absoluteString"))
        XCTAssertTrue(source.contains("savedPageId"))
        XCTAssertTrue(source.contains("navigationInstanceID"))
        XCTAssertTrue(source.contains("navigationRevision"))
        XCTAssertTrue(source.contains("incrementingNavigationRevision()"))
    }

    func testArticleViewKeepsExistingPageInsteadOfReloadingWhenItReturnsToTopOfStack() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        let navigationSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/AppState+Navigation.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("movedOffTopOfArticleStack"))
        XCTAssertTrue(source.contains(".onChange(of: appState.activeArticleDestination?.navigationIdentity)"))
        XCTAssertTrue(source.contains("activeIdentity == articleIdentity"))
        XCTAssertTrue(source.contains("restoreCapturedArticleScrollIfNeeded"))
        XCTAssertTrue(source.contains("restoreCapturedArticleScrollIfNeeded(attempt:"))
        XCTAssertTrue(source.contains("captureCurrentArticleScroll"))
        XCTAssertTrue(source.contains("window.scrollTo(0, \\(offsetY))"))
        XCTAssertTrue(source.contains("if hasLoadedBefore {"))
        XCTAssertFalse(source.contains("hasLoadedBefore || viewModel.hasReusableRenderedArticle"))
        XCTAssertFalse(source.contains("viewModel.hasReusableRenderedArticle"))
        XCTAssertTrue(source.contains("setArticleBottomBarCovered(false)"))
        XCTAssertTrue(source.contains("setArticleBottomBarExitProgress(progress)"))
        XCTAssertFalse(source.contains("Returned to top article destination - reloading expected page"))
        XCTAssertFalse(source.contains("Detected return navigation - using reload with blank overlay"))
        XCTAssertFalse(navigationSource.contains("bumpTopArticleNavigationRevision"))
        XCTAssertFalse(navigationSource.contains("requestArticleBackStackRecoveryReload()"))
        XCTAssertTrue(source.contains("appState.navigateBackWithinActiveArticleStack(animated: animated)"))
        XCTAssertTrue(source.contains("navigateBackFromArticle(animated: false)"))
        XCTAssertTrue(source.contains("viewModel.recoverRenderedArticleMismatchIfNeeded(theme: osrsTheme"))
        XCTAssertTrue(source.contains("appState.navigateBack(animated: animated)"))
        XCTAssertTrue(source.contains("onBackProgress:"))
        XCTAssertTrue(source.contains("appState.activeArticleDestination != nil"))
        if let progressStart = source.range(of: "onBackProgress: { progress in"),
           let progressEnd = source.range(of: "isContentsOpen:", range: progressStart.upperBound..<source.endIndex) {
            let backProgress = String(source[progressStart.lowerBound..<progressEnd.lowerBound])
            XCTAssertTrue(backProgress.contains("setArticleBottomBarExitProgress(progress)"))
            XCTAssertTrue(backProgress.contains("setArticleBottomBarCovered(false)"))
            XCTAssertFalse(backProgress.contains("showMainTabBar()"))
            XCTAssertFalse(backProgress.contains("hideMainTabBar()"))
            XCTAssertFalse(backProgress.contains("canNavigateBackWithinActiveArticleStack"))
        } else {
            XCTFail("onBackProgress is missing")
        }
        guard let navigateStart = source.range(of: "private func navigateBackFromArticle"),
              let navigateEnd = source.range(of: "private var offlineCacheBanner") else {
            XCTFail("navigateBackFromArticle is missing")
            return
        }
        let navigateBack = String(source[navigateStart.lowerBound..<navigateEnd.lowerBound])
        let showBarIndex = navigateBack.range(of: "showMainTabBar()")
        let withinStackIndex = navigateBack.range(
            of: "navigateBackWithinActiveArticleStack(animated: animated)"
        )
        XCTAssertNotNil(withinStackIndex)
        XCTAssertNotNil(showBarIndex, "Root article back still needs to reveal the home tab bar")
        if let showBarIndex, let withinStackIndex {
            XCTAssertTrue(
                withinStackIndex.lowerBound < showBarIndex.lowerBound,
                "Home tab bar must not appear until a root article actually leaves the stack"
            )
        }
        XCTAssertFalse(source.contains("viewModel.isLoading && showProgressBar"))
        let tabSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/CustomMainTabView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(tabSource.contains("articleBottomBarExitProgress"))
    }

    func testArticleViewModelCanRebindVisibleArticleToNativeDestination() throws {
        let root = try repositoryRoot()
        let articleViewModelSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(articleViewModelSource.contains("private(set) var pageUrl: URL"))
        XCTAssertTrue(articleViewModelSource.contains("func loadArticleDestination(_ destination: ArticleDestination, theme: any osrsThemeProtocol)"))
        XCTAssertTrue(articleViewModelSource.contains("pageUrl = destination.url"))
        XCTAssertTrue(articleViewModelSource.contains("pageTitle_ = destination.title"))
        XCTAssertTrue(articleViewModelSource.contains("snippet_ = destination.snippet"))
        XCTAssertTrue(articleViewModelSource.contains("thumbnailUrl_ = destination.thumbnailUrl"))
        XCTAssertTrue(articleViewModelSource.contains("loadArticle(theme: theme, isReload: true)"))
    }

    @MainActor
    func testActiveArticleStackReportsWhenPreviousDestinationExists() throws {
        let appState = AppState()
        appState.selectedTab = .search

        let bloodMoon = try ArticleDestination(
            title: "The Blood Moon Rises",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))
        )
        let quickGuide = try ArticleDestination(
            title: "The Blood Moon Rises/Quick guide",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))
        )

        appState.searchNavigationStack = [.article(bloodMoon)]
        XCTAssertFalse(appState.canNavigateBackWithinActiveArticleStack)

        appState.searchNavigationStack.append(.article(quickGuide))
        XCTAssertTrue(appState.canNavigateBackWithinActiveArticleStack)
    }

    @MainActor
    func testActiveArticleStackPopOnlyRemovesTopArticleDestination() throws {
        let appState = AppState()
        appState.selectedTab = .search

        let bloodMoon = try ArticleDestination(
            title: "The Blood Moon Rises",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))
        )
        let quickGuide = try ArticleDestination(
            title: "The Blood Moon Rises/Quick guide",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))
        )
        appState.searchNavigationStack = [.article(bloodMoon), .article(quickGuide)]

        XCTAssertTrue(appState.navigateBackWithinActiveArticleStack())
        guard case .article(let recoveredBloodMoon) = appState.searchNavigationStack.last else {
            return XCTFail("Expected remaining search destination to be an article")
        }
        XCTAssertEqual(recoveredBloodMoon.url, bloodMoon.url)
        XCTAssertEqual(recoveredBloodMoon.navigationInstanceID, bloodMoon.navigationInstanceID)
        XCTAssertEqual(recoveredBloodMoon.navigationRevision, bloodMoon.navigationRevision)
        XCTAssertNil(appState.articleBackStackRecoveryDestination)
        XCTAssertEqual(appState.articleBackStackRecoveryRequestID, 0)
        XCTAssertFalse(appState.navigateBackWithinActiveArticleStack())
        XCTAssertEqual(appState.searchNavigationStack.count, 1)
        XCTAssertEqual(appState.articleBackStackRecoveryRequestID, 0)
    }

    @MainActor
    func testPoppedArticleRouteIsSuppressedDuringBackTransition() throws {
        let appState = AppState()
        appState.selectedTab = .search

        let bloodMoon = try ArticleDestination(
            title: "The Blood Moon Rises",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))
        )
        let quickGuideURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))
        let quickGuide = ArticleDestination(
            title: "The Blood Moon Rises/Quick guide",
            url: quickGuideURL
        )
        appState.searchNavigationStack = [.article(bloodMoon), .article(quickGuide)]

        XCTAssertTrue(appState.navigateBackWithinActiveArticleStack())
        appState.routeInternalArticleLink(quickGuideURL, sourceArticleURL: quickGuideURL)

        guard case .article(let recoveredBloodMoon) = appState.searchNavigationStack.last else {
            return XCTFail("Expected remaining search destination to be an article")
        }
        XCTAssertEqual(recoveredBloodMoon.url, bloodMoon.url)

        appState.routeInternalArticleLink(quickGuideURL, sourceArticleURL: bloodMoon.url)
        guard case .article(let reopenedQuickGuide) = appState.searchNavigationStack.last else {
            return XCTFail("Expected the visible source article to reopen the popped destination immediately")
        }
        XCTAssertEqual(reopenedQuickGuide.url, quickGuideURL)
    }

    @MainActor
    func testAcceptedBackSuppressionIsSourceScopedAcrossRapidTwoArticlePops() throws {
        let appState = AppState()
        appState.selectedTab = .search
        let first = try ArticleDestination(
            title: "First",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/First"))
        )
        let second = try ArticleDestination(
            title: "Second",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Second"))
        )
        appState.searchNavigationStack = [.article(first), .article(second)]

        let secondTransition = "second-render-pass"
        XCTAssertTrue(appState.beginArticleBackAction(
            articleIdentity: second.navigationIdentity,
            transitionIdentity: secondTransition
        ))
        XCTAssertTrue(appState.navigateBackWithinActiveArticleStack())
        appState.completeArticleBackAction(transitionIdentity: secondTransition, accepted: true)
        XCTAssertFalse(appState.beginArticleBackAction(
            articleIdentity: second.navigationIdentity,
            transitionIdentity: secondTransition
        ), "A duplicate callback from the popped article must be ignored exactly once")

        let recoveredFirst = try XCTUnwrap(appState.activeArticleDestination)
        let firstTransition = "first-render-pass"
        XCTAssertTrue(appState.beginArticleBackAction(
            articleIdentity: recoveredFirst.navigationIdentity,
            transitionIdentity: firstTransition
        ), "The newly visible article must be allowed to pop immediately")
        XCTAssertTrue(appState.navigateBackFromActiveRootArticle())
        appState.completeArticleBackAction(transitionIdentity: firstTransition, accepted: true)
        XCTAssertTrue(appState.searchNavigationStack.isEmpty)
    }

    @MainActor
    func testNoOpBackDoesNotConsumeTransitionIdentity() throws {
        let appState = AppState()
        appState.selectedTab = .search
        let article = try ArticleDestination(
            title: "Only",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Only"))
        )
        appState.searchNavigationStack = [.article(article)]

        XCTAssertTrue(appState.beginArticleBackAction(
            articleIdentity: article.navigationIdentity,
            transitionIdentity: "same-transition"
        ))
        appState.completeArticleBackAction(transitionIdentity: "same-transition", accepted: false)
        XCTAssertTrue(appState.beginArticleBackAction(
            articleIdentity: article.navigationIdentity,
            transitionIdentity: "same-transition"
        ))
    }

    @MainActor
    func testFreshSameURLAndSavedArticleReopensReceiveNewBackTransitionIdentity() throws {
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Amulet_of_glory"))

        for (tab, savedPageID) in [(TabItem.news, nil), (.saved, "saved-amulet")] {
            let appState = AppState()
            appState.selectedTab = tab
            let first = ArticleDestination(title: "Amulet of glory", url: url, savedPageId: savedPageID)
            switch tab {
            case .news: appState.newsNavigationStack = [.article(first)]
            case .saved: appState.savedNavigationStack = [.article(first)]
            default: return XCTFail("Unexpected test tab")
            }

            let firstTransition = "\(first.navigationIdentity)|rendered=\(url.absoluteString)"
            XCTAssertTrue(appState.beginArticleBackAction(
                articleIdentity: first.navigationIdentity,
                transitionIdentity: firstTransition
            ))
            XCTAssertTrue(appState.navigateBackFromActiveRootArticle())
            appState.completeArticleBackAction(transitionIdentity: firstTransition, accepted: true)

            let reopened = ArticleDestination(title: "Amulet of glory", url: url, savedPageId: savedPageID)
            XCTAssertNotEqual(reopened.navigationInstanceID, first.navigationInstanceID)
            switch tab {
            case .news: appState.newsNavigationStack = [.article(reopened)]
            case .saved: appState.savedNavigationStack = [.article(reopened)]
            default: return XCTFail("Unexpected test tab")
            }

            let reopenedTransition = "\(reopened.navigationIdentity)|rendered=\(url.absoluteString)"
            XCTAssertTrue(appState.beginArticleBackAction(
                articleIdentity: reopened.navigationIdentity,
                transitionIdentity: reopenedTransition
            ), "A fresh presentation of the same \(tab.rawValue) article must not inherit the old duplicate-back token")
            XCTAssertTrue(appState.navigateBackFromActiveRootArticle())
            appState.completeArticleBackAction(transitionIdentity: reopenedTransition, accepted: true)
            XCTAssertNil(appState.activeArticleDestination)
        }
    }

    @MainActor
    func testMixedStacksDoNotReportPreviousArticleDestination() throws {
        let appState = AppState()
        appState.selectedTab = .saved

        let bloodMoon = try ArticleDestination(
            title: "The Blood Moon Rises",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))
        )
        appState.savedNavigationStack = [.search, .article(bloodMoon)]

        XCTAssertFalse(appState.canNavigateBackWithinActiveArticleStack)
        XCTAssertFalse(appState.navigateBackWithinActiveArticleStack())
        XCTAssertEqual(appState.savedNavigationStack, [.search, .article(bloodMoon)])
    }

    @MainActor
    func testHomeRootArticleBackIgnoresRetainedOffscreenHistoryStack() throws {
        let appState = AppState()
        let homeArticle = try ArticleDestination(
            title: "Wyrmscraig & Sailing Changes",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:Wyrmscraig_%26_Sailing_Changes"))
        )
        let staleHistoryArticle = try ArticleDestination(
            title: "Stale history article",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Varrock"))
        )
        appState.selectedTab = .news
        appState.newsNavigationStack = [.article(homeArticle)]
        appState.historyNavigationStack = [.article(staleHistoryArticle)]

        XCTAssertEqual(appState.activeArticleDestination, homeArticle)
        XCTAssertTrue(appState.navigateBackFromActiveRootArticle())
        XCTAssertTrue(appState.newsNavigationStack.isEmpty)
        XCTAssertEqual(appState.historyNavigationStack, [.article(staleHistoryArticle)])
    }

    @MainActor
    func testWyrmscraigHistoryNavigationPreservesDecodedTitleAndThumbnail() throws {
        let appState = AppState()
        let articleURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:Wyrmscraig_%26_Sailing_Changes"))
        let thumbnailURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/thumb/Wyrmscraig.png/320px-Wyrmscraig.png"))

        appState.navigateToArticleInHistory(
            title: osrsStringUtils.extractMainTitle("Update:Wyrmscraig &amp;amp; Sailing Changes"),
            url: articleURL,
            snippet: "Wyrmscraig &amp;amp; Sailing notes",
            thumbnailUrl: thumbnailURL
        )

        guard case .article(let destination) = appState.historyNavigationStack.last else {
            return XCTFail("Expected Wyrmscraig to navigate through the History article stack.")
        }
        XCTAssertEqual(destination.title, "Wyrmscraig & Sailing Changes")
        XCTAssertEqual(destination.url, articleURL)
        XCTAssertEqual(destination.thumbnailUrl, thumbnailURL)
    }

    func testSavingAnUpdatePreservesTheThumbnailCarriedByNavigation() throws {
        let root = try repositoryRoot()
        let articleViewModelSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        let savedViewModelSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/SavedPagesViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            articleViewModelSource.contains("metadata.thumbnailUrl ?? thumbnailUrl_ ?? extractThumbnailUrl()"),
            "Saving must retain the Home/Search/History thumbnail when pageimages omits update artwork."
        )
        XCTAssertTrue(savedViewModelSource.contains("osrsHistoryUpdateMetadataResolver.cachedMetadata("))
        XCTAssertTrue(savedViewModelSource.contains("metadata.thumbnailUrl ?? cachedMetadata?.thumbnailUrl"))
    }

    func testArticleBackFallsBackToWebViewArticleHistoryOnlyWithoutNativeArticleBelow() throws {
        let root = try repositoryRoot()
        let articleViewSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        let viewModelSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(articleViewSource.contains("appState.navigateBackWithinActiveArticleStack(animated: animated)"))
        XCTAssertTrue(articleViewSource.contains("viewModel.goBackToPreviousWebViewArticleIfNeeded()"))
        XCTAssertTrue(articleViewSource.contains("appState.navigateBackFromActiveRootArticle(animated: animated)"))
        XCTAssertTrue(viewModelSource.contains("Self.osrsShouldUseWebViewArticleHistory(currentURL: currentURL, pageURL: pageUrl)"))
        XCTAssertTrue(viewModelSource.contains("webView.goBack()"))
    }

    @MainActor
    func testWebViewArticleHistoryFallbackIgnoresSameArticleFragments() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:The_Blood_Moon_Rises_Tweaks_%26_Fixes"))
        let anchoredCurrentURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Update:The_Blood_Moon_Rises_Tweaks_%26_Fixes#Thank_You"))

        XCTAssertFalse(
            ArticleViewModel.osrsShouldUseWebViewArticleHistory(
                currentURL: anchoredCurrentURL,
                pageURL: pageURL
            )
        )
    }

    @MainActor
    func testWebViewArticleHistoryFallbackIgnoresSameArticleEncodingDifferences() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:The_Blood_Moon_Rises_Tweaks_%26_Fixes"))
        let decodedCurrentURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Update:The_Blood_Moon_Rises_Tweaks_&_Fixes"))

        XCTAssertFalse(
            ArticleViewModel.osrsShouldUseWebViewArticleHistory(
                currentURL: decodedCurrentURL,
                pageURL: pageURL
            )
        )
    }

    @MainActor
    func testWebViewArticleHistoryFallbackStillDetectsDifferentArticle() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:The_Blood_Moon_Rises_Tweaks_%26_Fixes"))
        let differentArticleURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Maggot_King"))

        XCTAssertTrue(
            ArticleViewModel.osrsShouldUseWebViewArticleHistory(
                currentURL: differentArticleURL,
                pageURL: pageURL
            )
        )
    }

    @MainActor
    func testWebViewArticleNavigationPromotionIgnoresSameArticleAnchor() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:The_Blood_Moon_Rises_Tweaks_%26_Fixes"))
        let anchorURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Update:The_Blood_Moon_Rises_Tweaks_&_Fixes#Quest_Fixes"))

        XCTAssertFalse(
            ArticleViewModel.osrsShouldPromoteWebViewArticleNavigation(
                candidateURL: anchorURL,
                pageURL: pageURL
            )
        )
    }

    @MainActor
    func testWebViewArticleNavigationPromotionDetectsDifferentArticle() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:The_Blood_Moon_Rises_Tweaks_%26_Fixes"))
        let differentArticleURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/The_Blood_Moon_Rises"))

        XCTAssertTrue(
            ArticleViewModel.osrsShouldPromoteWebViewArticleNavigation(
                candidateURL: differentArticleURL,
                pageURL: pageURL
            )
        )
    }

    @MainActor
    func testWebViewArticleNavigationDoesNotPromoteWikiHostOrUnderscoreAliases() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Calculator:Agility/Agility_arena_tickets"))
        let assetAlias = try XCTUnwrap(URL(string: "app-assets://localhost/w/Calculator:Agility/Agility arena tickets"))
        let spaceAlias = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Calculator:Agility/Agility arena tickets"))

        XCTAssertFalse(
            ArticleViewModel.osrsShouldPromoteWebViewArticleNavigation(
                candidateURL: assetAlias,
                pageURL: pageURL
            )
        )
        XCTAssertFalse(
            ArticleViewModel.osrsShouldPromoteWebViewArticleNavigation(
                candidateURL: spaceAlias,
                pageURL: pageURL
            )
        )
        XCTAssertEqual(
            ArticleViewModel.osrsArticleHistoryIdentity(for: pageURL),
            ArticleViewModel.osrsArticleHistoryIdentity(for: assetAlias)
        )
    }

    @MainActor
    func testContentsScrollScriptKeepsSelectedHeadingBelowNativeChrome() {
        let script = ArticleViewModel.osrsScrollToSectionScript(for: "Other_Fixes_&_What's_Next")

        XCTAssertFalse(script.contains("scrollIntoView"))
        XCTAssertFalse(script.contains("element.scrollIntoView(true)"))
        XCTAssertTrue(script.contains("headerOffset"))
        XCTAssertTrue(script.contains("scrollPaddingTop"))
        XCTAssertTrue(script.contains("paddingTop"))
        XCTAssertTrue(script.contains("getBoundingClientRect().top"))
        XCTAssertTrue(script.contains("window.scrollTo"))
        XCTAssertTrue(script.contains(#""Other_Fixes_&_What's_Next""#))
    }

    @MainActor
    func testBackNavigationDebouncesDuplicateBackActions() throws {
        let appState = AppState()
        appState.selectedTab = .search

        let bloodMoon = try ArticleDestination(
            title: "The Blood Moon Rises",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))
        )
        let quickGuide = try ArticleDestination(
            title: "The Blood Moon Rises/Quick guide",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"))
        )
        appState.searchNavigationStack = [.article(bloodMoon), .article(quickGuide)]

        appState.navigateBack()
        appState.navigateBack()

        XCTAssertEqual(appState.searchNavigationStack, [.article(bloodMoon)])
    }

    @MainActor
    func testArticleSearchRoutesEveryOwningTabToCanonicalActiveSearch() throws {
        let article = try ArticleDestination(
            title: "Falador",
            url: XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Falador"))
        )

        for origin in TabItem.allCases {
            let appState = AppState()
            appState.selectedTab = origin
            switch origin {
            case .news: appState.newsNavigationStack = [.article(article)]
            case .saved: appState.savedNavigationStack = [.article(article)]
            case .search: appState.searchNavigationStack = [.article(article)]
            case .map: appState.mapNavigationStack = [.article(article)]
            case .more: appState.moreNavigationStack = [.article(article)]
            }

            appState.navigateToActiveSearch()

            XCTAssertEqual(appState.selectedTab, .search, "origin=\(origin)")
            XCTAssertTrue(appState.searchNavigationStack.isEmpty, "origin=\(origin)")
            XCTAssertEqual(
                appState.pendingSearchActivationIntent?.startsVoiceRecognition,
                false,
                "origin=\(origin)"
            )

            let generation = try XCTUnwrap(appState.pendingSearchActivationIntent?.generation)
            XCTAssertTrue(appState.consumeSearchActivationIntent(generation: generation))
            XCTAssertTrue(appState.returnFromActiveSearchIfNeeded(), "origin=\(origin)")
            XCTAssertEqual(appState.selectedTab, origin, "origin=\(origin)")
            switch origin {
            case .news:
                XCTAssertEqual(appState.newsNavigationStack, [.article(article)])
            case .saved:
                XCTAssertEqual(appState.savedNavigationStack, [.article(article)])
            case .search:
                XCTAssertEqual(appState.searchNavigationStack, [.article(article)])
            case .map:
                XCTAssertEqual(appState.mapNavigationStack, [.article(article)])
            case .more:
                XCTAssertEqual(appState.moreNavigationStack, [.article(article)])
            }
        }
    }

    @MainActor
    func testVoiceSearchActivationIsGenerationBoundAndConsumedExactlyOnce() {
        let appState = AppState()
        appState.selectedTab = .saved

        appState.navigateToActiveSearch(startsVoiceRecognition: true)
        let first = appState.pendingSearchActivationIntent
        XCTAssertNotNil(first)
        XCTAssertTrue(first?.startsVoiceRecognition == true)
        XCTAssertTrue(appState.consumeSearchActivationIntent(generation: first?.generation ?? 0))
        XCTAssertFalse(appState.consumeSearchActivationIntent(generation: first?.generation ?? 0))

        appState.navigateToActiveSearch(startsVoiceRecognition: true)
        let second = appState.pendingSearchActivationIntent
        XCTAssertNotEqual(first?.generation, second?.generation)
        XCTAssertFalse(appState.consumeSearchActivationIntent(generation: first?.generation ?? 0))
        XCTAssertTrue(appState.consumeSearchActivationIntent(generation: second?.generation ?? 0))
    }

    @MainActor
    func testLegacyHomeAndHistorySearchEntryPointsUseCanonicalReturnContext() {
        let appState = AppState()

        appState.selectedTab = .news
        appState.navigateToSearch()
        XCTAssertEqual(appState.selectedTab, .search)
        XCTAssertEqual(appState.pendingSearchActivationIntent?.returnContext.originTab, .news)
        let homeGeneration = appState.pendingSearchActivationIntent?.generation ?? 0
        XCTAssertTrue(appState.consumeSearchActivationIntent(generation: homeGeneration))
        XCTAssertTrue(appState.returnFromActiveSearchIfNeeded())
        XCTAssertEqual(appState.selectedTab, .news)

        appState.selectedTab = .more
        appState.navigateToSearchFromHistory()
        XCTAssertEqual(appState.selectedTab, .search)
        XCTAssertEqual(appState.pendingSearchActivationIntent?.returnContext.originTab, .more)
        XCTAssertTrue(appState.historyNavigationStack.isEmpty)
    }

    @MainActor
    func testLeavingSearchInvalidatesUnconsumedVoiceActivation() {
        let appState = AppState()
        appState.selectedTab = .news
        appState.navigateToActiveSearch(startsVoiceRecognition: true)
        XCTAssertNotNil(appState.pendingSearchActivationIntent)

        appState.setSelectedTab(.news)

        XCTAssertNil(appState.pendingSearchActivationIntent)
    }

    func testSearchViewAcknowledgesIntentAfterCallbacksWithoutFixedDelay() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/SearchView.swift"),
            encoding: .utf8
        )
        let helper = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift"),
            encoding: .utf8
        )

        let setupRange = try XCTUnwrap(source.range(of: "setupVoiceSearch()"))
        let activationRange = try XCTUnwrap(source.range(of: "activatePendingSearchIntentIfNeeded()"))
        XCTAssertLessThan(setupRange.lowerBound, activationRange.lowerBound)
        XCTAssertTrue(source.contains("consumeSearchActivationIntent(generation: intent.generation)"))
        XCTAssertTrue(source.contains("appState.selectedTab == .search"))
        XCTAssertTrue(source.contains("if appState.selectedTab != .search"))
        XCTAssertTrue(source.contains("searchViewAppeared"))
        XCTAssertTrue(source.contains("appState.returnFromActiveSearchIfNeeded()"))
        XCTAssertFalse(helper.contains("beginVoiceSearchAfterNavigation"))
        XCTAssertFalse(helper.contains("100_000_000"))
    }

    func testSavedArticleRetryUsesExactOwnerTransferAndPublishedRouteResolution() throws {
        let root = try repositoryRoot()
        let articleView = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(articleView.contains("await performArticleSaveAction()"))
        XCTAssertTrue(articleView.contains("replacingPresentationOwner: savedCacheSessionToken"))
        XCTAssertTrue(articleView.contains("performSaveAction(explicitSaveReservation: reservation)"))
        XCTAssertTrue(articleView.contains("currentSavedCachePageIdForArticle() ?? initialSavedPageId"))
        XCTAssertTrue(articleView.contains("appState.activeArticleDestination?.navigationIdentity == articleIdentity"))
        XCTAssertTrue(viewModel.contains("explicitSaveReservation preReservedExplicitSaveLease"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("platforms/ios/osrswiki.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root from \(#filePath)")
    }
}

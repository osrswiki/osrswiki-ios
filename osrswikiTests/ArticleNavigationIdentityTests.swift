//
//  ArticleNavigationIdentityTests.swift
//  osrswikiTests
//
//  Regression coverage for stacked article view identity.
//

import XCTest
@testable import osrswiki

final class ArticleNavigationIdentityTests: XCTestCase {
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
        XCTAssertTrue(source.contains("navigationRevision"))
        XCTAssertTrue(source.contains("incrementingNavigationRevision()"))
    }

    func testArticleViewReloadsExpectedArticleWhenItReturnsToTopOfStack() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("movedOffTopOfArticleStack"))
        XCTAssertTrue(source.contains(".onChange(of: appState.activeArticleDestination?.navigationIdentity)"))
        XCTAssertTrue(source.contains("activeIdentity == articleIdentity"))
        XCTAssertTrue(source.contains("viewModel.loadArticle(theme: osrsTheme, isReload: true)"))
        XCTAssertTrue(source.contains("appState.navigateBackWithinActiveArticleStack()"))
        XCTAssertTrue(source.contains(".onChange(of: appState.articleBackStackRecoveryRequestID)"))
        XCTAssertTrue(source.contains("appState.articleBackStackRecoveryDestination"))
        XCTAssertTrue(source.contains("viewModel.loadArticleDestination(destination, theme: osrsTheme)"))
        XCTAssertTrue(source.contains("viewModel.recoverRenderedArticleMismatchIfNeeded(theme: osrsTheme"))
        XCTAssertTrue(source.contains("appState.navigateBack()"))
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
        XCTAssertEqual(recoveredBloodMoon.navigationRevision, bloodMoon.navigationRevision + 1)
        XCTAssertEqual(appState.articleBackStackRecoveryDestination?.url, bloodMoon.url)
        XCTAssertEqual(appState.articleBackStackRecoveryDestination?.navigationRevision, bloodMoon.navigationRevision + 1)
        XCTAssertEqual(appState.articleBackStackRecoveryRequestID, 1)
        XCTAssertFalse(appState.navigateBackWithinActiveArticleStack())
        XCTAssertEqual(appState.searchNavigationStack.count, 1)
        XCTAssertEqual(appState.articleBackStackRecoveryRequestID, 1)
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
        appState.routeInternalArticleLink(quickGuideURL)

        guard case .article(let recoveredBloodMoon) = appState.searchNavigationStack.last else {
            return XCTFail("Expected remaining search destination to be an article")
        }
        XCTAssertEqual(recoveredBloodMoon.url, bloodMoon.url)
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

        XCTAssertTrue(articleViewSource.contains("appState.navigateBackWithinActiveArticleStack()"))
        XCTAssertTrue(articleViewSource.contains("viewModel.goBackToPreviousWebViewArticleIfNeeded()"))
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
    func testContentsScrollScriptKeepsSelectedHeadingBelowNativeChrome() {
        let script = ArticleViewModel.osrsScrollToSectionScript(for: "Other_Fixes_&_What's_Next")

        XCTAssertTrue(script.contains("getBoundingClientRect().top + window.pageYOffset"))
        XCTAssertTrue(script.contains("headerOffset"))
        XCTAssertTrue(script.contains("window.scrollTo"))
        XCTAssertFalse(script.contains("scrollIntoView"))
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

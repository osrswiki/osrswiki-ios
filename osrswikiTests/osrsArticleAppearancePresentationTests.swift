import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import osrswiki

@MainActor
final class osrsArticleAppearancePresentationTests: XCTestCase {
    func testInteractiveDismissStaysDismissedThroughArticleChromeUpdates() {
        let presentation = osrsArticleAppearancePresentation()
        presentation.handleShowAppearanceNotification(
            Notification(name: .showAppearanceSettings),
            now: 1
        )
        XCTAssertTrue(presentation.isPresented, "Bottom-bar Appearance posts showAppearanceSettings")

        presentation.dismiss(now: 1.1)
        XCTAssertFalse(presentation.isPresented)

        presentation.handleArticleChromeUpdate(arguments: [], now: 1.11)
        presentation.handleArticleChromeUpdate(
            arguments: ["-startArticleShowAppearance"],
            now: 1.12
        )
        presentation.handleShowAppearanceNotification(
            Notification(name: .showAppearanceSettings),
            now: 1.13
        )
        XCTAssertFalse(
            presentation.isPresented,
            "onAppear / environment refresh / a leftover showAppearanceSettings must not auto-reopen after dismiss"
        )

        presentation.present(now: 1.1 + osrsArticleAppearancePresentation.redisplaySuppressionInterval + 0.01)
        XCTAssertTrue(presentation.isPresented, "A later user open must still present")
    }

    func testLaunchAppearanceArgumentIsConsumedOnce() {
        let presentation = osrsArticleAppearancePresentation()
        presentation.handleArticleChromeUpdate(
            arguments: ["-startArticleShowAppearance", "-highlightFloorNumberingOnAppearance"],
            now: 2
        )
        XCTAssertTrue(presentation.isPresented)
        XCTAssertTrue(presentation.highlightFloorNumbering)

        presentation.dismiss(now: 2.2)
        XCTAssertFalse(presentation.isPresented)
        XCTAssertFalse(presentation.highlightFloorNumbering)

        presentation.handleArticleChromeUpdate(
            arguments: ["-startArticleShowAppearance", "-highlightFloorNumberingOnAppearance"],
            now: 2.2 + osrsArticleAppearancePresentation.redisplaySuppressionInterval + 0.05
        )
        XCTAssertFalse(
            presentation.isPresented,
            "The launch-arg open is a one-shot; article onAppear after dismiss must stay dismissed"
        )
    }

    func testSheetBindingWriteFalseClearsPresentIntent() {
        let presentation = osrsArticleAppearancePresentation()
        presentation.present(now: 3)
        presentation.isPresentedBinding.wrappedValue = false
        XCTAssertFalse(presentation.isPresented)
        presentation.isPresentedBinding.wrappedValue = true
        XCTAssertFalse(
            presentation.isPresented,
            "Interactive dismiss must suppress an immediate re-present write"
        )
    }

    func testArticleHostedAppearancePathDismissStaysDismissed() {
        let themeManager = osrsThemeManager(userDefaults: isolatedDefaults())
        let appState = AppState()
        let overlay = GlobalOverlayManager()
        let url = URL(string: "https://oldschool.runescape.wiki/w/Varrock")!
        let destination = ArticleDestination(title: "Varrock", url: url)
        let identity = destination.navigationIdentity
        appState.selectedTab = .search
        appState.searchNavigationStack = [.article(destination)]

        let host = UIHostingController(
            rootView: osrsArticleAppearanceTestHost(
                themeManager: themeManager,
                appState: appState,
                overlayManager: overlay,
                pageTitle: "Varrock",
                pageUrl: url,
                navigationIdentity: identity
            )
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        NotificationCenter.default.post(name: .showAppearanceSettings, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertNotNil(
            host.presentedViewController,
            "Article chrome present path must show the Appearances sheet"
        )

        let presented = host.presentedViewController
        presented?.dismiss(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertNil(
            host.presentedViewController,
            "Interactive dismiss must stay dismissed through an extra article view update"
        )

        NotificationCenter.default.post(name: .showAppearanceSettings, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertNotNil(
            host.presentedViewController,
            "Opening Appearances again after the dismiss settled must still work"
        )
        host.presentedViewController?.dismiss(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        window.isHidden = true
        window.rootViewController = nil
    }

    func testThemeSwitchFromArticleAppearanceKeepsDocumentAndChrome() {
        XCTAssertFalse(
            osrsArticleAppearanceThemeApply.shouldRestoreSceneCompositorOnThemePaint(
                isLiveSelectionChange: true
            )
        )
        XCTAssertTrue(
            osrsArticleAppearanceThemeApply.shouldRestoreSceneCompositorOnThemePaint(
                isLiveSelectionChange: false
            )
        )

        let themeManager = osrsThemeManager(userDefaults: isolatedDefaults())
        themeManager.setTheme(.osrsLight)
        let overlay = GlobalOverlayManager()
        let url = URL(string: "https://oldschool.runescape.wiki/w/Varrock")!
        let identity = "article-appearance-theme"
        let viewModel = ArticleViewModel(pageUrl: url, pageTitle: "Varrock")
        let html = String(
            repeating: "<p id='mw-content-text'>Varrock article body for live theme paint.</p>",
            count: 8
        )
        viewModel.seedCommittedArticleHTMLForTests(html, theme: osrsLightTheme())
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        viewModel.webView = webView

        overlay.showArticleBottomBar(owner: identity) {
            osrsArticleBottomBar(
                onSaveAction: {},
                onFindInPageAction: {},
                onAppearanceAction: { viewModel.performAppearanceAction() },
                onContentsAction: {},
                isBookmarked: false,
                saveState: .notSaved,
                saveProgress: 0,
                hasTableOfContents: true
            )
        }

        let presentation = osrsArticleAppearancePresentation()
        presentation.present(now: 10)

        let selections: [osrsThemeSelection] = [.osrsDark, .osrsLight, .automatic, .osrsDark, .automatic]
        for selection in selections {
            themeManager.setTheme(selection)
            osrsArticleAppearanceThemeApply.applyToExistingArticle(
                theme: themeManager.currentTheme,
                themeManager: themeManager,
                viewModel: viewModel
            )
            XCTAssertTrue(viewModel.hasCommittedArticleHTML, "Theme apply must keep committed HTML")
            XCTAssertTrue(
                viewModel.webView === webView,
                "Theme apply must keep the existing article WKWebView"
            )
            XCTAssertTrue(
                osrsArticleAppearanceThemeApply.articleChromeIsClaimed(
                    overlayManager: overlay,
                    articleIdentity: identity
                ),
                "Article chrome must remain claimed after \(selection.rawValue)"
            )
            XCTAssertEqual(viewModel.webViewRenderGeneration, 0, "Must not rebuild the article surface")
        }

        presentation.dismiss(now: 11)
        XCTAssertFalse(presentation.isPresented)
        XCTAssertTrue(viewModel.hasCommittedArticleHTML)
        XCTAssertTrue(viewModel.webView === webView)
        XCTAssertTrue(
            osrsArticleAppearanceThemeApply.articleChromeIsClaimed(
                overlayManager: overlay,
                articleIdentity: identity
            )
        )
        _ = webView
    }

    func testLiveThemeSelectionDoesNotAskForSceneRestore() throws {
        let root = repositoryRoot()
        let themeSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/OSRSThemeManager.swift"),
            encoding: .utf8
        )
        let articleSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            themeSource.contains("osrsArticleAppearanceThemeApply.shouldRestoreSceneCompositorOnThemePaint"),
            "Live theme picks must consult the article appearance compositor policy"
        )
        XCTAssertTrue(themeSource.contains("isLiveSelectionChange: true"))
        XCTAssertTrue(themeSource.contains("paintWindows(restoreSceneCompositor:"))
        XCTAssertTrue(articleSource.contains("appearancePresentation.handleShowAppearanceNotification"))
        XCTAssertTrue(articleSource.contains("appearancePresentation.handleArticleChromeUpdate()"))
        XCTAssertTrue(articleSource.contains("appearancePresentation.dismiss()"))
        XCTAssertTrue(articleSource.contains("applyAppearanceThemeToExistingArticle()"))
        XCTAssertFalse(
            articleSource.contains("isShowingAppearanceSettings = true"),
            "Article chrome must not flip a raw presented flag on appear"
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "osrsArticleAppearancePresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("platforms/ios/osrswiki.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
    }
}

private struct osrsArticleAppearanceTestHost: View {
    @ObservedObject var themeManager: osrsThemeManager
    @ObservedObject var appState: AppState
    @ObservedObject var overlayManager: GlobalOverlayManager
    let pageTitle: String
    let pageUrl: URL
    let navigationIdentity: String

    var body: some View {
        ArticleView(
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            navigationIdentity: navigationIdentity,
            collapseTablesEnabled: false,
            managesMainTabBarVisibility: false
        )
        .environmentObject(themeManager)
        .environmentObject(appState)
        .environment(\.osrsTheme, themeManager.currentTheme)
        .overlayManager(overlayManager)
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
    }
}

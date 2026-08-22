import XCTest
@testable import osrswiki

final class osrsArticleLoadRegressionContractTests: XCTestCase {
    func testFirstPaintPrewarmAndSwitcherPinWorkRemainIntact() throws {
        let root = try repositoryRoot()
        let htmlBuilder = try source(root, "platforms/ios/osrswiki/Services/osrsPageHtmlBuilder.swift")
        let viewModel = try source(root, "platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift")
        let articleView = try source(root, "platforms/ios/osrswiki/Views/ArticleView.swift")
        let prepared = try source(root, "platforms/ios/osrswiki/Services/osrsPreparedArticleWebViewStore.swift")
        let switcher = try source(root, "platforms/ios/osrswiki/Assets/web/switch_infobox.js")
        let firstViewport = try source(root, "platforms/ios/osrswiki/Assets/web/first_viewport_assets.js")
        let compositor = try source(root, "platforms/ios/osrswiki/Services/osrsSceneCompositor.swift")
        let themePaint = try source(root, "platforms/ios/osrswiki/Utils/osrsWebViewThemePaint.swift")
        let articleWebView = try source(root, "platforms/ios/osrswiki/Views/ArticleWebView.swift")

        XCTAssertTrue(htmlBuilder.contains("osrs-article-first-paint"))
        XCTAssertTrue(htmlBuilder.contains("background-color: #28221d"))
        XCTAssertTrue(htmlBuilder.contains("--body-main: #28221d"))
        XCTAssertTrue(htmlBuilder.contains("alegreya_bold.ttf"))
        XCTAssertTrue(prepared.contains("osrsPreparedArticleWebViewStore"))
        XCTAssertTrue(viewModel.contains("startLiveArticleAssetWarmIfNeeded"))
        XCTAssertTrue(viewModel.contains("osrsNotifyFirstViewComplete"))
        XCTAssertTrue(viewModel.contains("mustWriteDocument"))
        XCTAssertTrue(viewModel.contains("recoverBlankResume"))
        XCTAssertTrue(viewModel.contains("pendingArticleLoadIsReload = false"))
        XCTAssertFalse(viewModel.contains("pendingArticleLoadIsReload = true"))
        XCTAssertTrue(viewModel.contains("lastCommittedArticleHTML"))
        XCTAssertTrue(viewModel.contains("osrsForegroundHealthProbeMaxAttempts"))
        XCTAssertTrue(viewModel.contains("javascript-unavailable"))
        XCTAssertTrue(viewModel.contains("Recommitting cached article HTML"))
        XCTAssertTrue(viewModel.contains("osrsArticleWebKitRuntime.recycleProcessPool()"))
        XCTAssertTrue(viewModel.contains("isRefreshing && !needsContentProcessRecovery"))
        XCTAssertTrue(viewModel.contains("skipping loadHTMLString"))
        XCTAssertTrue(articleView.contains("hasCommittedArticleHTML"))
        XCTAssertTrue(articleView.contains("osrsResumeFrameOverlay.discard()"))
        let tabView = try source(root, "platforms/ios/osrswiki/Views/CustomMainTabView.swift")
        XCTAssertTrue(tabView.contains("osrsResumeFrameOverlay.discard()"))
        XCTAssertFalse(articleView.contains("needsContentProcessRecovery = false"))
        let newsView = try source(root, "platforms/ios/osrswiki/Views/NewsView.swift")
        XCTAssertTrue(newsView.contains("osrsResumedNavigationHost"))
        XCTAssertTrue(switcher.contains("lockSwitcherMinBlockSize"))
        XCTAssertTrue(switcher.contains("stabilizeSwitcherScrollPin"))
        XCTAssertTrue(switcher.contains("bindSwitcherViewportPin"))
        XCTAssertTrue(switcher.contains("osrsSwitcherScrollingElement"))
        XCTAssertTrue(firstViewport.contains("osrsWatchFirstViewComplete"))
        XCTAssertTrue(firstViewport.contains("__osrsLayoutStability"))
        XCTAssertTrue(compositor.contains("stripNonImageLayerContents"))
        XCTAssertTrue(compositor.contains("isUniformFill"))
        XCTAssertTrue(themePaint.contains("placeholderHTML"))
        XCTAssertTrue(themePaint.contains("loadPlaceholderIfEmpty"))
        XCTAssertTrue(themePaint.contains("documentStartPaintScript"))
        XCTAssertTrue(themePaint.contains("webView.isOpaque = false"))
        XCTAssertTrue(htmlBuilder.contains("usesDarkTheme"))
        XCTAssertTrue(htmlBuilder.contains("html:not(.theme-osrs-dark)"))
        XCTAssertTrue(articleWebView.contains("Theme-paint before any other WK configuration"))
        XCTAssertTrue(viewModel.contains("osrsAppRoot.themeManager.currentTheme"))
        XCTAssertFalse(viewModel.contains("loadArticle(theme: osrsLightTheme()"))
        let proxy = try source(root, "platforms/ios/osrswiki/Extensions/ArticleViewModel+ProxyIntegration.swift")
        XCTAssertFalse(proxy.contains("loadArticle(theme: osrsLightTheme()"))
        XCTAssertTrue(proxy.contains("osrsAppRoot.themeManager.currentTheme"))
        let launchPlist = try source(root, "platforms/ios/osrswiki/Info.plist")
        XCTAssertTrue(launchPlist.contains("osrsLaunchBackground"))
        XCTAssertTrue(launchPlist.contains("UILaunchStoryboardName"))
        XCTAssertTrue(launchPlist.contains("LaunchScreen"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "platforms/ios/osrswiki/LaunchScreen.storyboard"
                ).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "platforms/ios/osrswiki/Assets.xcassets/osrsLaunchBackground.colorset/Contents.json"
                ).path
            )
        )
        XCTAssertTrue(themePaint.contains("isUnpaintedSystemFill"))
        XCTAssertTrue(themePaint.contains("isUniformFill"))
        XCTAssertTrue(themePaint.contains("meanLuminance >= 220"))
        XCTAssertTrue(articleWebView.contains("loadPlaceholderIfEmpty"))
        let warmer = try source(root, "platforms/ios/osrswiki/Services/osrsWebViewProcessWarmer.swift")
        XCTAssertTrue(warmer.contains("func recycleProcessPool()"))
        XCTAssertTrue(warmer.contains("WKWebsiteDataStore.default()"))
        XCTAssertTrue(warmer.contains("osrsPreparedArticleWebViewStore.shared.removeAll()"))
        let tabBar = try source(root, "platforms/ios/osrswiki/Extensions/UITabBar+FastRestore.swift")
        XCTAssertTrue(tabBar.contains("cover.clipsToBounds = behind"))
        XCTAssertTrue(tabBar.contains("cover.layer.masksToBounds = behind"))
        let sceneDelegate = try source(root, "platforms/ios/osrswiki/Services/osrsSceneDelegate.swift")
        XCTAssertTrue(sceneDelegate.contains("reconnectSwiftUIHostToWindow()"))
        XCTAssertTrue(sceneDelegate.contains("ArticleView @StateObject"))
        XCTAssertTrue(compositor.contains("reparentWebViews(in:"))
        XCTAssertTrue(compositor.contains("osrsResumeFrameOverlay"))
        XCTAssertTrue(compositor.contains("captureResumeFrame"))
        XCTAssertTrue(compositor.contains("osrsResumeCoverWindow"))
        XCTAssertTrue(compositor.contains("UIColor(patternImage"))
        XCTAssertTrue(compositor.contains("revealWhenLiveWebViewPaints"))
        XCTAssertTrue(compositor.contains("static func discard()"))
        XCTAssertTrue(compositor.contains("install(on: window)"))
        XCTAssertTrue(compositor.contains("makeKeyAndVisible()"))
        XCTAssertFalse(compositor.contains("osrsResumedArticleViewController"))
    }

    func testUnpaintedSystemFillIsWhiteNotThemedDark() {
        XCTAssertTrue(osrsWebViewThemePaint.isUnpaintedSystemFill(solidImage(color: .white)))
        XCTAssertFalse(
            osrsWebViewThemePaint.isUnpaintedSystemFill(
                solidImage(color: UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1))
            )
        )
        XCTAssertFalse(
            osrsWebViewThemePaint.isUnpaintedSystemFill(
                solidImage(color: UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1))
            )
        )
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(solidImage(color: UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1))))
        XCTAssertFalse(osrsWebViewThemePaint.isUniformFill(contrastingImage()))
    }

    private func contrastingImage() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
    }

    private func solidImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
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

    private func source(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

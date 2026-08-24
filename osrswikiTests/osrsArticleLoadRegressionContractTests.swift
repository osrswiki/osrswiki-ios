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

        XCTAssertTrue(viewModel.contains("recommitCachedArticleAfterBackground"))
        XCTAssertTrue(viewModel.contains("wakeLiveArticleWebView"))
        let recommitBody = viewModel
            .components(separatedBy: "func recommitCachedArticleAfterBackground")
            .dropFirst()
            .first?
            .components(separatedBy: "func recoverRenderedDocumentAfterBackground")
            .first ?? ""
        XCTAssertFalse(
            recommitBody.contains("wakeLiveArticleWebView"),
            "Ordinary resume must not reparent WK; that parks GPU tiles after a healthy DOM"
        )
        XCTAssertTrue(viewModel.contains("noteApplicationDidEnterBackground"))
        XCTAssertTrue(viewModel.contains("pendingBackgroundDocumentRecommit"))
        XCTAssertTrue(viewModel.contains("lastDocumentRecommitAt"))
        XCTAssertTrue(articleView.contains("noteApplicationDidEnterBackground()"))
        XCTAssertTrue(articleView.contains("recommitCachedArticleAfterBackground(force:"))
        XCTAssertTrue(articleView.contains("forceDocumentRecommit"))
        XCTAssertTrue(articleView.contains("onChange(of: viewModel.isRefreshing)"))
        XCTAssertTrue(htmlBuilder.contains("osrs-article-first-paint"))
        XCTAssertTrue(htmlBuilder.contains("background-color: #28221d"))
        XCTAssertTrue(htmlBuilder.contains("--body-main: #28221d"))
        XCTAssertTrue(htmlBuilder.contains("alegreya_bold.ttf"))
        XCTAssertTrue(htmlBuilder.contains("osrsActivateDeferredStylesheet"))
        XCTAssertTrue(htmlBuilder.contains("data-osrs-css=\"deferred\""))
        XCTAssertTrue(htmlBuilder.contains("LOAD-MINMAX html_ready"))
        XCTAssertTrue(prepared.contains("osrsArticlePreloadPolicy"))
        XCTAssertTrue(prepared.contains("speculativeLiveArticlePreloadsEnabled = false"))
        XCTAssertTrue(prepared.contains("guard osrsArticlePreloadPolicy.speculativeLiveArticlePreloadsEnabled else"))
        let coordinatorSource = try source(root, "platforms/ios/osrswiki/Services/osrsArticleDocumentCoordinator.swift")
        XCTAssertTrue(coordinatorSource.contains("guard osrsArticlePreloadPolicy.speculativeLiveArticlePreloadsEnabled else"))
        XCTAssertTrue(coordinatorSource.contains("policy-disabled"))
        XCTAssertTrue(coordinatorSource.contains("speculativeLiveArticlePreloadsEnabled else { return }"))
        XCTAssertTrue(viewModel.contains("startLiveArticleAssetWarmIfNeeded"))
        XCTAssertTrue(viewModel.contains("osrsNotifyFirstViewComplete"))
        XCTAssertTrue(viewModel.contains("revealing via first-view fallback"))
        XCTAssertFalse(viewModel.contains("Page rendering timed out. Please try reloading."))
        XCTAssertTrue(viewModel.contains("mustWriteDocument"))
        XCTAssertTrue(viewModel.contains("recoverBlankResume"))
        XCTAssertTrue(viewModel.contains("pendingArticleLoadIsReload = false"))
        XCTAssertFalse(viewModel.contains("pendingArticleLoadIsReload = true"))
        XCTAssertTrue(viewModel.contains("lastCommittedArticleHTML"))
        XCTAssertTrue(viewModel.contains("osrsForegroundHealthProbeMaxAttempts"))
        XCTAssertTrue(viewModel.contains("javascript-unavailable"))
        XCTAssertTrue(viewModel.contains("Recommitting cached article HTML"))
        XCTAssertTrue(viewModel.contains("applyingLivePaintPreferences(cachedHTML, theme: theme)"))
        XCTAssertTrue(viewModel.contains("pendingLiveThemePaintAfterReload"))
        let probeBody = viewModel
            .components(separatedBy: "private func probeRenderedSnapshotIfNeeded")
            .dropFirst()
            .first?
            .components(separatedBy: "static func osrsSnapshotLooksCompositorBlank")
            .first ?? ""
        XCTAssertTrue(probeBody.contains("isUnpaintedSystemFill"))
        XCTAssertTrue(probeBody.contains("clearFrozenWebKitScrollSnapshot"))
        XCTAssertFalse(
            probeBody.contains("markNeedsContentProcessRecovery"),
            "A frozen WKScrollView snapshot is not a dead document"
        )
        XCTAssertFalse(
            probeBody.contains("isUniformFill(image)"),
            "Themed parchment/dark must not trigger a blank-resume rebuild"
        )
        XCTAssertFalse(
            probeBody.contains("recoverBlankResume"),
            "Snapshot recovery must keep article chrome via loadArticle, not recoverBlankResume"
        )
        XCTAssertTrue(viewModel.contains("osrsArticleWebKitRuntime.recycleProcessPool()"))
        XCTAssertTrue(viewModel.contains("isRefreshing && !needsContentProcessRecovery"))
        XCTAssertTrue(viewModel.contains("skipping loadHTMLString"))
        XCTAssertTrue(viewModel.contains("hasCommittedArticleHTML"))
        XCTAssertTrue(articleView.contains("osrsResumeFrameOverlay.discard()"))
        let tabView = try source(root, "platforms/ios/osrswiki/Views/CustomMainTabView.swift")
        XCTAssertTrue(tabView.contains("osrsResumeFrameOverlay.discard()"))
        XCTAssertTrue(articleView.contains("needsContentProcessRecovery = false"))
        XCTAssertTrue(articleView.contains("loadArticle(theme: osrsTheme, isReload: true)"))
        let newsView = try source(root, "platforms/ios/osrswiki/Views/NewsView.swift")
        XCTAssertTrue(newsView.contains("osrsResumedNavigationHost"))
        XCTAssertTrue(switcher.contains("lockSwitcherMinBlockSize"))
        XCTAssertTrue(switcher.contains("stabilizeSwitcherScrollPin"))
        XCTAssertTrue(switcher.contains("bindSwitcherViewportPin"))
        XCTAssertTrue(switcher.contains("osrsSwitcherScrollingElement"))
        XCTAssertTrue(firstViewport.contains("osrsWatchFirstViewComplete"))
        XCTAssertTrue(firstViewport.contains("__osrsLayoutStability"))
        XCTAssertTrue(firstViewport.contains("osrs-first-view-complete"))
        XCTAssertTrue(firstViewport.contains("Event: FirstViewPainted"))
        XCTAssertTrue(firstViewport.contains("Event: FirstViewportSettled"))
        XCTAssertTrue(firstViewport.contains("__osrsFirstViewportSettled"))
        XCTAssertTrue(firstViewport.contains("osrs-first-viewport-settled"))
        XCTAssertTrue(firstViewport.contains("osrsWatchFirstViewportSettled") || firstViewport.contains("reportSettled"))
        XCTAssertTrue(articleWebView.contains("Event: FirstViewPainted"))
        XCTAssertTrue(articleWebView.contains("Event: FirstViewportSettled"))
        XCTAssertTrue(articleWebView.contains("completeLoadingWithBodyReveal"))
        XCTAssertTrue(articleWebView.contains("Event: FirstViewportSettled"))
        XCTAssertTrue(articleWebView.contains("markFirstViewportSettled"))
        XCTAssertTrue(viewModel.contains("LOAD-MINMAX first_viewport_settled"))
        XCTAssertTrue(viewModel.contains("articleOpenAt"))
        XCTAssertTrue(viewModel.contains("markFirstViewportSettled"))
        XCTAssertTrue(
            articleWebView.contains("Event: FirstViewportSettled:"),
            "loadGeneration prefixes must include FirstViewportSettled"
        )
        // Settled is stopwatch-only: must not share the reveal hasPrefix gate.
        XCTAssertNil(
            articleWebView.range(
                of: #"FirstViewportSettled[\s\S]{0,160}?completeLoadingWithBodyReveal"#,
                options: .regularExpression
            ),
            "FirstViewportSettled must not call completeLoadingWithBodyReveal"
        )
        let revealGate = articleWebView
            .components(separatedBy: "private func handleRenderTimelineMessage")
            .dropFirst()
            .first?
            .components(separatedBy: "private static func loadGeneration")
            .first ?? ""
        XCTAssertTrue(revealGate.contains("Event: FirstViewPainted"))
        XCTAssertTrue(revealGate.contains("Event: StylingScriptsComplete"))
        XCTAssertTrue(revealGate.contains("Event: FirstViewportSettled"))
        // The OR'd reveal branch must stay painted/styling only.
        XCTAssertTrue(
            revealGate.contains("message.hasPrefix(\"Event: FirstViewPainted\") || message.hasPrefix(\"Event: StylingScriptsComplete\")"),
            "Reveal hasPrefix list must remain FirstViewPainted / StylingScriptsComplete only"
        )
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
        let restoreResumeBody = sceneDelegate
            .components(separatedBy: "private func restoreResumedScene")
            .dropFirst()
            .first?
            .components(separatedBy: "private func reconnectSwiftUIHostToWindow")
            .first ?? ""
        XCTAssertTrue(restoreResumeBody.contains("reconnectSwiftUIHostToWindow()"))
        XCTAssertTrue(restoreResumeBody.contains("detachFromKeyWindowForResume"))
        XCTAssertTrue(restoreResumeBody.contains("osrsSceneCompositor.restore"))
        XCTAssertFalse(
            restoreResumeBody.contains("bounceWindowOutOfSnapshotMode"),
            "A replacement UIWindow plus windowScene=nil left Safari resume as theme fill"
        )
        XCTAssertTrue(sceneDelegate.contains("nudgeCompositor(on: windowScene)"))
        XCTAssertTrue(
            restoreResumeBody.contains("requestSceneSessionActivation"),
            "Safari resume must activate this scene session so SpringBoard drops the parked snapshot"
        )
        XCTAssertTrue(restoreResumeBody.contains("window.windowLevel = .statusBar"))
        XCTAssertFalse(
            restoreResumeBody.contains("window.windowScene = nil")
                || restoreResumeBody.contains(".windowScene = nil"),
            "Nilling windowScene left Safari resume as parchment"
        )
        XCTAssertFalse(
            sceneDelegate.contains("hostView.removeFromSuperview()"),
            "Detaching the already-attached SwiftUI host parks WK GPU tiles on resume"
        )
        XCTAssertTrue(sceneDelegate.contains("hostView.superview !== container.view"))
        XCTAssertTrue(compositor.contains("reparentWebViews(in:"))
        XCTAssertTrue(compositor.contains("osrsResumeFrameOverlay"))
        XCTAssertTrue(compositor.contains("captureResumeFrame"))
        XCTAssertTrue(compositor.contains("osrsResumeCoverWindow"))
        XCTAssertTrue(compositor.contains("revealWhenLiveWebViewPaints"))
        XCTAssertTrue(compositor.contains("static func discard()"))
        XCTAssertTrue(compositor.contains("installOnWindowLayer"))
        XCTAssertTrue(compositor.contains("hasCapturedFrame"))
        XCTAssertTrue(compositor.contains("Keep window-layer resume pixels"))
        XCTAssertFalse(
            compositor.contains("!containsWebView(view) && layerContentsLookUniform(view)"),
            "skipping every WK ancestor left the DropShadow snapshot covering the LCD"
        )
        XCTAssertTrue(compositor.contains("stripSwitcherSnapshot(from:"))
        XCTAssertTrue(compositor.contains("wakeLiveArticleWebView"))
        XCTAssertTrue(compositor.contains("isLargeSnapshotCover"))
        XCTAssertTrue(compositor.contains("parkPreparedWarmerHosts"))
        XCTAssertTrue(compositor.contains("containsLiveArticleWebView"))
        XCTAssertTrue(prepared.contains("detachFromKeyWindowForResume"))
        let restoreBody = compositor
            .components(separatedBy: "static func restore(_ window: UIWindow)")
            .dropFirst()
            .first?
            .components(separatedBy: "static func captureResumeFrame")
            .first ?? ""
        XCTAssertTrue(restoreBody.contains("nudgeLayer(root.view)"))
        XCTAssertTrue(restoreBody.contains("installOnWindowLayer"))
        XCTAssertTrue(restoreBody.contains("installPassthroughResumePixels"))
        XCTAssertTrue(compositor.contains("isUserInteractionEnabled = false"))
        XCTAssertTrue(compositor.contains("osrs_resume_passthrough_frame"))
        XCTAssertTrue(compositor.contains("blitPassthroughResumePixels"))
        XCTAssertTrue(compositor.contains("osrsHitTarget"))
        XCTAssertTrue(compositor.contains("adoptLiveRootIfNeeded"))
        XCTAssertTrue(compositor.contains("hasAdoptedLiveRoot"))
        XCTAssertTrue(compositor.contains("osrsAppSceneViewController"))
        XCTAssertTrue(compositor.contains("onAdoptedPrimary"))
        XCTAssertTrue(compositor.contains("overlay.makeKey()"))
        XCTAssertTrue(compositor.contains("live.isHidden = true"))
        XCTAssertTrue(compositor.contains("makeOverlayKeyIfInstalled"))
        XCTAssertTrue(compositor.contains("imageView.image = image"))
        XCTAssertTrue(compositor.contains("passthrough retained"))
        XCTAssertTrue(
            sceneDelegate.contains("osrsResumeFrameOverlay.makeOverlayKeyIfInstalled()"),
            "Resume nudge must not steal key from the LCD overlay"
        )
        XCTAssertFalse(
            restoreBody.contains("reparentWebViews(in: root.view)"),
            "Reparenting WK on every restore parks GPU tiles after a healthy DOM"
        )
        XCTAssertTrue(
            restoreBody.contains("window.layer.contents = nil"),
            "SpringBoard switcher snapshot on UIWindow.layer.contents covers the live WK tree"
        )
        XCTAssertFalse(
            restoreBody.contains("osrsResumeFrameOverlay.discard()"),
            "Discarding captured resume pixels on restore left LCD as theme fill"
        )
        XCTAssertFalse(
            restoreBody.contains("stripSwitcherSnapshot(from: window)"),
            "Nilling window contents every frame keeps iOS 26 in empty-snapshot mode"
        )
        XCTAssertFalse(
            restoreBody.contains("detachFromKeyWindowForResume"),
            "Detaching the prepared warmer from restore() parked the live article host"
        )
        XCTAssertFalse(compositor.contains("takeSnapshot(with:"))
        XCTAssertTrue(compositor.contains("install(on root:"))
        XCTAssertFalse(compositor.contains("paintWindowLayer"))
        XCTAssertFalse(compositor.contains("installCoverWindow"))
        XCTAssertTrue(compositor.contains("osrsSceneCompositorLooksBlank must not be posted from restore()"))
        XCTAssertFalse(compositor.contains("osrsResumedArticleViewController"))
    }


    func testLiveInlineFirstPaintCssFlagWired() throws {
        let root = try repositoryRoot()
        let prefs = try source(root, "platforms/ios/osrswiki/Services/osrsLoadPerformancePrefs.swift")
        XCTAssertTrue(prefs.contains("static var inlineLiveFirstPaintCss: Bool = true"))
        let coord = try source(root, "platforms/ios/osrswiki/Services/osrsArticleDocumentCoordinator.swift")
        XCTAssertTrue(coord.contains("inlineFirstPaintCss: osrsLoadPerformancePrefs.inlineLiveFirstPaintCss"))
        let loader = try source(root, "platforms/ios/osrswiki/Services/osrsPageContentLoader.swift")
        XCTAssertTrue(loader.contains("inlineFirstPaintCss: Bool = osrsLoadPerformancePrefs.inlineLiveFirstPaintCss"))
        let viewModel = try source(root, "platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift")
        XCTAssertTrue(viewModel.contains("inlineFirstPaintCss: osrsLoadPerformancePrefs.inlineLiveFirstPaintCss"))
        let htmlBuilder = try source(root, "platforms/ios/osrswiki/Services/osrsPageHtmlBuilder.swift")
        XCTAssertTrue(htmlBuilder.contains("inlineFirstPaintCss: Bool = false"))
        XCTAssertTrue(htmlBuilder.contains("data-osrs-inline-css"))
    }

    func testCriticalArticleBundleFlagDefaultsOnAndWired() throws {
        let root = try repositoryRoot()
        let prefs = try source(root, "platforms/ios/osrswiki/Services/osrsLoadPerformancePrefs.swift")
        XCTAssertTrue(prefs.contains("static var useCriticalArticleBundle: Bool = true"))
        let builder = try source(root, "platforms/ios/osrswiki/Services/osrsPageHtmlBuilder.swift")
        XCTAssertTrue(builder.contains("osrsLoadPerformancePrefs.useCriticalArticleBundle"))
        XCTAssertTrue(builder.contains("criticalArticleBundleAsset = \"styles/critical-article.min.css\""))
        let bundlePath = root.appendingPathComponent("shared/css/critical-article.min.css")
        let css = try String(contentsOf: bundlePath, encoding: .utf8)
        XCTAssertTrue(css.contains("AUTO-GENERATED"))
        XCTAssertTrue(css.contains("infobox-bonuses") || css.contains("table-layout"))
    }


    func testTask8BonusesMinCellGuardrailProbeAndAntiCrushCssLocked() throws {
        let root = try repositoryRoot()
        let probe = try String(
            contentsOf: root.appendingPathComponent("tools/qa/bonuses-min-cell-guardrail-probe.js"),
            encoding: .utf8
        )
        XCTAssertTrue(probe.contains("table.infobox-bonuses"))
        XCTAssertTrue(probe.contains("minW >= 28"))
        XCTAssertTrue(probe.contains("getBoundingClientRect"))
        XCTAssertTrue(probe.contains("minCellWidth"))

        let guide = try String(
            contentsOf: root.appendingPathComponent("tools/qa/article-load-fvs-task8-guardrail.md"),
            encoding: .utf8
        )
        XCTAssertTrue(guide.contains("bonuses-min-cell-guardrail-probe.js"))
        XCTAssertTrue(guide.contains("Abyssal whip"))

        let fixesPath = root.appendingPathComponent("shared/css/fixes.css")
        let fixes = try String(contentsOf: fixesPath, encoding: .utf8)
        XCTAssertTrue(fixes.contains("--osrs-bonuses-min-inline-size"))
        XCTAssertTrue(fixes.contains("table.infobox-bonuses:not(.main-infobox)"))
        XCTAssertTrue(fixes.contains("min-width: var(--osrs-bonuses-min-inline-size)"))
    }

    func testFirstViewportSettledDoesNotTriggerReveal() throws {
        let root = try repositoryRoot()
        let articleWebView = try source(root, "platforms/ios/osrswiki/Views/ArticleWebView.swift")
        
        // Find the handleRenderTimelineMessage implementation
        let handleBody = articleWebView
            .components(separatedBy: "private func handleRenderTimelineMessage")
            .dropFirst()
            .first?
            .components(separatedBy: "private static func loadGeneration")
            .first ?? ""
        
        // Verify FirstViewportSettled handling exists
        XCTAssertTrue(handleBody.contains("Event: FirstViewportSettled"))
        
        // Verify FirstViewportSettled branch does NOT call completeLoadingWithBodyReveal
        let settledBranch = handleBody
            .components(separatedBy: "Event: FirstViewportSettled")
            .dropFirst()
            .first?
            .components(separatedBy: "} else if message.hasPrefix")
            .first?
            .components(separatedBy: "} else {")
            .first ?? ""
        
        XCTAssertFalse(
            settledBranch.contains("completeLoadingWithBodyReveal"),
            "FirstViewportSettled must NOT trigger body reveal (reveal remains FirstViewPainted only)"
        )
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

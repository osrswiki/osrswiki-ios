import UIKit
import WebKit
import XCTest
@testable import osrswiki

@MainActor
final class osrsHostThemeFillTests: XCTestCase {
    private var hostWindow: UIWindow?

    override func tearDown() {
        hostWindow?.isHidden = true
        hostWindow = nil
        super.tearDown()
    }

    func testOpaqueFillStaysOffWhileArticleWebViewIsStillPresent() {
        XCTAssertFalse(
            osrsHostThemeFill.shouldPaintOpaqueFill(liveArticleWebViewPresent: true),
            "A still-valid article WK must not sit under an opaque theme fill"
        )
        XCTAssertTrue(
            osrsHostThemeFill.shouldPaintOpaqueFill(liveArticleWebViewPresent: false),
            "Empty tabs still need the theme parchment when no article WK is live"
        )
    }

    /// TF42 whole-page fill (cycle 49): `apply(to:)` painted the full-screen
    /// `UITextEffectsWindow` (keyboard support window, above the scene window)
    /// opaque theme fill because it never contains an article WK. That opaque
    /// system window was the whole-page `#28221d` at Find/search/Name
    /// keyboard-second on device. Theme paint must skip non-app-content
    /// windows and clear any fill an earlier pass left on them.
    func testApplyNeverPaintsKeyboardSupportWindowOpaque() throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        guard let textEffectsClass = NSClassFromString("UITextEffectsWindow") as? UIWindow.Type else {
            throw XCTSkip("UITextEffectsWindow unavailable")
        }
        let window = textEffectsClass.init(frame: CGRect(x: 0, y: 0, width: 420, height: 912))
        defer { window.isHidden = true }

        XCTAssertFalse(
            osrsSceneCompositor.isAppContentWindow(window),
            "UITextEffectsWindow must never be classified as app content"
        )

        osrsHostThemeFill.apply(to: window, themeBackground: theme)
        XCTAssertFalse(
            window.isOpaque && window.backgroundColor == theme,
            "Theme paint must not make the keyboard support window an opaque fill"
        )

        // A pass that ran before the guard existed may have painted it; the
        // next apply must restore transparency.
        window.backgroundColor = theme
        window.isOpaque = true
        osrsHostThemeFill.apply(to: window, themeBackground: theme)
        XCTAssertNil(
            window.backgroundColor,
            "apply(to:) must clear a theme fill left on a non-app-content window"
        )
        XCTAssertFalse(window.isOpaque)
    }

    func testApplyClearsHostBackgroundOverLiveArticleWebViewAndKeepsItForEmptyHost() async throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)

        let empty = makeWindow(theme: theme, includeArticleWebView: false)
        osrsHostThemeFill.apply(to: empty, themeBackground: theme)
        XCTAssertEqual(
            osrsHostThemeFill.opaqueBackgroundColor(
                themeBackground: theme,
                liveArticleWebViewPresent: false
            ),
            theme
        )
        XCTAssertEqual(empty.backgroundColor, theme)
        XCTAssertEqual(empty.rootViewController?.view.backgroundColor, theme)

        let live = makeWindow(theme: theme, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        XCTAssertTrue(
            osrsSceneCompositor.containsLiveArticleWebView(live),
            "Shipped live-WK walk must see the hosted article web view"
        )

        let field = UITextField(frame: CGRect(x: 8, y: 700, width: 300, height: 44))
        field.accessibilityIdentifier = "native-calc-field-name"
        field.placeholder = "Name"
        live.rootViewController?.view.addSubview(field)
        XCTAssertTrue(field.becomeFirstResponder())

        osrsWebViewThemePaint.apply(to: webView, theme: osrsDarkTheme())
        osrsHostThemeFill.apply(to: live, themeBackground: theme)
        XCTAssertEqual(live.backgroundColor, UIColor.clear)
        XCTAssertEqual(live.rootViewController?.view.backgroundColor, UIColor.clear)

        let snapshot = snapshot(live)
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(snapshot),
            "Find/Name-style first responder must not leave a uniform theme fill over a live WK range=\(osrsWebViewThemePaint.luminanceRange(snapshot))"
        )
        field.resignFirstResponder()
        XCTAssertFalse(live.rootViewController?.view.isOpaque ?? true)
        XCTAssertTrue(
            isThemeParchment(webView.underPageBackgroundColor, expected: theme),
            "Host fill over a live WK must not isolate under-page to clear"
        )
    }

    func testApplyClearsThemeColoredHostViewsOverLiveArticleWebView() async throws {
        let theme = UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1)
        let live = makeWindow(theme: theme, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        let filler = UIView(frame: live.bounds)
        filler.backgroundColor = theme
        filler.isOpaque = true
        live.rootViewController?.view.insertSubview(filler, at: 0)

        osrsHostThemeFill.apply(to: live, themeBackground: theme)

        XCTAssertLessThan(
            filler.backgroundColor?.cgColor.alpha ?? 1,
            0.05,
            "Theme parchment UIView behind a live WK must not keep compositing on Find/keyboard"
        )
        XCTAssertFalse(filler.isOpaque)
        XCTAssertTrue(osrsSceneCompositor.containsLiveArticleWebView(live))
    }

    func testLoadedArticleThemePaintKeepsThemeParchmentBehindLiveTiles() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)

        osrsHostThemeFill.apply(to: live, themeBackground: themeColor)
        osrsWebViewThemePaint.apply(to: webView, theme: osrsDarkTheme())

        XCTAssertTrue(
            isThemeParchment(webView.underPageBackgroundColor, expected: themeColor),
            "Loaded apply() must keep theme parchment, not isolate under-page to clear"
        )
        XCTAssertFalse(webView.isOpaque)
        XCTAssertFalse(webView.scrollView.isOpaque)
        XCTAssertTrue(isThemeParchment(webView.backgroundColor, expected: themeColor))
        XCTAssertTrue(isThemeParchment(webView.scrollView.backgroundColor, expected: themeColor))
        XCTAssertFalse(live.rootViewController?.view.isOpaque ?? true)
        XCTAssertNil(firstParkedArticlePaint(in: live))
    }

    func testApplyLeavesWebKitInternalScrollViewsUnpainted() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        // WebKit's composited-overflow scrollport (WKChildScrollView) is a
        // plain UIScrollView the app does not own. Its scrolled content's
        // alpha reveals WebKit's own page tile below; an opaque app fill
        // there was the Uncharged-left parchment band (gutter spec Phase 16).
        let scroller = UIScrollView(frame: CGRect(x: 0, y: 0, width: 340, height: 287))
        scroller.backgroundColor = themeColor // stale fill from an earlier apply
        scroller.isOpaque = true
        webView.scrollView.addSubview(scroller)
        defer { scroller.removeFromSuperview() }

        osrsWebViewThemePaint.apply(to: webView, theme: osrsDarkTheme())

        XCTAssertTrue(
            isThemeParchment(webView.scrollView.backgroundColor, expected: themeColor),
            "The WKWebView's own scrollView keeps the theme underlay"
        )
        XCTAssertNil(
            scroller.backgroundColor,
            "WK-internal scroll views must stay unpainted (nil); an opaque theme fill covers WebKit's correctly painted page tile"
        )
        XCTAssertFalse(scroller.isOpaque)

        let nestedFill = UIView(frame: CGRect(x: 0, y: 0, width: 820, height: 38352))
        nestedFill.backgroundColor = themeColor
        nestedFill.isOpaque = true
        webView.scrollView.addSubview(nestedFill)
        defer { nestedFill.removeFromSuperview() }
        osrsWebViewThemePaint.apply(to: webView, theme: osrsDarkTheme())
        XCTAssertNil(
            nestedFill.backgroundColor,
            "Anonymous WK-internal UIViews must stay unpainted; iPad dumps showed 820x38352 opaque parchment covering GPU tiles"
        )
        XCTAssertFalse(nestedFill.isOpaque)
    }

    func testApplyLiveThemeOnLoadedArticleKeepsThemeParchment() async throws {
        let parchment = UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1)
        let live = makeWindow(theme: parchment, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        viewModel.setWebView(webView)
        osrsWebViewThemePaint.apply(to: webView, theme: osrsLightTheme())
        XCTAssertTrue(isThemeParchment(webView.underPageBackgroundColor, expected: parchment))

        viewModel.applyLiveTheme(osrsLightTheme(), themeManager: osrsThemeManager())

        XCTAssertTrue(
            isThemeParchment(webView.underPageBackgroundColor, expected: parchment),
            "applyLiveTheme must keep #E2DBC8 parchment under a loaded article"
        )
        XCTAssertTrue(isThemeParchment(webView.backgroundColor, expected: parchment))
        XCTAssertTrue(isThemeParchment(webView.scrollView.backgroundColor, expected: parchment))
        XCTAssertFalse(webView.isOpaque)
    }

    func testLoadedArticleThemePaintLeavesImportantHtmlBodyParchment() async throws {
        let parchment = UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1)
        let live = makeWindow(theme: parchment, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style id="osrs-article-first-paint">
        html, body { background-color: #e2dbc8 !important; color: #000000 !important; }
        </style>
        </head>
        <body>
        <h1>Varrock</h1>
        <p>The capital of Misthalin is a busy trade city with a palace.</p>
        </body>
        </html>
        """
        try await loadHTML(html, in: webView)
        osrsWebViewThemePaint.apply(to: webView, theme: osrsLightTheme())
        let computed = try await computedBodyBackground(webView)
        XCTAssertTrue(
            computed.contains("226, 219, 200") || computed.lowercased().contains("e2dbc8"),
            "Loaded apply() must not isolate html/body to transparent computed=\(computed)"
        )
        XCTAssertTrue(isThemeParchment(webView.underPageBackgroundColor, expected: parchment))
        let overlayId = try await evaluateString(
            "document.getElementById('osrs-overlay-page-fill') ? 'present' : 'missing'",
            in: webView
        )
        XCTAssertEqual(overlayId, "missing", "apply() must not inject overlay-page-fill isolate")
    }

    func testFindExpandKeepsHtmlBodyParchmentAndDoesNotIsolate() async throws {
        let parchment = UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1)
        let live = makeWindow(theme: parchment, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style id="osrs-article-first-paint">
        html, body { background-color: #e2dbc8 !important; color: #000000 !important; }
        </style>
        </head>
        <body>
        <h1>Varrock</h1>
        <p>The capital of Misthalin is a busy trade city with a palace.</p>
        </body>
        </html>
        """
        try await loadHTML(html, in: webView)
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        viewModel.setWebView(webView)
        viewModel.applyLiveTheme(osrsLightTheme(), themeManager: osrsThemeManager())

        let presented = expectation(description: "find expand completed")
        viewModel.performFindInPageAction {
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 5)
        defer { viewModel.hideFindInPageAction() }

        let overlayId = try await evaluateString(
            "document.getElementById('osrs-overlay-page-fill') ? 'present' : 'missing'",
            in: webView
        )
        XCTAssertEqual(
            overlayId,
            "missing",
            "Find must not inject overlay-page-fill isolate"
        )
        let computed = try await evaluateString(
            "getComputedStyle(document.body).backgroundColor",
            in: webView
        )
        XCTAssertTrue(
            computed.contains("226, 219, 200") || computed.lowercased().contains("e2dbc8"),
            "Find present must keep html/body parchment, not transparent computed=\(computed)"
        )
        XCTAssertTrue(
            isThemeParchment(webView.underPageBackgroundColor, expected: parchment),
            "Find preserve must keep theme parchment, not force under-page to clear"
        )
        XCTAssertNil(firstParkedArticlePaint(in: live))
    }

    func testFindKeepsInTreeArticlePaintWhenWebKitCompositorParksWithoutACoverWindow() async throws {
        let theme = UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1)
        let live = makeWindow(theme: theme, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        viewModel.setWebView(webView)

        let presented = expectation(description: "find presented without parked paint")
        viewModel.performFindInPageAction {
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 5)
        defer { viewModel.hideFindInPageAction() }

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNil(
            firstParkedArticlePaint(in: live),
            "Find must not pin osrs_parked_article_paint over the live article"
        )
        XCTAssertNil(
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Find must not mint osrs_live_overlay_frame"
        )
        XCTAssertFalse(live is osrsResumeCoverWindow)
        XCTAssertTrue(osrsSceneCompositor.containsLiveArticleWebView(live))
        XCTAssertFalse(
            webView.scrollView.isHidden,
            "Hiding WKScrollView blanks the live tree for Name/search"
        )
        XCTAssertFalse(webView.isHidden)
        XCTAssertEqual(webView.alpha, 1, accuracy: 0.01)
    }

    func testPinReinstallsLastGoodWhenLiveSnapshotIsUniformThemeFillWithoutACoverWindow() async throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: theme, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        let windowsBefore = live.windowScene?.windows.count ?? 1
        let painted = UIGraphicsImageRenderer(bounds: live.bounds).image { ctx in
            UIColor.white.setFill()
            ctx.fill(live.bounds)
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 16, y: 48, width: 120, height: 180))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 180, y: 240, width: 90, height: 140))
        }
        XCTAssertFalse(osrsWebViewThemePaint.isUniformFill(painted))
        osrsSceneCompositor.rememberPaintedArticle(painted)

        let name = UITextField(frame: CGRect(x: 24, y: 96, width: 200, height: 36))
        name.accessibilityIdentifier = "native-calc-field-name"
        live.rootViewController?.view.addSubview(name)

        let pinned = expectation(description: "plant leftover last-good sibling")
        osrsSceneCompositor.pinParkedArticlePaint(from: webView) {
            pinned.fulfill()
        }
        await fulfillment(of: [pinned], timeout: 4)
        XCTAssertNotNil(
            firstParkedArticlePaint(in: live),
            "Sanity: leftover pin must be in the tree before overlay begin clears it"
        )

        osrsSceneCompositor.beginLiveOverlaySession()
        defer { osrsSceneCompositor.endLiveOverlaySession() }

        XCTAssertNil(
            firstParkedArticlePaint(in: live),
            "Overlay begin must clear osrs_parked_article_paint, not reinstall last-good"
        )
        XCTAssertNil(
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Find/search/Name must not mint osrs_live_overlay_frame"
        )
        XCTAssertFalse(live is osrsResumeCoverWindow)
        XCTAssertTrue(osrsSceneCompositor.containsLiveArticleWebView(live))
        XCTAssertEqual(
            live.windowScene?.windows.count ?? windowsBefore,
            windowsBefore,
            "Overlay begin must not mint a second UIWindow"
        )
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        viewModel.setWebView(webView)
        viewModel.preserveRenderedArticleDuringFind(webView)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(
            firstParkedArticlePaint(in: live),
            "preserveRenderedArticleDuringFind must not re-pin last-good"
        )
        let hitPoint = name.convert(CGPoint(x: 8, y: 8), to: live)
        let hit = live.hitTest(hitPoint, with: nil)
        XCTAssertFalse(hit is osrsResumeCoverWindow)
        XCTAssertTrue(
            hit === name || (hit?.isDescendant(of: name) ?? false),
            "Hits must still reach the live tree, not a cover window hit=\(String(describing: hit))"
        )
    }

    func testFindKeyboardOverlayDoesNotMintALastGoodCoverWindow() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)

        osrsSceneCompositor.beginLiveOverlaySession()
        defer { osrsSceneCompositor.endLiveOverlaySession() }

        XCTAssertNil(
            firstParkedArticlePaint(in: live),
            "Find/search/Name overlay must not pin osrs_parked_article_paint"
        )
        XCTAssertNil(
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Find/search/Name must not mint a last-good cover window over a live WK"
        )
        XCTAssertTrue(
            osrsSceneCompositor.containsLiveArticleWebView(live),
            "The article WK must stay in the live tree during Find/Name/search"
        )
        XCTAssertEqual(live.backgroundColor, UIColor.clear)
    }

    /// Cycle 51: the overlay fill was never WindowServer Metal above the
    /// scene tree; it was the theme-painted UITextEffectsWindow (cycle 49).
    /// The overlay session must keep the live tree visible with no bitmap
    /// cover window and no resume cover, and must leave the keyboard support
    /// window unpainted.
    func testLiveOverlaySessionKeepsLiveTreeWithNoCoverWindow() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        live.makeKeyAndVisible()
        osrsSceneCompositor.rememberPaintedArticle(from: live)
        let contentsBeforeBegin = webView.layer.contents as AnyObject?

        osrsSceneCompositor.beginLiveOverlaySession()
        defer { osrsSceneCompositor.endLiveOverlaySession() }

        XCTAssertFalse(live is osrsResumeCoverWindow)
        XCTAssertNil(
            firstParkedArticlePaint(in: live),
            "Overlay session must not pin osrs_parked_article_paint"
        )
        if contentsBeforeBegin == nil {
            XCTAssertNil(
                webView.layer.contents,
                "Overlay begin must not stamp last-good onto a WK whose contents were unset"
            )
            XCTAssertNil(
                webView.scrollView.layer.contents,
                "Overlay begin must not stamp last-good onto scrollView.layer.contents"
            )
        }
        XCTAssertNil(
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Overlay session must not mint osrs_live_overlay_frame"
        )
        XCTAssertTrue(osrsSceneCompositor.containsLiveArticleWebView(live))
        XCTAssertFalse(
            osrsSceneCompositor.shouldRestoreResumeCover(didLeaveToBackground: false)
        )
        let coverWindows = (live.windowScene?.windows ?? []).filter {
            $0 !== live && !osrsSceneCompositor.isAppContentWindow($0)
                && $0.isOpaque && $0.backgroundColor != nil && $0.isHidden == false
        }
        XCTAssertTrue(
            coverWindows.isEmpty,
            "Overlay session must not leave an opaque non-content window over the live tree"
        )
        let hit = live.hitTest(CGPoint(x: live.bounds.midX, y: live.bounds.midY), with: nil)
        XCTAssertFalse(hit is osrsResumeCoverWindow)
    }

    func testResumeCoverInstallsOnlyAfterTrueBackground() {
        XCTAssertFalse(
            osrsSceneCompositor.shouldRestoreResumeCover(didLeaveToBackground: false),
            "Find/keyboard resign-active must not mint osrsResumeCoverWindow"
        )
        XCTAssertTrue(
            osrsSceneCompositor.shouldRestoreResumeCover(didLeaveToBackground: true),
            "Real background resume still mints the cover"
        )
    }

    func testResumeLastGoodComesDownOnceLiveWebViewPaints() async throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: theme, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        live.makeKeyAndVisible()
        let painted = UIGraphicsImageRenderer(bounds: live.bounds).image { ctx in
            UIColor.white.setFill()
            ctx.fill(live.bounds)
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 16, y: 48, width: 120, height: 180))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 180, y: 240, width: 90, height: 140))
        }
        XCTAssertFalse(osrsWebViewThemePaint.isUniformFill(painted))
        osrsResumeFrameOverlay.rememberPaintedArticle(painted)
        XCTAssertTrue(
            osrsResumeFrameOverlay.hasCapturedFrame,
            "Sanity: contrasting last-good must be captured"
        )

        osrsSceneCompositor.noteDidEnterBackground()
        osrsResumeFrameOverlay.installOnWindowLayer(live)
        XCTAssertEqual(
            osrsSceneCompositor.layerContentsKind(live.layer.contents),
            "CGImage",
            "installOnWindowLayer must stamp last-good before live WK teardown"
        )
        XCTAssertTrue(
            osrsSceneCompositor.shouldRestoreResumeCover(didLeaveToBackground: true)
        )
        XCTAssertNotNil(
            osrsSceneCompositor.firstLiveArticleWebView(in: live),
            "Hosted article WK must remain in the test window"
        )

        osrsResumeFrameOverlay.revealWhenLiveWebViewPaints()
        XCTAssertTrue(
            osrsResumeFrameOverlay.liveArticleIsPainting(),
            "Hosted loaded article must count as painting so last-good can come down range=\(osrsWebViewThemePaint.luminanceRange(snapshot(live)))"
        )
        XCTAssertNil(
            osrsResumeFrameOverlay.firstPassthroughImageView(),
            "Passthrough UIImageView must come down once live WK is painting"
        )
        XCTAssertFalse(
            osrsResumeFrameOverlay.lastGoodIsCoveringLiveArticle,
            "window.layer last-good stamp must not stay over a painting WK"
        )
        XCTAssertEqual(
            osrsSceneCompositor.layerContentsKind(live.layer.contents),
            "nil",
            "window.layer.contents last-good stamp must come down once live WK paints"
        )
        osrsResumeFrameOverlay.discard()
        XCTAssertNil(osrsResumeFrameOverlay.firstPassthroughImageView())
    }

    func testDumpWindowOnLiveArticleReportsWKAndHitsStayOffCover() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        live.makeKeyAndVisible()

        osrsSceneCompositor.dumpWindow(live)

        let dumpURL = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("osrs-scene-dump.txt")
        let dump = try String(contentsOf: dumpURL, encoding: .utf8)
        XCTAssertTrue(dump.contains("WKWebView"), "TF 42 Find/search/Name dumps must still list WK")
        XCTAssertTrue(dump.contains("contents=set") || dump.contains("contents=nil"))
        XCTAssertTrue(dump.contains("overlay="))
        XCTAssertFalse(
            dump.contains("osrsResumeCoverWindow"),
            "Overlay-session dump of the live window must not be a cover window"
        )

        let points = [
            CGPoint(x: live.bounds.midX, y: 80),
            CGPoint(x: live.bounds.midX, y: live.bounds.midY),
            CGPoint(x: live.bounds.midX, y: max(live.bounds.maxY - 120, 80)),
        ]
        for point in points {
            let hit = live.hitTest(point, with: nil)
            XCTAssertFalse(
                hit is osrsResumeCoverWindow,
                "Hit at \(point) must stay on the live tree, not a cover"
            )
        }
        XCTAssertFalse(webView.isHidden)
        XCTAssertEqual(webView.alpha, 1, accuracy: 0.01)
        XCTAssertTrue(dump.contains("passthrough="), "Same-second dump must log cover passthrough")
        XCTAssertTrue(dump.contains("adopted="), "Same-second dump must log cover adopt")
        XCTAssertTrue(dump.contains("firstResponder="), "Same-second dump must log first responder")
        XCTAssertTrue(dump.contains("tabBar"), "Same-second dump must log tab-bar alpha")
        XCTAssertTrue(dump.contains("hit y=80"), "Same-second dump must log hit-test at y≈80")
        XCTAssertTrue(dump.contains("hit y=mid"), "Same-second dump must log mid-article hit-test")
        XCTAssertTrue(dump.contains("hit y=aboveKb"), "Same-second dump must log above-keyboard hit-test")
        XCTAssertTrue(dump.contains("kind="), "Same-second dump must log contents kind")
        XCTAssertTrue(dump.contains("keyClass="), "Same-second dump must log key window class")
        XCTAssertTrue(dump.contains("opaque="), "Same-second dump must log isOpaque")
        XCTAssertTrue(dump.contains("wkBackground="), "Same-second dump must log WK _isBackground")
        XCTAssertEqual(osrsSceneCompositor.layerContentsKind(nil), "nil")
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        XCTAssertEqual(
            osrsSceneCompositor.layerContentsKind(sample.cgImage),
            "CGImage",
            "Shipped contents-kind probe must name a CGImage stamp"
        )
    }

    func testBeginLiveOverlaySessionDumpsOnNestedSearchDepth() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        live.makeKeyAndVisible()
        for _ in 0..<8 {
            osrsSceneCompositor.endLiveOverlaySession()
        }

        osrsSceneCompositor.beginLiveOverlaySession()
        defer {
            osrsSceneCompositor.endLiveOverlaySession()
            osrsSceneCompositor.endLiveOverlaySession()
        }

        let dumpURL = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("osrs-scene-dump.txt")
        let first = try String(contentsOf: dumpURL, encoding: .utf8)
        XCTAssertTrue(
            first.contains("overlayDepth=1"),
            "Find present must dump at overlay depth 1"
        )

        try "stale-find-dump".write(to: dumpURL, atomically: true, encoding: .utf8)
        osrsSceneCompositor.beginLiveOverlaySession()
        let second = try String(contentsOf: dumpURL, encoding: .utf8)
        XCTAssertFalse(
            second.contains("stale-find-dump"),
            "Article-search after Find must rewrite dumpWindow, not reuse the depth 0→1 file"
        )
        XCTAssertTrue(
            second.contains("overlayDepth=2"),
            "Search/Name nested overlay must dump at depth ≥1, not only 0→1"
        )
        XCTAssertTrue(second.contains("kind="))
        XCTAssertTrue(second.contains("passthrough="))
        XCTAssertTrue(second.contains("firstResponder="))
    }

    func testDumpWindowCensusNamesAllContextsAndLiveCaptionComputedStyle() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadHTML(
            """
            <!doctype html>
            <html>
            <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
            <body style="visibility: visible; background: #28221d;">
            <table class="infobox infobox-switch infobox-bonuses" id="bonuses">
              <caption class="infobox-switch-buttons-caption">
                <div class="infobox-buttons" id="chargeRow">
                  <span class="button">Uncharged</span>
                  <span class="button">1</span>
                </div>
              </caption>
              <tbody><tr><th>Attack bonuses</th><td>+10</td></tr></tbody>
            </table>
            </body>
            </html>
            """,
            in: webView
        )
        live.makeKeyAndVisible()
        osrsSceneCompositor.dumpWindow(live)
        let dumpURL = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("osrs-scene-dump.txt")
        var dump = try String(contentsOf: dumpURL, encoding: .utf8)
        let cssDeadline = Date().addingTimeInterval(2)
        while Date() < cssDeadline,
              !dump.contains("btnCount="),
              !dump.contains("cssCap=no-wk"),
              !dump.contains("cssUncharged=") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            dump = (try? String(contentsOf: dumpURL, encoding: .utf8)) ?? dump
        }
        XCTAssertTrue(
            dump.contains("dumpCssV=js-first-v3"),
            "Installed dumpWindow must be the JS-first census, not stale-cache: \(dump.suffix(400))"
        )
        XCTAssertTrue(dump.contains("allCtx="), "C49-class dump must enumerate process CAContexts: \(dump.suffix(400))")
        XCTAssertTrue(dump.contains("winCtx="), "C49-class dump must map windows to context ids")
        XCTAssertTrue(
            dump.contains("unchargedY="),
            "Dump must lock a gutter sample to an Uncharged chip Y, not only y=148: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("btnCount="),
            "Hosted dump with a live article WK must count .button nodes, not cssCap=no-wk: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("cssFromPoint="),
            "Hosted dump must name the elementFromPoint node left of Uncharged: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("cssUncharged=") || dump.contains("cssCap=tag="),
            "Dump must include computed style of the live Uncharged caption/tabber node"
        )
        XCTAssertTrue(
            dump.contains("dumpTileV=owner-v2"),
            "Dump must stamp the Uncharged-Y IOSurface owner census: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("tileProbe="),
            "Dump must name the window Uncharged-left probe: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("tileOwner="),
            "Dump must name which WK contents layer owns Uncharged-left: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("cls=page")
                || dump.contains("cls=chip")
                || dump.contains("cls=scroll-snapshot")
                || dump.contains("cls=other")
                || dump.contains("cls=n/a"),
            "Tile owner must report frame class page|chip|scroll-snapshot, not caption CSS: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("dumpRemoteV=layer-v4"),
            "Dump must census the full window layer tree in paint order: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("bands="),
            "layer-v4 must sample band-only 4pt crops at Uncharged-Y per covering layer: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("bgExtends="),
            "Dump must name _backgroundExtendsBeyondPage at Find-up: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("remoteOwner="),
            "Dump must name covering contributing layers in paint order: \(dump.suffix(400))"
        )
        XCTAssertTrue(
            dump.contains("gutterDeepestParchment="),
            "layer-v4 must summarize the deepest parchment-opaque gutterL layer: \(dump.suffix(400))"
        )
        XCTAssertFalse(dump.contains("CARenderServerGetInfo"))
        XCTAssertFalse(dump.contains("GetClientProcessId"))
    }





    func testCoverMintingAndHostFillDecisionStayOnTheShippedPath() throws {
        let root = try repositoryRoot()
        let fill = try source(root, "platforms/ios/osrswiki/Services/osrsHostThemeFill.swift")
        let compositor = try source(root, "platforms/ios/osrswiki/Services/osrsSceneCompositor.swift")
        let tabView = try source(root, "platforms/ios/osrswiki/Views/CustomMainTabView.swift")
        let articleView = try source(root, "platforms/ios/osrswiki/Views/ArticleView.swift")
        let themeManager = try source(root, "platforms/ios/osrswiki/Models/OSRSThemeManager.swift")
        let sceneDelegate = try source(root, "platforms/ios/osrswiki/Services/osrsSceneDelegate.swift")

        XCTAssertTrue(fill.contains("shouldPaintOpaqueFill(liveArticleWebViewPresent:"))
        XCTAssertTrue(fill.contains("guard osrsSceneCompositor.isAppContentWindow(window)"))
        XCTAssertTrue(fill.contains("osrsResumeCoverWindow"))
        XCTAssertFalse(
            fill.contains("underPageBackgroundColor = UIColor.clear"),
            "Host fill must not isolate a loaded article WK to clear"
        )
        XCTAssertTrue(fill.contains("clearThemeColoredHostViews"))
        XCTAssertFalse(fill.contains("layer.contents = nil"))
        let viewModel = try source(root, "platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift")
        let preserve = viewModel
            .components(separatedBy: "func preserveRenderedArticleDuringFind")
            .dropFirst()
            .first?
            .components(separatedBy: "func ")
            .first ?? ""
        XCTAssertTrue(preserve.contains("osrsWebViewThemePaint.apply"))
        XCTAssertFalse(preserve.contains("isOpaque = true"))
        XCTAssertFalse(
            preserve.contains("underPageBackgroundColor = UIColor.clear"),
            "preserveRenderedArticleDuringFind must not force under-page to clear"
        )
        XCTAssertFalse(fill.contains("#if DEBUG"))
        XCTAssertFalse(fill.contains("shouldPreserveLiveHierarchy"))
        XCTAssertFalse(fill.contains("layer.contents = nil"))

        XCTAssertTrue(compositor.contains("installPassthroughResumePixels"))
        XCTAssertTrue(compositor.contains("class osrsResumeCoverWindow"))
        XCTAssertTrue(compositor.contains("adoptLiveRootIfNeeded"))
        XCTAssertTrue(compositor.contains("insertSubview(imageView, at: 0)"))
        XCTAssertFalse(compositor.contains("shouldPreserveLiveHierarchy() && !osrsHostThemeFill"))

        XCTAssertTrue(tabView.contains("osrsHostThemeFill.shouldPaintOpaqueFill"))
        XCTAssertTrue(articleView.contains("osrsHostThemeFill.shouldPaintOpaqueFill"))
        let app = try source(root, "platforms/ios/osrswiki/osrswikiApp.swift")
        XCTAssertTrue(app.contains("osrsHostThemeFill.shouldPaintOpaqueFill"))
        XCTAssertTrue(themeManager.contains("osrsHostThemeFill.apply(to:"))
        XCTAssertTrue(sceneDelegate.contains("osrsHostThemeFill.apply(to:"))
        let themePaint = try source(root, "platforms/ios/osrswiki/Utils/osrsWebViewThemePaint.swift")
        let applyBody = themePaint
            .components(separatedBy: "static func apply(to webView: WKWebView, theme:")
            .dropFirst()
            .first?
            .components(separatedBy: "static var keepCompositorAliveScript")
            .first ?? ""
        XCTAssertTrue(applyBody.contains("let compositorFill = pageColor"))
        XCTAssertFalse(
            applyBody.contains("UIColor.clear"),
            "Loaded apply() must not isolate compositor fill to clear"
        )
        XCTAssertFalse(themePaint.contains("osrs-overlay-page-fill"))
        XCTAssertFalse(themePaint.contains("background-color: transparent !important"))
        XCTAssertFalse(viewModel.contains("osrs-overlay-page-fill"))
        XCTAssertFalse(viewModel.contains("clearLoadedDocumentPageFillScript"))
        let begin = compositor
            .components(separatedBy: "static func beginLiveOverlaySession")
            .dropFirst()
            .first?
            .components(separatedBy: "static func endLiveOverlaySession")
            .first ?? ""
        XCTAssertTrue(begin.contains("osrsWebViewThemePaint.apply"))
        XCTAssertFalse(begin.contains("layer.contents = nil"))
        XCTAssertFalse(begin.contains("pinLiveArticleFrame"))
        XCTAssertFalse(
            begin.contains("pinParkedArticlePaint(from:"),
            "Find/search/Name overlay must not pin last-good"
        )
        XCTAssertFalse(
            begin.contains("pinLastGoodOnWebViewLayer("),
            "Overlay begin must not stamp last-good on WK layer.contents"
        )
        XCTAssertTrue(
            begin.contains("removeParkedArticlePaint"),
            "Overlay begin must clear any leftover osrs_parked_article_paint sibling"
        )
        XCTAssertTrue(begin.contains("rememberPaintedArticle"))
        XCTAssertTrue(compositor.contains("osrs_parked_article_paint"))
        XCTAssertTrue(compositor.contains("parkedArticleLastGood"))
        let findAction = viewModel
            .components(separatedBy: "func performFindInPageAction")
            .dropFirst()
            .first?
            .components(separatedBy: "func presentNativeFindInterface")
            .first ?? ""
        XCTAssertFalse(
            findAction.contains("pinParkedArticlePaint(from:"),
            "performFindInPageAction must present Find without pinning last-good"
        )
        XCTAssertFalse(
            preserve.contains("pinParkedArticlePaint(from:"),
            "preserveRenderedArticleDuringFind must not pin or re-pin last-good"
        )
        XCTAssertTrue(viewModel.contains("rememberPaintedArticle(from:"))
        XCTAssertFalse(begin.contains("#if DEBUG"))
        let liveTheme = viewModel
            .components(separatedBy: "func applyLiveTheme")
            .dropFirst()
            .first?
            .components(separatedBy: "func applyThemeColors")
            .first ?? ""
        XCTAssertTrue(liveTheme.contains("osrsWebViewThemePaint.apply"))
        XCTAssertFalse(compositor.contains("webView.layer.contents = nil"))
        XCTAssertFalse(compositor.contains("pinLiveArticleFrame"))
        XCTAssertFalse(compositor.contains("osrs_live_overlay_frame"))
        XCTAssertFalse(compositor.contains("removePinnedArticleOverlay"))
        XCTAssertFalse(viewModel.contains("pinLiveArticleFrame"))
        XCTAssertTrue(compositor.contains("shouldRestoreResumeCover(didLeaveToBackground:"))
        XCTAssertTrue(compositor.contains("revealWhenLiveWebViewPaints"))
        XCTAssertTrue(compositor.contains("removeLastGoodCover"))
        XCTAssertFalse(compositor.contains("passthrough retained"))
        let became = sceneDelegate
            .components(separatedBy: "func handleBecameActive")
            .dropFirst()
            .first?
            .components(separatedBy: "private var sceneContainer")
            .first ?? ""
        XCTAssertTrue(became.contains("didLeaveToBackground"))
        XCTAssertTrue(became.contains("restoreResumedScene"))
        XCTAssertTrue(
            compositor.contains("appendAllContextCensus"),
            "dumpWindow must keep the C49-class CAContext census"
        )
        XCTAssertTrue(
            compositor.contains("requestCssComputedCaptionTabber"),
            "dumpWindow must keep live caption/tabber computed-style census"
        )
        XCTAssertTrue(
            compositor.contains("dumpCssV=js-first-v3"),
            "dumpWindow must stamp a version so a stale Release binary cannot fake the live DOM census"
        )
        XCTAssertTrue(
            compositor.contains("appendTileOwnerCensus"),
            "dumpWindow must census WK contents IOSurfaces at Uncharged-Y"
        )
        XCTAssertTrue(
            compositor.contains("dumpTileV=owner-v2"),
            "dumpWindow must stamp tile-owner census version"
        )
        XCTAssertTrue(
            compositor.contains("appendRemoteTileCensus"),
            "dumpWindow must census contents=nil page tiled CALayers"
        )
        XCTAssertTrue(
            compositor.contains("dumpRemoteV=layer-v4"),
            "dumpWindow must stamp remote-tile census version"
        )
        XCTAssertTrue(
            compositor.contains("walk(window.layer, depth: 0)"),
            "layer-v4 must walk the full window layer tree in paint order, not name-filtered WK views"
        )
        XCTAssertTrue(
            compositor.contains("gutterDeepestParchment"),
            "layer-v4 must summarize the deepest parchment-opaque layer at gutterL"
        )
        XCTAssertTrue(
            compositor.contains("descendsFromOverlay"),
            "dumpWindow must name find-overlay descent for covering layers"
        )
        XCTAssertTrue(compositor.contains("CARenderServerRenderLayerWithTransform"))
        XCTAssertFalse(
            compositor.contains("CARenderServerGetClientProcessId"),
            "C46 client-process SPI must stay out of dumpWindow"
        )
        XCTAssertFalse(
            compositor.contains("dlsym(quartz, \"CARenderServerGetInfo\")"),
            "C46 render-server info SPI must stay out of dumpWindow"
        )
    }

    private func isThemeParchment(_ color: UIColor?, expected: UIColor) -> Bool {
        guard let color else { return false }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var themeRed: CGFloat = 0, themeGreen: CGFloat = 0, themeBlue: CGFloat = 0, themeAlpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              expected.getRed(&themeRed, green: &themeGreen, blue: &themeBlue, alpha: &themeAlpha) else {
            return false
        }
        return alpha > 0.5
            && abs(red - themeRed) < 0.03
            && abs(green - themeGreen) < 0.03
            && abs(blue - themeBlue) < 0.03
    }

    private func makeWindow(theme: UIColor, includeArticleWebView: Bool) -> UIWindow {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.backgroundColor = theme
        if includeArticleWebView {
            let webView = WKWebView(
                frame: host.view.bounds,
                configuration: WKWebViewConfiguration()
            )
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.accessibilityIdentifier = "article_web_view"
            host.view.addSubview(webView)
        }
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = host.view.frame
        } else {
            window = UIWindow(frame: host.view.frame)
        }
        window.backgroundColor = theme
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        hostWindow = window
        return window
    }

    private func firstOverlayFrameAcrossScenes() -> UIImageView? {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                if let found = firstOverlayFrame(in: window) {
                    return found
                }
            }
        }
        return nil
    }

    private func firstOverlayFrame(in view: UIView) -> UIImageView? {
        if let imageView = view as? UIImageView,
           imageView.accessibilityIdentifier == "osrs_live_overlay_frame" {
            return imageView
        }
        for child in view.subviews {
            if let found = firstOverlayFrame(in: child) {
                return found
            }
        }
        return nil
    }

    private func firstParkedArticlePaint(in view: UIView) -> UIImageView? {
        if let imageView = view as? UIImageView,
           imageView.accessibilityIdentifier == "osrs_parked_article_paint" {
            return imageView
        }
        for child in view.subviews {
            if let found = firstParkedArticlePaint(in: child) {
                return found
            }
        }
        return nil
    }

    private func firstWebView(in window: UIWindow) -> WKWebView? {
        func walk(_ view: UIView) -> WKWebView? {
            if let web = view as? WKWebView {
                return web
            }
            for child in view.subviews {
                if let found = walk(child) {
                    return found
                }
            }
            return nil
        }
        return walk(window)
    }

    private func loadArticleHTML(in webView: WKWebView) async throws {
        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="visibility: visible; background: #f4eaea;">
        <h1>Varrock</h1>
        <p>The capital of Misthalin is a busy trade city with a palace.</p>
        </body>
        </html>
        """
        let didFinish = expectation(description: "host-fill article HTML loaded")
        let delegate = HostFillNavigationDelegate(didFinish: didFinish)
        webView.navigationDelegate = delegate
        objc_setAssociatedObject(webView, &HostFillNavigationDelegate.handle, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10)
        try await Task.sleep(nanoseconds: 80_000_000)
    }

    private func loadHTML(_ html: String, in webView: WKWebView) async throws {
        let didFinish = expectation(description: "host-fill custom HTML loaded")
        let delegate = HostFillNavigationDelegate(didFinish: didFinish)
        webView.navigationDelegate = delegate
        objc_setAssociatedObject(webView, &HostFillNavigationDelegate.handle, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10)
        try await Task.sleep(nanoseconds: 80_000_000)
    }

    private func computedBodyBackground(_ webView: WKWebView) async throws -> String {
        try await Task.sleep(nanoseconds: 150_000_000)
        return try await evaluateString(
            "getComputedStyle(document.body).backgroundColor",
            in: webView
        )
    }

    private func evaluateString(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    private func snapshot(_ window: UIWindow) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
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

private final class HostFillNavigationDelegate: NSObject, WKNavigationDelegate {
    static var handle: UInt8 = 0
    let didFinish: XCTestExpectation

    init(didFinish: XCTestExpectation) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}

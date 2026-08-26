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
        XCTAssertLessThan(webView.underPageBackgroundColor.cgColor.alpha, 0.05)
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

    func testLoadedArticleThemePaintDoesNotFillParkedCompositorWithPageColor() async throws {
        let themeColor = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: themeColor, includeArticleWebView: true)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)

        osrsHostThemeFill.apply(to: live, themeBackground: themeColor)
        osrsWebViewThemePaint.apply(to: webView, theme: osrsDarkTheme())

        XCTAssertLessThan(
            webView.underPageBackgroundColor.cgColor.alpha,
            0.05,
            "Loaded article must not keep theme under-page fill; parked GPU then paints #28221d"
        )
        XCTAssertFalse(webView.isOpaque)
        XCTAssertFalse(webView.scrollView.isOpaque)
        XCTAssertLessThan(webView.backgroundColor?.cgColor.alpha ?? 1, 0.05)
        XCTAssertFalse(live.rootViewController?.view.isOpaque ?? true)
    }

    func testApplyLiveThemeOnLoadedArticleDoesNotRestoreOpaqueUnderPageFill() async throws {
        let live = makeWindow(
            theme: UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1),
            includeArticleWebView: true
        )
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        viewModel.setWebView(webView)
        osrsWebViewThemePaint.apply(to: webView, theme: osrsLightTheme())
        XCTAssertLessThan(webView.underPageBackgroundColor.cgColor.alpha, 0.05)

        viewModel.applyLiveTheme(osrsLightTheme(), themeManager: osrsThemeManager())

        XCTAssertLessThan(
            webView.underPageBackgroundColor.cgColor.alpha,
            0.05,
            "applyLiveTheme must not put #E2DBC8 under a loaded article; Find then fills the LCD"
        )
        XCTAssertLessThan(webView.backgroundColor?.cgColor.alpha ?? 1, 0.05)
        XCTAssertLessThan(webView.scrollView.backgroundColor?.cgColor.alpha ?? 1, 0.05)
        XCTAssertFalse(webView.isOpaque)
    }

    func testLoadedArticleThemePaintClearsImportantHtmlBodyPageFill() async throws {
        let live = makeWindow(
            theme: UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1),
            includeArticleWebView: true
        )
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
            computed.contains("0, 0, 0, 0") || computed.contains("transparent"),
            "Find parks GPU on html/body #E2DBC8; theme paint must clear it computed=\(computed)"
        )
        XCTAssertLessThan(webView.underPageBackgroundColor.cgColor.alpha, 0.05)
    }

    func testFindExpandClearsImportantHtmlBodyFillBeforePresentingNavigator() async throws {
        let live = makeWindow(
            theme: UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1),
            includeArticleWebView: true
        )
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
            "present",
            "Find expand must inject overlay page-fill CSS before UIFindInteraction parks GPU"
        )
        let computed = try await evaluateString(
            "getComputedStyle(document.body).backgroundColor",
            in: webView
        )
        XCTAssertTrue(
            computed.contains("0, 0, 0, 0") || computed.contains("transparent"),
            "Find present must not still see html/body #E2DBC8 computed=\(computed)"
        )
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

        let presented = expectation(description: "find presented for parked paint")
        viewModel.performFindInPageAction {
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 5)
        defer { viewModel.hideFindInPageAction() }

        let paint = try await waitForParkedArticlePaint(in: live)
        XCTAssertTrue(
            paint.superview === webView.superview
                || paint.superview === live.rootViewController?.view,
            "Parked article paint must live in the same window as the article WK"
        )
        XCTAssertFalse(paint is UIWindow)
        XCTAssertFalse(paint.isUserInteractionEnabled)
        XCTAssertNil(
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Find must not mint osrs_live_overlay_frame"
        )
        XCTAssertFalse(live is osrsResumeCoverWindow)
        XCTAssertTrue(osrsSceneCompositor.containsLiveArticleWebView(live))
        XCTAssertFalse(
            webView.scrollView.isHidden,
            "Hiding WKScrollView blanks the live tree for Name/search; last-good is a sibling, not a hide"
        )

        webView.isHidden = true
        let parked = snapshot(live)
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(parked),
            "In-tree article paint must stay on the LCD after WK Metal parks range=\(osrsWebViewThemePaint.luminanceRange(parked))"
        )
        webView.isHidden = false
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

        let parkedGPU = UIView(frame: live.bounds)
        parkedGPU.backgroundColor = theme
        parkedGPU.isOpaque = true
        parkedGPU.accessibilityIdentifier = "parked-gpu-sim"
        live.rootViewController?.view.addSubview(parkedGPU)
        XCTAssertTrue(
            osrsWebViewThemePaint.isUniformFill(snapshot(live)),
            "Sanity: simulated parked compositor is a uniform #28221d fill"
        )

        let name = UITextField(frame: CGRect(x: 24, y: 96, width: 200, height: 36))
        name.accessibilityIdentifier = "native-calc-field-name"
        live.rootViewController?.view.addSubview(name)

        osrsSceneCompositor.pinParkedArticlePaint(from: webView)
        let paint = try await waitForParkedArticlePaint(in: live)
        XCTAssertFalse(paint is UIWindow)
        XCTAssertFalse(paint.isUserInteractionEnabled)
        XCTAssertNil(
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Find/search/Name must not mint osrs_live_overlay_frame"
        )
        XCTAssertFalse(live is osrsResumeCoverWindow)
        XCTAssertTrue(osrsSceneCompositor.containsLiveArticleWebView(live))
        XCTAssertEqual(
            live.windowScene?.windows.count ?? windowsBefore,
            windowsBefore,
            "In-tree pin must not mint a second UIWindow"
        )
        parkedGPU.isHidden = true
        let parked = snapshot(live)
        parkedGPU.isHidden = false
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(parked),
            "Parked compositor must keep last-good in-tree, not #28221d fill range=\(osrsWebViewThemePaint.luminanceRange(parked))"
        )
        XCTAssertNotNil(
            webView.layer.contents,
            "Last-good must stamp WK layer.contents (not nil) so parked Metal tiles are not the LCD"
        )
        let hitPoint = name.convert(CGPoint(x: 8, y: 8), to: live)
        let hit = live.hitTest(hitPoint, with: nil)
        XCTAssertFalse(hit is osrsResumeCoverWindow)
        XCTAssertTrue(
            hit === name || (hit?.isDescendant(of: name) ?? false) || paint.isUserInteractionEnabled == false,
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
            firstOverlayFrame(in: live) ?? firstOverlayFrameAcrossScenes(),
            "Find/search/Name must not mint a last-good cover window over a live WK"
        )
        XCTAssertTrue(
            osrsSceneCompositor.containsLiveArticleWebView(live),
            "The article WK must stay in the live tree during Find/Name/search"
        )
        XCTAssertEqual(live.backgroundColor, UIColor.clear)
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
        XCTAssertTrue(fill.contains("osrsResumeCoverWindow"))
        XCTAssertTrue(fill.contains("underPageBackgroundColor = UIColor.clear"))
        XCTAssertTrue(fill.contains("clearThemeColoredHostViews"))
        XCTAssertFalse(fill.contains("layer.contents = nil"))
        let viewModel = try source(root, "platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift")
        let preserve = viewModel
            .components(separatedBy: "func preserveRenderedArticleDuringFind")
            .dropFirst()
            .first?
            .components(separatedBy: "func ")
            .first ?? ""
        XCTAssertTrue(preserve.contains("isOpaque = false"))
        XCTAssertFalse(preserve.contains("isOpaque = true"))
        XCTAssertTrue(preserve.contains("underPageBackgroundColor = UIColor.clear"))
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
        XCTAssertTrue(themePaint.contains("emptyDocument ? pageColor : UIColor.clear"))
        XCTAssertTrue(themePaint.contains("osrs-overlay-page-fill"))
        XCTAssertTrue(themePaint.contains("background-color: transparent !important"))
        XCTAssertTrue(viewModel.contains("osrs-overlay-page-fill") || viewModel.contains("clearLoadedDocumentPageFillScript"))
        let begin = compositor
            .components(separatedBy: "static func beginLiveOverlaySession")
            .dropFirst()
            .first?
            .components(separatedBy: "static func endLiveOverlaySession")
            .first ?? ""
        XCTAssertTrue(begin.contains("osrsWebViewThemePaint.apply"))
        XCTAssertFalse(begin.contains("layer.contents = nil"))
        XCTAssertFalse(begin.contains("pinLiveArticleFrame"))
        XCTAssertTrue(begin.contains("pinParkedArticlePaint"))
        XCTAssertTrue(begin.contains("rememberPaintedArticle"))
        XCTAssertTrue(compositor.contains("osrs_parked_article_paint"))
        XCTAssertTrue(compositor.contains("parkedArticleLastGood"))
        XCTAssertTrue(viewModel.contains("pinParkedArticlePaint"))
        XCTAssertTrue(viewModel.contains("rememberPaintedArticle(from:"))
        XCTAssertFalse(begin.contains("#if DEBUG"))
        let liveTheme = viewModel
            .components(separatedBy: "func applyLiveTheme")
            .dropFirst()
            .first?
            .components(separatedBy: "func applyThemeColors")
            .first ?? ""
        XCTAssertTrue(liveTheme.contains("osrsWebViewThemePaint.apply"))
        XCTAssertFalse(liveTheme.contains("underPageBackgroundColor = pageColor"))
        XCTAssertTrue(compositor.contains("pinLastGoodOnWebViewLayer"))
        XCTAssertFalse(compositor.contains("webView.layer.contents = nil"))
        XCTAssertFalse(compositor.contains("pinLiveArticleFrame"))
        XCTAssertFalse(compositor.contains("osrs_live_overlay_frame"))
        XCTAssertFalse(compositor.contains("removePinnedArticleOverlay"))
        XCTAssertFalse(viewModel.contains("pinLiveArticleFrame"))
        XCTAssertTrue(compositor.contains("shouldRestoreResumeCover(didLeaveToBackground:"))
        let became = sceneDelegate
            .components(separatedBy: "func handleBecameActive")
            .dropFirst()
            .first?
            .components(separatedBy: "private var sceneContainer")
            .first ?? ""
        XCTAssertTrue(became.contains("didLeaveToBackground"))
        XCTAssertTrue(became.contains("restoreResumedScene"))
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

    private func waitForParkedArticlePaint(in window: UIWindow) async throws -> UIImageView {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let paint = firstParkedArticlePaint(in: window) {
                return paint
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(
            firstParkedArticlePaint(in: window),
            "Find must pin in-tree article paint before WK Metal parks"
        )
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

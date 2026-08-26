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

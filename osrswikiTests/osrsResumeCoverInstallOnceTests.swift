import UIKit
import WebKit
import XCTest
@testable import osrswiki

/// Resume used to stamp last-good four times: theme paint, scene lifecycle,
/// article recommit, and compositor restore/nudge all call `restore()`.
@MainActor
final class osrsResumeCoverInstallOnceTests: XCTestCase {
    private var hostWindow: UIWindow?
    private var viewModel: ArticleViewModel?

    override func setUp() {
        super.setUp()
        osrsSceneCompositor.resetResumeCoverStateForTesting()
    }

    override func tearDown() {
        osrsSceneCompositor.dumpWindowEnabled = false
        hostWindow?.isHidden = true
        hostWindow = nil
        viewModel = nil
        osrsSceneCompositor.resetResumeCoverStateForTesting()
        super.tearDown()
    }

    func testResumeCoverInstallsOnceOnFirstResumeOnlyThisSession() async throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: theme)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        live.makeKeyAndVisible()

        let article = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        article.webView = webView
        viewModel = article

        osrsResumeFrameOverlay.rememberPaintedArticle(contrastingLastGood(in: live.bounds))
        XCTAssertTrue(
            osrsResumeFrameOverlay.hasCapturedFrame,
            "Sanity: contrasting last-good must be captured before resume"
        )

        osrsSceneCompositor.noteDidEnterBackground()
        fireFourResumeCoverInstallPaths(on: live, viewModel: article)
        XCTAssertEqual(
            osrsResumeFrameOverlay.coverInstallCountForCurrentResume,
            1,
            "Theme paint, lifecycle, article recommit, and restore/nudge must share one install"
        )
        XCTAssertEqual(
            osrsSceneCompositor.layerContentsKind(live.layer.contents),
            "CGImage",
            "Cover must be on the window before the article compositor is trusted"
        )

        osrsResumeFrameOverlay.revealWhenLiveWebViewPaints()
        osrsSceneCompositor.restore(live)
        osrsThemeManager.osrsUnhideResumedHostViews(in: live)
        XCTAssertEqual(
            osrsResumeFrameOverlay.coverInstallCountForCurrentResume,
            1,
            "Completing restore / scroll reveal must not stamp the cover again"
        )

        osrsSceneCompositor.noteDidEnterBackground()
        XCTAssertEqual(
            osrsResumeFrameOverlay.coverInstallCountForCurrentResume,
            0,
            "A new resume generation starts at zero installs"
        )
        fireFourResumeCoverInstallPaths(on: live, viewModel: article)
        XCTAssertEqual(
            osrsResumeFrameOverlay.coverInstallCountForCurrentResume,
            0,
            "Matching #58, later warm resumes in the same session must not restamp the cover"
        )
    }

    func testResumeCoverComesDownAfterFirstResumeOnceLiveWebViewPaints() async throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: theme)
        let webView = try XCTUnwrap(firstWebView(in: live))
        try await loadArticleHTML(in: webView)
        live.makeKeyAndVisible()

        let article = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        article.webView = webView
        viewModel = article

        osrsResumeFrameOverlay.rememberPaintedArticle(contrastingLastGood(in: live.bounds))
        osrsSceneCompositor.noteDidEnterBackground()
        fireFourResumeCoverInstallPaths(on: live, viewModel: article)
        XCTAssertEqual(
            osrsResumeFrameOverlay.coverInstallCountForCurrentResume,
            1,
            "First resume of the session must install the cover once"
        )
        XCTAssertTrue(
            osrsResumeFrameOverlay.lastGoodIsCoveringLiveArticle,
            "Last-good must be covering before reveal"
        )
        XCTAssertTrue(
            osrsResumeFrameOverlay.liveArticleIsPainting(),
            "Hosted loaded article must count as painting so last-good can come down"
        )

        osrsResumeFrameOverlay.revealWhenLiveWebViewPaints()
        if osrsResumeFrameOverlay.lastGoodIsCoveringLiveArticle {
            try await Task.sleep(nanoseconds: 50_000_000)
            osrsResumeFrameOverlay.revealWhenLiveWebViewPaints()
        }
        XCTAssertNil(
            osrsResumeFrameOverlay.firstPassthroughImageView(),
            "Passthrough UIImageView must come down once live WK is painting"
        )
        XCTAssertFalse(
            osrsResumeFrameOverlay.lastGoodIsCoveringLiveArticle,
            "Cover must not stay over a painting WK after the first resume"
        )
        XCTAssertEqual(
            osrsSceneCompositor.layerContentsKind(live.layer.contents),
            "nil",
            "window.layer.contents last-good stamp must come down once live WK paints"
        )
    }

    func testResumeRestoreDoesNotDumpWindowEvenWhenOptedIn() async throws {
        let theme = UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
        let live = makeWindow(theme: theme)
        osrsResumeFrameOverlay.rememberPaintedArticle(contrastingLastGood(in: live.bounds))
        osrsSceneCompositor.noteDidEnterBackground()

        let dumpURL = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("osrs-scene-dump.txt")
        try? FileManager.default.removeItem(at: dumpURL)

        osrsSceneCompositor.dumpWindowEnabled = false
        osrsSceneCompositor.dumpWindow(live)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dumpURL.path),
            "dumpWindow must be a no-op unless explicitly opted in"
        )

        osrsSceneCompositor.dumpWindowEnabled = true
        defer { osrsSceneCompositor.dumpWindowEnabled = false }
        osrsSceneCompositor.restore(live)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dumpURL.path),
            "restore() must not dumpWindow even when the Debug census is opted in"
        )

        osrsSceneCompositor.dumpWindow(live)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dumpURL.path),
            "An explicit dumpWindow call must still write when opted in"
        )
    }

    func testFourResumeCoverCallSitesStillExist() throws {
        let root = try repositoryRoot()
        let compositor = try source(root, "platforms/ios/osrswiki/Services/osrsSceneCompositor.swift")
        let sceneDelegate = try source(root, "platforms/ios/osrswiki/Services/osrsSceneDelegate.swift")
        let themeManager = try source(root, "platforms/ios/osrswiki/Models/OSRSThemeManager.swift")
        let articleView = try source(root, "platforms/ios/osrswiki/Views/ArticleView.swift")
        let viewModelSource = try source(root, "platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift")
        let tabView = try source(root, "platforms/ios/osrswiki/Views/CustomMainTabView.swift")
        let appState = try source(root, "platforms/ios/osrswiki/Models/AppState.swift")

        XCTAssertTrue(compositor.contains("beginResumeCoverGeneration()"))
        XCTAssertTrue(compositor.contains("coverInstallCountForCurrentResume"))
        XCTAssertTrue(compositor.contains("installedCoverGeneration == resumeCoverGeneration"))
        XCTAssertTrue(compositor.contains("didInstallCoverThisSession"))
        XCTAssertTrue(compositor.contains("if hasAdoptedLiveRoot || didInstallCoverThisSession { return }"))
        XCTAssertTrue(compositor.contains("pinOpaqueCoverOnTop(of:"))
        XCTAssertTrue(compositor.contains("bringSubviewToFront"))
        XCTAssertTrue(compositor.contains("resumeCoverAdoptPending"))
        XCTAssertTrue(compositor.contains("coverSafetyTimeoutNs"))
        XCTAssertTrue(compositor.contains("allowCoverRevealAfterNextTurn"))
        XCTAssertFalse(
            compositor.contains("CATransaction.setCompletionBlock"),
            "Cover reveal must not wait on a CATransaction completion that never fires"
        )
        XCTAssertTrue(compositor.contains("dumpWindowEnabled"))
        let restoreBody = compositor
            .components(separatedBy: "static func restore(_ window: UIWindow)")
            .dropFirst()
            .first?
            .components(separatedBy: "static func captureResumeFrame")
            .first ?? ""
        XCTAssertFalse(
            restoreBody.contains("dumpWindow("),
            "Resume restore must not call dumpWindow"
        )
        let adoptedRestore = restoreBody
            .components(separatedBy: "if osrsResumeFrameOverlay.hasAdoptedLiveRoot")
            .dropFirst()
            .first?
            .components(separatedBy: "window.isHidden = false")
            .first ?? ""
        XCTAssertFalse(
            adoptedRestore.contains("installOnWindowLayer"),
            "Adopted later resumes must match #58 and skip the cover"
        )
        XCTAssertTrue(
            adoptedRestore.contains("revealWhenLiveWebViewPaints"),
            "Adopted later resumes must still take a leftover cover down"
        )
        let adoptBody = compositor
            .components(separatedBy: "static func adoptLiveRootIfNeeded()")
            .dropFirst()
            .first?
            .components(separatedBy: "static func installOnWindowLayer")
            .first ?? ""
        XCTAssertFalse(
            adoptBody.contains("dumpWindow("),
            "Adopting the live root must not dumpWindow"
        )
        XCTAssertTrue(
            adoptBody.contains("pinOpaqueCoverOnTop(of: overlay, image:"),
            "Root-VC move must keep last-good opaque on top"
        )
        XCTAssertTrue(
            adoptBody.contains("allowCoverRevealAfterNextTurn"),
            "Cover stays up for the adopt commit, then reveals on the next turn"
        )
        XCTAssertTrue(
            themeManager.contains("osrsSceneCompositor.restore(window)"),
            "Theme paint still restores the scene compositor on foreground"
        )
        XCTAssertTrue(
            tabView.contains("osrsSceneCompositor.restoreResumedScenes()"),
            "Lifecycle didBecomeActive still restores resumed scenes"
        )
        XCTAssertTrue(appState.contains("osrsSceneCompositor.restoreResumedScenes()"))
        XCTAssertTrue(
            viewModelSource.contains("osrsSceneCompositor.restore(window)"),
            "Article recommit after background still restores the window"
        )
        XCTAssertTrue(articleView.contains("recommitCachedArticleAfterBackground(force:"))
        XCTAssertTrue(
            sceneDelegate.contains("osrsSceneCompositor.restore(window)"),
            "Scene restore / nudge still restore the window"
        )
        XCTAssertTrue(sceneDelegate.contains("nudgeCompositor(on: windowScene)"))
    }

    private func fireFourResumeCoverInstallPaths(on window: UIWindow, viewModel: ArticleViewModel) {
        osrsSceneCompositor.restore(window)
        osrsThemeManager.osrsUnhideResumedHostViews(in: window)
        viewModel.recommitCachedArticleAfterBackground()
        osrsSceneCompositor.restoreResumedScenes()
    }

    private func contrastingLastGood(in bounds: CGRect) -> UIImage {
        UIGraphicsImageRenderer(bounds: bounds).image { ctx in
            UIColor.white.setFill()
            ctx.fill(bounds)
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 16, y: 48, width: 120, height: 180))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 180, y: 240, width: 90, height: 140))
        }
    }

    private func makeWindow(theme: UIColor) -> UIWindow {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.backgroundColor = theme
        let webView = WKWebView(
            frame: host.view.bounds,
            configuration: WKWebViewConfiguration()
        )
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.accessibilityIdentifier = "article_web_view"
        host.view.addSubview(webView)
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

    private func firstWebView(in window: UIWindow) -> WKWebView? {
        func walk(_ view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            for child in view.subviews {
                if let found = walk(child) { return found }
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
        let didFinish = expectation(description: "resume-cover article HTML loaded")
        let delegate = osrsResumeCoverInstallNavigationDelegate(didFinish: didFinish)
        webView.navigationDelegate = delegate
        objc_setAssociatedObject(
            webView,
            &osrsResumeCoverInstallNavigationDelegate.handle,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10)
        try await Task.sleep(nanoseconds: 80_000_000)
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

private final class osrsResumeCoverInstallNavigationDelegate: NSObject, WKNavigationDelegate {
    static var handle: UInt8 = 0
    let didFinish: XCTestExpectation

    init(didFinish: XCTestExpectation) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}

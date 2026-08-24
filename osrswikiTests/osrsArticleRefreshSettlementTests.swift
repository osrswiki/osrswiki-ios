import XCTest
import UIKit
import WebKit
@testable import osrswiki

private final class ArticleRefreshNavigationDelegate: NSObject, WKNavigationDelegate {
    let didFinish: XCTestExpectation

    init(didFinish: XCTestExpectation) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}

@MainActor
final class osrsArticleRefreshSettlementTests: XCTestCase {
    private var hostWindow: UIWindow?
    private var navigationDelegate: ArticleRefreshNavigationDelegate?

    override func tearDown() {
        hostWindow?.isHidden = true
        hostWindow = nil
        navigationDelegate = nil
        super.tearDown()
    }

    func testPullToRefreshSettlementMatchesFreshOpenInLightAndDark() async throws {
        try await assertRefreshMatchesFreshOpen(style: .light, usesDarkTheme: false)
        try await assertRefreshMatchesFreshOpen(style: .dark, usesDarkTheme: true)
    }

    func testPullToRefreshSettlementClearsLeftoverInsetAndOffset() async throws {
        let harness = try await makeHarness(style: .light, usesDarkTheme: false)
        let baseline = try await captureSnapshot(harness.webView)
        XCTAssertGreaterThan(baseline.titleViewportY, 20, "Fresh-open title must sit below baked chrome clearance")

        applyPullToRefreshLeftover(on: harness.webView.scrollView)
        let leftover = try await captureSnapshot(harness.webView)
        XCTAssertFalse(
            osrsArticleRefreshSettlement.matches(leftover, baseline),
            "Leftover UIRefreshControl inset/offset must differ from a fresh open so the test can fail without settlement"
        )

        harness.viewModel.settleArticleScrollAfterRefresh()
        try await Task.sleep(nanoseconds: 400_000_000)
        let settled = try await captureSnapshot(harness.webView)
        XCTAssertTrue(
            osrsArticleRefreshSettlement.matches(settled, baseline),
            "Settlement leftover=\(describe(leftover)) settled=\(describe(settled)) baseline=\(describe(baseline))"
        )
    }

    func testRefreshPagePathSettlesToFreshOpenBaseline() async throws {
        try await assertRefreshMatchesFreshOpen(style: .unspecified, usesDarkTheme: false)
    }

    private func assertRefreshMatchesFreshOpen(
        style: UIUserInterfaceStyle,
        usesDarkTheme: Bool
    ) async throws {
        let harness = try await makeHarness(style: style, usesDarkTheme: usesDarkTheme)
        let baseline = try await captureSnapshot(harness.webView)
        XCTAssertGreaterThan(baseline.titleViewportY, 20)

        applyPullToRefreshLeftover(on: harness.webView.scrollView)
        harness.viewModel.seedCommittedArticleHTMLForTests(
            harness.html,
            theme: usesDarkTheme ? osrsDarkTheme() : osrsLightTheme()
        )
        harness.webView.navigationDelegate = harness.viewModel
        harness.viewModel.refreshPage(theme: usesDarkTheme ? osrsDarkTheme() : osrsLightTheme())

        try await waitUntilRefreshing(harness.viewModel)
        try await waitUntilRefreshSettles(harness.viewModel)
        try await Task.sleep(nanoseconds: 400_000_000)

        let after = try await captureSnapshot(harness.webView)
        XCTAssertTrue(
            osrsArticleRefreshSettlement.matches(after, baseline),
            "Post-refresh \(describe(after)) must match fresh-open \(describe(baseline)) style=\(style.rawValue)"
        )

        applyPullToRefreshLeftover(on: harness.webView.scrollView)
        harness.viewModel.settleArticleScrollAfterRefresh()
        try await Task.sleep(nanoseconds: 400_000_000)
        let afterSecond = try await captureSnapshot(harness.webView)
        XCTAssertTrue(
            osrsArticleRefreshSettlement.matches(afterSecond, baseline),
            "Second PTR leftover did not settle: \(describe(afterSecond)) vs \(describe(baseline))"
        )
    }

    private struct Harness {
        let webView: WKWebView
        let viewModel: ArticleViewModel
        let html: String
    }

    private func makeHarness(
        style: UIUserInterfaceStyle,
        usesDarkTheme: Bool
    ) async throws -> Harness {
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: WKWebViewConfiguration()
        )
        osrsArticleRefreshSettlement.configure(webView.scrollView)
        webView.scrollView.refreshControl = UIRefreshControl()
        viewModel.setWebView(webView)
        attach(webView, style: style)

        let html = articleHTML(usesDarkTheme: usesDarkTheme)
        try await load(html, in: webView)
        viewModel.seedCommittedArticleHTMLForTests(
            html,
            theme: usesDarkTheme ? osrsDarkTheme() : osrsLightTheme()
        )
        return Harness(webView: webView, viewModel: viewModel, html: html)
    }

    private func attach(_ webView: WKWebView, style: UIUserInterfaceStyle) {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        webView.frame = host.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(webView)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = host.view.frame
        } else {
            window = UIWindow(frame: host.view.frame)
        }
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        webView.layoutIfNeeded()
        hostWindow = window
    }

    private func load(_ html: String, in webView: WKWebView) async throws {
        let didFinish = expectation(description: "article HTML loaded")
        let delegate = ArticleRefreshNavigationDelegate(didFinish: didFinish)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10.0)
        try await Task.sleep(nanoseconds: 80_000_000)
        webView.scrollView.setContentOffset(.zero, animated: false)
        webView.scrollView.layoutIfNeeded()
    }

    private func captureSnapshot(_ webView: WKWebView) async throws -> osrsArticleRefreshSettlement.Snapshot {
        webView.scrollView.layoutIfNeeded()
        let metrics = try await evaluate(webView, """
        (() => {
            const title = document.querySelector('h1.page-header');
            const rect = title.getBoundingClientRect();
            return {
                titleViewportY: rect.top,
                titleDocumentY: rect.top + window.scrollY
            };
        })()
        """)
        return osrsArticleRefreshSettlement.snapshot(
            from: webView.scrollView,
            titleDocumentY: number(metrics, "titleDocumentY"),
            titleViewportY: number(metrics, "titleViewportY")
        )
    }

    private func applyPullToRefreshLeftover(on scrollView: UIScrollView) {
        scrollView.refreshControl?.beginRefreshing()
        var inset = scrollView.contentInset
        inset.top += 80
        scrollView.contentInset = inset
        scrollView.setContentOffset(
            CGPoint(x: 0, y: -scrollView.adjustedContentInset.top - 40),
            animated: false
        )
        scrollView.layoutIfNeeded()
    }

    private func waitUntilRefreshing(_ viewModel: ArticleViewModel) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if viewModel.isRefreshing { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("refreshPage never set isRefreshing")
    }

    private func waitUntilRefreshSettles(_ viewModel: ArticleViewModel) async throws {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if !viewModel.isRefreshing {
                return
            }
            if viewModel.loadingProgress >= 0.9 {
                viewModel.completeLoadingWithBodyReveal()
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        viewModel.completeLoadingWithBodyReveal()
        try await Task.sleep(nanoseconds: 300_000_000)
        if viewModel.isRefreshing {
            viewModel.settleArticleScrollAfterRefresh()
        }
    }

    private func articleHTML(usesDarkTheme: Bool) -> String {
        let chromeClearance = Int(
            (osrsSearchControlGeometry.compactHeight + osrsOverlayChromeMetrics.pairedEdgeGap + 8).rounded()
        )
        let bottomChrome = Int(
            (osrsOverlayChromeMetrics.floatingBarHeight + osrsOverlayChromeMetrics.pairedEdgeGap + 24).rounded()
        )
        let firstPaint = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: chromeClearance,
            safeAreaTopPx: Int(osrsOverlayChromeMetrics.topInset.rounded()),
            safeAreaBottomPx: Int(osrsOverlayChromeMetrics.bottomInset.rounded()),
            bottomChromePx: bottomChrome,
            usesDarkTheme: usesDarkTheme
        )
        let themeClass = usesDarkTheme ? "theme-osrs-dark" : ""
        return """
        <!doctype html>
        <html class="\(themeClass)">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(firstPaint)
        <style>
        body { margin: 0; }
        h1.page-header { margin: 0; font-size: 28px; line-height: 1.2; }
        </style>
        </head>
        <body class="\(themeClass)" style="visibility: visible;">
        <h1 class="page-header">Varrock</h1>
        <p id="lead">The capital of Misthalin is a busy trade city with a palace, museum, and surrounding wilderness.</p>
        <div style="height: 2400px">scrollable tail so pull-to-refresh has room to rubber-band</div>
        </body>
        </html>
        """
    }

    private func evaluate(_ webView: WKWebView, _ script: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let dictionary = result as? [String: Any] {
                    continuation.resume(returning: dictionary)
                } else {
                    continuation.resume(returning: [:])
                }
            }
        }
    }

    private func number(_ state: [String: Any], _ key: String) -> CGFloat {
        if let value = state[key] as? NSNumber {
            return CGFloat(value.doubleValue)
        }
        if let value = state[key] as? Double {
            return CGFloat(value)
        }
        return 0
    }

    private func describe(_ snapshot: osrsArticleRefreshSettlement.Snapshot) -> String {
        "inset.top=\(snapshot.contentInset.top) adjusted.top=\(snapshot.adjustedContentInset.top) offset.y=\(snapshot.contentOffset.y) titleViewportY=\(snapshot.titleViewportY) titleDocumentY=\(snapshot.titleDocumentY)"
    }
}

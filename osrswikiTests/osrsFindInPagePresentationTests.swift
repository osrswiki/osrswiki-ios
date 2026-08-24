import XCTest
import UIKit
import WebKit
@testable import osrswiki

private final class FindInPageNavigationDelegate: NSObject, WKNavigationDelegate {
    let didFinish: XCTestExpectation

    init(didFinish: XCTestExpectation) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}

@MainActor
final class osrsFindInPagePresentationTests: XCTestCase {
    private var hostWindow: UIWindow?
    private var navigationDelegate: FindInPageNavigationDelegate?

    override func tearDown() {
        hostWindow?.isHidden = true
        hostWindow = nil
        navigationDelegate = nil
        super.tearDown()
    }

    func testPresentAndDismissFindKeepsHostedArticleWebViewInWindow() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 16,
            "UIFindInteraction requires iOS 16+"
        )

        let harness = try await makeHarness()
        let webView = harness.webView
        let viewModel = harness.viewModel
        assertArticleWebViewUsable(webView, moment: "before present")
        XCTAssertFalse(viewModel.isNativeFindNavigatorVisible())
        let baselineSnapshot = visibleSnapshot(webView)
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(baselineSnapshot),
            "Baseline article snapshot must have contrast so a blank Find frame can fail range=\(osrsWebViewThemePaint.luminanceRange(baselineSnapshot))"
        )

        let presented = expectation(description: "find presented")
        viewModel.performFindInPageAction {
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 5)

        try await waitUntil(timeout: 4) {
            viewModel.isNativeFindNavigatorVisible() || findNavigatorHostAnywhere() != nil
        }
        assertArticleWebViewUsable(webView, moment: "after present")
        XCTAssertTrue(
            viewModel.isNativeFindNavigatorVisible() || findNavigatorHostAnywhere() != nil,
            "Shipped present must actually show the find navigator: \(describeAllWindows())"
        )
        let presentText = try await documentContains(webView, "Varrock")
        XCTAssertTrue(presentText, "after present: article document lost Varrock")
        try await Task.sleep(nanoseconds: 350_000_000)
        viewModel.preserveRenderedArticleDuringFind(webView)
        let presentSnapshot = visibleSnapshot(webView)
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(presentSnapshot)
                || osrsWebViewThemePaint.isUnpaintedSystemFill(presentSnapshot),
            "Find present must not blank the article compositor range=\(osrsWebViewThemePaint.luminanceRange(presentSnapshot))"
        )

        // Compositor-blank wake currently fires independently of Find. The shipped
        // present path must survive that wake without dropping the hosted WKWebView.
        viewModel.wakeRenderedDocumentAfterBackground()
        try await Task.sleep(nanoseconds: 250_000_000)
        assertArticleWebViewUsable(webView, moment: "after compositor-blank wake during find")
        XCTAssertTrue(
            viewModel.isNativeFindNavigatorVisible() || findNavigatorHostAnywhere() != nil,
            "Compositor-blank wake must not dismiss Find or rebuild the article webview: \(describeAllWindows())"
        )
        let wakeText = try await documentContains(webView, "Varrock")
        XCTAssertTrue(wakeText, "after compositor-blank wake: article document lost Varrock")

        viewModel.hideFindInPageAction()
        try await waitUntil(timeout: 6) {
            !viewModel.isFindInPageActive && findNavigatorHostAnywhere() == nil
        }
        assertArticleWebViewUsable(webView, moment: "after dismiss")
        XCTAssertFalse(viewModel.isFindInPageActive)
        XCTAssertNil(
            findNavigatorHostAnywhere(),
            "Find navigator chrome must leave the window after dismiss: \(describeAllWindows())"
        )
        let dismissText = try await documentContains(webView, "Varrock")
        XCTAssertTrue(dismissText, "after dismiss: article document lost Varrock")
    }

    private struct Harness {
        let webView: WKWebView
        let viewModel: ArticleViewModel
    }

    private func makeHarness() async throws -> Harness {
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock"
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: WKWebViewConfiguration()
        )
        if #available(iOS 16.0, *) {
            webView.isFindInteractionEnabled = true
        }
        webView.accessibilityIdentifier = "article_web_view"
        viewModel.setWebView(webView)
        attach(webView)
        webView.becomeFirstResponder()

        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="visibility: visible;">
        <h1 class="page-header">Varrock</h1>
        <p id="lead">The capital of Misthalin is a busy trade city with a palace, museum, and surrounding wilderness.</p>
        </body>
        </html>
        """
        try await load(html, in: webView)
        viewModel.seedCommittedArticleHTMLForTests(html, theme: osrsLightTheme())
        return Harness(webView: webView, viewModel: viewModel)
    }

    private func attach(_ webView: WKWebView) {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
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
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        webView.layoutIfNeeded()
        hostWindow = window
    }

    private func load(_ html: String, in webView: WKWebView) async throws {
        let didFinish = expectation(description: "article HTML loaded")
        let delegate = FindInPageNavigationDelegate(didFinish: didFinish)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10.0)
        try await Task.sleep(nanoseconds: 80_000_000)
    }

    private func assertArticleWebViewUsable(_ webView: WKWebView, moment: String) {
        XCTAssertNotNil(webView.window, "\(moment): article WKWebView left its window")
        XCTAssertNotNil(webView.superview, "\(moment): article WKWebView left the hierarchy")
        XCTAssertFalse(webView.isHidden, "\(moment): article WKWebView is hidden")
        XCTAssertGreaterThan(webView.bounds.width, 1, "\(moment): width=\(webView.bounds.width)")
        XCTAssertGreaterThan(webView.bounds.height, 1, "\(moment): height=\(webView.bounds.height)")
        XCTAssertEqual(webView.accessibilityIdentifier, "article_web_view")
    }

    private func visibleSnapshot(_ view: UIView) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private func documentContains(_ webView: WKWebView, _ needle: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.body && document.body.innerText") { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = result as? String ?? ""
                continuation.resume(returning: text.contains(needle))
            }
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }

    private func appWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    private func findNavigatorHostAnywhere() -> UIView? {
        for window in appWindows() {
            if let found = findNavigatorHost(in: window) {
                return found
            }
        }
        return nil
    }

    private func findNavigatorHost(in root: UIView?) -> UIView? {
        guard let root else { return nil }
        let name = NSStringFromClass(type(of: root))
        if name.localizedCaseInsensitiveContains("FindNavigator")
            || name.localizedCaseInsensitiveContains("UIFindBar")
            || name.localizedCaseInsensitiveContains("FindInteraction") {
            return root
        }
        for child in root.subviews {
            if let found = findNavigatorHost(in: child) {
                return found
            }
        }
        return nil
    }

    private func describeAllWindows() -> String {
        appWindows().map(describeHierarchy).joined(separator: " || ")
    }

    private func describeHierarchy(_ root: UIView) -> String {
        var lines: [String] = []
        func walk(_ view: UIView, depth: Int) {
            guard lines.count < 80 else { return }
            lines.append(
                String(repeating: "  ", count: depth)
                    + NSStringFromClass(type(of: view))
                    + " hidden=\(view.isHidden) frame=\(Int(view.frame.width))x\(Int(view.frame.height))"
            )
            view.subviews.prefix(12).forEach { walk($0, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return lines.joined(separator: " | ")
    }
}

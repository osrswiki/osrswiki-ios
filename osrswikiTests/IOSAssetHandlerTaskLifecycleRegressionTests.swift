import XCTest
import WebKit
@testable import osrswiki

/// Regression tests for the IOSAssetHandler task-lifecycle bugs reproduced on 2026-10-16
/// (ops/ios-crashes/2026-10-16-IOSAssetHandler-repro.md):
///  - "This task has already been stopped" NSException when WebKit's stop() arrived before
///    the handler's queued start work registered the task (2.1.2 (70) production crash).
///  - Deadlock between stop() on main (waiting on completionSemaphore) and a background
///    completion waiting for the main run loop inside -[WKURLSchemeTask didFailWithError:].
@MainActor
final class IOSAssetHandlerTaskLifecycleRegressionTests: XCTestCase {
    private final class RecordingProxy: NSObject, WKURLSchemeHandler {
        let inner: IOSAssetHandler
        private(set) var starts = 0
        private(set) var stops = 0
        init(inner: IOSAssetHandler) { self.inner = inner }
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            starts += 1
            inner.webView(webView, start: urlSchemeTask)
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
            stops += 1
            inner.webView(webView, stop: urlSchemeTask)
        }
    }

    private var window: UIWindow?

    private func makeWebView(_ proxy: RecordingProxy) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(proxy, forURLScheme: "app-assets")
        UserDefaults.standard.set("app-assets", forKey: "WKURLSchemeHandler_Scheme")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let window = UIWindow(frame: webView.frame)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        self.window = window
        return webView
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    /// Deterministic: park the handler's private taskQueue so WebKit's stop() is delivered
    /// before the queued start work runs, then let the work complete with an error.
    /// Before the fix this raised "This task has already been stopped" (5/5).
    func testStopDeliveredBeforeQueuedStartWorkDoesNotRaise() throws {
        let handler = IOSAssetHandler()
        let proxy = RecordingProxy(inner: handler)
        let webView = makeWebView(proxy)
        let taskQueue = try XCTUnwrap(
            Mirror(reflecting: handler).children.first { $0.label == "taskQueue" }?.value as? DispatchQueue,
            "IOSAssetHandler.taskQueue hook moved; update this regression test"
        )

        taskQueue.async { Thread.sleep(forTimeInterval: 2.0) }
        webView.loadHTMLString(
            "<html><body><img src=\"app-assets://localhost/regression/missing-asset.nope\"></body></html>",
            baseURL: URL(string: "app-assets://localhost/")!
        )
        spin(0.8)
        XCTAssertEqual(proxy.starts, 1, "WebKit should have started the asset task")
        webView.loadHTMLString("<html><body>away</body></html>", baseURL: URL(string: "about:blank")!)
        spin(0.4)
        XCTAssertEqual(proxy.stops, 1, "WebKit should have stopped the task while taskQueue was parked")
        spin(3.0) // taskQueue resumes; the queued completion must be ignored, not raise.
        XCTAssertEqual(handler.activeTaskCount, 0)
    }

    /// Stress: hundreds of in-flight asset tasks, then navigate away mid-load.
    /// Before the fix this deadlocked (main blocked in stop() on completionSemaphore).
    func testNavigateAwayDuringManyAssetLoadsDoesNotHang() {
        executionTimeAllowance = 120
        let handler = IOSAssetHandler()
        let proxy = RecordingProxy(inner: handler)
        let webView = makeWebView(proxy)
        for round in 0..<5 {
            let imgs = (0..<400)
                .map { "<img src=\"app-assets://localhost/regression/r\(round)-missing-\($0).nope\">" }
                .joined()
            webView.loadHTMLString("<html><body>\(imgs)</body></html>", baseURL: URL(string: "app-assets://localhost/")!)
            spin(0.15)
            webView.loadHTMLString("<html><body>away</body></html>", baseURL: URL(string: "about:blank")!)
            spin(1.0)
        }
        spin(1.0)
        XCTAssertGreaterThan(proxy.starts, 0)
        XCTAssertEqual(handler.activeTaskCount, 0, "every task must be completed or stopped")
    }

    /// Records WKURLSchemeTask callbacks and the thread they arrive on.
    private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
        let request: URLRequest
        private(set) var events: [String] = []
        private(set) var bytes = 0
        private(set) var allOnMain = true
        init(url: String) { request = URLRequest(url: URL(string: url)!) }
        private func record(_ e: String) { allOnMain = allOnMain && Thread.isMainThread; events.append(e) }
        func didReceive(_ response: URLResponse) { record("response") }
        func didReceive(_ data: Data) { bytes += data.count; record("data") }
        func didFinish() { record("finish") }
        func didFailWithError(_ error: Error) { record("fail") }
    }

    private func waitUntil(_ timeout: TimeInterval, _ cond: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline { spin(0.05) }
    }

    /// Positive path: a bundled asset is still served, and every WebKit call is on main.
    func testBundledAssetServedOnMainThread() {
        let handler = IOSAssetHandler()
        let webView = WKWebView(frame: .zero)
        let task = FakeSchemeTask(url: "app-assets://localhost/styles/collapsible_tables.css")
        handler.webView(webView, start: task)
        waitUntil(5) { task.events.contains("finish") || task.events.contains("fail") }
        XCTAssertEqual(task.events, ["response", "data", "finish"])
        XCTAssertGreaterThan(task.bytes, 0)
        XCTAssertTrue(task.allOnMain, "WKURLSchemeTask methods must be called on the main thread")
        XCTAssertEqual(handler.activeTaskCount, 0)
    }

    /// stop() immediately after start(): no WebKit callbacks may follow, and stop() returns at once.
    func testStopImmediatelyAfterStartSuppressesCallbacks() {
        let handler = IOSAssetHandler()
        let webView = WKWebView(frame: .zero)
        let tasks = (0..<50).map { FakeSchemeTask(url: "app-assets://localhost/regression/missing-\($0).nope") }
        for t in tasks { handler.webView(webView, start: t); handler.webView(webView, stop: t) }
        spin(2.0)
        XCTAssertTrue(tasks.allSatisfy { $0.events.isEmpty }, "stopped tasks must never be completed")
        XCTAssertEqual(handler.activeTaskCount, 0)
    }
}

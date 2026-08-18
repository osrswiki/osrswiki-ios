import UIKit
import WebKit

/// Shared WebKit runtime so visible-row HTML prewarm and the first article WebView
/// pay process startup once instead of on every cold article open.
enum osrsArticleWebKitRuntime {
    static let processPool = WKProcessPool()
}

/// Keeps one process-level WKWebView alive so the first article open does not pay
/// WebKit process startup after a visible-row HTML prewarm already completed.
enum osrsWebViewProcessWarmer {
    private static var retainedWebView: WKWebView?

    @MainActor
    static func warmIfNeeded() {
        guard retainedWebView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.processPool = osrsArticleWebKitRuntime.processPool
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.isOpaque = false
        webView.loadHTMLString(
            """
            <!doctype html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            </head><body></body></html>
            """,
            baseURL: URL(string: "https://oldschool.runescape.wiki/")
        )
        retainedWebView = webView
    }
}

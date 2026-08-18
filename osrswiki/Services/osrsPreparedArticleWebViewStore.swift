import UIKit
import WebKit
import ObjectiveC

/// Off-screen WKWebView cache so a visible-row prewarm pays HTML parse and first
/// layout before the user taps. Android's prepared-article path is a cache hit on
/// the same WebView; iOS still constructed a fresh WKWebView on every open.
@MainActor
final class osrsPreparedArticleWebViewStore: NSObject, WKNavigationDelegate {
    static let shared = osrsPreparedArticleWebViewStore()

    private struct Entry {
        let key: Key
        let webView: WKWebView
        var isReady: Bool
    }

    private struct Key: Hashable {
        let identity: osrsArticleDocumentIdentity
        let options: osrsArticleRenderOptions

        var token: String {
            "\(identity.value)|dark=\(options.usesDarkTheme)|collapse=\(options.collapseTablesEnabled)|scale=\(options.articleTextScale)"
        }
    }

    private var entries: [Entry] = []
    private let maxEntries = 2
    private var hostView: UIView?

    func preload(document: osrsPreparedArticleDocument, options: osrsArticleRenderOptions) {
        let key = Key(identity: document.request.identity, options: options)
        if entries.contains(where: { $0.key == key }) {
            return
        }

        let configuration = Self.makeConfiguration(sourceArticleURL: document.request.pageURL)
        let webView = WKWebView(frame: hostBounds, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.osrsPreparedDocumentKey = key.token
        attachToHost(webView)

        evictIfNeeded()
        entries.append(Entry(key: key, webView: webView, isReady: false))

        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
        let baseURL = URL(string: "\(customScheme)://localhost/")!
        webView.loadHTMLString(document.html, baseURL: baseURL)
        print("🔥 PreparedArticleWebView: preloading \(key.identity.value)")
    }

    func take(
        pageURL: URL,
        pageTitle: String?,
        options: osrsArticleRenderOptions
    ) -> WKWebView? {
        let identity = osrsArticleDocumentIdentity(pageURL: pageURL, pageTitle: pageTitle)
        let key = Key(identity: identity, options: options)
        guard let index = entries.firstIndex(where: { $0.key == key && $0.isReady }) else {
            return nil
        }
        let entry = entries.remove(at: index)
        entry.webView.removeFromSuperview()
        entry.webView.navigationDelegate = nil
        print("⚡ PreparedArticleWebView: handing off \(key.identity.value)")
        return entry.webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let token = webView.osrsPreparedDocumentKey,
              let index = entries.firstIndex(where: { $0.webView === webView && $0.key.token == token }) else {
            return
        }
        entries[index].isReady = true
        print("✅ PreparedArticleWebView: ready \(entries[index].key.identity.value)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        entries.removeAll { $0.webView === webView }
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        entries.removeAll { $0.webView === webView }
        webView.removeFromSuperview()
    }

    static func makeConfiguration(sourceArticleURL: URL) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = osrsArticleWebKitRuntime.processPool
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let customScheme = "app-assets"
        configuration.setURLSchemeHandler(
            IOSAssetHandler(sourceArticleURL: sourceArticleURL),
            forURLScheme: customScheme
        )
        UserDefaults.standard.set(customScheme, forKey: "WKURLSchemeHandler_Scheme")
        return configuration
    }

    private func evictIfNeeded() {
        while entries.count >= maxEntries {
            let evicted = entries.removeFirst()
            evicted.webView.stopLoading()
            evicted.webView.removeFromSuperview()
        }
    }

    private var hostBounds: CGRect {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return scene.screen.bounds
        }
        return CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    private func attachToHost(_ webView: WKWebView) {
        if hostView == nil {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
            let host = UIView(frame: hostBounds)
            host.isUserInteractionEnabled = false
            host.alpha = 0.01
            host.isAccessibilityElement = false
            window?.insertSubview(host, at: 0)
            hostView = host
        }
        guard let host = hostView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }
}

private var osrsPreparedDocumentKeyHandle: UInt8 = 0

extension WKWebView {
    var osrsPreparedDocumentKey: String? {
        get { objc_getAssociatedObject(self, &osrsPreparedDocumentKeyHandle) as? String }
        set {
            objc_setAssociatedObject(
                self,
                &osrsPreparedDocumentKeyHandle,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
        }
    }
}

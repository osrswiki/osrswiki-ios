import UIKit
import WebKit
import ObjectiveC

/// Speculative live article preloads are a product non-requirement.
/// Shared process-pool warmup and on-demand HTML cache may remain.
enum osrsArticlePreloadPolicy {
    static let speculativeLiveArticlePreloadsEnabled = false
}

/// Off-screen WKWebView cache for guessed destinations. Production preload is
/// hard-disabled; `take` is a miss so the live article WebView is created on demand.
@MainActor
final class osrsPreparedArticleWebViewStore: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = osrsPreparedArticleWebViewStore()

    static var isPaintPrewarmDisabled: Bool {
        !osrsArticlePreloadPolicy.speculativeLiveArticlePreloadsEnabled
            || ProcessInfo.processInfo.arguments.contains("-osrsDisableFirstViewPaintPrewarm")
    }

    private struct Entry {
        let key: Key
        let webView: WKWebView
        var isReady: Bool
        var isPainted: Bool
    }

    private struct Key: Hashable {
        let identity: osrsArticleDocumentIdentity
        let options: osrsArticleRenderOptions

        var token: String {
            "\(identity.value)|dark=\(options.usesDarkTheme)|collapse=\(options.collapseTablesEnabled)|wrap=\(options.wrapTableCellsEnabled)|scale=\(options.articleTextScale)"
        }
    }

    private var entries: [Entry] = []
    private let maxEntries = 2
    private var hostView: UIView?
    private var dwellPinCounts: [String: Int] = [:]
    private var foregroundPins: Set<String> = []
    private var preferredPins: Set<String> = []

    func pin(identity: String, foreground: Bool = false, preferred: Bool = false) {
        if preferred {
            preferredPins.insert(identity)
        }
        if foreground {
            foregroundPins.insert(identity)
        } else {
            dwellPinCounts[identity, default: 0] += 1
        }
    }

    func unpin(identity: String) {
        guard let count = dwellPinCounts[identity] else { return }
        if count > 1 {
            dwellPinCounts[identity] = count - 1
        } else {
            dwellPinCounts.removeValue(forKey: identity)
            if !foregroundPins.contains(identity) {
                preferredPins.remove(identity)
            }
        }
    }

    func unpinForeground(identity: String) {
        foregroundPins.remove(identity)
    }

    func cancel(identity: String) {
        guard !isPinned(identity) else { return }
        let doomed = entries.filter { $0.key.identity.value == identity && !$0.isPainted }
        doomed.forEach { entry in
            detachPreparedHandlers(entry.webView)
            entry.webView.stopLoading()
            entry.webView.removeFromSuperview()
        }
        entries.removeAll { $0.key.identity.value == identity && !$0.isPainted }
    }

    private func isPinned(_ identity: String) -> Bool {
        foregroundPins.contains(identity) || (dwellPinCounts[identity] ?? 0) > 0
    }

    private func isPreferred(_ identity: String) -> Bool {
        foregroundPins.contains(identity) || preferredPins.contains(identity)
    }

    private func evictIfNeeded(admitting identity: String) {
        while entries.count >= maxEntries {
            if let unpinned = entries.firstIndex(where: { !isPinned($0.key.identity.value) }) {
                evict(at: unpinned)
                continue
            }
            if isPreferred(identity),
               let other = entries.lastIndex(where: { !isPreferred($0.key.identity.value) }) {
                evict(at: other)
                continue
            }
            // Cap is full of pinned entries. Do not evict a preferred neighbor to admit another.
            break
        }
    }

    func preload(document: osrsPreparedArticleDocument, options: osrsArticleRenderOptions) {
        guard osrsArticlePreloadPolicy.speculativeLiveArticlePreloadsEnabled else {
            return
        }
        if osrsBackgroundWorkGate.shared.isPaused {
            Task { @MainActor in
                await osrsBackgroundWorkGate.shared.waitWhilePaused()
                self.preload(document: document, options: options)
            }
            return
        }
        let key = Key(identity: document.request.identity, options: options)
        if entries.contains(where: { $0.key == key }) {
            return
        }
        evictIfNeeded(admitting: key.identity.value)
        if entries.count >= maxEntries {
            NSLog("PreparedArticleWebView: skip preload identity=%@ cap is full of pinned", key.identity.value)
            return
        }

        let configuration = Self.makeConfiguration(sourceArticleURL: document.request.pageURL)
        configuration.userContentController.add(self, contentWorld: .page, name: "osrsFirstViewComplete")
        configuration.userContentController.add(self, contentWorld: .page, name: "osrsFirstViewportSettled")
        configuration.userContentController.add(self, contentWorld: .page, name: "osrsLiveAssetWarm")
        let webView = WKWebView(frame: hostBounds, configuration: configuration)
        osrsWebViewThemePaint.apply(to: webView, usesDarkTheme: options.usesDarkTheme)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.osrsPreparedDocumentKey = key.token
        attachToHost(webView)

        entries.append(Entry(key: key, webView: webView, isReady: false, isPainted: false))

        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
        let baseURL = URL(string: "\(customScheme)://localhost/")!
        webView.loadHTMLString(document.html, baseURL: baseURL)
        print("🔥 PreparedArticleWebView: preloading \(key.identity.value)")
        NSLog("PreparedArticleWebView: preloading identity=%@", key.identity.value)
    }

    func take(
        pageURL: URL,
        pageTitle: String?,
        options: osrsArticleRenderOptions
    ) -> WKWebView? {
        guard osrsArticlePreloadPolicy.speculativeLiveArticlePreloadsEnabled else {
            return nil
        }
        if Self.isPaintPrewarmDisabled {
            return nil
        }
        let identity = osrsArticleDocumentIdentity(pageURL: pageURL, pageTitle: pageTitle)
        let key = Key(identity: identity, options: options)
        guard let index = entries.firstIndex(where: { $0.key == key && $0.isReady && $0.isPainted }) else {
            let painted = entries.filter(\.isPainted).map(\.key.identity.value).joined(separator: ",")
            let ready = entries.filter(\.isReady).map(\.key.identity.value).joined(separator: ",")
            print("⚠️ PreparedArticleWebView: miss \(key.identity.value) painted=[\(painted)] ready=[\(ready)]")
            NSLog(
                "PreparedArticleWebView: miss identity=%@ painted=%@ ready=%@",
                key.identity.value,
                painted,
                ready
            )
            return nil
        }
        let entry = entries.remove(at: index)
        unpinForeground(identity: key.identity.value)
        detachPreparedHandlers(entry.webView)
        entry.webView.removeFromSuperview()
        entry.webView.navigationDelegate = nil
        print("⚡ PreparedArticleWebView: handing off \(key.identity.value)")
        NSLog("PreparedArticleWebView: handing off identity=%@", key.identity.value)
        return entry.webView
    }

    func removeAll() {
        for entry in entries {
            detachPreparedHandlers(entry.webView)
            entry.webView.stopLoading()
            entry.webView.removeFromSuperview()
        }
        entries.removeAll()
    }

    /// iOS 26 snapshots the first window WebView. The process-warmer host is
    /// inserted at window index 0, so resume must take it out of the key
    /// window. `attachToHost` puts it back on the next preload.
    func detachFromKeyWindowForResume() {
        hostView?.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let token = webView.osrsPreparedDocumentKey,
              let index = entries.firstIndex(where: { $0.webView === webView && $0.key.token == token }) else {
            return
        }
        if Self.isPaintPrewarmDisabled {
            entries[index].isReady = true
            entries[index].isPainted = false
            return
        }
        let identity = entries[index].key.identity.value
        webView.evaluateJavaScript(
            "window.osrsCollectFirstViewportUrls && window.osrsCollectFirstViewportUrls()"
        ) { result, _ in
            let raw = result as? [String] ?? []
            let urls = raw.compactMap(osrsOfflineArticleResourceSettlement.networkURL(from:))
            osrsFirstViewPrewarmStore.shared.promote(identity: identity, urls: urls)
        }
        webView.evaluateJavaScript(
            "window.osrsWatchFirstViewComplete && window.osrsWatchFirstViewComplete()"
        )
        pollPainted(webView, attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        remove(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        remove(webView)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "osrsFirstViewComplete" || message.name == "osrsFirstViewportSettled" else { return }
        guard osrsWebKitSecurityPolicy.canAcceptScriptMessage(name: message.name, frameInfo: message.frameInfo) else {
            return
        }
        // Stopwatch-only on prepared path; paint readiness stays on firstViewComplete.
        guard message.name == "osrsFirstViewComplete" else { return }
        guard let webView = message.webView else { return }
        markPainted(webView)
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

    private func markPainted(_ webView: WKWebView) {
        guard let index = entries.firstIndex(where: { $0.webView === webView }) else {
            return
        }
        if entries[index].isPainted && entries[index].isReady {
            return
        }
        entries[index].isPainted = true
        entries[index].isReady = true
        let identity = entries[index].key.identity.value
        print("✅ PreparedArticleWebView: painted \(identity)")
        NSLog("osrsFirstViewPaintWarm: done identity=%@", identity)
    }

    private func pollPainted(_ webView: WKWebView, attempt: Int) {
        guard entries.contains(where: { $0.webView === webView }) else { return }
        if entries.contains(where: { $0.webView === webView && $0.isPainted && $0.isReady }) {
            return
        }
        webView.evaluateJavaScript(
            """
            (function(){
              try {
                if (window.__osrsFirstViewPainted && window.osrsNotifyFirstViewComplete) {
                  window.osrsNotifyFirstViewComplete();
                }
              } catch (e) {}
              return window.__osrsFirstViewPainted === true;
            })()
            """
        ) { result, _ in
            if (result as? Bool) == true {
                self.markPainted(webView)
                return
            }
            if attempt >= 150 {
                self.markPainted(webView)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.pollPainted(webView, attempt: attempt + 1)
            }
        }
    }

    private func remove(_ webView: WKWebView) {
        detachPreparedHandlers(webView)
        entries.removeAll { $0.webView === webView }
        webView.removeFromSuperview()
    }

    private func detachPreparedHandlers(_ webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "osrsFirstViewComplete", contentWorld: .page)
        controller.removeScriptMessageHandler(forName: "osrsFirstViewportSettled", contentWorld: .page)
        controller.removeScriptMessageHandler(forName: "osrsLiveAssetWarm", contentWorld: .page)
    }

    private func evict(at index: Int) {
        let evicted = entries.remove(at: index)
        detachPreparedHandlers(evicted.webView)
        evicted.webView.stopLoading()
        evicted.webView.removeFromSuperview()
    }

    private var hostBounds: CGRect {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return scene.screen.bounds
        }
        return CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    private func attachToHost(_ webView: WKWebView) {
        if hostView == nil {
            let host = UIView(frame: hostBounds)
            host.isUserInteractionEnabled = false
            host.alpha = 0.01
            host.accessibilityIdentifier = "osrs_prepared_article_host"
            host.isAccessibilityElement = false
            host.accessibilityElementsHidden = true
            hostView = host
        }
        guard let host = hostView else { return }
        if host.superview == nil {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
            // Never insert at 0: iOS 26 snapshots the first window subview's
            // WKWebView as the resumed scene. Keep the live UITransitionView first.
            window?.addSubview(host)
        }
        // Keep the process-warmer off the live compositor. A full-screen
        // alpha=0.01 WKWebView at (0,0) is the first WebView in the window
        // and iOS 26 will snapshot it as the resumed scene.
        var parked = hostBounds
        parked.origin.x = hostBounds.width
        host.frame = parked
        host.alpha = 0.01
        host.setNeedsLayout()
        host.layoutIfNeeded()
        webView.isAccessibilityElement = false
        webView.accessibilityElementsHidden = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        host.layoutIfNeeded()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
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

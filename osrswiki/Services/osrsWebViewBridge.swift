//
//  osrsWebViewBridge.swift
//  osrswiki
//
//  JavaScript bridge for iOS WebView interactions
//  Provides gesture blocking functionality matching Android's OsrsWikiBridge
//

import Foundation
import WebKit

/// JavaScript bridge handler for WebView communication
class osrsWebViewBridge: NSObject, WKScriptMessageHandler {
    
    static let shared = osrsWebViewBridge()
    
    // JavaScript interface name matching Android
    static let bridgeName = "OsrsWikiBridge"
    
    override init() {
        super.init()
    }
    
    /// Handle messages from JavaScript - matches Android OsrsWikiBridge interface
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.bridgeName else { return }
        
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String else {
            print("[WebViewBridge] Invalid message format: \(message.body)")
            return
        }
        
        switch method {
        case "setHorizontalScroll":
            if let isScrolling = body["isScrolling"] as? Bool {
                handleSetHorizontalScroll(isScrolling)
            }

        case "setHorizontalScrollGesture":
            if let phase = body["phase"] as? String,
               let gestureId = body["gestureId"] as? String {
                let ownerId = body["ownerId"] as? String ?? "article-navigation"
                let isLocalOwner: Bool
                if let explicit = body["isLocalOwner"] as? Bool {
                    isLocalOwner = explicit
                } else {
                    let inProgress = phase == "begin" || phase == "change"
                    isLocalOwner = inProgress && ownerId != "article-navigation"
                }
                handleSetHorizontalScrollGesture(
                    phase: phase,
                    gestureId: gestureId,
                    ownerId: ownerId,
                    isLocalOwner: isLocalOwner
                )
            }

        case "setArticleTouchSequence":
            // iOS arbitration binds DOM ownership by gesture id; sequence is informational.
            break
            
        case "log":
            if let logMessage = body["message"] as? String {
                print("[WebViewBridge-JS] \(logMessage)")
            }

        case "playYouTube":
            if let videoId = body["videoId"] as? String {
                NotificationCenter.default.post(
                    name: .osrsPlayYouTubeRequested,
                    object: nil,
                    userInfo: ["videoId": videoId]
                )
            }

        case "fetchText":
            let requestId = body["id"] as? String ?? ""
            let url = body["url"] as? String ?? ""
            let webView = message.webView
            Task.detached {
                let text = await osrsGeChartPriceCache.fetchText(urlString: url)
                await MainActor.run {
                    osrsGeChartPriceCache.completeFetchText(on: webView, id: requestId, text: text)
                }
            }

        case "rememberGeChart":
            let url = body["url"] as? String ?? ""
            let text = body["text"] as? String ?? ""
            Task.detached {
                guard let parsed = URL(string: url), !text.isEmpty else { return }
                osrsGeChartPriceCache.write(url: parsed, body: text)
            }

        default:
            print("[WebViewBridge] Unknown method: \(method)")
        }
    }
    
    /// Handle horizontal scroll state from JavaScript
    private func handleSetHorizontalScroll(_ isScrolling: Bool) {
        DispatchQueue.main.async {
            osrsGestureState.shared.isJavaScriptScrollBlocked = isScrolling
            print("[WebViewBridge] JavaScript scroll blocking: \(isScrolling)")
        }
    }

    /// Phased local-scroll ownership — mirrors Android NativeMapHandler.setHorizontalScrollGesture.
    private func handleSetHorizontalScrollGesture(
        phase: String,
        gestureId: String,
        ownerId: String,
        isLocalOwner: Bool
    ) {
        DispatchQueue.main.async {
            print("[WebViewBridge] gesture phase=\(phase) id=\(gestureId) owner=\(ownerId) local=\(isLocalOwner)")
            switch phase {
            case "begin":
                osrsGestureState.shared.classifyJavaScriptGesture(
                    id: gestureId,
                    isLocalOwner: isLocalOwner
                )
            case "change":
                if isLocalOwner {
                    osrsGestureState.shared.claimJavaScriptGesture(id: gestureId)
                }
            case "end":
                osrsGestureState.shared.endJavaScriptGesture(id: gestureId)
            case "cancel":
                osrsGestureState.shared.cancelJavaScriptGesture(id: gestureId)
            default:
                break
            }
        }
    }
    
    /// Configure WebView with bridge and JavaScript integration
    static func configureWebView(_ webView: WKWebView) {
        // Add bridge message handler
        webView.configuration.userContentController.add(shared, name: bridgeName)
        
        // Inject iOS-compatible bridge JavaScript
        let bridgeScript = WKUserScript(source: bridgeJavaScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(bridgeScript)
        
        // Inject horizontal scroll interceptor (modified for iOS)
        if let interceptorScript = loadHorizontalScrollInterceptor() {
            let script = WKUserScript(source: interceptorScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            webView.configuration.userContentController.addUserScript(script)
        }
    }
    
    /// Bridge JavaScript interface matching Android
    private static var bridgeJavaScript: String {
        let ua = osrsWikiApiStewardship.appUserAgent("webview")
        return """
        window.osrsApiUserAgent = '\(ua)';
        window.OsrsWikiBridge = {
            // Match Android setHorizontalScroll interface
            setHorizontalScroll: function(isScrolling) {
                try {
                    window.webkit.messageHandlers.OsrsWikiBridge.postMessage({
                        method: 'setHorizontalScroll',
                        isScrolling: isScrolling
                    });
                } catch (e) {
                    console.warn('Failed to communicate horizontal scroll state:', e);
                }
            },

            // Phased ownership matching Android NativeMapHandler.setHorizontalScrollGesture.
            // horizontal_scroll_interceptor.js prefers this over the legacy bool API.
            setHorizontalScrollGesture: function(phase, gestureId, ownerId) {
                try {
                    var local = (phase === 'begin' || phase === 'change') && ownerId !== 'article-navigation';
                    var payload = {
                        method: 'setHorizontalScrollGesture',
                        phase: String(phase || ''),
                        gestureId: String(gestureId || ''),
                        ownerId: String(ownerId || 'article-navigation'),
                        isLocalOwner: !!local
                    };
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'setHorizontalScrollGesture',
                            phase: payload.phase,
                            gestureId: payload.gestureId,
                            ownerId: payload.ownerId,
                            isLocalOwner: payload.isLocalOwner
                        });
                    } else {
                        window.webkit.messageHandlers.OsrsWikiBridge.postMessage(payload);
                    }
                } catch (e) {
                    console.warn('Failed to communicate horizontal scroll gesture:', e);
                }
            },

            // Android binds DOM touch sequences to native pointer generations; iOS binds via
            // gesture id in classifyJavaScriptGesture. Keep the hook so the interceptor does
            // not silently no-op on one platform.
            setArticleTouchSequence: function(sequence) {
                try {
                    window.webkit.messageHandlers.OsrsWikiBridge.postMessage({
                        method: 'setArticleTouchSequence',
                        sequence: Number(sequence) || 0
                    });
                } catch (e) {}
            },
            
            // Match Android log interface  
            log: function(message) {
                try {
                    window.webkit.messageHandlers.OsrsWikiBridge.postMessage({
                        method: 'log',
                        message: message
                    });
                } catch (e) {
                    console.warn('Failed to log message:', e);
                }
            },

            playYouTube: function(videoId) {
                try {
                    window.webkit.messageHandlers.osrsYouTube.postMessage({
                        videoId: videoId
                    });
                } catch (e) {
                    try {
                        window.webkit.messageHandlers.OsrsWikiBridge.postMessage({
                            method: 'playYouTube',
                            videoId: videoId
                        });
                    } catch (ignored) {
                        console.warn('Failed to open YouTube video:', e);
                    }
                }
            },

            // Sync XHR matches main's first-view path. WKWebView already
            // sends the identified User-Agent via applicationNameForUserAgent.
            // Do not set Api-User-Agent here — that header is not CORS
            // safelisted and forces an OPTIONS preflight before the GET.
            fetchText: function(url) {
                try {
                    var xhr = new XMLHttpRequest();
                    xhr.open('GET', url, false);
                    xhr.setRequestHeader('Accept', 'application/json');
                    xhr.send(null);
                    var text = (xhr.status >= 200 && xhr.status < 300) ? (xhr.responseText || '') : '';
                    if (text) {
                        try {
                            window.webkit.messageHandlers.OsrsWikiBridge.postMessage({
                                method: 'rememberGeChart',
                                url: String(url || ''),
                                text: text
                            });
                        } catch (ignored) {}
                    }
                    return text;
                } catch (e) {
                    return '';
                }
            }
        };
        
        // Ensure bridge is available for horizontal scroll interceptor
        console.log('[WebViewBridge] iOS bridge initialized');
    """
    }
    
    /// Load horizontal scroll interceptor JavaScript 
    private static func loadHorizontalScrollInterceptor() -> String? {
        guard let url = Bundle.main.url(forResource: "horizontal_scroll_interceptor", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            print("[WebViewBridge] Warning: Could not load horizontal_scroll_interceptor.js")
            return nil
        }
        return script
    }
}

/// Extension to integrate bridge with ArticleWebView
extension ArticleWebView {
    /// Configure WebView for horizontal gesture support
    func configureGestureSupport(_ webView: WKWebView) {
        osrsWebViewBridge.configureWebView(webView)
    }
}

// Helper extension to find the view controller for presenting alerts
extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}

enum osrsGeChartPriceCache {
    private static let memoryLock = NSLock()
    private static var memory: [String: (expires: Date, body: String)] = [:]
    private static let itemIdRegex = try? NSRegularExpression(
        pattern: #"data-itemid=["'](\d+)["']"#
    )

    static func timeseriesURL(itemId: String) -> URL? {
        URL(string: "https://prices.runescape.wiki/api/v2/osrs/timeseries?lookback=1y&id=\(itemId)")
    }

    static func itemIDs(in html: String) -> [String] {
        guard let regex = itemIdRegex else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    /// Hydrate native memory from disk off the calling thread. Never wait for this.
    static func prefetchDiskAsync(itemIDs: [String]) {
        let ids = itemIDs
        guard !ids.isEmpty else { return }
        Task.detached {
            for id in ids {
                guard let url = timeseriesURL(itemId: id) else { continue }
                _ = readDisk(url: url)
            }
        }
    }

    /// Memory-only snapshot for HTML injection. Does not touch disk.
    static func memoryPrefetchScript(itemIDs: [String]) -> String {
        var hits: [String: Any] = [:]
        for id in itemIDs {
            guard
                let url = timeseriesURL(itemId: id),
                let raw = readMemory(url: url),
                let data = raw.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }
            hits[id] = obj
        }
        guard
            !hits.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: hits),
            let json = String(data: data, encoding: .utf8)
        else {
            return "window.__osrsGeChartPrefetch=window.__osrsGeChartPrefetch||{};"
        }
        return "window.__osrsGeChartPrefetch=Object.assign(window.__osrsGeChartPrefetch||{},\(json));"
    }

    static func fetchText(urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return "" }
        if let cached = readMemory(url: url) {
            return cached
        }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { readDisk(url: url) }
            group.addTask { await fetchNetworkOnce(url: url) }
            for await result in group {
                guard let result, !result.isEmpty else { continue }
                group.cancelAll()
                return result
            }
            return ""
        }
    }

    private static func fetchNetworkOnce(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue(
            osrsWikiApiStewardship.appUserAgent("native-bridge"),
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            guard (200...299).contains(status), !body.isEmpty else { return nil }
            write(url: url, body: body)
            return body
        } catch {
            return nil
        }
    }

    static func completeFetchText(on webView: WKWebView?, id: String, text: String) {
        guard let webView, !id.isEmpty else { return }
        let payload: [String: Any] = ["id": id, "text": text]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        webView.evaluateJavaScript("window.osrsFetchTextComplete && window.osrsFetchTextComplete(\(json));")
    }

    static func read(url: URL, now: Date = Date()) -> String? {
        readMemory(url: url, now: now) ?? readDisk(url: url, now: now)
    }

    static func readMemory(url: URL, now: Date = Date()) -> String? {
        let key = cacheKey(url)
        memoryLock.lock()
        defer { memoryLock.unlock() }
        if let hit = memory[key] {
            if now < hit.expires, !hit.body.isEmpty {
                return hit.body
            }
            memory.removeValue(forKey: key)
        }
        return nil
    }

    static func readDisk(url: URL, now: Date = Date()) -> String? {
        let key = cacheKey(url)
        let file = fileURL(for: key)
        guard
            let raw = try? String(contentsOf: file, encoding: .utf8),
            let split = raw.firstIndex(of: "\n")
        else {
            return nil
        }
        let expiresRaw = String(raw[..<split])
        let body = String(raw[raw.index(after: split)...])
        guard
            let expiresMs = TimeInterval(expiresRaw),
            now.timeIntervalSince1970 * 1000 < expiresMs,
            !body.isEmpty
        else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        memoryLock.lock()
        memory[key] = (Date(timeIntervalSince1970: expiresMs / 1000), body)
        memoryLock.unlock()
        return body
    }

    static func write(url: URL, body: String, now: Date = Date()) {
        guard !body.isEmpty else { return }
        let key = cacheKey(url)
        let expires = now.addingTimeInterval(osrsWikiApiStewardship.geChartCacheTTL)
        memoryLock.lock()
        memory[key] = (expires, body)
        memoryLock.unlock()
        let file = fileURL(for: key)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let expiresMs = Int(expires.timeIntervalSince1970 * 1000)
        try? "\(expiresMs)\n\(body)".write(to: file, atomically: true, encoding: .utf8)
    }

    private static func fileURL(for key: String) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("osrs-ge-charts", isDirectory: true)
            .appendingPathComponent("\(key).json")
    }

    private static func cacheKey(_ url: URL) -> String {
        Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
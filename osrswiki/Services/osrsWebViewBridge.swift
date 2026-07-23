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
            
        case "log":
            if let logMessage = body["message"] as? String {
                print("[WebViewBridge-JS] \(logMessage)")
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
    private static let bridgeJavaScript = """
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
            }
        };
        
        // Ensure bridge is available for horizontal scroll interceptor
        console.log('[WebViewBridge] iOS bridge initialized');
    """
    
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
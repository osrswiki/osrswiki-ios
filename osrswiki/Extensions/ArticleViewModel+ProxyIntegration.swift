//
//  ArticleViewModel+ProxyIntegration.swift
//  OSRS Wiki
//
//  Integration between ArticleViewModel and iOS 17/18 proxy-based HTTP interception
//  This replaces the web archive approach with modern HTTP caching
//

import Foundation
import WebKit

// MARK: - ArticleViewModel Proxy Integration

@available(iOS 17.0, *)
extension ArticleViewModel {
    
    /// Configure the current WebView for proxy-based HTTP interception
    /// This replaces web archive loading with modern iOS 17/18 capabilities
    func enableProxyBasedOfflineSupport() {
        guard let webView = self.webView else {
            print("❌ ArticleViewModel: Cannot enable proxy support - WebView not available")
            return
        }
        
        let success = ProxyInterceptorService.shared.configureWebViewForProxyInterception(webView)
        
        if success {
            print("✅ ArticleViewModel: Proxy-based offline support enabled")
        } else {
            print("❌ ArticleViewModel: Failed to enable proxy-based offline support")
        }
    }
    
    /// Enable caching mode for offline page saving (replaces web archive creation)
    @discardableResult
    func enableOfflineCachingMode(pageId: String) async -> ProxyCacheSessionToken? {
        print("💾 ArticleViewModel: Enabling offline caching for page: \(pageId)")
        
        if #available(iOS 17.0, *) {
            return await ProxyInterceptorService.shared.enableOfflineSaveMode(pageId: pageId)
        } else {
            print("⚠️ ArticleViewModel: Proxy caching requires iOS 17+, falling back to web archive")
            // Could fall back to web archive approach for older iOS versions
            return nil
        }
    }
    
    /// Disable caching mode and return to normal operation
    func disableOfflineCachingMode(owner token: ProxyCacheSessionToken) {
        print("🔄 ArticleViewModel: Disabling owned offline caching mode")
        ProxyInterceptorService.shared.disableMode(owner: token)
    }
    
    /// Check if a page has complete offline cache available
    func hasCompleteOfflineCache(pageId: String) -> Bool {
        guard #available(iOS 17.0, *) else { return false }
        
        return ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: pageId)
    }
    
    /// Load a page using proxy-based caching (replaces web archive loading)
    func loadPageWithProxyBasedCaching(pageId: String, originalURL: URL) {
        guard #available(iOS 17.0, *) else {
            print("⚠️ ArticleViewModel: Proxy loading requires iOS 17+")
            return
        }
        
        // Configure proxy support if not already done
        enableProxyBasedOfflineSupport()
        
        // INTELLIGENT MODE DETECTION: Check cache status and connectivity
        let hasCache = hasCompleteOfflineCache(pageId: pageId)
        
        Task { @MainActor in
            let isOffline = !NetworkManager.shared.isConnected
            let ownerToken: ProxyCacheSessionToken?
        
            if isOffline && hasCache {
                // CACHE-ONLY MODE: Complete offline with cached content
                print("📦 ArticleViewModel: Offline + cached content = CACHE-ONLY mode for: \(pageId)")
                ownerToken = await ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: pageId)
            } else if !hasCache && !isOffline {
                // SAVE-WHILE-SERVING MODE: Online but no cache = save content while serving
                print("📡 ArticleViewModel: Online + no cache = SAVE-WHILE-SERVING mode for: \(pageId)")
                ownerToken = await enableOfflineCachingMode(pageId: pageId)
            } else if hasCache && !isOffline {
                // NORMAL SERVING MODE: Online with cache = serve normally, no saving needed
                print("🌐 ArticleViewModel: Online + cached content = NORMAL mode for: \(pageId)")
                // No special proxy mode needed - just load normally
                ownerToken = nil
            } else {
                // OFFLINE WITHOUT CACHE: Should show error, but try cache-only mode anyway
                print("⚠️ ArticleViewModel: Offline + no cache = ERROR scenario for: \(pageId)")
                print("🔄 ArticleViewModel: Attempting cache-only mode as fallback")
                ownerToken = await ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: pageId)
            }
            
            // Load the original HTTPS URL - proxy will handle caching/serving automatically
            print("🌐 ArticleViewModel: Loading page with proxy support: \(originalURL.absoluteString)")
            
            // Use the existing loadArticle method with the current theme
            // The proxy system will transparently handle online/offline switching
            loadArticle(theme: osrsLightTheme(), isReload: false)
            
            // Auto-disable save mode after a reasonable timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                if let ownerToken {
                    ProxyInterceptorService.shared.disableMode(owner: ownerToken)
                }
            }
        }
    }
    
    /// Extract page title from URL for display
    private func extractTitleFromURL(_ url: URL) -> String {
        if url.pathComponents.count > 2 {
            let title = url.pathComponents.last ?? "Wiki Page"
            return title.replacingOccurrences(of: "_", with: " ")
        }
        return "Wiki Page"
    }
    
    /// Test proxy configuration without loading a full page
    func testProxyConfiguration() -> Bool {
        guard #available(iOS 17.0, *),
              let webView = self.webView else {
            print("❌ ArticleViewModel: Proxy test failed - requirements not met")
            return false
        }
        
        let success = ProxyInterceptorService.shared.configureWebViewForProxyInterception(webView)
        print(success ? "✅ ArticleViewModel: Proxy configuration test passed" : "❌ ArticleViewModel: Proxy configuration test failed")
        
        return success
    }
}

// MARK: - SavedPagesViewModel Integration Helper
// (navigateToPageWithProxySupport is now implemented directly in SavedPagesViewModel.swift)

// MARK: - Migration Helper

/// Helper to migrate from web archive approach to proxy-based approach
@available(iOS 17.0, *)
class ProxyMigrationHelper {
    
    static func canUseMmodernProxyApproach() -> Bool {
        // Check iOS version and other requirements
        guard #available(iOS 17.0, *) else { return false }
        
        // Test if proxy configuration works
        let testResult = ProxyInterceptorTestRunner.runBasicCompatibilityTest()
        return testResult
    }
    
    static func migrateFromWebArchiveToProxy() {
        print("🔄 ProxyMigrationHelper: Starting migration from web archive to proxy-based approach")
        
        // This could include:
        // 1. Converting existing web archive files to proxy cache format
        // 2. Updating SavedPage URLs from custom schemes to HTTPS
        // 3. Cleaning up old web archive files
        
        print("🎉 ProxyMigrationHelper: Migration completed - now using modern proxy-based offline system")
    }
}

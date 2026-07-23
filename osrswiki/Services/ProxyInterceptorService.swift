//
//  ProxyInterceptorService.swift
//  OSRS Wiki
//
//  iOS 17/18 Proxy-Based HTTP Interception Service
//  Modern replacement for web archive approach
//

import Foundation
import Network
import WebKit

/// Modern iOS 17/18 proxy-based HTTP interception service
/// Enables Android-style request/response caching for offline functionality
@available(iOS 17.0, *)
@MainActor
class ProxyInterceptorService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ProxyInterceptorService()
    
    // MARK: - Properties
    private var localServer: LocalHTTPServer?
    private var isServerRunning = false
    private let serverPort: UInt16 = 0
    private var activeServerPort: UInt16?
    private var currentPageId: String?
    private var activeSessionToken: ProxyCacheSessionToken?
    private weak var activeAssetHandler: IOSAssetHandler?
    
    // MARK: - Initialization
    private init() {
        print("🚀 ProxyInterceptorService: Initializing iOS 17+ HTTP interception service...")
        
        // Perform cache cleanup on startup to remove any corrupted entries
        DispatchQueue.global(qos: .background).async {
            // Delay to allow server initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.cleanupCorruptedCacheOnStartup()
            }
        }
    }
    
    /// Perform cache cleanup during app startup
    private func cleanupCorruptedCacheOnStartup() {
        do {
            // Initialize server if needed for cache cleanup
            try startLocalServerIfNeeded()
            cleanupCorruptedCache()
        } catch {
            print("⚠️ ProxyInterceptorService: Cache cleanup failed during startup: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Prepare app-owned proxy services without installing a WKWebView CONNECT proxy.
    func configureWebViewForProxyInterception(_ webView: WKWebView) -> Bool {
        webView.configuration.websiteDataStore.proxyConfigurations = []
        print("✅ ProxyInterceptorService: WKWebView CONNECT proxy disabled; app-owned requests may still use local cache routing")
        return true
    }
    
    /// Enable caching mode for offline page saving (like Android's X-Offline-Save header)
    @discardableResult
    func enableOfflineSaveMode(pageId: String) -> ProxyCacheSessionToken? {
        print("💾 ProxyInterceptorService: Enabling offline save mode for page: \(pageId)")
        do {
            try startLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for offline save mode: \(error)")
            return nil
        }
        currentPageId = pageId
        guard let localToken = localServer?.enableSaveMode(pageId: pageId) else {
            return nil
        }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        
        // CRITICAL: Also configure NetworkManager to route API calls through proxy
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(enabled: true, port: Int(activeServerPort))
        }

        return token
    }
    
    /// Register an IOSAssetHandler for coordinated save mode management
    func registerAssetHandler(_ handler: IOSAssetHandler) {
        activeAssetHandler = handler
        print("📝 ProxyInterceptorService: Registered IOSAssetHandler for coordinated caching")
    }
    
    /// Enable passive caching mode for lazy resource collection during normal browsing
    /// Like Android's OfflineCacheInterceptor but without marking as saved
    @discardableResult
    func enablePassiveCachingMode(pageId: String) -> ProxyCacheSessionToken? {
        print("🌐 ProxyInterceptorService: Enabling passive caching mode for page: \(pageId)")
        print("   → Resources will be cached automatically during browsing")
        do {
            try startLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for passive caching: \(error)")
            return nil
        }
        currentPageId = pageId
        
        // Enable save mode to cache resources, but they won't be marked as "saved"
        // This is the key to lazy caching - cache everything, save nothing
        guard let localToken = localServer?.enableSaveMode(pageId: pageId) else {
            return nil
        }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        
        // Configure NetworkManager to route through proxy for resource caching
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(enabled: true, port: Int(activeServerPort))
        }
        
        // NO TIMEOUT - save mode remains active until explicitly disabled
        // This ensures all resources are cached regardless of browsing speed
        print("   → Save mode will remain active until explicitly disabled (no timeout)")
        return token
    }
    
    /// Disable caching mode and return to normal operation
    func disableOfflineSaveMode() {
        print("🔄 ProxyInterceptorService: Disabling offline save mode")
        if let token = activeSessionToken {
            disableMode(owner: token)
            return
        }

        currentPageId = nil
        localServer?.disableSaveMode()
        
        // Also disable NetworkManager proxy routing
        Task { @MainActor in
            NetworkManager.shared.configureProxyRouting(enabled: false)
        }
    }

    func disableMode(owner token: ProxyCacheSessionToken) {
        guard activeSessionToken == token else {
            print("🔒 ProxyInterceptorService: Ignoring stale cache mode teardown for page: \(token.pageId)")
            return
        }

        currentPageId = nil
        activeSessionToken = nil
        localServer?.disableMode(owner: token.localToken)

        Task { @MainActor in
            NetworkManager.shared.configureProxyRouting(enabled: false)
        }
    }
    
    /// Check if a page has complete offline cache
    func hasCompleteOfflineCache(pageId: String) -> Bool {
        return localServer?.hasCompleteCache(pageId: pageId) ?? false
    }
    
    /// Link a saved page to existing cache from browsing (for instant saves)
    func linkSavedPageToCache(savedPageId: String, browsingPageId: String) {
        print("🔗 ProxyInterceptorService: Linking saved page '\(savedPageId)' to browsing cache '\(browsingPageId)'")
        
        // Copy or link the cache entries from browsing page ID to saved page ID
        localServer?.copyCacheEntries(from: browsingPageId, to: savedPageId)
        
        print("✅ ProxyInterceptorService: Cache linked successfully - instant save complete")
    }
    
    /// Enable cache-only mode for offline serving (no network attempts)
    @discardableResult
    func enableCacheOnlyMode(pageId: String) -> ProxyCacheSessionToken? {
        print("📦 ProxyInterceptorService: Enabling cache-only mode for page: \(pageId)")
        do {
            try startLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for cache-only mode: \(error)")
            return nil
        }
        currentPageId = pageId
        // Set page ID context without enabling save mode (we want to serve, not save)
        guard let localToken = localServer?.setPageIdContext(pageId: pageId) else {
            return nil
        }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        
        // Configure NetworkManager to route through proxy (cached content only)
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(enabled: true, port: Int(activeServerPort))
        }

        return token
    }
    
    
    /// Clean up corrupted cache entries (HTML error pages cached as binary resources)
    func cleanupCorruptedCache() {
        print("🧹 ProxyInterceptorService: Initiating cache cleanup...")
        localServer?.cleanupCorruptedCache()
    }
    
    /// Get current pageId context (for IOSAssetHandler cache lookups)
    func getCurrentPageId() -> String? {
        return currentPageId
    }
    
    /// Get cached response for asset requests (bridge to LocalHTTPServer for IOSAssetHandler)
    func getCachedAssetResponse(url: String, pageId: String) -> (data: Data, response: HTTPURLResponse)? {
        print("🔍 ProxyInterceptorService: Bridge request for cached asset: \(url), pageId: \(pageId)")
        
        guard let cachedResponse = localServer?.getCachedResponseForAsset(url: url, pageId: pageId) else {
            print("❌ ProxyInterceptorService: No cached response found through LocalHTTPServer")
            return nil
        }
        
        // Convert CachedHTTPResponse to format expected by IOSAssetHandler
        guard let originalUrl = URL(string: cachedResponse.url),
              let httpResponse = HTTPURLResponse(
                url: originalUrl,
                statusCode: cachedResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: cachedResponse.headers
              ) else {
            print("❌ ProxyInterceptorService: Failed to create HTTPURLResponse from cached data")
            return nil
        }
        
        print("✅ ProxyInterceptorService: Successfully bridged cached asset response (\(cachedResponse.data.count) bytes)")
        return (data: cachedResponse.data, response: httpResponse)
    }
    
    /// Audit cache contents for debugging incomplete caching issues
    func auditCacheForPage(pageId: String) {
        print("🔍 ProxyInterceptorService: Performing cache audit for pageId: \(pageId)")
        localServer?.auditCacheForPage(pageId: pageId)
    }
    
    /// Cache response directly from IOSAssetHandler for asset requests
    func cacheResponseForAsset(pageId: String, url: String, data: Data, response: HTTPURLResponse) {
        print("💾 ProxyInterceptorService: Caching asset response from IOSAssetHandler for URL: \(url)")
        
        // Use LocalHTTPServer to save the response to cache
        localServer?.cacheResponseDirect(pageId: pageId, url: url, data: data, response: response)
        
        print("✅ ProxyInterceptorService: Successfully cached asset response (\(data.count) bytes)")
    }
    
    // MARK: - Private Methods
    
    /// Start local HTTP server for request/response handling
    private func startLocalServerIfNeeded() throws {
        guard !isServerRunning else { return }
        
        let server = LocalHTTPServer(port: serverPort)
        let boundPort = try server.start()
        localServer = server
        isServerRunning = true
        activeServerPort = boundPort
        
        print("🌐 ProxyInterceptorService: Started local HTTP server on port \(boundPort)")
    }
    
    /// Stop local HTTP server
    func stopLocalServer() {
        localServer?.stop()
        localServer = nil
        isServerRunning = false
        activeServerPort = nil
        print("🛑 ProxyInterceptorService: Stopped local HTTP server")
    }

#if DEBUG
    func seedOfflineSavedPageForUITests(pageId: String, title: String) {
        do {
            try startLocalServerIfNeeded()
            localServer?.seedMainHTMLCacheForUITests(pageId: pageId, title: title)
            print("🧪 ProxyInterceptorService: Seeded offline cache for \(title) (\(pageId))")
        } catch {
            print("❌ ProxyInterceptorService: Failed to seed offline UI test cache: \(error)")
        }
    }
#endif
}

// MARK: - Local HTTP Server

// LocalHTTPServer is now in its own file: LocalHTTPServer.swift

// MARK: - Supporting Types
// CachedResponse is now CachedHTTPResponse in LocalHTTPServer.swift

// MARK: - Error Types

enum ProxyInterceptorError: Error {
    case serverStartFailed
    case proxyConfigurationFailed
    case unsupportediOSVersion
    
    var localizedDescription: String {
        switch self {
        case .serverStartFailed:
            return "Failed to start local HTTP server for proxy interception"
        case .proxyConfigurationFailed:
            return "Failed to configure WKWebView proxy settings"
        case .unsupportediOSVersion:
            return "Proxy interception requires iOS 17 or later"
        }
    }
}

struct ProxyCacheSessionToken: Equatable {
    let id = UUID()
    let pageId: String
    let localToken: LocalHTTPServerCacheSessionToken
}

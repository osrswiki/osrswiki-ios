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

private struct osrsPreparedProxyServer: @unchecked Sendable {
    let server: LocalHTTPServer
    let port: UInt16
    let generation: UInt64
}

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
    private var serverStartTask: Task<osrsPreparedProxyServer, Error>?
    private var serverStartGeneration: UInt64 = 0
#if DEBUG
    private var serverStartupDelayForTesting: TimeInterval = 0
#endif
    private var currentPageId: String?
    private var activeSessionToken: ProxyCacheSessionToken?
    private var explicitSaveReservation: ProxyExplicitSaveReservation?
    private var explicitSaveSessionToken: ProxyCacheSessionToken?
    private weak var activeAssetHandler: IOSAssetHandler?
    
    // MARK: - Initialization
    private init() {
        print("🚀 ProxyInterceptorService: Initializing iOS 17+ HTTP interception service...")

        // Cache maintenance must never start/listen or decode legacy media on MainActor. A
        // maintenance-only store shares the serialized cache-I/O queue and performs no networking.
        Task.detached(priority: .utility) {
            LocalHTTPServer(port: 0).performStartupMaintenanceAsync()
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
    func enableOfflineSaveMode(pageId: String) async -> ProxyCacheSessionToken? {
        print("💾 ProxyInterceptorService: Enabling offline save mode for page: \(pageId)")
        do {
            try await prepareLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for offline save mode: \(error)")
            return nil
        }
        guard !Task.isCancelled else { return nil }
        do {
            try await waitForExplicitSaveRelease()
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        currentPageId = pageId
        guard let localToken = localServer?.enableSaveMode(pageId: pageId) else {
            return nil
        }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        
        // CRITICAL: Also configure NetworkManager to route API calls through proxy
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(
                enabled: true,
                port: Int(activeServerPort),
                allowsDirectFallback: true
            )
        }

        return token
    }

    /// Explicit user saves refresh every required response through the local server. Client-side
    /// direct fallback is disabled so success cannot bypass the atomic page-scoped disk commit.
    /// Reserve before metadata lookup so a later presentation cannot acquire and then lose the
    /// singleton routing context while this save is preparing its durable namespace.
    func reserveExplicitSaveLease(
        replacingPresentationOwner owner: ProxyCacheSessionToken? = nil
    ) -> ProxyExplicitSaveReservation? {
        guard explicitSaveReservation == nil,
              explicitSaveSessionToken == nil else {
            return nil
        }

        if let owner {
            // Saved ArticleView already owns cache-only/cache-first routing. Transfer that exact
            // presentation owner into the explicit lease in one MainActor operation so another
            // article cannot steal the singleton between a separate disable and reservation.
            guard activeSessionToken == owner else { return nil }
            currentPageId = nil
            activeSessionToken = nil
            localServer?.disableMode(owner: owner.localToken)
            NetworkManager.shared.configureProxyRouting(enabled: false)
        } else {
            guard activeSessionToken == nil else { return nil }
        }

        let reservation = ProxyExplicitSaveReservation()
        explicitSaveReservation = reservation
        return reservation
    }

    func releaseExplicitSaveReservation(_ reservation: ProxyExplicitSaveReservation) {
        guard explicitSaveReservation == reservation else { return }
        explicitSaveReservation = nil
    }

    @discardableResult
    func enableExplicitOfflineSaveMode(
        pageId: String,
        saveGeneration: String,
        fallbackPageId: String? = nil,
        reservation: ProxyExplicitSaveReservation
    ) async -> ProxyCacheSessionToken? {
        print("💾 ProxyInterceptorService: Enabling authoritative offline refresh for page: \(pageId)")
        guard explicitSaveReservation == reservation,
              explicitSaveSessionToken == nil else {
            return nil
        }
        do {
            try await prepareLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for explicit save")
            return nil
        }
        if let existing = activeSessionToken {
            // A visible-article passive owner must yield to the explicit save, otherwise the
            // reservation is stranded and the save button stays on Retry.
            disableMode(owner: existing)
        }
        guard !Task.isCancelled,
              explicitSaveReservation == reservation,
              explicitSaveSessionToken == nil,
              activeSessionToken == nil else { return nil }
        currentPageId = pageId
        guard let localToken = localServer?.enableSaveMode(
            pageId: pageId,
            saveGeneration: saveGeneration,
            fallbackPageId: fallbackPageId,
            refreshFromNetwork: true
        ) else { return nil }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        explicitSaveSessionToken = token
        explicitSaveReservation = nil
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(
                enabled: true,
                port: Int(activeServerPort),
                allowsDirectFallback: false
            )
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
    func enablePassiveCachingMode(pageId: String) async -> ProxyCacheSessionToken? {
        print("🌐 ProxyInterceptorService: Enabling passive caching mode for page: \(pageId)")
        print("   → Resources will be cached automatically during browsing")
        do {
            try await prepareLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for passive caching: \(error)")
            return nil
        }
        guard !Task.isCancelled else { return nil }
        do {
            try await waitForExplicitSaveRelease()
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
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
            NetworkManager.shared.configureProxyRouting(
                enabled: true,
                port: Int(activeServerPort),
                allowsDirectFallback: true
            )
        }
        
        // NO TIMEOUT - save mode remains active until explicitly disabled
        // This ensures all resources are cached regardless of browsing speed
        print("   → Save mode will remain active until explicitly disabled (no timeout)")
        return token
    }
    
    /// Test-only emergency cleanup. Production lifecycle code must hold and release its exact
    /// `ProxyCacheSessionToken` so a stale view cannot tear down a newer owner.
#if DEBUG
    func disableOfflineSaveMode() {
        print("🔄 ProxyInterceptorService: Disabling offline save mode")
        if let token = activeSessionToken {
            disableMode(owner: token)
            return
        }

        currentPageId = nil
        localServer?.disableSaveMode()
        
        // Also disable NetworkManager proxy routing
        NetworkManager.shared.configureProxyRouting(enabled: false)
    }
#endif

    func disableMode(owner token: ProxyCacheSessionToken) {
        guard activeSessionToken == token else {
            print("🔒 ProxyInterceptorService: Ignoring stale cache mode teardown for page: \(token.pageId)")
            return
        }

        currentPageId = nil
        activeSessionToken = nil
        if explicitSaveSessionToken == token {
            explicitSaveSessionToken = nil
        }
        localServer?.disableMode(owner: token.localToken)

        NetworkManager.shared.configureProxyRouting(enabled: false)
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

    func removeCachedResponses(pageId: String) async {
        if let localServer {
            await localServer.removeCachedResponsesAsync(pageId: pageId)
            return
        }

        // Deletion is a storage operation, not a reason to bind a listener. Construct and scan
        // the page namespace entirely away from MainActor when the proxy has not run yet.
        await Task.detached(priority: .utility) {
            let maintenanceStore = LocalHTTPServer(port: 0)
            await maintenanceStore.removeCachedResponsesAsync(pageId: pageId)
        }.value
    }
    
    /// Enable cache-only mode for offline serving (no network attempts)
    @discardableResult
    func enableCacheOnlyMode(pageId: String) async -> ProxyCacheSessionToken? {
        print("📦 ProxyInterceptorService: Enabling cache-only mode for page: \(pageId)")
        do {
            try await prepareLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for cache-only mode: \(error)")
            return nil
        }
        guard !Task.isCancelled else { return nil }
        do {
            try await waitForExplicitSaveRelease()
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        currentPageId = pageId
        // Set page ID context without enabling save mode (we want to serve, not save)
        guard let localToken = localServer?.setPageIdContext(
            pageId: pageId,
            allowsOriginOnMiss: false
        ) else {
            return nil
        }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        
        // Configure NetworkManager to route through proxy (cached content only)
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(
                enabled: true,
                port: Int(activeServerPort),
                allowsDirectFallback: false
            )
        }

        return token
    }

    /// Prefer this saved page's durable cache while online, then fall back to origin for a cache
    /// miss. This covers stale reachability/captive/handoff failures without writing new bytes.
    @discardableResult
    func enableCacheFirstMode(pageId: String) async -> ProxyCacheSessionToken? {
        print("📦 ProxyInterceptorService: Enabling cache-first mode for saved page: \(pageId)")
        do {
            try await prepareLocalServerIfNeeded()
        } catch {
            print("❌ ProxyInterceptorService: Failed to start local server for cache-first mode")
            return nil
        }
        guard !Task.isCancelled else { return nil }
        do {
            try await waitForExplicitSaveRelease()
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        currentPageId = pageId
        guard let localToken = localServer?.setPageIdContext(
            pageId: pageId,
            allowsOriginOnMiss: true
        ) else { return nil }
        let token = ProxyCacheSessionToken(pageId: pageId, localToken: localToken)
        activeSessionToken = token
        if let activeServerPort {
            NetworkManager.shared.configureProxyRouting(
                enabled: true,
                port: Int(activeServerPort),
                allowsDirectFallback: true
            )
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

    func hasPersistedResponse(
        pageId: String,
        url: URL,
        saveGeneration: String? = nil
    ) -> Bool {
        localServer?.hasPersistedResponse(
            pageId: pageId,
            url: url.absoluteString,
            saveGeneration: saveGeneration
        ) ?? false
    }

    func hasPersistedResponses(
        pageId: String,
        urls: [URL],
        saveGeneration: String? = nil
    ) -> Bool {
        localServer?.hasPersistedResponses(
            pageId: pageId,
            urls: urls.map(\.absoluteString),
            saveGeneration: saveGeneration
        ) ?? false
    }

    func persistExplicitSaveResponse(
        pageId: String,
        url: URL,
        data: Data,
        response: URLResponse,
        saveGeneration: String
    ) async -> Bool {
        guard let localServer, let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return await withCheckedContinuation { continuation in
            localServer.cacheResponseDirectAsync(
                pageId: pageId,
                url: url.absoluteString,
                data: data,
                response: httpResponse,
                saveGeneration: saveGeneration
            ) { persisted in
                continuation.resume(returning: persisted)
            }
        }
    }

    func hasPersistedResponseAsync(
        pageId: String,
        url: URL,
        saveGeneration: String? = nil
    ) async -> Bool {
        guard let localServer else { return false }
        return await localServer.hasPersistedResponseAsync(
            pageId: pageId,
            url: url.absoluteString,
            saveGeneration: saveGeneration
        )
    }

    func hasPersistedResponsesAsync(
        pageId: String,
        urls: [URL],
        saveGeneration: String? = nil
    ) async -> Bool {
        guard let localServer else { return false }
        return await localServer.hasPersistedResponsesAsync(
            pageId: pageId,
            urls: urls.map(\.absoluteString),
            saveGeneration: saveGeneration
        )
    }

    func persistedByteCountAsync(
        pageId: String,
        urls: [URL],
        saveGeneration: String? = nil
    ) async -> Int64? {
        guard let localServer else { return nil }
        return await localServer.persistedByteCountAsync(
            pageId: pageId,
            urls: urls.map(\.absoluteString),
            saveGeneration: saveGeneration
        )
    }

    func hasPersistedMainResponse(pageId: String, url: URL) -> Bool {
        localServer?.hasPersistedMainResponse(
            pageId: pageId,
            url: url.absoluteString
        ) ?? false
    }

    func hasPersistedMainResponseAsync(pageId: String, url: URL) async -> Bool {
        if let localServer {
            return await localServer.hasPersistedMainResponseAsync(
                pageId: pageId,
                url: url.absoluteString
            )
        }

        return await Task.detached(priority: .utility) {
            let maintenanceStore = LocalHTTPServer(port: 0)
            return await maintenanceStore.hasPersistedMainResponseAsync(
                pageId: pageId,
                url: url.absoluteString
            )
        }.value
    }
    
    /// Audit cache contents for debugging incomplete caching issues
    func auditCacheForPage(pageId: String) {
        print("🔍 ProxyInterceptorService: Performing cache audit for pageId: \(pageId)")
        localServer?.auditCacheForPage(pageId: pageId)
    }
    
    /// Cache response directly from IOSAssetHandler for asset requests
    func cacheResponseForAsset(pageId: String, url: String, data: Data, response: HTTPURLResponse) {
        print("💾 ProxyInterceptorService: Caching asset response from IOSAssetHandler for URL: \(url)")
        
        localServer?.cacheResponseDirectAsync(
            pageId: pageId,
            url: url,
            data: data,
            response: response
        ) { persisted in
            if persisted {
                print("✅ ProxyInterceptorService: Successfully cached asset response (\(data.count) bytes)")
            } else {
                print("❌ ProxyInterceptorService: Asset response was not durably cached")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Coalesce listener preparation away from MainActor, then install the ready server and port
    /// atomically before any caller changes cache ownership or NetworkManager routing.
    private func prepareLocalServerIfNeeded() async throws {
        if isServerRunning, localServer != nil, activeServerPort != nil {
            return
        }

        let generation: UInt64
        let task: Task<osrsPreparedProxyServer, Error>
        if let serverStartTask {
            task = serverStartTask
            generation = serverStartGeneration
        } else {
            serverStartGeneration &+= 1
            generation = serverStartGeneration
            let requestedPort = serverPort
#if DEBUG
            let startupDelay = serverStartupDelayForTesting
#else
            let startupDelay: TimeInterval = 0
#endif
            let newTask = Task.detached(priority: .utility) {
                let server = LocalHTTPServer(port: requestedPort)
                let port = try await server.startAsync(
                    startupDelayForTesting: startupDelay
                )
                return osrsPreparedProxyServer(
                    server: server,
                    port: port,
                    generation: generation
                )
            }
            serverStartTask = newTask
            task = newTask
        }

        do {
            let prepared = try await task.value
            guard prepared.generation == serverStartGeneration else {
                prepared.server.stop()
                throw CancellationError()
            }

            if let localServer {
                if localServer !== prepared.server {
                    prepared.server.stop()
                }
            } else {
                localServer = prepared.server
                activeServerPort = prepared.port
                isServerRunning = true
                print("🌐 ProxyInterceptorService: Installed ready local server on port \(prepared.port)")
            }
            serverStartTask = nil
        } catch {
            if generation == serverStartGeneration {
                serverStartTask = nil
            }
            throw error
        }
    }

    /// Article presentation modes serialize behind the one authoritative explicit-save lease.
    /// This keeps unrelated foreground/passive requests from inheriting the saved page's global
    /// routing context. Callers remain cancellation-aware, so only the latest visible owner
    /// resumes after the explicit save releases.
    func waitForExplicitSaveRelease() async throws {
        while explicitSaveReservation != nil || explicitSaveSessionToken != nil {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try Task.checkCancellation()
    }
    
    /// Stop local HTTP server
    func stopLocalServer() {
        serverStartGeneration &+= 1
        serverStartTask?.cancel()
        serverStartTask = nil
        currentPageId = nil
        activeSessionToken = nil
        explicitSaveReservation = nil
        explicitSaveSessionToken = nil
        localServer?.disableSaveMode()
        localServer?.stop()
        localServer = nil
        isServerRunning = false
        activeServerPort = nil
        NetworkManager.shared.configureProxyRouting(enabled: false)
        print("🛑 ProxyInterceptorService: Stopped local HTTP server")
    }

#if DEBUG
    var activeCachePageIdForTesting: String? {
        localServer?.activeCachePageIdForTesting
    }

    var explicitSavePageIdForTesting: String? {
        explicitSaveSessionToken?.pageId
    }

    var hasExplicitSaveReservationForTesting: Bool {
        explicitSaveReservation != nil
    }

    func setServerStartupDelayForTesting(_ delay: TimeInterval) {
        serverStartupDelayForTesting = max(0, delay)
    }

    func seedOfflineSavedPageForUITests(pageId: String, title: String) {
        // This deterministic DEBUG fixture does not require a listener. Avoid reintroducing the
        // production startup wait merely to seed bytes before a UI test begins.
        let cacheStore = localServer ?? LocalHTTPServer(port: 0)
        cacheStore.seedMainHTMLCacheForUITests(pageId: pageId, title: title)
        print("🧪 ProxyInterceptorService: Seeded offline cache for \(title) (\(pageId))")
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

struct ProxyExplicitSaveReservation: Equatable, Sendable {
    let id = UUID()
}

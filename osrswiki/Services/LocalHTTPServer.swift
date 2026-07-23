//
//  LocalHTTPServer.swift
//  OSRS Wiki
//
//  Simple HTTP server for proxy-based HTTP interception
//  Uses Foundation networking to avoid external dependencies
//

import Foundation
import Network
import CryptoKit

/// Simple HTTP server using iOS 17+ Network framework
/// Handles proxy requests and caches responses for offline functionality
@available(iOS 17.0, *)
class LocalHTTPServer {
    
    private let port: UInt16
    private let listenerQueue = DispatchQueue(label: "osrswiki.local-http-server.listener")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var listeningPort: UInt16?
    
    // Request/response caching like Android's OfflineCacheInterceptor
    private let cachedResponses = LocalHTTPResponseCache()
    private var saveMode = false
    private var currentPageId: String?
    private var currentOwnerToken: LocalHTTPServerCacheSessionToken?
    
    // Cache storage directory
    private let cacheDirectory: URL

    init(port: UInt16, cacheDirectory: URL? = nil) {
        self.port = port
        
        // Initialize cache directory
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.cacheDirectory = documentsPath.appendingPathComponent("offline_http_cache")
        }
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        
        print("🏗️ LocalHTTPServer: Initialized for port \(port)")
        print("💾 LocalHTTPServer: Cache directory: \(self.cacheDirectory.path)")
    }
    
    func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        let requestedPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(integerLiteral: port)
        let listener = try NWListener(using: parameters, on: requestedPort)
        self.listener = listener

        let startupSemaphore = DispatchSemaphore(value: 0)
        var startupResult: Result<UInt16, Error>?
        
        listener.newConnectionHandler = { [weak self] connection in
            DispatchQueue.main.async {
                self?.handleNewConnection(connection)
            }
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let boundPort = self?.listener?.port?.rawValue ?? self?.port ?? 0
                self?.listeningPort = boundPort
                print("✅ LocalHTTPServer: Started successfully on port \(boundPort)")
                print("🔍 LocalHTTPServer: Ready to intercept and cache HTTP requests")
                if startupResult == nil {
                    startupResult = .success(boundPort)
                    startupSemaphore.signal()
                }
            case .failed(let error):
                print("❌ LocalHTTPServer: Failed to start: \(error)")
                if startupResult == nil {
                    startupResult = .failure(LocalHTTPServerError.startFailed(error))
                    startupSemaphore.signal()
                }
            case .cancelled:
                print("🛑 LocalHTTPServer: Listener cancelled")
            default:
                print("🔄 LocalHTTPServer: State changed to \(state)")
            }
        }
        
        listener.start(queue: listenerQueue)

        switch startupSemaphore.wait(timeout: .now() + 2.0) {
        case .success:
            return try startupResult?.get() ?? port
        case .timedOut:
            listener.cancel()
            throw LocalHTTPServerError.startTimedOut
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        listeningPort = nil
        
        // Close all connections
        connections.forEach { $0.cancel() }
        connections.removeAll()
        
        print("🛑 LocalHTTPServer: Stopped")
    }
    
    // MARK: - Save Mode Control
    
    @discardableResult
    func enableSaveMode(pageId: String) -> LocalHTTPServerCacheSessionToken {
        let token = LocalHTTPServerCacheSessionToken()
        saveMode = true
        currentPageId = pageId
        currentOwnerToken = token
        print("💾 LocalHTTPServer: Save mode enabled for page: \(pageId)")
        return token
    }
    
    func disableSaveMode() {
        saveMode = false
        currentPageId = nil
        currentOwnerToken = nil
        print("🔄 LocalHTTPServer: Save mode disabled")
    }

    func disableMode(owner token: LocalHTTPServerCacheSessionToken) {
        guard currentOwnerToken == token else {
            print("🔒 LocalHTTPServer: Ignoring stale cache mode teardown for owner \(token.id)")
            return
        }

        disableSaveMode()
    }
    
    /// Set page ID context for cache lookups without enabling save mode (for offline serving)
    @discardableResult
    func setPageIdContext(pageId: String) -> LocalHTTPServerCacheSessionToken {
        let token = LocalHTTPServerCacheSessionToken()
        saveMode = false  // Don't save new responses
        currentPageId = pageId  // But provide pageId context for cache key generation
        currentOwnerToken = token
        print("📦 LocalHTTPServer: Page ID context set for offline serving: \(pageId)")
        return token
    }

    var activeCachePageIdForTesting: String? {
        currentPageId
    }
    
    func hasCompleteCache(pageId: String) -> Bool {
        // Check if we have cached responses for this page
        let pageResponses = allCacheKeys(for: pageId)
        let hasMainHTML = pageResponses.contains { Self.isMainArticleCacheKey($0) }
        let hasResource = pageResponses.contains { !Self.isMainArticleCacheKey($0) }
        
        print("🔍 LocalHTTPServer: Page \(pageId) has \(pageResponses.count) cached resources, main HTML: \(hasMainHTML), resources: \(hasResource)")
        
        return hasMainHTML && hasResource
    }

#if DEBUG
    func seedMainHTMLCacheForUITests(pageId: String, title: String) {
        let escapedTitle = title.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <p>Seeded offline article content for \(escapedTitle).</p>
        <p>This page was loaded from the simulator-only UI test cache.</p>
        """
        let payload: [String: Any] = [
            "parse": [
                "pageid": 1001,
                "title": title,
                "displaytitle": title,
                "revid": 1,
                "text": ["*": html]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            print("❌ LocalHTTPServer: Failed to serialize UI test cache payload")
            return
        }

        var urlComponents = URLComponents(string: "https://oldschool.runescape.wiki/api.php")!
        urlComponents.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "text|displaytitle|revid"),
            URLQueryItem(name: "disablelimitreport", value: "1"),
            URLQueryItem(name: "wrapoutputclass", value: "mw-parser-output"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "page", value: title)
        ]
        guard let urlString = urlComponents.url?.absoluteString else {
            print("❌ LocalHTTPServer: Failed to build UI test cache URL")
            return
        }
        let response = CachedHTTPResponse(
            url: urlString,
            data: data,
            timestamp: Date(),
            pageId: pageId,
            statusCode: 200,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let cacheKey = Self.cacheKeyForRequest(pageId: pageId, method: "GET", url: urlString)
        cachedResponses.set(response, forKey: cacheKey)
        saveCachedResponseToDisk(response: response, cacheKey: cacheKey)

        let assetURL = "https://oldschool.runescape.wiki/images/Varrock.png"
        let assetResponse = CachedHTTPResponse(
            url: assetURL,
            data: Data("seeded-image".utf8),
            timestamp: Date(),
            pageId: pageId,
            statusCode: 200,
            headers: ["Content-Type": "image/png"]
        )
        let assetCacheKey = Self.cacheKey(pageId: pageId, method: "GET", url: assetURL)
        cachedResponses.set(assetResponse, forKey: assetCacheKey)
        saveCachedResponseToDisk(response: assetResponse, cacheKey: assetCacheKey)
        print("🧪 LocalHTTPServer: Seeded main HTML cache for \(pageId) (\(data.count) bytes)")
    }
#endif
    
    /// Direct cache save method for IOSAssetHandler integration
    /// This ensures images saved by IOSAssetHandler are available for offline access
    func cacheResponseDirect(pageId: String, url: String, data: Data, response: HTTPURLResponse) {
        // Generate cache key consistent with how we look up resources
        let method = "GET"
        let cacheKey = Self.cacheKey(pageId: pageId, method: method, url: url)
        
        // Convert headers to proper format
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                headers[keyString] = valueString
            }
        }
        
        // Create cached response object
        let cachedResponse = CachedHTTPResponse(
            url: url,
            data: data,
            timestamp: Date(),
            pageId: pageId,
            statusCode: response.statusCode,
            headers: headers
        )
        
        // Store in memory cache
        cachedResponses.set(cachedResponse, forKey: cacheKey)
        
        // Also persist to disk
        saveCachedResponseToDisk(response: cachedResponse, cacheKey: cacheKey)
        
        print("💾 LocalHTTPServer: Direct cached response for \(url) (key: \(cacheKey), status: \(response.statusCode), size: \(data.count) bytes)")
    }
    
    /// Copy cache entries from one page ID to another (for instant saves using lazy cache)
    func copyCacheEntries(from sourcePageId: String, to destinationPageId: String) {
        print("📋 LocalHTTPServer: Copying cache entries from '\(sourcePageId)' to '\(destinationPageId)'")
        
        // Find all cached entries for the source page
        let sourceEntries = cachedResponses.entries(withPrefix: "\(sourcePageId)_")
        var copiedCount = 0
        
        for (sourceKey, sourceValue) in sourceEntries {
            // Replace the source page ID with destination page ID in the key
            let destinationKey = sourceKey.replacingOccurrences(of: "\(sourcePageId)_", with: "\(destinationPageId)_")
            
            let copiedResponse = CachedHTTPResponse(
                url: sourceValue.url,
                data: sourceValue.data,
                timestamp: Date(),
                pageId: destinationPageId,
                statusCode: sourceValue.statusCode,
                headers: sourceValue.headers
            )

            cachedResponses.set(copiedResponse, forKey: destinationKey)
            saveCachedResponseToDisk(response: copiedResponse, cacheKey: destinationKey)
            
            copiedCount += 1
            
            // Log first few copies for debugging
            if copiedCount <= 3 {
                print("   → Copied: \(sourceKey) → \(destinationKey)")
            }
        }
        
        print("✅ LocalHTTPServer: Copied \(copiedCount) cache entries from browsing to saved page")
    }
    
    /// Get cached response for external asset requests (used by IOSAssetHandler)
    func getCachedResponseForAsset(url: String, pageId: String) -> CachedHTTPResponse? {
        print("🔍 LocalHTTPServer: Looking up cached asset for URL: \(url), pageId: \(pageId)")
        print("🔍 LocalHTTPServer: Current pageId context: \(currentPageId ?? "nil")")
        
        // Verify pageId context matches what we expect
        if currentPageId != pageId {
            print("⚠️ LocalHTTPServer: PageId mismatch! Expected: \(pageId), Current: \(currentPageId ?? "nil")")
            print("🔧 LocalHTTPServer: Using provided pageId to ensure cache key matches")
            
            // Generate cache key directly with provided pageId to ensure consistency
            let cacheKey = Self.cacheKey(pageId: pageId, method: "GET", url: url)
            print("🔍 LocalHTTPServer: Generated cache key with provided pageId: \(cacheKey)")
            
            if let cachedResponse = getCachedResponse(cacheKey: cacheKey) {
                print("✅ LocalHTTPServer: Found cached asset response for: \(url)")
                return cachedResponse
            } else {
                print("❌ LocalHTTPServer: No cached asset response found for: \(url)")
                return nil
            }
        } else {
            // PageId context is correct, use normal cache key generation
            let cacheKey = generateCacheKey(method: "GET", url: url)
            print("🔍 LocalHTTPServer: Generated cache key: \(cacheKey)")
            
            if let cachedResponse = getCachedResponse(cacheKey: cacheKey) {
                print("✅ LocalHTTPServer: Found cached asset response for: \(url)")
                return cachedResponse
            } else {
                print("❌ LocalHTTPServer: No cached asset response found for: \(url)")
                return nil
            }
        }
    }
    
    // MARK: - Connection Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.start(queue: .main)
        receiveHTTPRequest(from: connection)
        
        // PHASE 14.2: Enhanced connection monitoring
        print("🔗 LocalHTTPServer: New connection from: \(connection.endpoint)")
    }
    
    private func receiveHTTPRequest(from connection: NWConnection) {
        // Read HTTP request data
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            
            if error != nil {
                print("❌ LocalHTTPServer: Receive error: \(error?.localizedDescription ?? "Unknown error")")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                self?.processHTTPRequest(data: data, connection: connection)
            }
            
            if !isComplete {
                // Continue receiving data
                self?.receiveHTTPRequest(from: connection)
            }
        }
    }
    
    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            print("❌ LocalHTTPServer: Failed to decode request data")
            sendHTTPError(connection: connection, statusCode: 400, message: "Bad Request")
            return
        }
        
#if DEBUG
        // PHASE 14.2: Enhanced request monitoring
        print("📨 LocalHTTPServer: Received HTTP request:")
        print("📨 Request data (\(data.count) bytes): \(String(requestString.prefix(200)))")
#endif
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            print("❌ LocalHTTPServer: No request line found")
            sendHTTPError(connection: connection, statusCode: 400, message: "Invalid Request")
            return
        }
        
        print("📨 LocalHTTPServer: Request line: \(requestLine)")
        
        // Parse request line: "CONNECT example.com:443 HTTP/1.1"
        let requestComponents = requestLine.components(separatedBy: " ")
        guard requestComponents.count >= 2 else {
            sendHTTPError(connection: connection, statusCode: 400, message: "Invalid Request Line")
            return
        }
        
        let method = requestComponents[0]
        let urlString = requestComponents[1]
        
        print("🌐 LocalHTTPServer: \(method) request for: \(urlString)")
        
        // Handle different HTTP methods
        switch method {
        case "CONNECT":
            handleCONNECTRequest(urlString: urlString, connection: connection)
        case "GET", "POST":
            // PHASE 14.2: Enhanced URL processing logging
            print("🔄 LocalHTTPServer: Processing \(method) request for: \(urlString)")
            
            // Check if this is a rewritten URL from NetworkManager
            let actualURL = decodeRewrittenURL(urlString)
            if actualURL != urlString {
                print("🔄 LocalHTTPServer: URL decoded successfully")
            }
            
            handleHTTPRequest(method: method, urlString: actualURL, connection: connection)
        default:
            sendHTTPError(connection: connection, statusCode: 501, message: "Method Not Implemented")
        }
    }
    
    private func handleCONNECTRequest(urlString: String, connection: NWConnection) {
        print("⚠️ LocalHTTPServer: Rejecting CONNECT request for \(urlString); HTTPS tunneling is not implemented")
        sendHTTPError(
            connection: connection,
            statusCode: 501,
            message: "CONNECT tunneling is not supported"
        )
    }
    
    private func handleHTTPRequest(method: String, urlString: String, connection: NWConnection) {
        // CACHE-FIRST LOGIC: Check cache before network
        let cacheKey = generateCacheKey(method: method, url: urlString)
        
        // Always try cache first for better offline support
        if let cachedResponse = getCachedResponseForRequest(cacheKey: cacheKey, method: method, url: urlString) {
            print("📦 LocalHTTPServer: Serving cached response for: \(urlString)")
            sendCachedResponse(cachedResponse: cachedResponse, connection: connection)
            return
        }
        
        // SAVE MODE CHECK: If in save mode, always try to fetch for caching
        if saveMode {
            print("🌐 LocalHTTPServer: Save mode active - fetching and caching: \(urlString)")
            fetchAndCacheResponse(method: method, urlString: urlString, connection: connection, cacheKey: cacheKey)
            return
        }
        
        // OFFLINE DETECTION: Only check connectivity when NOT in save mode
        Task { @MainActor in
            let isOfflineMode = !NetworkManager.shared.isConnected
            if isOfflineMode {
                print("📵 LocalHTTPServer: Offline mode - cannot fetch: \(urlString)")
                sendHTTPError(connection: connection, statusCode: 503, message: "Service Unavailable - Offline")
                return
            }
            
            // ONLINE WITHOUT SAVE MODE: Fetch without caching
            print("🌐 LocalHTTPServer: Fetching without caching: \(urlString)")
            fetchWithoutCaching(method: method, urlString: urlString, connection: connection)
        }
    }
    
    private func fetchAndCacheResponse(method: String, urlString: String, connection: NWConnection, cacheKey: String) {
        // Create URLSession request to fetch from actual server
        guard let url = URL(string: urlString) else {
            sendHTTPError(connection: connection, statusCode: 400, message: "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Add common headers for MediaWiki API compatibility
        request.setValue("osrswiki-ios/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
        
        print("🌐 LocalHTTPServer: Making network request to: \(urlString)")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ LocalHTTPServer: Network request failed: \(error)")
                self.sendHTTPError(connection: connection, statusCode: 502, message: "Bad Gateway")
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                print("❌ LocalHTTPServer: Invalid response received")
                self.sendHTTPError(connection: connection, statusCode: 502, message: "Bad Gateway")
                return
            }
            
            print("✅ LocalHTTPServer: Network request successful (status: \(httpResponse.statusCode))")
            
            // Cache the response if in save mode AND it's a successful response
            if self.saveMode, let pageId = self.currentPageId {
                if self.shouldCacheResponse(httpResponse: httpResponse, url: urlString, data: data) {
                    self.cacheResponse(pageId: pageId, cacheKey: cacheKey, data: data, url: urlString, httpResponse: httpResponse)
                } else {
                    print("⚠️ LocalHTTPServer: Skipping cache for invalid response - status: \(httpResponse.statusCode), url: \(urlString)")
                }
            }
            
            // Send response to client
            self.sendNetworkResponse(data: data, httpResponse: httpResponse, connection: connection)
        }
        
        task.resume()
    }
    
    private func fetchWithoutCaching(method: String, urlString: String, connection: NWConnection) {
        // Similar to fetchAndCacheResponse but without caching
        guard let url = URL(string: urlString) else {
            sendHTTPError(connection: connection, statusCode: 400, message: "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("osrswiki-ios/1.0", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ LocalHTTPServer: Network request failed: \(error)")
                self.sendHTTPError(connection: connection, statusCode: 502, message: "Bad Gateway")
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                self.sendHTTPError(connection: connection, statusCode: 502, message: "Bad Gateway")
                return
            }
            
            self.sendNetworkResponse(data: data, httpResponse: httpResponse, connection: connection)
        }
        
        task.resume()
    }
    
    private func sendNetworkResponse(data: Data, httpResponse: HTTPURLResponse, connection: NWConnection) {
        // Build HTTP response with proper headers
        var responseString = "HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\r\n"

        // Add essential connection management headers
        responseString += "Connection: close\r\n"
        responseString += "Server: osrswiki-proxy/1.0\r\n"
        responseString += "Date: \(DateFormatter.httpDateFormatter.string(from: Date()))\r\n"

        // Forward important headers from original response
        // CRITICAL: Skip Content-Encoding because URLSession ALREADY DECOMPRESSED the data for us
        // The data we receive is uncompressed, but the original response headers still say gzip
        // If we forward Content-Encoding: gzip with uncompressed data, the client fails with "cannot decode raw data"
        for (key, value) in httpResponse.allHeaderFields {
            guard let keyString = key as? String, let valueString = value as? String else { continue }
            let lowercaseKey = keyString.lowercased()
            // Skip headers we've already set, will set, or compression-related headers
            if lowercaseKey == "connection" || lowercaseKey == "server" || lowercaseKey == "date" ||
               lowercaseKey == "content-length" || lowercaseKey == "content-encoding" || lowercaseKey == "transfer-encoding" {
                continue
            }
            responseString += "\(keyString): \(valueString)\r\n"
        }

        // Add Content-Length (must match actual data size)
        responseString += "Content-Length: \(data.count)\r\n"
        responseString += "\r\n"

        // Combine headers and body
        var responseData = Data(responseString.utf8)
        responseData.append(data)

        // Log response details for debugging
        let hasGzip = (httpResponse.value(forHTTPHeaderField: "Content-Encoding")?.lowercased().contains("gzip")) ?? false
        print("🔍 LocalHTTPServer: Sending network response (\(responseData.count) total bytes, gzip: \(hasGzip))")

        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                print("❌ LocalHTTPServer: Response send error: \(error)")
            } else {
                print("✅ LocalHTTPServer: Response sent successfully")
            }

            // Close connection after response
            connection.cancel()
        })
    }
    
    // MARK: - Caching
    
    static func cacheKey(pageId: String?, method: String, url: String) -> String {
        let normalizedMethod = method.uppercased()
        let normalizedURL = normalizedURLString(url)
        let digest = SHA256.hash(data: Data(normalizedURL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        if let pageId {
            return "\(pageId)_\(normalizedMethod)_\(digest)"
        }

        return "\(normalizedMethod)_\(digest)"
    }

    static func cacheKeyForRequest(pageId: String?, method: String, url: String) -> String {
        guard let pageId else {
            return cacheKey(pageId: nil, method: method, url: url)
        }

        if isArticleParseAPIRequest(url) {
            let normalizedMethod = method.uppercased()
            let normalizedURL = normalizedURLString(url)
            let digest = SHA256.hash(data: Data(normalizedURL.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return "\(pageId)_main_\(normalizedMethod)_\(digest)"
        }

        return cacheKey(pageId: pageId, method: method, url: url)
    }

    private func generateCacheKey(method: String, url: String) -> String {
        guard let pageId = currentPageId else {
            return Self.cacheKey(pageId: nil, method: method, url: url)
        }

        if Self.isArticleParseAPIRequest(url) {
            print("🔍 LocalHTTPServer: Marking API response as main HTML for page: \(pageId)")
        }

        return Self.cacheKeyForRequest(pageId: pageId, method: method, url: url)
    }
    
    private func cacheResponse(pageId: String, cacheKey: String, data: Data, url: String, httpResponse: HTTPURLResponse) {
        // CRITICAL FIX: Proper header field conversion without unsafe casting
        // ALSO: Strip Content-Encoding since URLSession already decompressed the data for us
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                let lowercaseKey = keyString.lowercased()
                // Skip compression-related headers since data is already decompressed by URLSession
                if lowercaseKey == "content-encoding" || lowercaseKey == "transfer-encoding" {
                    print("🔧 LocalHTTPServer: Stripping \(keyString) header (data already decompressed by URLSession)")
                    continue
                }
                headers[keyString] = valueString
            }
        }

        print("🔍 LocalHTTPServer: Caching response with \(headers.count) headers: \(headers.keys.joined(separator: ", "))")
        
        let response = CachedHTTPResponse(
            url: url,
            data: data,
            timestamp: Date(),
            pageId: pageId,
            statusCode: httpResponse.statusCode,
            headers: headers
        )
        
        cachedResponses.set(response, forKey: cacheKey)
        print("💾 LocalHTTPServer: Cached response for \(url) (key: \(cacheKey), status: \(httpResponse.statusCode))")
        
        // Also save to persistent storage for offline access
        saveCachedResponseToDisk(response: response, cacheKey: cacheKey)
    }
    
    /// Validate if response should be cached (prevents caching error pages as binary resources)
    private func shouldCacheResponse(httpResponse: HTTPURLResponse, url: String, data: Data) -> Bool {
        // Only cache successful responses
        guard (200...299).contains(httpResponse.statusCode) else {
            print("🚫 LocalHTTPServer: Not caching HTTP error response \(httpResponse.statusCode) for: \(url)")
            return false
        }
        
        // Validate content type for binary resources
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let isBinaryResource = url.contains(".ttf") || url.contains(".woff") || url.contains(".png") || url.contains(".jpg") || url.contains(".jpeg")
        
        if isBinaryResource && contentType.lowercased().contains("text/html") {
            print("🚨 LocalHTTPServer: CACHE CORRUPTION PREVENTED - HTML response for binary resource: \(url)")
            print("🚨 Content-Type: \(contentType), Expected: binary, Got: HTML")
            if let htmlPreview = String(data: data.prefix(200), encoding: .utf8) {
                print("🚨 HTML content preview: \(htmlPreview)")
            }
            return false
        }
        
        print("✅ LocalHTTPServer: Response validation passed for: \(url) (status: \(httpResponse.statusCode), type: \(contentType))")
        return true
    }
    
    /// Audit all cached resources for a specific pageId
    func auditCacheForPage(pageId: String) {
        print("🔍 LocalHTTPServer: CACHE AUDIT for pageId: \(pageId)")
        print("═══════════════════════════════════════════════════════")
        
        var pageResources: [String: CachedHTTPResponse] = [:]
        
        // Check in-memory cache
        for (cacheKey, response) in cachedResponses.entries(withPrefix: "\(pageId)_") {
            pageResources[cacheKey] = response
        }
        
        // Check disk cache for additional entries
        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
                let cacheKey = cacheFile.deletingPathExtension().lastPathComponent
                if cacheKey.hasPrefix("\(pageId)_") {
                    if pageResources[cacheKey] == nil {
                        // Load from disk if not in memory
                        if let diskResponse = loadCachedResponseFromDisk(cacheKey: cacheKey) {
                            pageResources[cacheKey] = diskResponse
                        }
                    }
                }
            }
        } catch {
            print("⚠️ LocalHTTPServer: Error reading cache directory during audit: \(error)")
        }
        
        print("📊 CACHE AUDIT RESULTS:")
        print("   Total cached resources: \(pageResources.count)")
        
        if pageResources.isEmpty {
            print("   ❌ NO CACHED RESOURCES FOUND")
        } else {
            // Sort by cache key for consistent output
            let sortedResources = pageResources.sorted { $0.key < $1.key }
            
            for (cacheKey, response) in sortedResources {
                let resourceType = determineResourceType(url: response.url)
                let sizeFormatted = ByteCountFormatter().string(fromByteCount: Int64(response.data.count))
                
                print("   ✅ \(resourceType): \(response.url)")
                print("      Cache Key: \(cacheKey)")
                print("      Status: \(response.statusCode), Size: \(sizeFormatted)")
                print("      Cached: \(response.timestamp.formatted())")
                
                if Self.isMainArticleCacheKey(cacheKey) {
                    print("      🎯 MAIN HTML CONTENT")
                }
                print("")
            }
        }
        
        print("═══════════════════════════════════════════════════════")
    }
    
    /// Determine resource type from URL for diagnostic purposes
    private func determineResourceType(url: String) -> String {
        if url.contains("api.php") {
            return "API"
        } else if url.contains(".png") || url.contains(".jpg") || url.contains(".jpeg") || url.contains(".gif") {
            return "IMAGE"
        } else if url.contains(".css") {
            return "CSS"
        } else if url.contains(".js") {
            return "JS"
        } else if url.contains("load.php") {
            return "MEDIAWIKI"
        } else if url.contains(".woff") || url.contains(".ttf") || url.contains(".otf") {
            return "FONT"
        } else {
            return "OTHER"
        }
    }

    /// Clean up corrupted cache entries (HTML error pages cached as binary resources)
    func cleanupCorruptedCache() {
        print("🧹 LocalHTTPServer: Starting corrupted cache cleanup...")
        var corruptedKeys: [String] = []
        var cleanedCount = 0
        
        // Check in-memory cache
        for (cacheKey, response) in cachedResponses.entries() {
            if isCorruptedCacheEntry(response: response, cacheKey: cacheKey) {
                corruptedKeys.append(cacheKey)
            }
        }
        
        // Remove corrupted entries from memory
        for key in corruptedKeys {
            cachedResponses.removeValue(forKey: key)
            cleanedCount += 1
            print("🗑️ LocalHTTPServer: Removed corrupted cache entry: \(key)")
        }
        
        // Clean up disk cache
        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
                if let response = loadCachedResponseFromDisk(cacheKey: cacheFile.deletingPathExtension().lastPathComponent),
                   isCorruptedCacheEntry(response: response, cacheKey: cacheFile.deletingPathExtension().lastPathComponent) {
                    
                    try FileManager.default.removeItem(at: cacheFile)
                    cleanedCount += 1
                    print("🗑️ LocalHTTPServer: Deleted corrupted cache file: \(cacheFile.lastPathComponent)")
                }
            }
        } catch {
            print("⚠️ LocalHTTPServer: Error during disk cache cleanup: \(error)")
        }
        
        print("✅ LocalHTTPServer: Cache cleanup complete - removed \(cleanedCount) corrupted entries")
    }
    
    /// Check if a cache entry is corrupted (HTML content for binary resource)
    private func isCorruptedCacheEntry(response: CachedHTTPResponse, cacheKey: String) -> Bool {
        // Skip validation for successful responses
        guard response.statusCode != 200 else { return false }
        
        // Check if it's a binary resource URL with HTML content
        let isBinaryResource = response.url.contains(".ttf") || response.url.contains(".woff") || 
                              response.url.contains(".png") || response.url.contains(".jpg") || 
                              response.url.contains(".jpeg") || response.url.contains(".gif")
        
        if isBinaryResource {
            let contentType = response.headers["Content-Type"] ?? ""
            if contentType.lowercased().contains("text/html") {
                print("🚨 LocalHTTPServer: Found corrupted cache entry - HTML cached as binary: \(response.url)")
                return true
            }
            
            // Also check if data contains HTML markers
            if let dataString = String(data: response.data.prefix(100), encoding: .utf8),
               dataString.contains("<!DOCTYPE") || dataString.contains("<html") {
                print("🚨 LocalHTTPServer: Found corrupted cache entry - HTML data in binary resource: \(response.url)")
                return true
            }
        }
        
        return false
    }
    
    private func getCachedResponse(cacheKey: String) -> CachedHTTPResponse? {
        // First try in-memory cache
        if let cachedResponse = cachedResponses.response(forKey: cacheKey) {
            return cachedResponse
        }
        
        // Then try loading from disk for persistent offline access
        return loadCachedResponseFromDisk(cacheKey: cacheKey)
    }

    private func getCachedResponseForRequest(cacheKey: String, method: String, url: String) -> CachedHTTPResponse? {
        if let cachedResponse = getCachedResponse(cacheKey: cacheKey) {
            return cachedResponse
        }

        guard let pageId = currentPageId,
              Self.isArticleParseAPIRequest(url) else {
            return nil
        }

        let legacyCacheKey = "\(pageId)_main.html"
        guard let legacyResponse = getCachedResponse(cacheKey: legacyCacheKey) else {
            return nil
        }

        guard Self.normalizedURLString(legacyResponse.url) == Self.normalizedURLString(url) else {
            print("⚠️ LocalHTTPServer: Ignoring legacy main HTML cache for mismatched API request")
            print("   Cached URL: \(legacyResponse.url)")
            print("   Requested URL: \(url)")
            return nil
        }

        print("📦 LocalHTTPServer: Serving matching legacy main HTML cache for: \(url)")
        return legacyResponse
    }
    
    private func sendCachedResponse(cachedResponse: CachedHTTPResponse, connection: NWConnection) {
        // Build proper HTTP response with cached headers and status
        var responseString = "HTTP/1.1 \(cachedResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: cachedResponse.statusCode))\r\n"

        // Add essential connection management headers first
        responseString += "Connection: close\r\n"
        responseString += "Server: osrswiki-proxy/1.0\r\n"
        responseString += "Date: \(DateFormatter.httpDateFormatter.string(from: Date()))\r\n"

        // Use original cached data - let URLSession handle any compression transparently
        let finalData = cachedResponse.data

        // Add cached headers (skip duplicates and compression headers)
        // CRITICAL: Skip Content-Encoding because cached data is ALREADY DECOMPRESSED by URLSession
        // If we send Content-Encoding: gzip with uncompressed data, URLSession fails with "cannot decode raw data"
        for (key, value) in cachedResponse.headers {
            let lowercaseKey = key.lowercased()
            // Skip headers we've already set, will set, or compression-related headers
            if lowercaseKey == "connection" || lowercaseKey == "server" || lowercaseKey == "date" ||
               lowercaseKey == "content-length" || lowercaseKey == "content-encoding" || lowercaseKey == "transfer-encoding" {
                continue
            }
            responseString += "\(key): \(value)\r\n"
        }

        // Set Content-Length to match actual data size
        responseString += "Content-Length: \(finalData.count)\r\n"
        responseString += "\r\n"

        // Combine headers and body
        var responseData = Data(responseString.utf8)
        responseData.append(finalData)

        // Log response details for debugging
        let hasGzip = cachedResponse.headers["Content-Encoding"]?.lowercased().contains("gzip") ?? false
        print("🔍 LocalHTTPServer: Sending cached response (\(responseData.count) total bytes, gzip: \(hasGzip)):")
        print("🔍 Response headers preview: \(String(responseString.prefix(300)))")

        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                print("❌ LocalHTTPServer: Cached response send error: \(error)")
            } else {
                print("📦 LocalHTTPServer: Cached response sent successfully for: \(cachedResponse.url)")
            }

            // Close connection after response
            connection.cancel()
        })
    }
    
    // MARK: - Persistent Storage
    
    private func getPageCacheDirectory(pageId: String) throws -> URL {
        let pageDirectory = cacheDirectory.appendingPathComponent(pageId)
        try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
        return pageDirectory
    }
    
    private func saveCachedResponseToDisk(response: CachedHTTPResponse, cacheKey: String) {
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        
        do {
            let data = try JSONEncoder().encode(response)
            try data.write(to: cacheFile)
            print("💾 LocalHTTPServer: Saved cached response to disk: \(cacheFile.lastPathComponent)")
        } catch {
            print("❌ LocalHTTPServer: Failed to save cached response to disk: \(error)")
        }
    }
    
    private func loadCachedResponseFromDisk(cacheKey: String) -> CachedHTTPResponse? {
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let response = try JSONDecoder().decode(CachedHTTPResponse.self, from: data)
            print("📦 LocalHTTPServer: Loaded cached response from disk: \(cacheFile.lastPathComponent)")
            
            // Add to memory cache for faster access
            cachedResponses.set(response, forKey: cacheKey)
            return response
        } catch {
            // File doesn't exist or couldn't be decoded - this is normal for new requests
            return nil
        }
    }
    
    /// Decode rewritten URLs from NetworkManager back to original HTTPS URLs
    private func decodeRewrittenURL(_ urlString: String) -> String {
        // Convert: /https/oldschool.runescape.wiki/api.php?... back to https://oldschool.runescape.wiki/api.php?...
        if urlString.hasPrefix("/https/") {
            let remainingPath = String(urlString.dropFirst(7)) // Remove "/https/"
            let decodedURL = "https://\(remainingPath)"
            print("🔄 LocalHTTPServer: Decoded rewritten URL: \(urlString) -> \(decodedURL)")
            return decodedURL
        }
        return urlString
    }
    
    private func sendHTTPError(connection: NWConnection, statusCode: Int, message: String) {
        let response = "HTTP/1.1 \(statusCode) \(message)\r\nConnection: close\r\nContent-Length: \(message.utf8.count)\r\n\r\n\(message)"
        let responseData = response.data(using: .utf8)!

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })

        print("❌ LocalHTTPServer: Sent error \(statusCode): \(message)")
    }

    private func allCacheKeys(for pageId: String) -> [String] {
        var keys = Set(cachedResponses.keys(withPrefix: "\(pageId)_"))

        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
                let cacheKey = cacheFile.deletingPathExtension().lastPathComponent
                if cacheKey.hasPrefix("\(pageId)_") {
                    keys.insert(cacheKey)
                }
            }
        } catch {
            print("⚠️ LocalHTTPServer: Error reading cache directory for page \(pageId): \(error)")
        }

        return Array(keys)
    }

    private static func normalizedURLString(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
        }

        return components.string ?? urlString
    }

    private static func isArticleParseAPIRequest(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              components.path.hasSuffix("/api.php"),
              let queryItems = components.queryItems else {
            return false
        }

        let action = queryItems.first { $0.name == "action" }?.value?.lowercased()
        let page = queryItems.first { $0.name == "page" }?.value
        return action == "parse" && page?.isEmpty == false
    }

    private static func isMainArticleCacheKey(_ cacheKey: String) -> Bool {
        cacheKey.contains("_main_") || cacheKey.hasSuffix("_main.html")
    }
}

@available(iOS 17.0, *)
enum LocalHTTPServerError: Error {
    case startFailed(NWError)
    case startTimedOut
}

// MARK: - Supporting Types

@available(iOS 17.0, *)
struct CachedHTTPResponse: Codable {
    let url: String
    let data: Data
    let timestamp: Date
    let pageId: String
    let statusCode: Int
    let headers: [String: String]
}

struct LocalHTTPServerCacheSessionToken: Equatable {
    let id = UUID()
}

@available(iOS 17.0, *)
final class LocalHTTPResponseCache {
    private let lock = NSLock()
    private var storage: [String: CachedHTTPResponse] = [:]
    private var keysByPagePrefix: [String: Set<String>] = [:]

    func response(forKey key: String) -> CachedHTTPResponse? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ response: CachedHTTPResponse, forKey key: String) {
        lock.lock()
        storage[key] = response
        if let pagePrefix = pagePrefix(forCacheKey: key) {
            keysByPagePrefix[pagePrefix, default: []].insert(key)
        }
        lock.unlock()
    }

    func removeValue(forKey key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        if let pagePrefix = pagePrefix(forCacheKey: key) {
            keysByPagePrefix[pagePrefix]?.remove(key)
            if keysByPagePrefix[pagePrefix]?.isEmpty == true {
                keysByPagePrefix.removeValue(forKey: pagePrefix)
            }
        }
        lock.unlock()
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if let indexedKeys = keysByPagePrefix[prefix] {
            return Array(indexedKeys)
        }
        return storage.keys.filter { $0.hasPrefix(prefix) }
    }

    func entries(withPrefix prefix: String? = nil) -> [(String, CachedHTTPResponse)] {
        lock.lock()
        defer { lock.unlock() }
        if let prefix, let indexedKeys = keysByPagePrefix[prefix] {
            return indexedKeys.compactMap { key in
                storage[key].map { (key, $0) }
            }
        }

        return storage
            .filter { key, _ in
                guard let prefix else { return true }
                return key.hasPrefix(prefix)
            }
            .map { ($0.key, $0.value) }
    }

    private func pagePrefix(forCacheKey key: String) -> String? {
        for marker in ["_main_", "_GET_", "_POST_", "_main.html"] {
            if let markerRange = key.range(of: marker) {
                return String(key[..<markerRange.lowerBound]) + "_"
            }
        }
        return nil
    }
}

// MARK: - HTTP Date Formatting Extension
extension DateFormatter {
    static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

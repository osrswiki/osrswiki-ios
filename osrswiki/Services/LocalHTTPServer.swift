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

protocol osrsCancellableRequest: AnyObject {
    func cancel()
}

extension URLSessionDataTask: osrsCancellableRequest {}

final class osrsCancellableRequestRegistry<Key: Hashable> {
    private let lock = NSLock()
    private var requests: [Key: osrsCancellableRequest] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func insert(_ request: osrsCancellableRequest, for key: Key) {
        lock.lock()
        let previous = requests.updateValue(request, forKey: key)
        lock.unlock()
        previous?.cancel()
    }

    @discardableResult
    func finish(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return requests.removeValue(forKey: key) != nil
    }

    func cancel(_ key: Key) {
        lock.lock()
        let request = requests.removeValue(forKey: key)
        lock.unlock()
        request?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let active = Array(requests.values)
        requests.removeAll()
        lock.unlock()
        active.forEach { $0.cancel() }
    }
}

final class osrsObjectLifecycleRegistry<Object: AnyObject> {
    private let lock = NSLock()
    private var objects: [ObjectIdentifier: Object] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return objects.count
    }

    var values: [Object] {
        lock.lock()
        defer { lock.unlock() }
        return Array(objects.values)
    }

    func insert(_ object: Object) {
        lock.lock()
        objects[ObjectIdentifier(object)] = object
        lock.unlock()
    }

    func remove(_ object: Object) {
        lock.lock()
        objects.removeValue(forKey: ObjectIdentifier(object))
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        objects.removeAll()
        lock.unlock()
    }
}

enum osrsHTTPRequestHeaderAccumulationResult: Equatable {
    case awaitingMore
    case complete(Data)
    case tooLarge
    case alreadyComplete
}

/// TCP does not preserve HTTP message boundaries. Accumulate exactly one request header per
/// connection so policy headers cannot be lost when the kernel splits them across receive calls.
struct osrsHTTPRequestHeaderAccumulator {
    static let maximumHeaderBytes = 64 * 1024

    private(set) var bufferedData = Data()
    private(set) var isComplete = false

    mutating func append(
        _ chunk: Data,
        maximumHeaderBytes: Int = Self.maximumHeaderBytes
    ) -> osrsHTTPRequestHeaderAccumulationResult {
        guard !isComplete else { return .alreadyComplete }

        bufferedData.append(chunk)
        let delimiter = Data([13, 10, 13, 10])
        if let delimiterRange = bufferedData.range(of: delimiter) {
            guard delimiterRange.upperBound <= maximumHeaderBytes else {
                isComplete = true
                bufferedData.removeAll(keepingCapacity: false)
                return .tooLarge
            }
            isComplete = true
            let header = bufferedData.subdata(in: bufferedData.startIndex..<delimiterRange.upperBound)
            bufferedData.removeAll(keepingCapacity: false)
            return .complete(header)
        }

        guard bufferedData.count <= maximumHeaderBytes else {
            isComplete = true
            bufferedData.removeAll(keepingCapacity: false)
            return .tooLarge
        }
        return .awaitingMore
    }
}

/// NWListener readiness, cancellation, and timeout may race on different queues. Keep the
/// continuation single-shot without blocking whichever actor initiated server preparation.
private final class osrsLocalHTTPServerStartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func performOnce(_ action: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        action()
    }
}

/// Simple HTTP server using iOS 17+ Network framework
/// Handles proxy requests and caches responses for offline functionality
@available(iOS 17.0, *)
final class LocalHTTPServer: @unchecked Sendable {
    private static let cacheIOQueueKey = DispatchSpecificKey<UInt8>()
    private static let cacheIOQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "osrswiki.local-http-server.cache-io", qos: .utility)
        queue.setSpecific(key: cacheIOQueueKey, value: 1)
        return queue
    }()

    private static func cacheIOSync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: cacheIOQueueKey) != nil {
            return body()
        }
        return cacheIOQueue.sync(execute: body)
    }
    
    private let port: UInt16
    private let listenerQueue = DispatchQueue(label: "osrswiki.local-http-server.listener")
    private var listener: NWListener?
    private let connections = osrsObjectLifecycleRegistry<NWConnection>()
    private let upstreamRequests = osrsCancellableRequestRegistry<ObjectIdentifier>()
    private var requestHeaderAccumulators: [ObjectIdentifier: osrsHTTPRequestHeaderAccumulator] = [:]
    private(set) var listeningPort: UInt16?
    
    // Request/response caching like Android's OfflineCacheInterceptor
    private let cachedResponses = LocalHTTPResponseCache()
    private var saveMode = false
    private var currentPageId: String?
    private var currentOwnerToken: LocalHTTPServerCacheSessionToken?
    private var currentSaveGeneration: String?
    private var currentFallbackPageId: String?
    private var refreshesFromNetwork = false
    private var allowsOriginOnMiss = false
    
    // Cache storage directory
    private let cacheDirectory: URL
    private let diskWriter: (Data, URL) throws -> Void
    private let originSession: URLSession
    private let durableRefreshSession: URLSession

    init(
        port: UInt16,
        cacheDirectory: URL? = nil,
        originSession: URLSession? = nil,
        durableRefreshSession: URLSession? = nil,
        diskWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.port = port
        self.diskWriter = diskWriter
        self.originSession = originSession ?? URLSession.shared
        if let durableRefreshSession {
            self.durableRefreshSession = durableRefreshSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = false
            self.durableRefreshSession = URLSession(configuration: configuration)
        }
        
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

    /// Start the listener without parking the caller's thread. Production cache modes await this
    /// method from MainActor, so even a slow listener bind must leave SwiftUI/WebKit responsive.
    /// The delay hook is internal and exists solely for a deterministic heartbeat regression.
    func startAsync(startupDelayForTesting: TimeInterval = 0) async throws -> UInt16 {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    let parameters = NWParameters.tcp
                    parameters.allowLocalEndpointReuse = true

                    let requestedPort = port == 0
                        ? NWEndpoint.Port.any
                        : NWEndpoint.Port(integerLiteral: port)
                    let listener = try NWListener(using: parameters, on: requestedPort)
                    let gate = osrsLocalHTTPServerStartupGate()
                    self.listener = listener

                    listener.newConnectionHandler = { [weak self] connection in
                        DispatchQueue.main.async {
                            self?.handleNewConnection(connection)
                        }
                    }

                    listener.stateUpdateHandler = { [weak self, weak listener] state in
                        switch state {
                        case .ready:
                            let boundPort = listener?.port?.rawValue ?? self?.port ?? 0
                            self?.listeningPort = boundPort
                            print("✅ LocalHTTPServer: Started asynchronously on port \(boundPort)")
                            gate.performOnce {
                                continuation.resume(returning: boundPort)
                            }
                        case .failed(let error):
                            print("❌ LocalHTTPServer: Async start failed: \(error)")
                            gate.performOnce {
                                continuation.resume(
                                    throwing: LocalHTTPServerError.startFailed(error)
                                )
                            }
                        case .cancelled:
                            gate.performOnce {
                                continuation.resume(throwing: CancellationError())
                            }
                        default:
                            break
                        }
                    }

                    let beginListening = { [weak listener] in
                        guard let listener else { return }
                        listener.start(queue: self.listenerQueue)
                    }
                    if startupDelayForTesting > 0 {
                        listenerQueue.asyncAfter(
                            deadline: .now() + startupDelayForTesting,
                            execute: beginListening
                        )
                    } else {
                        beginListening()
                    }

                    listenerQueue.asyncAfter(
                        deadline: .now() + startupDelayForTesting + 2.0
                    ) { [weak listener] in
                        gate.performOnce {
                            listener?.cancel()
                            continuation.resume(throwing: LocalHTTPServerError.startTimedOut)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: { [weak self] in
            self?.stop()
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        listeningPort = nil
        
        // Close all connections
        upstreamRequests.cancelAll()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        
        print("🛑 LocalHTTPServer: Stopped")
    }
    
    // MARK: - Save Mode Control
    
    @discardableResult
    func enableSaveMode(
        pageId: String,
        saveGeneration: String? = nil,
        fallbackPageId: String? = nil,
        refreshFromNetwork: Bool = false
    ) -> LocalHTTPServerCacheSessionToken {
        let token = LocalHTTPServerCacheSessionToken()
        saveMode = true
        currentPageId = pageId
        currentOwnerToken = token
        currentSaveGeneration = saveGeneration
        currentFallbackPageId = fallbackPageId
        refreshesFromNetwork = refreshFromNetwork
        allowsOriginOnMiss = true
        print("💾 LocalHTTPServer: Save mode enabled for page: \(pageId)")
        return token
    }
    
    func disableSaveMode() {
        saveMode = false
        currentPageId = nil
        currentOwnerToken = nil
        currentSaveGeneration = nil
        currentFallbackPageId = nil
        refreshesFromNetwork = false
        allowsOriginOnMiss = false
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
    func setPageIdContext(
        pageId: String,
        allowsOriginOnMiss: Bool = false
    ) -> LocalHTTPServerCacheSessionToken {
        let token = LocalHTTPServerCacheSessionToken()
        saveMode = false  // Don't save new responses
        currentPageId = pageId  // But provide pageId context for cache key generation
        currentOwnerToken = token
        currentSaveGeneration = nil
        currentFallbackPageId = nil
        refreshesFromNetwork = false
        self.allowsOriginOnMiss = allowsOriginOnMiss
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

        var urlComponents = URLComponents(string: osrsWikiParseRequest.endpoint)!
        urlComponents.queryItems = osrsWikiParseRequest.queryItems(page: title)
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
        if saveCachedResponseToDisk(response: response, cacheKey: cacheKey) {
            cachedResponses.set(response, forKey: cacheKey)
        }

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
        if saveCachedResponseToDisk(response: assetResponse, cacheKey: assetCacheKey) {
            cachedResponses.set(assetResponse, forKey: assetCacheKey)
        }
        print("🧪 LocalHTTPServer: Seeded main HTML cache for \(pageId) (\(data.count) bytes)")
    }
#endif
    
    /// Direct cache save method for IOSAssetHandler integration
    /// This ensures images saved by IOSAssetHandler are available for offline access
    @discardableResult
    func cacheResponseDirect(
        pageId: String,
        url: String,
        data: Data,
        response: HTTPURLResponse,
        saveGeneration: String? = nil
    ) -> Bool {
        guard Self.shouldCacheResponse(
            httpResponse: response,
            url: url,
            data: data,
            expectsNonHTMLResource: saveGeneration != nil && !Self.isArticleParseAPIRequest(url)
        ) else {
            return false
        }

        // Generate cache key consistent with how we look up resources
        let method = "GET"
        let cacheKey = Self.cacheKeyForRequest(pageId: pageId, method: method, url: url)
        
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
            headers: headers,
            saveGeneration: saveGeneration
        )

        // Durability is the source of truth. Never publish bytes to memory before their atomic
        // disk commit succeeds, otherwise explicit-save verification can observe a false success.
        guard saveCachedResponseToDisk(response: cachedResponse, cacheKey: cacheKey) else {
            return false
        }
        cachedResponses.set(cachedResponse, forKey: cacheKey)
        
        print("💾 LocalHTTPServer: Direct cached response for \(url) (key: \(cacheKey), status: \(response.statusCode), size: \(data.count) bytes)")
        return true
    }

    func cacheResponseDirectAsync(
        pageId: String,
        url: String,
        data: Data,
        response: HTTPURLResponse,
        saveGeneration: String? = nil,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        Self.cacheIOQueue.async { [weak self] in
            guard let self else { return }
            let persisted = self.cacheResponseDirect(
                pageId: pageId,
                url: url,
                data: data,
                response: response,
                saveGeneration: saveGeneration
            )
            DispatchQueue.main.async { completion(persisted) }
        }
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

            if saveCachedResponseToDisk(response: copiedResponse, cacheKey: destinationKey) {
                cachedResponses.set(copiedResponse, forKey: destinationKey)
                copiedCount += 1
            }
            
            // Log first few copies for debugging
            if copiedCount <= 3 {
                print("   → Copied: \(sourceKey) → \(destinationKey)")
            }
        }
        
        print("✅ LocalHTTPServer: Copied \(copiedCount) cache entries from browsing to saved page")
    }

    @discardableResult
    func copyCachedResponse(
        from sourcePageId: String,
        to destinationPageId: String,
        url: String,
        saveGeneration: String
    ) -> CachedHTTPResponse? {
        let sourceKey = Self.cacheKeyForRequest(pageId: sourcePageId, method: "GET", url: url)
        guard let source = getCachedResponse(cacheKey: sourceKey) ?? loadCachedResponseFromDisk(cacheKey: sourceKey) else {
            return nil
        }
        guard let sourceURL = URL(string: source.url),
              let httpResponse = HTTPURLResponse(
                url: sourceURL,
                statusCode: source.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: source.headers
              ),
              Self.shouldCacheResponse(
                httpResponse: httpResponse,
                url: source.url,
                data: source.data,
                expectsNonHTMLResource: false
              )
        else {
            print("🚫 LocalHTTPServer: Refusing to copy invalid session asset \(url)")
            return nil
        }
        let destinationKey = Self.cacheKeyForRequest(pageId: destinationPageId, method: "GET", url: url)
        let copied = CachedHTTPResponse(
            url: source.url,
            data: source.data,
            timestamp: Date(),
            pageId: destinationPageId,
            statusCode: source.statusCode,
            headers: source.headers,
            saveGeneration: saveGeneration
        )
        guard saveCachedResponseToDisk(response: copied, cacheKey: destinationKey) else {
            return nil
        }
        cachedResponses.set(copied, forKey: destinationKey)
        return copied
    }

    func writePaintHTML(pageId: String, html: String) {
        try? osrsSavedPaintStore.write(pageId: pageId, html: html, cacheDirectory: cacheDirectory)
    }

    func readPaintHTML(pageId: String) -> String? {
        osrsSavedPaintStore.read(pageId: pageId, cacheDirectory: cacheDirectory)
    }

    func removePaintHTML(pageId: String) {
        osrsSavedPaintStore.remove(pageId: pageId, cacheDirectory: cacheDirectory)
    }
    
    /// Get cached response for external asset requests (used by IOSAssetHandler)
    func getCachedResponseForAsset(url: String, pageId: String? = nil) -> CachedHTTPResponse? {
        print("🔍 LocalHTTPServer: Looking up cached asset for URL: \(url), pageId: \(pageId ?? "nil")")
        print("🔍 LocalHTTPServer: Current pageId context: \(currentPageId ?? "nil")")
        let isImages = url.contains("/images/")
        let digest = Self.cacheKeyForRequest(pageId: nil, method: "GET", url: url)

        var pageIds: [String] = []
        if let pageId, !pageId.isEmpty {
            pageIds.append(pageId)
        }
        if let currentPageId, !pageIds.contains(currentPageId) {
            pageIds.append(currentPageId)
        }

        if isImages {
            NSLog(
                "osrsImagesLookup: server lookup url=%@ namedPageId=%@ currentPageId=%@ pageIds=%@ digest=%@ cacheDir=%@",
                url,
                pageId ?? "nil",
                currentPageId ?? "nil",
                pageIds.isEmpty ? "nil" : pageIds.joined(separator: ","),
                digest,
                cacheDirectory.path
            )
        }

        for candidate in pageIds {
            let cacheKey = Self.cacheKeyForRequest(pageId: candidate, method: "GET", url: url)
            print("🔍 LocalHTTPServer: Generated cache key with pageId \(candidate): \(cacheKey)")
            if let cachedResponse = getCachedResponse(cacheKey: cacheKey) {
                print("✅ LocalHTTPServer: Found cached asset response for: \(url) (pageId: \(candidate))")
                if isImages {
                    NSLog(
                        "osrsImagesLookup: server named hit pageId=%@ bytes=%d key=%@",
                        candidate,
                        cachedResponse.data.count,
                        cacheKey
                    )
                }
                return cachedResponse
            }
        }

        if let snapshotResponse = getCachedSnapshotResponseForAssetDigest(url: url) {
            print("✅ LocalHTTPServer: Found cached asset via snapshot digest fallback for: \(url) (pageId: \(snapshotResponse.pageId))")
            if isImages {
                NSLog(
                    "osrsImagesLookup: server digest hit pageId=%@ bytes=%d",
                    snapshotResponse.pageId,
                    snapshotResponse.data.count
                )
            }
            return snapshotResponse
        }

        if let transcodeResponse = getCachedSnapshotResponseForWikiAudioTranscode(url: url) {
            print("✅ LocalHTTPServer: Found cached wiki audio transcode for ogg request: \(url) (pageId: \(transcodeResponse.pageId))")
            if isImages {
                NSLog(
                    "osrsImagesLookup: ogg transcode hit pageId=%@ bytes=%d cachedUrl=%@",
                    transcodeResponse.pageId,
                    transcodeResponse.data.count,
                    transcodeResponse.url
                )
            }
            return transcodeResponse
        }

        print("❌ LocalHTTPServer: No cached asset response found for: \(url)")
        if isImages {
            NSLog("osrsImagesLookup: server miss url=%@ digest=%@", url, digest)
        }
        return nil
    }

    /// Infobox `<audio>` keeps the original `/images/*.ogg` source. Explicit Save persists the
    /// preferred `/images/transcoded/…/.ogg.mp3` blob (different query, different digest).
    static func wikiAudioTranscodePath(from url: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        let path = components.path
        guard path.hasPrefix("/images/"), !path.contains("/transcoded/") else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "ogg" || ext == "oga" else { return nil }
        let filename = (path as NSString).lastPathComponent
        guard !filename.isEmpty else { return nil }
        return "/images/transcoded/\(filename)/\(filename).mp3"
    }

    /// Saved infobox media lives under `__snapshot__` even when the live handler still
    /// looks up a browsing pageId and `currentPageId` is nil or browsing.
    private func getCachedSnapshotResponseForAssetDigest(url: String) -> CachedHTTPResponse? {
        let methodDigest = Self.cacheKeyForRequest(pageId: nil, method: "GET", url: url)
        guard methodDigest.hasPrefix("GET_"), methodDigest.count == 4 + 64 else {
            if url.contains("/images/") {
                NSLog("osrsImagesLookup: digest key invalid methodDigest=%@", methodDigest)
            }
            return nil
        }
        let suffix = "_\(methodDigest).cache"

        let cacheFiles: [URL]
        do {
            cacheFiles = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            print("⚠️ LocalHTTPServer: Error reading cache directory for snapshot digest fallback: \(error)")
            NSLog(
                "osrsImagesLookup: cacheDir list error dir=%@ err=%@",
                cacheDirectory.path,
                String(describing: error)
            )
            return nil
        }

        var suffixMatches = 0
        var snapshotNames: [String] = []
        for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
            let name = cacheFile.lastPathComponent
            if name.contains("__snapshot__") {
                snapshotNames.append(name)
            }
            guard name.contains("__snapshot__"), name.hasSuffix(suffix) else { continue }
            suffixMatches += 1
            let cacheKey = cacheFile.deletingPathExtension().lastPathComponent
            if let cachedResponse = getCachedResponse(cacheKey: cacheKey) {
                if url.contains("/images/") {
                    NSLog(
                        "osrsImagesLookup: digest suffix hit file=%@ bytes=%d",
                        name,
                        cachedResponse.data.count
                    )
                }
                return cachedResponse
            }
            let decodeError = peekCachedResponseDecodeError(cacheKey: cacheKey)
            NSLog(
                "osrsImagesLookup: digest suffix match but decode nil file=%@ key=%@ decodeErr=%@",
                name,
                cacheKey,
                decodeError ?? "nil"
            )
        }
        if url.contains("/images/") {
            let sample = snapshotNames.prefix(8).joined(separator: ",")
            NSLog(
                "osrsImagesLookup: digest scan miss suffix=%@ cacheFiles=%d snapshotFiles=%d suffixMatches=%d sample=%@",
                suffix,
                cacheFiles.count,
                snapshotNames.count,
                suffixMatches,
                sample
            )
        }
        return nil
    }

    /// Live infobox play requests `/images/Sea_Shanty_2.ogg?8e3b9` while Save stored
    /// `/images/transcoded/Sea_Shanty_2.ogg/Sea_Shanty_2.ogg.mp3?f5d67`. Match the transcode
    /// path on snapshot blobs, ignoring the cache-busting query.
    private func getCachedSnapshotResponseForWikiAudioTranscode(url: String) -> CachedHTTPResponse? {
        guard let transcodePath = Self.wikiAudioTranscodePath(from: url) else { return nil }
        let needles = [
            transcodePath,
            transcodePath.replacingOccurrences(of: "/", with: "\\/")
        ].compactMap { $0.data(using: .utf8) }

        let cacheFiles: [URL]
        do {
            cacheFiles = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            NSLog(
                "osrsImagesLookup: transcode cacheDir list error dir=%@ err=%@",
                cacheDirectory.path,
                String(describing: error)
            )
            return nil
        }

        for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
            let name = cacheFile.lastPathComponent
            guard name.contains("__snapshot__") else { continue }
            guard let fileData = try? Data(contentsOf: cacheFile),
                  needles.contains(where: { fileData.firstRange(of: $0) != nil }) else {
                continue
            }
            let cacheKey = cacheFile.deletingPathExtension().lastPathComponent
            guard let cachedResponse = getCachedResponse(cacheKey: cacheKey) else { continue }
            let cachedPath = URLComponents(string: cachedResponse.url)?.path
            if cachedPath == transcodePath {
                NSLog(
                    "osrsImagesLookup: transcode path hit file=%@ ogg=%@ mp3=%@",
                    name,
                    url,
                    cachedResponse.url
                )
                return cachedResponse
            }
        }
        if url.contains("/images/") {
            NSLog("osrsImagesLookup: transcode path miss ogg=%@ path=%@", url, transcodePath)
        }
        return nil
    }

    /// Offline availability is a durability contract, not merely a successful network response
    /// or an in-memory cache hit. Verify the exact page-scoped key can be decoded from disk.
    func hasPersistedResponse(
        pageId: String,
        method: String = "GET",
        url: String,
        saveGeneration: String? = nil
    ) -> Bool {
        let cacheKey = Self.cacheKeyForRequest(pageId: pageId, method: method, url: url)
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return false }
        guard let saveGeneration else { return true }
        let metadataFile = cacheDirectory.appendingPathComponent("\(cacheKey).meta")
        guard let data = try? Data(contentsOf: metadataFile),
              let metadata = try? JSONDecoder().decode(CachePersistenceMetadata.self, from: data) else {
            return false
        }
        return metadata.saveGeneration == saveGeneration
    }

    func hasPersistedResponses(
        pageId: String,
        method: String = "GET",
        urls: [String],
        saveGeneration: String? = nil
    ) -> Bool {
        urls.allSatisfy {
            hasPersistedResponse(
                pageId: pageId,
                method: method,
                url: $0,
                saveGeneration: saveGeneration
            )
        }
    }

    func hasPersistedResponseAsync(
        pageId: String,
        method: String = "GET",
        url: String,
        saveGeneration: String? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            Self.cacheIOQueue.async { [weak self] in
                continuation.resume(returning: self?.hasPersistedResponse(
                    pageId: pageId,
                    method: method,
                    url: url,
                    saveGeneration: saveGeneration
                ) ?? false)
            }
        }
    }

    func hasPersistedResponsesAsync(
        pageId: String,
        method: String = "GET",
        urls: [String],
        saveGeneration: String? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            Self.cacheIOQueue.async { [weak self] in
                continuation.resume(returning: self?.hasPersistedResponses(
                    pageId: pageId,
                    method: method,
                    urls: urls,
                    saveGeneration: saveGeneration
                ) ?? false)
            }
        }
    }

    /// Return the exact on-disk byte cost of a verified page snapshot. URL identities are
    /// deduplicated before summing, and every entry must belong to the requested save generation.
    /// Call the async wrapper from UI-owned code so directory/file metadata I/O stays off main.
    func persistedByteCount(
        pageId: String,
        method: String = "GET",
        urls: [String],
        saveGeneration: String? = nil
    ) -> Int64? {
        let uniqueURLs = Dictionary(grouping: urls, by: {
            Self.cacheKeyForRequest(pageId: pageId, method: method, url: $0)
        }).compactMap { $0.value.first }

        var total: Int64 = 0
        for url in uniqueURLs {
            guard hasPersistedResponse(
                pageId: pageId,
                method: method,
                url: url,
                saveGeneration: saveGeneration
            ) else { return nil }

            let cacheKey = Self.cacheKeyForRequest(pageId: pageId, method: method, url: url)
            let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
                  let fileSize = (attributes[.size] as? NSNumber)?.int64Value else {
                return nil
            }
            let (newTotal, overflow) = total.addingReportingOverflow(fileSize)
            guard !overflow else { return nil }
            total = newTotal
        }
        return total
    }

    func persistedByteCountAsync(
        pageId: String,
        method: String = "GET",
        urls: [String],
        saveGeneration: String? = nil
    ) async -> Int64? {
        await withCheckedContinuation { continuation in
            Self.cacheIOQueue.async { [weak self] in
                continuation.resume(returning: self?.persistedByteCount(
                    pageId: pageId,
                    method: method,
                    urls: urls,
                    saveGeneration: saveGeneration
                ))
            }
        }
    }

    func hasPersistedMainResponse(pageId: String, url: String) -> Bool {
        Self.cacheIOSync {
            guard Self.isArticleParseAPIRequest(url) else { return false }

            let exactKey = Self.cacheKeyForRequest(pageId: pageId, method: "GET", url: url)
            if let exactResponse = loadPersistedResponseDirectly(cacheKey: exactKey) {
                if isValidPersistedMainResponse(exactResponse, pageId: pageId, requestURL: url) {
                    return true
                }
                removePersistedCacheEntry(cacheKey: exactKey)
            } else {
                removePersistedCacheEntry(cacheKey: exactKey)
            }

            let legacyKey = "\(pageId)_main.html"
            guard let legacyResponse = loadPersistedResponseDirectly(cacheKey: legacyKey) else {
                removePersistedCacheEntry(cacheKey: legacyKey)
                return false
            }
            guard isValidPersistedMainResponse(legacyResponse, pageId: pageId, requestURL: url) else {
                removePersistedCacheEntry(cacheKey: legacyKey)
                return false
            }
            return true
        }
    }

    private func isValidPersistedMainResponse(
        _ response: CachedHTTPResponse,
        pageId: String,
        requestURL: String
    ) -> Bool {
        guard response.pageId == pageId,
              Self.normalizedURLString(response.url) == Self.normalizedURLString(requestURL),
              let responseURL = URL(string: response.url),
              let httpResponse = HTTPURLResponse(
                url: responseURL,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ),
              Self.shouldCacheResponse(
                httpResponse: httpResponse,
                url: response.url,
                data: response.data
              ),
              (try? JSONDecoder().decode(osrsParseResponse.self, from: response.data)) != nil else {
            return false
        }
        return true
    }

    /// Durability probes must not be satisfied by the byte-cost memory LRU. Read and decode the
    /// final on-disk file directly so a warm memory entry cannot mask a missing/truncated cache.
    private func loadPersistedResponseDirectly(cacheKey: String) -> CachedHTTPResponse? {
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder().decode(CachedHTTPResponse.self, from: data)
    }

    private func removePersistedCacheEntry(cacheKey: String) {
        cachedResponses.removeValue(forKey: cacheKey)
        try? FileManager.default.removeItem(
            at: cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        )
        try? FileManager.default.removeItem(
            at: cacheDirectory.appendingPathComponent("\(cacheKey).meta")
        )
    }

    func hasPersistedMainResponseAsync(pageId: String, url: String) async -> Bool {
        await withCheckedContinuation { continuation in
            Self.cacheIOQueue.async { [weak self] in
                continuation.resume(
                    returning: self?.hasPersistedMainResponse(pageId: pageId, url: url) ?? false
                )
            }
        }
    }

    func removeCachedResponses(pageId: String, completion: (() -> Void)? = nil) {
        let cacheDirectory = self.cacheDirectory
        Self.cacheIOQueue.async { [weak self] in
            defer { completion?() }
            guard let self else { return }
            for (key, response) in self.cachedResponses.entries() where response.pageId == pageId {
                self.cachedResponses.removeValue(forKey: key)
            }
            guard let cacheFiles = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ) else { return }
            for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
                let key = cacheFile.deletingPathExtension().lastPathComponent
                guard Self.pageId(fromCacheKey: key) == pageId else { continue }
                self.cachedResponses.removeValue(forKey: key)
                do {
                    try FileManager.default.removeItem(at: cacheFile)
                    try? FileManager.default.removeItem(
                        at: cacheDirectory.appendingPathComponent("\(key).meta")
                    )
                } catch {
                    print("❌ LocalHTTPServer: Failed to remove page-scoped cache file")
                }
            }
            osrsSavedPaintStore.remove(pageId: pageId, cacheDirectory: cacheDirectory)
        }
    }

    func removeCachedResponsesAsync(pageId: String) async {
        await withCheckedContinuation { continuation in
            removeCachedResponses(pageId: pageId) {
                continuation.resume()
            }
        }
    }

    /// Crash-safe cleanup for speculative browsing namespaces. Explicit saved-page UUID
    /// namespaces are deliberately exempt and remain repository-owned until unsave/clear.
    func cleanupPassiveResponses(
        now: Date = Date(),
        maximumAge: TimeInterval = 24 * 60 * 60,
        maximumTotalBytes: Int = 64 * 1024 * 1024
    ) {
        guard let cacheFiles = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var retained: [(url: URL, key: String, modified: Date, bytes: Int)] = []
        for cacheFile in cacheFiles where cacheFile.pathExtension == "cache" {
            let key = cacheFile.deletingPathExtension().lastPathComponent
            guard Self.pageId(fromCacheKey: key)?.hasPrefix("browsing_") == true else { continue }
            let values = try? cacheFile.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey
            ])
            let modified = values?.contentModificationDate ?? .distantPast
            let bytes = values?.fileSize ?? 0
            if now.timeIntervalSince(modified) > maximumAge {
                cachedResponses.removeValue(forKey: key)
                try? FileManager.default.removeItem(at: cacheFile)
                try? FileManager.default.removeItem(
                    at: cacheDirectory.appendingPathComponent("\(key).meta")
                )
            } else {
                retained.append((cacheFile, key, modified, bytes))
            }
        }

        var retainedBytes = retained.reduce(0) { $0 + $1.bytes }
        for entry in retained.sorted(by: { $0.modified < $1.modified })
            where retainedBytes > max(0, maximumTotalBytes) {
            cachedResponses.removeValue(forKey: entry.key)
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                try? FileManager.default.removeItem(
                    at: cacheDirectory.appendingPathComponent("\(entry.key).meta")
                )
                retainedBytes -= entry.bytes
            }
        }
    }

    func performStartupMaintenanceAsync(completion: (() -> Void)? = nil) {
        Self.cacheIOQueue.async { [self] in
            self.cleanupCorruptedCache()
            self.cleanupPassiveResponses()
            completion?()
        }
    }
    
    // MARK: - Connection Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.insert(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                self.finishConnection(connection, cancelUpstream: true)
            default:
                break
            }
        }
        
        connection.start(queue: .main)
        receiveHTTPRequest(from: connection)
        
        // PHASE 14.2: Enhanced connection monitoring
        print("🔗 LocalHTTPServer: New connection from: \(connection.endpoint)")
    }

    private func finishConnection(_ connection: NWConnection, cancelUpstream: Bool) {
        let key = ObjectIdentifier(connection)
        if cancelUpstream {
            upstreamRequests.cancel(key)
        }
        requestHeaderAccumulators.removeValue(forKey: key)
        connections.remove(connection)
    }

#if DEBUG
    var activeConnectionCountForTesting: Int { connections.count }
    var activeUpstreamRequestCountForTesting: Int { upstreamRequests.count }
    var memoryCacheByteCostForTesting: Int { cachedResponses.byteCost }
    var memoryCacheEntryCountForTesting: Int { cachedResponses.entries().count }

    func cachedResponseForRequestForTesting(
        pageId: String,
        method: String = "GET",
        url: String
    ) -> CachedHTTPResponse? {
        let cacheKey = Self.cacheKeyForRequest(pageId: pageId, method: method, url: url)
        return getCachedResponseForRequest(
            cacheKey: cacheKey,
            method: method,
            url: url,
            pageId: pageId
        )
    }
#endif
    
    private func receiveHTTPRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                print("❌ LocalHTTPServer: Receive error: \(error?.localizedDescription ?? "Unknown error")")
                self.finishConnection(connection, cancelUpstream: true)
                connection.cancel()
                return
            }

            let key = ObjectIdentifier(connection)
            var accumulator = self.requestHeaderAccumulators[key] ?? osrsHTTPRequestHeaderAccumulator()
            let result = accumulator.append(data ?? Data())
            self.requestHeaderAccumulators[key] = accumulator

            switch result {
            case .complete(let headerData):
                self.requestHeaderAccumulators.removeValue(forKey: key)
                self.processHTTPRequest(data: headerData, connection: connection)
            case .tooLarge:
                self.requestHeaderAccumulators.removeValue(forKey: key)
                self.sendHTTPError(
                    connection: connection,
                    statusCode: 431,
                    message: "Request Header Fields Too Large"
                )
            case .alreadyComplete:
                // A connection is parsed at most once, even if Network delivers another callback.
                break
            case .awaitingMore:
                if isComplete {
                    self.requestHeaderAccumulators.removeValue(forKey: key)
                    self.sendHTTPError(connection: connection, statusCode: 400, message: "Incomplete Request")
                } else {
                    self.receiveHTTPRequest(from: connection)
                }
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
        let allowsOfflineStorage = !Self.requestForbidsOfflineStorage(headerLines: lines.dropFirst())
        
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
            
            handleHTTPRequest(
                method: method,
                urlString: actualURL,
                allowsOfflineStorage: allowsOfflineStorage,
                connection: connection
            )
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
    
    private func handleHTTPRequest(
        method: String,
        urlString: String,
        allowsOfflineStorage: Bool,
        connection: NWConnection
    ) {
        let capturedPageId = currentPageId
        let capturedOwnerToken = currentOwnerToken
        let capturedRefreshesFromNetwork = refreshesFromNetwork
        let capturedSaveGeneration = currentSaveGeneration
        let capturedFallbackPageId = currentFallbackPageId
        let capturedSaveMode = saveMode
        let capturedAllowsOriginOnMiss = allowsOriginOnMiss
        let cacheKey = Self.cacheKeyForRequest(
            pageId: capturedPageId,
            method: method,
            url: urlString
        )
        let lookupPageId = capturedRefreshesFromNetwork
            ? (capturedFallbackPageId ?? capturedPageId)
            : capturedPageId
        let lookupCacheKey = Self.cacheKeyForRequest(
            pageId: lookupPageId,
            method: method,
            url: urlString
        )
        Self.cacheIOQueue.async { [weak self] in
            guard let self else { return }
            let existingCachedResponse = self.getCachedResponseForRequest(
                cacheKey: lookupCacheKey,
                method: method,
                url: urlString,
                pageId: lookupPageId
            )
            DispatchQueue.main.async {
                guard self.currentPageId == capturedPageId,
                      self.currentOwnerToken == capturedOwnerToken else {
                    self.sendHTTPError(
                        connection: connection,
                        statusCode: 409,
                        message: "Cache Context Changed"
                    )
                    return
                }
                self.continueHTTPRequest(
                    method: method,
                    urlString: urlString,
                    allowsOfflineStorage: allowsOfflineStorage,
                    connection: connection,
                    cacheKey: cacheKey,
                    existingCachedResponse: existingCachedResponse,
                    refreshesFromNetwork: capturedRefreshesFromNetwork,
                    saveGeneration: capturedSaveGeneration,
                    saveMode: capturedSaveMode,
                    allowsOriginOnMiss: capturedAllowsOriginOnMiss
                )
            }
        }
    }

    private func continueHTTPRequest(
        method: String,
        urlString: String,
        allowsOfflineStorage: Bool,
        connection: NWConnection,
        cacheKey: String,
        existingCachedResponse: CachedHTTPResponse?,
        refreshesFromNetwork: Bool,
        saveGeneration: String?,
        saveMode: Bool,
        allowsOriginOnMiss: Bool
    ) {

        // Explicit saves are authoritative refreshes. Existing browsing/saved bytes are retained
        // only as an origin-failure fallback; they must never satisfy this generation's success.
        if !refreshesFromNetwork, let cachedResponse = existingCachedResponse {
            print("📦 LocalHTTPServer: Serving cached response for: \(urlString)")
            sendCachedResponse(cachedResponse: cachedResponse, connection: connection)
            return
        }
        
        // SAVE MODE CHECK: If in save mode, always try to fetch for caching
        if Self.shouldPersistResponse(
            saveModeActive: saveMode,
            requestForbidsStorage: !allowsOfflineStorage
        ) {
            print("🌐 LocalHTTPServer: Save mode active - fetching and caching: \(urlString)")
            fetchAndCacheResponse(
                method: method,
                urlString: urlString,
                connection: connection,
                cacheKey: cacheKey,
                fallbackCachedResponse: refreshesFromNetwork ? existingCachedResponse : nil,
                saveGeneration: saveGeneration,
                requiresDurableCommit: refreshesFromNetwork
            )
            return
        }

        if !allowsOfflineStorage {
            print("🛡️ LocalHTTPServer: Per-request no-store marker bypasses active page cache ownership")
        }
        
        guard allowsOriginOnMiss else {
            print("📵 LocalHTTPServer: Cache-only miss for: \(urlString)")
            sendHTTPError(connection: connection, statusCode: 503, message: "Service Unavailable - Offline")
            return
        }

        // NWPath is advisory and may lag a working transport during launch or handoff. Cache-first
        // mode therefore lets URLSession adjudicate an actual origin miss; cache-only mode above
        // remains an explicit policy used by forced-offline tests and durable offline reads.
        print("🌐 LocalHTTPServer: Cache miss allows origin fetch: \(urlString)")
        fetchWithoutCaching(method: method, urlString: urlString, connection: connection)
    }

    static func requestForbidsOfflineStorage<S: Sequence>(headerLines: S) -> Bool where S.Element == String {
        for line in headerLines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.caseInsensitiveCompare("X-OSRS-No-Offline-Store") == .orderedSame else {
                continue
            }
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return value == "1" || value == "true"
        }
        return false
    }

    static func shouldPersistResponse(
        saveModeActive: Bool,
        requestForbidsStorage: Bool
    ) -> Bool {
        saveModeActive && !requestForbidsStorage
    }

    static func shouldPersistCapturedResponse(
        capturedPageId: String,
        capturedOwnerToken: LocalHTTPServerCacheSessionToken,
        currentPageId: String?,
        currentOwnerToken: LocalHTTPServerCacheSessionToken?,
        saveModeActive: Bool
    ) -> Bool {
        saveModeActive &&
            capturedPageId == currentPageId &&
            capturedOwnerToken == currentOwnerToken
    }
    
    private func fetchAndCacheResponse(
        method: String,
        urlString: String,
        connection: NWConnection,
        cacheKey: String,
        fallbackCachedResponse: CachedHTTPResponse?,
        saveGeneration: String?,
        requiresDurableCommit: Bool
    ) {
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
        if requiresDurableCommit {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Cache-Bust")
        }

        guard let capturedPageId = currentPageId,
              let capturedOwnerToken = currentOwnerToken else {
            sendHTTPError(connection: connection, statusCode: 409, message: "Cache Owner Unavailable")
            return
        }
        
        print("🌐 LocalHTTPServer: Making network request to: \(urlString)")
        
        let upstreamSession = requiresDurableCommit ? durableRefreshSession : originSession
        let task = upstreamSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let connectionKey = ObjectIdentifier(connection)
            guard self.upstreamRequests.finish(connectionKey) else { return }
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ LocalHTTPServer: Network request failed: \(error)")
                    self.sendRefreshFallbackOrError(
                        fallbackCachedResponse,
                        connection: connection,
                        statusCode: 502,
                        message: "Bad Gateway"
                    )
                    return
                }

                guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                    print("❌ LocalHTTPServer: Invalid response received")
                    self.sendRefreshFallbackOrError(
                        fallbackCachedResponse,
                        connection: connection,
                        statusCode: 502,
                        message: "Bad Gateway"
                    )
                    return
                }

                print("✅ LocalHTTPServer: Network request successful (status: \(httpResponse.statusCode))")
                let stillOwnsSaveSession = Self.shouldPersistCapturedResponse(
                    capturedPageId: capturedPageId,
                    capturedOwnerToken: capturedOwnerToken,
                    currentPageId: self.currentPageId,
                    currentOwnerToken: self.currentOwnerToken,
                    saveModeActive: self.saveMode
                )
                guard stillOwnsSaveSession else {
                    print("🔒 LocalHTTPServer: Discarding response after cache ownership changed")
                    if requiresDurableCommit {
                        self.sendRefreshFallbackOrError(
                            fallbackCachedResponse,
                            connection: connection,
                            statusCode: 409,
                            message: "Cache Owner Changed"
                        )
                    } else {
                        self.sendNetworkResponse(data: data, httpResponse: httpResponse, connection: connection)
                    }
                    return
                }

                let responseCanBeCached = Self.shouldCacheResponse(
                    httpResponse: httpResponse,
                    url: urlString,
                    data: data,
                    expectsNonHTMLResource: requiresDurableCommit && !Self.isArticleParseAPIRequest(urlString)
                )
                guard responseCanBeCached else {
                    if requiresDurableCommit {
                        self.sendRefreshFallbackOrError(
                            fallbackCachedResponse,
                            connection: connection,
                            statusCode: 507,
                            message: "Offline Storage Unavailable"
                        )
                    } else {
                        self.sendNetworkResponse(data: data, httpResponse: httpResponse, connection: connection)
                    }
                    return
                }
                self.cacheResponse(
                    pageId: capturedPageId,
                    cacheKey: cacheKey,
                    data: data,
                    url: urlString,
                    httpResponse: httpResponse,
                    saveGeneration: saveGeneration
                ) { persisted in
                    if requiresDurableCommit && !persisted {
                        self.sendRefreshFallbackOrError(
                            fallbackCachedResponse,
                            connection: connection,
                            statusCode: 507,
                            message: "Offline Storage Unavailable"
                        )
                    } else {
                        self.sendNetworkResponse(data: data, httpResponse: httpResponse, connection: connection)
                    }
                }
            }
        }
        upstreamRequests.insert(task, for: ObjectIdentifier(connection))
        task.resume()
    }

    private func sendRefreshFallbackOrError(
        _ fallback: CachedHTTPResponse?,
        connection: NWConnection,
        statusCode: Int,
        message: String
    ) {
        if let fallback {
            print("📦 LocalHTTPServer: Authoritative refresh failed; preserving prior durable response")
            sendCachedResponse(cachedResponse: fallback, connection: connection)
        } else {
            sendHTTPError(connection: connection, statusCode: statusCode, message: message)
        }
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
        
        let task = originSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let connectionKey = ObjectIdentifier(connection)
            guard self.upstreamRequests.finish(connectionKey) else { return }
            DispatchQueue.main.async {
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
        }
        upstreamRequests.insert(task, for: ObjectIdentifier(connection))
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

        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("❌ LocalHTTPServer: Response send error: \(error)")
            } else {
                print("✅ LocalHTTPServer: Response sent successfully")
            }

            // Close connection after response
            self?.finishConnection(connection, cancelUpstream: false)
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

    static func pageId(fromCacheKey cacheKey: String) -> String? {
        if cacheKey.hasSuffix("_main.html") {
            return String(cacheKey.dropLast("_main.html".count))
        }
        for marker in ["_main_GET_", "_main_POST_", "_GET_", "_POST_"] {
            guard cacheKey.count > marker.count + 64 else { continue }
            let markerStart = cacheKey.index(cacheKey.endIndex, offsetBy: -(marker.count + 64))
            let markerEnd = cacheKey.index(markerStart, offsetBy: marker.count)
            let digest = cacheKey[markerEnd...]
            if cacheKey[markerStart..<markerEnd] == marker,
               digest.count == 64,
               digest.allSatisfy({ $0.isHexDigit }) {
                return String(cacheKey[..<markerStart])
            }
        }
        return nil
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
    
    private func cacheResponse(
        pageId: String,
        cacheKey: String,
        data: Data,
        url: String,
        httpResponse: HTTPURLResponse,
        saveGeneration: String?,
        completion: @escaping (Bool) -> Void
    ) {
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
            headers: headers,
            saveGeneration: saveGeneration
        )

        Self.cacheIOQueue.async { [weak self] in
            guard let self else { return }
            let persisted = self.saveCachedResponseToDisk(response: response, cacheKey: cacheKey)
            if persisted {
                self.cachedResponses.set(response, forKey: cacheKey)
                print("💾 LocalHTTPServer: Cached response for \(url) (key: \(cacheKey), status: \(httpResponse.statusCode))")
            }
            DispatchQueue.main.async {
                completion(persisted)
            }
        }
    }
    
    private static let nonHTMLResourceExtensions: Set<String> = [
        "apng", "avif", "bmp", "css", "eot", "gif", "ico", "jpeg", "jpg", "m4a",
        "mp3", "oga", "ogg", "otf", "png", "svg", "tif", "tiff", "ttf", "webp",
        "woff", "woff2"
    ]

    private static let imageResourceExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "ico", "jpeg", "jpg", "png", "svg",
        "tif", "tiff", "webp"
    ]

    /// Validate responses before publication or durable commit. Explicitly enumerated offline
    /// resources are non-HTML even when their URL has no useful extension; passive caching also
    /// recognizes common artwork/font/stylesheet/audio extensions from the parsed URL path. This
    /// keeps captive-portal and upstream error documents from satisfying a save generation.
    static func shouldCacheResponse(
        httpResponse: HTTPURLResponse,
        url: String,
        data: Data,
        expectsNonHTMLResource: Bool = false
    ) -> Bool {
        // Only cache successful responses
        guard (200...299).contains(httpResponse.statusCode) else {
            print("🚫 LocalHTTPServer: Not caching HTTP error response \(httpResponse.statusCode) for: \(url)")
            return false
        }

        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "")
            .lowercased()
        let pathExtension = URL(string: url)?.pathExtension.lowercased() ?? ""
        let isKnownNonHTMLPath = nonHTMLResourceExtensions.contains(pathExtension)
        let contentTypeIsNonHTMLResource = contentType.hasPrefix("image/") ||
            contentType.hasPrefix("audio/") ||
            contentType.hasPrefix("font/") ||
            contentType.hasPrefix("text/css") ||
            contentType.contains("application/font") ||
            contentType.contains("application/vnd.ms-fontobject")
        let requiresNonHTML = expectsNonHTMLResource || isKnownNonHTMLPath || contentTypeIsNonHTMLResource

        let contentTypeIsHTML = contentType.contains("text/html") ||
            contentType.contains("application/xhtml+xml")
        let prefix = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let bodyLooksLikeHTML = prefix.hasPrefix("<!doctype html") ||
            prefix.hasPrefix("<html") ||
            prefix.hasPrefix("<head") ||
            prefix.hasPrefix("<body")

        if requiresNonHTML && (contentTypeIsHTML || bodyLooksLikeHTML) {
            print("🚨 LocalHTTPServer: CACHE CORRUPTION PREVENTED - HTML response for non-HTML resource: \(url)")
            print("🚨 Content-Type: \(contentType), Expected: artwork/font/stylesheet/audio")
            if let htmlPreview = String(data: data.prefix(200), encoding: .utf8) {
                print("🚨 HTML content preview: \(htmlPreview)")
            }
            return false
        }

        if expectsNonHTMLResource {
            guard !data.isEmpty else {
                print("🚨 LocalHTTPServer: Rejecting empty explicit offline resource: \(url)")
                return false
            }

            if pathExtension == "css" || contentType.hasPrefix("text/css") {
                guard contentType.hasPrefix("text/css") else {
                    print("🚨 LocalHTTPServer: Rejecting stylesheet with unsupported MIME \(contentType): \(url)")
                    return false
                }
            } else if pathExtension == "svg" || contentType.contains("svg") {
                guard bodyLooksLikeSVG(data) else {
                    print("🚨 LocalHTTPServer: Rejecting invalid SVG payload: \(url)")
                    return false
                }
            } else if imageResourceExtensions.contains(pathExtension) || contentType.hasPrefix("image/") {
                guard imageBodyMatchesExpectedArtwork(data, pathExtension: pathExtension, contentType: contentType) else {
                    print("🚨 LocalHTTPServer: Rejecting invalid artwork payload (type=\(contentType)): \(url)")
                    return false
                }
            } else if isExplicitWikiAudioResource(pathExtension: pathExtension, contentType: contentType) {
                guard audioBodyMatchesExpectedMagic(data, pathExtension: pathExtension, contentType: contentType) else {
                    print("🚨 LocalHTTPServer: Rejecting invalid audio payload (type=\(contentType)): \(url)")
                    return false
                }
            } else if contentType.hasPrefix("font/") ||
                        contentType.contains("application/font") ||
                        contentType.contains("application/vnd.ms-fontobject") {
                // Fonts are not part of explicit article artwork enumeration, but retaining
                // this narrow branch keeps direct cache validation correct for legacy callers.
            } else {
                print("🚨 LocalHTTPServer: Rejecting unclassifiable explicit offline resource (type=\(contentType)): \(url)")
                return false
            }
        }

        print("✅ LocalHTTPServer: Response validation passed for: \(url) (status: \(httpResponse.statusCode), type: \(contentType))")
        return true
    }

    private static func isExplicitWikiAudioResource(pathExtension: String, contentType: String) -> Bool {
        ["mp3", "ogg", "oga", "m4a"].contains(pathExtension) ||
            contentType.hasPrefix("audio/") ||
            contentType.contains("application/ogg")
    }

    private static func audioBodyMatchesExpectedMagic(
        _ data: Data,
        pathExtension: String,
        contentType: String
    ) -> Bool {
        let expectsMPEG = pathExtension == "mp3" ||
            contentType.hasPrefix("audio/mpeg") ||
            contentType.hasPrefix("audio/mp3")
        let expectsOgg = pathExtension == "ogg" ||
            pathExtension == "oga" ||
            contentType.hasPrefix("audio/ogg") ||
            contentType.contains("application/ogg")
        let expectsM4A = pathExtension == "m4a" ||
            contentType.hasPrefix("audio/mp4") ||
            contentType.hasPrefix("audio/x-m4a") ||
            contentType.hasPrefix("audio/m4a")

        if expectsMPEG {
            return bodyLooksLikeMPEGAudio(data)
        }
        if expectsOgg {
            return bodyLooksLikeOggAudio(data)
        }
        if expectsM4A {
            return bodyLooksLikeM4AAudio(data)
        }
        // Generic audio/* with no more specific hint: accept any supported wiki audio magic.
        return bodyLooksLikeMPEGAudio(data) || bodyLooksLikeOggAudio(data) || bodyLooksLikeM4AAudio(data)
    }

    private static func bodyLooksLikeMPEGAudio(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(3))
        if bytes.count >= 3 && Array(bytes.prefix(3)) == Array("ID3".utf8) {
            return true
        }
        // MPEG frame sync: 11 set bits then layer bits (common wiki MP3 starts FF FB / FF FA / FF F3).
        return bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0
    }

    private static func bodyLooksLikeOggAudio(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        return bytes.count >= 4 && Array(bytes.prefix(4)) == Array("OggS".utf8)
    }

    private static func bodyLooksLikeM4AAudio(_ data: Data) -> Bool {
        let prefix = [UInt8](data.prefix(12))
        guard prefix.count >= 8 else { return false }
        // ISO BMFF "ftyp" box typically at offset 4; accept "ftyp" anywhere in the first 12 bytes.
        let needle = Array("ftyp".utf8)
        for start in 0...(prefix.count - needle.count) {
            if Array(prefix[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }

    private static func bodyLooksLikeSVG(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(4_096), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return prefix.contains("<svg") && !prefix.contains("<html")
    }

    private static func imageBodyMatchesExpectedArtwork(
        _ data: Data,
        pathExtension: String,
        contentType: String
    ) -> Bool {
        if pathExtension == "svg" || contentType.contains("svg") {
            return bodyLooksLikeSVG(data)
        }

        let bytes = [UInt8](data.prefix(16))
        func starts(_ signature: [UInt8]) -> Bool {
            bytes.count >= signature.count && Array(bytes.prefix(signature.count)) == signature
        }
        let isPNG = starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let isJPEG = starts([0xFF, 0xD8, 0xFF])
        let isGIF = starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8))
        let isBMP = starts([0x42, 0x4D])
        let isICO = starts([0x00, 0x00, 0x01, 0x00])
        let isTIFF = starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A])
        let isWebP = bytes.count >= 12 &&
            Array(bytes[0..<4]) == Array("RIFF".utf8) &&
            Array(bytes[8..<12]) == Array("WEBP".utf8)
        let isAVIF = bytes.count >= 12 &&
            Array(bytes[4..<8]) == Array("ftyp".utf8) &&
            ["avif", "avis"].contains(String(decoding: bytes[8..<12], as: UTF8.self))

        switch pathExtension {
        case "apng", "png": return isPNG
        case "avif": return isAVIF
        case "bmp": return isBMP
        case "gif": return isGIF
        case "ico": return isICO
        case "jpeg", "jpg": return isJPEG
        case "tif", "tiff": return isTIFF
        case "webp": return isWebP
        default:
            return isPNG || isJPEG || isGIF || isBMP || isICO || isTIFF || isWebP || isAVIF
        }
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
                let cacheKey = cacheFile.deletingPathExtension().lastPathComponent
                if let response = loadCachedResponseFromDisk(cacheKey: cacheKey),
                   isCorruptedCacheEntry(response: response, cacheKey: cacheKey) {
                    cachedResponses.removeValue(forKey: cacheKey)
                    try FileManager.default.removeItem(at: cacheFile)
                    try? FileManager.default.removeItem(
                        at: cacheDirectory.appendingPathComponent("\(cacheKey).meta")
                    )
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
        guard let url = URL(string: response.url),
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ) else {
            return true
        }
        return !Self.shouldCacheResponse(
            httpResponse: httpResponse,
            url: response.url,
            data: response.data
        )
    }
    
    private func getCachedResponse(cacheKey: String) -> CachedHTTPResponse? {
        // First try in-memory cache
        if let cachedResponse = cachedResponses.response(forKey: cacheKey) {
            return cachedResponse
        }
        
        // Then try loading from disk for persistent offline access
        return loadCachedResponseFromDisk(cacheKey: cacheKey)
    }

    private func getCachedResponseForRequest(
        cacheKey: String,
        method: String,
        url: String,
        pageId: String?
    ) -> CachedHTTPResponse? {
        if let cachedResponse = getCachedResponse(cacheKey: cacheKey) {
            return cachedResponse
        }

        guard let pageId,
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

        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("❌ LocalHTTPServer: Cached response send error: \(error)")
            } else {
                print("📦 LocalHTTPServer: Cached response sent successfully for: \(cachedResponse.url)")
            }

            // Close connection after response
            self?.finishConnection(connection, cancelUpstream: false)
            connection.cancel()
        })
    }
    
    // MARK: - Persistent Storage
    
    private func getPageCacheDirectory(pageId: String) throws -> URL {
        let pageDirectory = cacheDirectory.appendingPathComponent(pageId)
        try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
        return pageDirectory
    }
    
    @discardableResult
    private func saveCachedResponseToDisk(response: CachedHTTPResponse, cacheKey: String) -> Bool {
        Self.cacheIOSync {
            let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
            let metadataFile = cacheDirectory.appendingPathComponent("\(cacheKey).meta")

            do {
                let data = try JSONEncoder().encode(response)
                try diskWriter(data, cacheFile)
                let metadata = CachePersistenceMetadata(saveGeneration: response.saveGeneration)
                try JSONEncoder().encode(metadata).write(to: metadataFile, options: .atomic)
                print("💾 LocalHTTPServer: Saved cached response to disk: \(cacheFile.lastPathComponent)")
                return true
            } catch {
                print("❌ LocalHTTPServer: Failed to save cached response to disk: \(error)")
                return false
            }
        }
    }
    
    private func loadCachedResponseFromDisk(cacheKey: String) -> CachedHTTPResponse? {
        Self.cacheIOSync {
            let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")

            do {
                let data = try Data(contentsOf: cacheFile)
                let response = try JSONDecoder().decode(CachedHTTPResponse.self, from: data)
                print("📦 LocalHTTPServer: Loaded cached response from disk: \(cacheFile.lastPathComponent)")

                // Add to memory cache for faster access. The byte-cost LRU prevents disk lookups
                // from rehydrating an unbounded legacy cache.
                cachedResponses.set(response, forKey: cacheKey)
                return response
            } catch {
                if cacheKey.contains("__snapshot__") || cacheKey.contains("_GET_") {
                    NSLog(
                        "osrsImagesLookup: disk decode error key=%@ file=%@ exists=%d err=%@",
                        cacheKey,
                        cacheFile.lastPathComponent,
                        FileManager.default.fileExists(atPath: cacheFile.path) ? 1 : 0,
                        String(describing: error)
                    )
                }
                return nil
            }
        }
    }

    private func peekCachedResponseDecodeError(cacheKey: String) -> String? {
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        do {
            let data = try Data(contentsOf: cacheFile)
            _ = try JSONDecoder().decode(CachedHTTPResponse.self, from: data)
            return nil
        } catch {
            return String(describing: error)
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

        connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
            self?.finishConnection(connection, cancelUpstream: false)
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
        osrsCanonicalNetworkURLString(urlString)
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

private struct CachePersistenceMetadata: Codable {
    let saveGeneration: String?
}

@available(iOS 17.0, *)
struct CachedHTTPResponse: Codable {
    let url: String
    let data: Data
    let timestamp: Date
    let pageId: String
    let statusCode: Int
    let headers: [String: String]
    let saveGeneration: String?

    init(
        url: String,
        data: Data,
        timestamp: Date,
        pageId: String,
        statusCode: Int,
        headers: [String: String],
        saveGeneration: String? = nil
    ) {
        self.url = url
        self.data = data
        self.timestamp = timestamp
        self.pageId = pageId
        self.statusCode = statusCode
        self.headers = headers
        self.saveGeneration = saveGeneration
    }
}

struct LocalHTTPServerCacheSessionToken: Equatable {
    let id = UUID()
}

@available(iOS 17.0, *)
final class LocalHTTPResponseCache {
    private struct Entry {
        let response: CachedHTTPResponse
        let byteCost: Int
        var access: UInt64
    }

    private let lock = NSLock()
    private let maximumByteCost: Int
    private var storage: [String: Entry] = [:]
    private var keysByPagePrefix: [String: Set<String>] = [:]
    private var totalByteCost = 0
    private var accessCounter: UInt64 = 0

    init(maximumByteCost: Int = 24 * 1024 * 1024) {
        self.maximumByteCost = max(0, maximumByteCost)
    }

    func response(forKey key: String) -> CachedHTTPResponse? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = storage[key] else { return nil }
        accessCounter &+= 1
        entry.access = accessCounter
        storage[key] = entry
        return entry.response
    }

    func set(_ response: CachedHTTPResponse, forKey key: String) {
        lock.lock()
        if let old = storage[key] {
            totalByteCost -= old.byteCost
        }
        accessCounter &+= 1
        let byteCost = Self.byteCost(of: response)
        storage[key] = Entry(response: response, byteCost: byteCost, access: accessCounter)
        totalByteCost += byteCost
        if let pagePrefix = pagePrefix(forCacheKey: key) {
            keysByPagePrefix[pagePrefix, default: []].insert(key)
        }
        evictIfNeeded()
        lock.unlock()
    }

    func removeValue(forKey key: String) {
        lock.lock()
        if let removed = storage.removeValue(forKey: key) {
            totalByteCost -= removed.byteCost
        }
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
                storage[key].map { (key, $0.response) }
            }
        }

        return storage
            .filter { key, _ in
                guard let prefix else { return true }
                return key.hasPrefix(prefix)
            }
            .map { ($0.key, $0.value.response) }
    }

    var byteCost: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalByteCost
    }

    private func evictIfNeeded() {
        while totalByteCost > maximumByteCost,
              let victim = storage.min(by: { $0.value.access < $1.value.access }) {
            storage.removeValue(forKey: victim.key)
            totalByteCost -= victim.value.byteCost
            if let pagePrefix = pagePrefix(forCacheKey: victim.key) {
                keysByPagePrefix[pagePrefix]?.remove(victim.key)
                if keysByPagePrefix[pagePrefix]?.isEmpty == true {
                    keysByPagePrefix.removeValue(forKey: pagePrefix)
                }
            }
        }
    }

    private static func byteCost(of response: CachedHTTPResponse) -> Int {
        response.data.count + response.url.utf8.count + response.pageId.utf8.count +
            response.headers.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
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

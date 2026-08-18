//
//  NetworkManager.swift
//  OSRS Wiki
//
//  Network utility with connectivity monitoring, retry logic, and standardized error handling
//

import Foundation
import Network

/// One transport/cache identity for app-owned HTTP requests. Preserve meaningful path/query
/// case and percent encoding, normalize only scheme/host/query ordering, and discard fragments
/// because they are never sent over HTTP.
nonisolated func osrsCanonicalNetworkURLString(_ urlString: String) -> String {
    guard var components = URLComponents(string: urlString) else {
        return urlString
    }

    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    components.fragment = nil

    if let percentEncodedQuery = components.percentEncodedQuery,
       !percentEncodedQuery.isEmpty {
        // URLComponents.queryItems decodes reserved `%2F`/`%3F` bytes and may serialize them as
        // literal query delimiters. Sort the encoded fields themselves so equivalent ordering is
        // stable without changing authored query data or the loopback/cache identity.
        components.percentEncodedQuery = percentEncodedQuery
            .split(separator: "&", omittingEmptySubsequences: false)
            .map(String.init)
            .sorted()
            .joined(separator: "&")
    }

    return components.string ?? urlString
}

extension Notification.Name {
    static let osrsNetworkPathConditionsDidChange = Notification.Name("osrsNetworkPathConditionsDidChange")
}

enum osrsNetworkRoutingPolicy: Equatable, Sendable {
    case configured
    /// Retain configured proxy-first/direct-fallback and forced-offline cache behavior while
    /// marking this individual request as ineligible for passive/offline cache writes.
    case configuredNoStore
}

private func osrsNetworkDebugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}

@MainActor
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    @Published var isConnected = true
    @Published var connectionType: NWInterface.InterfaceType?
    @Published private(set) var isConstrained = false
    @Published private(set) var isExpensive = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var session: URLSession
    private var defaultSession: URLSession
    private var directNoStoreSession: URLSession
    private var proxySession: URLSession?
#if DEBUG
    private var forcedOfflineOverrideForTests = osrsTestEnvironment.forcesNetworkOfflineForUITests
    private var networkConditionOverrideForTests = osrsTestEnvironment.networkConditionForUITests

    var isForcedOfflineForTests: Bool {
        forcedOfflineOverrideForTests
    }

    var networkConditionForTests: osrsNetworkConditionForTests {
        networkConditionOverrideForTests
    }

    func setForcedOfflineForTests(_ forced: Bool) {
        forcedOfflineOverrideForTests = forced
        if forced {
            isConnected = false
            connectionType = nil
        } else {
            isConnected = true
        }
    }

    func setNetworkConditionForTests(_ condition: osrsNetworkConditionForTests) {
        networkConditionOverrideForTests = condition
    }
#endif
    
    private init() {
        // Configure default URLSession with reasonable timeouts
        let defaultConfig = URLSessionConfiguration.default
        defaultConfig.timeoutIntervalForRequest = 15.0
        defaultConfig.timeoutIntervalForResource = 30.0
        defaultConfig.waitsForConnectivity = false // Don't wait indefinitely
        self.defaultSession = URLSession(configuration: defaultConfig)
        self.session = defaultSession // Start with default session

        let directConfig = URLSessionConfiguration.ephemeral
        directConfig.timeoutIntervalForRequest = 15.0
        directConfig.timeoutIntervalForResource = 30.0
        directConfig.waitsForConnectivity = false
        directConfig.urlCache = nil
        directConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.directNoStoreSession = URLSession(configuration: directConfig)

#if DEBUG
        if forcedOfflineOverrideForTests {
            isConnected = false
            connectionType = nil
        }
#endif

        startMonitoring()
    }
    
    private var proxyEnabled = false
    private var proxyPort = 8080
    private var proxyAllowsDirectFallback = true
    
    /// Configure proxy routing through localhost server  
    func configureProxyRouting(
        enabled: Bool,
        port: Int = 8080,
        allowsDirectFallback: Bool = true
    ) {
        proxyEnabled = enabled
        proxyPort = port
        proxyAllowsDirectFallback = allowsDirectFallback
        
        if enabled {
            osrsNetworkDebugLog("🔗 NetworkManager: Enabled request routing through localhost:\(port)")
        } else {
            osrsNetworkDebugLog("🔄 NetworkManager: Disabled request routing, using direct connection")
        }
    }
    
    /// Rewrite URL to go through localhost if proxy is enabled
    private func rewriteURLForProxy(_ url: URL) -> URL {
        guard proxyEnabled else { return url }

        let canonicalString = osrsCanonicalNetworkURLString(url.absoluteString)
        guard let original = URLComponents(string: canonicalString),
              let host = original.host else {
            return url
        }
        let authority = original.port.map { "\(host):\($0)" } ?? host
        let originalPath = original.percentEncodedPath.isEmpty ? "/" : original.percentEncodedPath

        // Convert HTTPS URLs to go through localhost HTTP server
        // https://oldschool.runescape.wiki/api.php -> http://localhost:8080/https/oldschool.runescape.wiki/api.php
        var rewritten = URLComponents()
        rewritten.scheme = "http"
        rewritten.host = "127.0.0.1"
        rewritten.port = proxyPort
        rewritten.percentEncodedPath = "/https/\(authority)\(originalPath)"
        rewritten.percentEncodedQuery = original.percentEncodedQuery
        let rewrittenURL = rewritten.url
        
        osrsNetworkDebugLog("🔄 NetworkManager: Rewriting URL: \(url.absoluteString) -> \(rewrittenURL?.absoluteString ?? "invalid")")
        return rewrittenURL ?? url
    }

    private func requestURLs(
        for url: URL,
        routingPolicy: osrsNetworkRoutingPolicy
    ) -> [URL] {
        guard proxyEnabled else { return [url] }
        let proxyURL = rewriteURLForProxy(url)
#if DEBUG
        // Forced-offline tests may still exercise the loopback cache server,
        // but must never escape to the real network through direct fallback.
        if forcedOfflineOverrideForTests {
            return [proxyURL]
        }
#endif
        guard proxyAllowsDirectFallback, proxyURL != url else { return [proxyURL] }
        return [proxyURL, url]
    }

#if DEBUG
    func requestURLsForTesting(
        for url: URL,
        routingPolicy: osrsNetworkRoutingPolicy
    ) -> [URL] {
        requestURLs(for: url, routingPolicy: routingPolicy)
    }

    var proxyRoutingStateForTesting: (enabled: Bool, allowsDirectFallback: Bool) {
        (proxyEnabled, proxyAllowsDirectFallback)
    }
#endif
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
#if DEBUG
                if self?.forcedOfflineOverrideForTests == true {
                    self?.isConnected = false
                    self?.connectionType = nil
                    self?.isConstrained = false
                    self?.isExpensive = false
                    osrsNetworkDebugLog("🧪 NetworkManager: Ignoring NWPathMonitor update while forced offline for UI tests")
                    NotificationCenter.default.post(name: .osrsNetworkPathConditionsDidChange, object: nil)
                    return
                }
#endif
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                self?.isConstrained = path.isConstrained
                self?.isExpensive = path.isExpensive
                NotificationCenter.default.post(name: .osrsNetworkPathConditionsDidChange, object: nil)
                
                if path.status == .satisfied {
                    osrsNetworkDebugLog("🌐 NetworkManager: Connection restored")
                } else {
                    osrsNetworkDebugLog("🚫 NetworkManager: Connection lost")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Perform network request with standardized error handling
    func performRequest<T: Codable>(
        url: URL,
        responseType: T.Type,
        retryCount: Int = 1,
        bypassCache: Bool = false,
        routingPolicy: osrsNetworkRoutingPolicy = .configured
    ) async throws -> T {
        let (data, _) = try await performTransportRequest(
            url: url,
            retryCount: retryCount,
            bypassCache: bypassCache,
            routingPolicy: routingPolicy
        )

        do {
            let result = try JSONDecoder().decode(T.self, from: data)
            osrsNetworkDebugLog("✅ NetworkManager: JSON decode successful for type: \(T.self)")
            return result
        } catch {
            osrsNetworkDebugLog("❌ NetworkManager: JSON decode failed for type \(T.self): \(error)")
            throw NetworkError.invalidData
        }
    }

    /// Authoritative explicit-save transport. These requests must always reach the configured
    /// loopback route instead of being satisfied by URLSession's warmed response cache, because
    /// only a fresh loopback request can be stamped into the active save generation.
    func performExplicitOfflineRequest<T: Codable>(
        url: URL,
        responseType: T.Type,
        retryCount: Int = 1
    ) async throws -> T {
        try await performRequest(
            url: url,
            responseType: responseType,
            retryCount: retryCount,
            bypassCache: true,
            routingPolicy: .configured
        )
    }
    
    /// Perform raw data request with error handling (for HTML, images, etc.)
    func performDataRequest(
        url: URL,
        retryCount: Int = 1,
        bypassCache: Bool = false,
        routingPolicy: osrsNetworkRoutingPolicy = .configured
    ) async throws -> (Data, URLResponse) {
        try await performTransportRequest(
            url: url,
            retryCount: retryCount,
            bypassCache: bypassCache,
            routingPolicy: routingPolicy
        )
    }

    func performExplicitOfflineDataRequest(
        url: URL,
        retryCount: Int = 1
    ) async throws -> (Data, URLResponse) {
        try await performDataRequest(
            url: url,
            retryCount: retryCount,
            bypassCache: true,
            routingPolicy: .configured
        )
    }

    private nonisolated static func transportRequest(
        for url: URL,
        bypassCache: Bool,
        routingPolicy: osrsNetworkRoutingPolicy
    ) -> URLRequest {
        var request = URLRequest(url: url)
        if bypassCache || routingPolicy == .configuredNoStore {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue(String(Date().timeIntervalSince1970), forHTTPHeaderField: "X-Cache-Bust")
        }
        if routingPolicy == .configuredNoStore {
            request.setValue("1", forHTTPHeaderField: "X-OSRS-No-Offline-Store")
        }
        return request
    }

#if DEBUG
    nonisolated static func explicitOfflineRequestForTesting(url: URL) -> URLRequest {
        transportRequest(for: url, bypassCache: true, routingPolicy: .configured)
    }
#endif

    private func performTransportRequest(
        url: URL,
        retryCount: Int,
        bypassCache: Bool,
        routingPolicy: osrsNetworkRoutingPolicy = .configured
    ) async throws -> (Data, URLResponse) {
        var lastError: NetworkError?

        osrsNetworkDebugLog("🔍 NetworkManager: performDataRequest starting - proxyEnabled: \(proxyEnabled), isConnected: \(isConnected)")
        osrsNetworkDebugLog("🔍 NetworkManager: Original URL: \(url.absoluteString)")

#if DEBUG
        // Reachability monitors are advisory and can briefly be stale on app
        // launch or network handoff. Only the explicit test override is a
        // request gate; real requests are allowed to reach URLSession.
        if forcedOfflineOverrideForTests && !proxyEnabled {
            throw NetworkError.noConnection
        }
#endif

        let candidates = requestURLs(for: url, routingPolicy: routingPolicy)
        for (candidateIndex, requestURL) in candidates.enumerated() {
            let hasDirectFallback = candidateIndex < candidates.count - 1
            for attempt in 0...retryCount {
                do {
                    let (data, response): (Data, URLResponse)
                    osrsNetworkDebugLog("🌐 NetworkManager: Making data request to: \(requestURL.absoluteString) (attempt \(attempt + 1))")

                    if let simulatedResponse = try await simulatedNetworkResponseForTestsIfNeeded(url: requestURL) {
                        data = simulatedResponse.data
                        response = simulatedResponse.response
                    } else {
                        if bypassCache || routingPolicy == .configuredNoStore {
                            let request = Self.transportRequest(
                                for: requestURL,
                                bypassCache: bypassCache,
                                routingPolicy: routingPolicy
                            )
                            let requestSession = routingPolicy == .configuredNoStore ? directNoStoreSession : session
                            (data, response) = try await requestSession.data(for: request)
                        } else {
                            (data, response) = try await session.data(from: requestURL)
                        }
                    }

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        throw NetworkError.from(httpStatusCode: httpResponse.statusCode)
                    }

                    return (data, response)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let networkError: NetworkError
                    if let urlError = error as? URLError {
                        networkError = NetworkError.from(urlError)
                    } else if let typedError = error as? NetworkError {
                        networkError = typedError
                    } else {
                        networkError = NetworkError.unknown(error)
                    }
                    lastError = networkError

                    if networkError.isRetryable && attempt < retryCount {
                        let delay = TimeInterval(pow(2.0, Double(attempt)))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }

                    if hasDirectFallback {
                        osrsNetworkDebugLog("⚠️ NetworkManager: Local cache route failed; retrying the original URL directly")
                        break
                    }
                    throw networkError
                }
            }
        }

        throw lastError ?? NetworkError.unknown(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"]))
    }

    private func simulatedNetworkResponseForTestsIfNeeded(url: URL) async throws -> (data: Data, response: URLResponse)? {
#if DEBUG
        switch networkConditionOverrideForTests {
        case .none:
            return nil
        case .latency(let seconds):
            try await sleepForNetworkCondition(seconds)
            return nil
        case .timeout(let seconds):
            try await sleepForNetworkCondition(seconds)
            throw NetworkError.timeout
        case .connectionLost(let seconds):
            try await sleepForNetworkCondition(seconds)
            throw NetworkError.connectionLost
        case .serverError(let statusCode, let seconds):
            try await sleepForNetworkCondition(seconds)
            throw NetworkError.serverError(statusCode)
        case .captivePortal(let seconds):
            try await sleepForNetworkCondition(seconds)
            let data = Data("""
            <!doctype html>
            <html>
              <head><title>Network Sign In</title></head>
              <body>Please sign in to continue.</body>
            </html>
            """.utf8)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            ) ?? URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
            return (data, response)
        }
#else
        return nil
#endif
    }

    private func sleepForNetworkCondition(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(min(seconds, 30) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
    
    /// Check if currently connected to internet
    var hasConnection: Bool {
        return isConnected
    }
    
    /// Get connection status description for user display
    var connectionStatus: String {
        if !isConnected {
            return "No internet connection"
        }
        
        switch connectionType {
        case .wifi:
            return "Connected via Wi-Fi"
        case .cellular:
            return "Connected via cellular"
        case .wiredEthernet:
            return "Connected via ethernet"
        case .loopback:
            return "Connected"
        case .other:
            return "Connected"
        case .none:
            return "Connected"
        @unknown default:
            return "Connected"
        }
    }
    
    deinit {
        monitor.cancel()
    }
}

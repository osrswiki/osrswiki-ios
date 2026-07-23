//
//  NetworkManager.swift
//  OSRS Wiki
//
//  Network utility with connectivity monitoring, retry logic, and standardized error handling
//

import Foundation
import Network

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
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var session: URLSession
    private var defaultSession: URLSession
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
    
    /// Configure proxy routing through localhost server  
    func configureProxyRouting(enabled: Bool, port: Int = 8080) {
        proxyEnabled = enabled
        proxyPort = port
        
        if enabled {
            osrsNetworkDebugLog("🔗 NetworkManager: Enabled request routing through localhost:\(port)")
        } else {
            osrsNetworkDebugLog("🔄 NetworkManager: Disabled request routing, using direct connection")
        }
    }
    
    /// Rewrite URL to go through localhost if proxy is enabled
    private func rewriteURLForProxy(_ url: URL) -> URL {
        guard proxyEnabled else { return url }
        
        // Convert HTTPS URLs to go through localhost HTTP server
        // https://oldschool.runescape.wiki/api.php -> http://localhost:8080/https/oldschool.runescape.wiki/api.php
        let rewrittenURL = URL(string: "http://127.0.0.1:\(proxyPort)/https/\(url.host ?? "unknown")\(url.path)\(url.query != nil ? "?" + url.query! : "")")
        
        osrsNetworkDebugLog("🔄 NetworkManager: Rewriting URL: \(url.absoluteString) -> \(rewrittenURL?.absoluteString ?? "invalid")")
        return rewrittenURL ?? url
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
#if DEBUG
                if self?.forcedOfflineOverrideForTests == true {
                    self?.isConnected = false
                    self?.connectionType = nil
                    osrsNetworkDebugLog("🧪 NetworkManager: Ignoring NWPathMonitor update while forced offline for UI tests")
                    return
                }
#endif
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                
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
        retryCount: Int = 1
    ) async throws -> T {
        var lastError: NetworkError?
        
        // PHASE 14.1: Add comprehensive proxy debugging
        osrsNetworkDebugLog("🔍 NetworkManager: performRequest starting - proxyEnabled: \(proxyEnabled), isConnected: \(isConnected)")
        osrsNetworkDebugLog("🔍 NetworkManager: Original URL: \(url.absoluteString)")
        
        // Check connectivity before attempting request (skip if proxy routing enabled for caching)
        if !isConnected && !proxyEnabled {
            throw NetworkError.noConnection
        }
        
        // CRITICAL FIX: Apply URL rewriting for proxy routing (was missing!)
        let requestURL = rewriteURLForProxy(url)
        if requestURL.absoluteString != url.absoluteString {
            osrsNetworkDebugLog("🔄 NetworkManager: URL rewritten for proxy: \(url.absoluteString) -> \(requestURL.absoluteString)")
        }
        
        for attempt in 0...retryCount {
            do {
                osrsNetworkDebugLog("🌐 NetworkManager: Making request to: \(requestURL.absoluteString) (attempt \(attempt + 1))")
                let data: Data
                let response: URLResponse

                if let simulatedResponse = try await simulatedNetworkResponseForTestsIfNeeded(url: requestURL) {
                    data = simulatedResponse.data
                    response = simulatedResponse.response
                } else {
                    (data, response) = try await session.data(from: requestURL)
                }
                
                // Validate HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    osrsNetworkDebugLog("❌ NetworkManager: Invalid response type received")
                    throw NetworkError.invalidResponse
                }
                
                osrsNetworkDebugLog("✅ NetworkManager: HTTP response received - status: \(httpResponse.statusCode), data: \(data.count) bytes")
                
                // Handle HTTP error codes
                if !(200...299).contains(httpResponse.statusCode) {
                    osrsNetworkDebugLog("❌ NetworkManager: HTTP error status: \(httpResponse.statusCode)")
                    throw NetworkError.from(httpStatusCode: httpResponse.statusCode)
                }
                
                // Decode response with enhanced error handling
                do {
                    // Log raw response for debugging JSON decode issues
                    if let jsonString = String(data: data, encoding: .utf8) {
                        osrsNetworkDebugLog("📄 NetworkManager: Raw response preview: \(String(jsonString.prefix(200)))")
                    }
                    
                    let result = try JSONDecoder().decode(T.self, from: data)
                    osrsNetworkDebugLog("✅ NetworkManager: JSON decode successful for type: \(T.self)")
                    return result
                } catch {
                    osrsNetworkDebugLog("❌ NetworkManager: JSON decode failed for type \(T.self): \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        osrsNetworkDebugLog("📄 NetworkManager: Failed JSON content: \(jsonString)")
                    }
                    throw NetworkError.invalidData
                }
                
            } catch let urlError as URLError {
                let networkError = NetworkError.from(urlError)
                lastError = networkError
                
                // Don't retry non-retryable errors
                if !networkError.isRetryable || attempt >= retryCount {
                    throw networkError
                }
                
                osrsNetworkDebugLog("🔄 NetworkManager: Retrying request (attempt \(attempt + 1)/\(retryCount + 1)) after error: \(networkError.localizedDescription)")
                
                // Wait before retry with exponential backoff
                let delay = TimeInterval(pow(2.0, Double(attempt)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
            } catch let networkError as NetworkError {
                lastError = networkError
                
                if !networkError.isRetryable || attempt >= retryCount {
                    throw networkError
                }
                
                osrsNetworkDebugLog("🔄 NetworkManager: Retrying request (attempt \(attempt + 1)/\(retryCount + 1)) after error: \(networkError.localizedDescription)")
                
                let delay = TimeInterval(pow(2.0, Double(attempt)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
            } catch {
                let networkError = NetworkError.unknown(error)
                lastError = networkError
                
                if attempt >= retryCount {
                    throw networkError
                }
                
                osrsNetworkDebugLog("🔄 NetworkManager: Retrying request (attempt \(attempt + 1)/\(retryCount + 1)) after unknown error: \(error.localizedDescription)")
                
                let delay = TimeInterval(pow(2.0, Double(attempt)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // This should never be reached, but provide fallback
        throw lastError ?? NetworkError.unknown(NSError(domain: "NetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"]))
    }
    
    /// Perform raw data request with error handling (for HTML, images, etc.)
    func performDataRequest(
        url: URL,
        retryCount: Int = 1,
        bypassCache: Bool = false
    ) async throws -> (Data, URLResponse) {
        var lastError: NetworkError?
        
        // PHASE 15.1: Add comprehensive proxy debugging
        osrsNetworkDebugLog("🔍 NetworkManager: performDataRequest starting - proxyEnabled: \(proxyEnabled), isConnected: \(isConnected)")
        osrsNetworkDebugLog("🔍 NetworkManager: Original URL: \(url.absoluteString)")
        
        // Check connectivity before attempting request (skip if proxy routing enabled for caching)
        if !isConnected && !proxyEnabled {
            throw NetworkError.noConnection
        }
        
        // Rewrite URL for proxy if enabled
        let requestURL = rewriteURLForProxy(url)
        if requestURL.absoluteString != url.absoluteString {
            osrsNetworkDebugLog("🔄 NetworkManager: URL rewritten for proxy: \(url.absoluteString) -> \(requestURL.absoluteString)")
        }
        
        for attempt in 0...retryCount {
            do {
                let (data, response): (Data, URLResponse)
                osrsNetworkDebugLog("🌐 NetworkManager: Making data request to: \(requestURL.absoluteString) (attempt \(attempt + 1))")
                
                if let simulatedResponse = try await simulatedNetworkResponseForTestsIfNeeded(url: requestURL) {
                    data = simulatedResponse.data
                    response = simulatedResponse.response
                } else {
                    if bypassCache {
                        // Create request with cache bypass headers
                        var request = URLRequest(url: requestURL)
                        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
                        request.setValue(String(Date().timeIntervalSince1970), forHTTPHeaderField: "X-Cache-Bust")

                        osrsNetworkDebugLog("🔄 NetworkManager: Making fresh request (bypassing cache)")
                        (data, response) = try await session.data(for: request)
                    } else {
                        (data, response) = try await session.data(from: requestURL)
                    }
                }
                
                // Validate HTTP response if applicable
                if let httpResponse = response as? HTTPURLResponse {
                    osrsNetworkDebugLog("✅ NetworkManager: HTTP data response received - status: \(httpResponse.statusCode), data: \(data.count) bytes")
                    
                    if !(200...299).contains(httpResponse.statusCode) {
                        osrsNetworkDebugLog("❌ NetworkManager: HTTP error status: \(httpResponse.statusCode)")
                        throw NetworkError.from(httpStatusCode: httpResponse.statusCode)
                    }
                } else {
                    osrsNetworkDebugLog("✅ NetworkManager: Non-HTTP response received - data: \(data.count) bytes")
                }
                
                return (data, response)
                
            } catch let urlError as URLError {
                let networkError = NetworkError.from(urlError)
                lastError = networkError
                
                if !networkError.isRetryable || attempt >= retryCount {
                    throw networkError
                }
                
                osrsNetworkDebugLog("🔄 NetworkManager: Retrying data request (attempt \(attempt + 1)/\(retryCount + 1)) after error: \(networkError.localizedDescription)")
                
                let delay = TimeInterval(pow(2.0, Double(attempt)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
            } catch let networkError as NetworkError {
                lastError = networkError
                
                if !networkError.isRetryable || attempt >= retryCount {
                    throw networkError
                }
                
                osrsNetworkDebugLog("🔄 NetworkManager: Retrying data request (attempt \(attempt + 1)/\(retryCount + 1)) after error: \(networkError.localizedDescription)")
                
                let delay = TimeInterval(pow(2.0, Double(attempt)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
            } catch {
                let networkError = NetworkError.unknown(error)
                lastError = networkError
                
                if attempt >= retryCount {
                    throw networkError
                }
                
                osrsNetworkDebugLog("🔄 NetworkManager: Retrying data request (attempt \(attempt + 1)/\(retryCount + 1)) after unknown error: \(error.localizedDescription)")
                
                let delay = TimeInterval(pow(2.0, Double(attempt)))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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

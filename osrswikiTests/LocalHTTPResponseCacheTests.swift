//
//  LocalHTTPResponseCacheTests.swift
//  osrswikiTests
//

import XCTest
@testable import osrswiki

private final class osrsOriginTransportStub: URLProtocol {
    private static let lock = NSLock()
    private static var requestCountStorage = 0
    private static var lastRequestStorage: URLRequest?

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountStorage
    }

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequestStorage
    }

    static func reset() {
        lock.lock()
        requestCountStorage = 0
        lastRequestStorage = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requestCountStorage += 1
        Self.lastRequestStorage = request
        Self.lock.unlock()

        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x46, 0x52, 0x45, 0x53, 0x48])
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@available(iOS 17.0, *)
final class LocalHTTPResponseCacheTests: XCTestCase {
    func testRequestCacheKeyIsStableAndNormalizesEquivalentURLs() throws {
        let first = LocalHTTPServer.cacheKey(
            pageId: "page-123",
            method: "GET",
            url: "HTTPS://OldSchool.Runescape.Wiki/images/thumb/Varrock.png/300px-Varrock.png?b=2&a=1"
        )
        let second = LocalHTTPServer.cacheKey(
            pageId: "page-123",
            method: "get",
            url: "https://oldschool.runescape.wiki/images/thumb/Varrock.png/300px-Varrock.png?a=1&b=2"
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("page-123_GET_"))
        XCTAssertFalse(first.contains("hashValue"))
    }

    func testExplicitOfflineRefreshRequestBypassesAWarmedURLCacheEntry() throws {
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/Warm.png"))
        let cache = URLCache(memoryCapacity: 1_024_000, diskCapacity: 0)
        let ordinaryRequest = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: Data("stale".utf8)),
            for: ordinaryRequest
        )
        XCTAssertNotNil(cache.cachedResponse(for: ordinaryRequest), "Fixture must begin warm")

        let explicitRequest = NetworkManager.explicitOfflineRequestForTesting(url: url)
        XCTAssertEqual(explicitRequest.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(explicitRequest.value(forHTTPHeaderField: "Cache-Control"), "no-store, no-cache")
        XCTAssertEqual(explicitRequest.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertNotNil(explicitRequest.value(forHTTPHeaderField: "X-Cache-Bust"))
        XCTAssertNil(
            explicitRequest.value(forHTTPHeaderField: "X-OSRS-No-Offline-Store"),
            "Explicit refresh must bypass URLSession cache while remaining eligible for the active durable generation"
        )
    }

    func testHTTPFragmentsShareOneDurableCacheIdentityAndGeneration() throws {
        let cacheDirectory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: cacheDirectory)
        let pageId = "saved-svg-fragment"
        let generation = "save-generation-fragment"
        let inventoryURL = "https://oldschool.runescape.wiki/images/sprite.svg?rev=A#inventory"
        let equipmentURL = "https://oldschool.runescape.wiki/images/sprite.svg?rev=A#equipment"
        let networkURL = "https://oldschool.runescape.wiki/images/sprite.svg?rev=A"

        XCTAssertEqual(
            LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: inventoryURL),
            LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: equipmentURL)
        )
        XCTAssertEqual(
            LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: equipmentURL),
            LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: networkURL)
        )

        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: networkURL)),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/svg+xml"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: networkURL,
            data: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8),
            response: response,
            saveGeneration: generation
        ))
        XCTAssertTrue(server.hasPersistedResponse(
            pageId: pageId,
            url: inventoryURL,
            saveGeneration: generation
        ))
        XCTAssertTrue(server.hasPersistedResponse(
            pageId: pageId,
            url: equipmentURL,
            saveGeneration: generation
        ))
    }

    func testVerifiedSnapshotByteCountIsExactDeduplicatedAndGenerationBound() async throws {
        let directory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let pageId = "saved-byte-count"
        let generation = "saved-byte-count-generation"
        let parseURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/api.php?action=parse&page=Varrock"))
        let imageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/Varrock.png"))
        let parseResponse = try XCTUnwrap(HTTPURLResponse(
            url: parseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        let imageResponse = try XCTUnwrap(HTTPURLResponse(
            url: imageURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))

        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: parseURL.absoluteString,
            data: Data(#"{"parse":{"text":"<img>"}}"#.utf8),
            response: parseResponse,
            saveGeneration: generation
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: imageURL.absoluteString,
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01]),
            response: imageResponse,
            saveGeneration: generation
        ))

        let urls = [parseURL.absoluteString, imageURL.absoluteString]
        let expected = try urls.reduce(Int64(0)) { partial, url in
            let key = LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: url)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent("\(key).cache").path
            )
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return partial + fileSize
        }

        let persistedByteCount = await server.persistedByteCountAsync(
            pageId: pageId,
            urls: urls + [imageURL.absoluteString],
            saveGeneration: generation
        )
        XCTAssertEqual(
            persistedByteCount,
            expected,
            "Duplicate resource identities must not inflate the published Saved size"
        )
        let staleGenerationByteCount = await server.persistedByteCountAsync(
            pageId: pageId,
            urls: urls,
            saveGeneration: "stale-generation"
        )
        XCTAssertNil(staleGenerationByteCount)
    }

    func testArticleParseCacheKeyIncludesRequestedArticleURL() throws {
        let pageId = "page__w_The_Blood_Moon_Rises"
        let bloodMoonURL = "https://oldschool.runescape.wiki/api.php?action=parse&format=json&prop=text%7Cdisplaytitle%7Crevid&disablelimitreport=1&wrapoutputclass=mw-parser-output&redirects=1&page=The%20Blood%20Moon%20Rises"
        let chambersURL = "https://oldschool.runescape.wiki/api.php?action=parse&format=json&prop=text%7Cdisplaytitle%7Crevid&disablelimitreport=1&wrapoutputclass=mw-parser-output&redirects=1&page=Chambers%20of%20Xeric"

        let bloodMoonKey = LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: bloodMoonURL)
        let chambersKey = LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: chambersURL)

        XCTAssertNotEqual(bloodMoonKey, chambersKey)
        XCTAssertTrue(bloodMoonKey.hasPrefix("\(pageId)_main_GET_"))
        XCTAssertFalse(bloodMoonKey.hasSuffix("_main.html"))
    }

    func testCopiedCacheEntriesRemainReadableAfterServerRecreation() throws {
        let cacheDirectory = try makeTemporaryCacheDirectory()
        let sourceServer = LocalHTTPServer(port: 0, cacheDirectory: cacheDirectory)
        let url = "https://oldschool.runescape.wiki/images/thumb/Varrock_East_bank.png/600px-Varrock_East_bank.png?732e4"
        let payload = Data("image-bytes".utf8)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: url)),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))

        sourceServer.cacheResponseDirect(pageId: "browsing-page", url: url, data: payload, response: response)
        sourceServer.copyCacheEntries(from: "browsing-page", to: "saved-page")

        let relaunchedServer = LocalHTTPServer(port: 0, cacheDirectory: cacheDirectory)
        relaunchedServer.setPageIdContext(pageId: "saved-page")
        let cached = relaunchedServer.getCachedResponseForAsset(url: url, pageId: "saved-page")

        XCTAssertEqual(cached?.data, payload)
        XCTAssertEqual(cached?.pageId, "saved-page")
        XCTAssertEqual(cached?.headers["Content-Type"], "image/png")
    }

    func testOfflineCompletionRequiresEveryExactResourceToBePersisted() throws {
        let cacheDirectory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: cacheDirectory)
        let pageId = "saved-required-set"
        let urls = [
            "https://oldschool.runescape.wiki/images/required-a.png",
            "https://oldschool.runescape.wiki/images/required-b.png"
        ]
        for urlString in urls {
            let url = try XCTUnwrap(URL(string: urlString))
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            ))
            server.cacheResponseDirect(
                pageId: pageId,
                url: urlString,
                data: Data(urlString.utf8),
                response: response
            )
        }

        XCTAssertTrue(server.hasPersistedResponses(pageId: pageId, urls: urls))

        // Model one disk write failing after the response was accepted into memory. The exact
        // persisted-set contract must fail even though that response remains readable in memory.
        let missingKey = LocalHTTPServer.cacheKeyForRequest(
            pageId: pageId,
            method: "GET",
            url: urls[1]
        )
        try FileManager.default.removeItem(
            at: cacheDirectory.appendingPathComponent("\(missingKey).cache")
        )
        XCTAssertNotNil(server.getCachedResponseForAsset(url: urls[1], pageId: pageId))
        XCTAssertFalse(server.hasPersistedResponses(pageId: pageId, urls: urls))
    }

    func testTextOnlySavedPageUsesDurableMainResponseWithoutRequiringAnAsset() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let pageId = "saved-text-only"
        let parseURL = try XCTUnwrap(ArticleViewModel.makeParseRequestURL(pageTitle: "Text only"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: parseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: parseURL.absoluteString,
            data: validParsePayload(title: "Text only"),
            response: response
        ))

        XCTAssertTrue(server.hasPersistedMainResponse(pageId: pageId, url: parseURL.absoluteString))
        XCTAssertFalse(
            server.hasCompleteCache(pageId: pageId),
            "The legacy main-plus-resource heuristic must not gate a valid text-only saved page"
        )
    }

    func testPersistedMainProbeRequiresValidOnDiskParseAndExactLegacyIdentity() throws {
        let directory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let pageId = "saved-main-probe"
        let parseURL = try XCTUnwrap(ArticleViewModel.makeParseRequestURL(pageTitle: "Varrock"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: parseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: parseURL.absoluteString,
            data: validParsePayload(title: "Varrock"),
            response: response
        ))
        XCTAssertTrue(server.hasPersistedMainResponse(pageId: pageId, url: parseURL.absoluteString))

        let exactKey = LocalHTTPServer.cacheKeyForRequest(
            pageId: pageId,
            method: "GET",
            url: parseURL.absoluteString
        )
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(exactKey).cache")
        )
        XCTAssertNotNil(
            server.cachedResponseForRequestForTesting(pageId: pageId, url: parseURL.absoluteString),
            "Fixture must retain a warm memory entry after the durable file is removed"
        )
        XCTAssertFalse(
            server.hasPersistedMainResponse(pageId: pageId, url: parseURL.absoluteString),
            "A warm memory response must never satisfy the durable-main probe"
        )
        XCTAssertNil(
            server.cachedResponseForRequestForTesting(pageId: pageId, url: parseURL.absoluteString),
            "A failed durable-main probe must evict the warm memory entry so the next online load can heal from origin"
        )

        let legacyKey = "\(pageId)_main.html"
        let mismatchedURL = try XCTUnwrap(ArticleViewModel.makeParseRequestURL(pageTitle: "Falador"))
        let mismatchedLegacy = CachedHTTPResponse(
            url: mismatchedURL.absoluteString,
            data: validParsePayload(title: "Falador"),
            timestamp: Date(),
            pageId: pageId,
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        let legacyFile = directory.appendingPathComponent("\(legacyKey).cache")
        try JSONEncoder().encode(mismatchedLegacy).write(to: legacyFile, options: .atomic)
        XCTAssertFalse(server.hasPersistedMainResponse(pageId: pageId, url: parseURL.absoluteString))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyFile.path),
            "A mismatched legacy main file must be rejected and cleaned up"
        )

        try Data("not-json".utf8).write(to: legacyFile, options: .atomic)
        XCTAssertFalse(server.hasPersistedMainResponse(pageId: pageId, url: parseURL.absoluteString))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyFile.path),
            "An undecodable legacy main file must be rejected and cleaned up"
        )
    }

    @MainActor
    func testExplicitDurableUpstreamBypassesWarmCacheAndPersistsFreshBytes() async throws {
        osrsOriginTransportStub.reset()
        let originURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/Warm.png"))
        let warmedCache = URLCache(memoryCapacity: 1_024_000, diskCapacity: 0)
        let ordinaryRequest = URLRequest(url: originURL)
        let staleResponse = try XCTUnwrap(HTTPURLResponse(
            url: originURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        warmedCache.storeCachedResponse(
            CachedURLResponse(response: staleResponse, data: Data("stale".utf8)),
            for: ordinaryRequest
        )
        XCTAssertNotNil(warmedCache.cachedResponse(for: ordinaryRequest))

        let upstreamConfiguration = URLSessionConfiguration.default
        upstreamConfiguration.urlCache = warmedCache
        upstreamConfiguration.requestCachePolicy = .useProtocolCachePolicy
        upstreamConfiguration.protocolClasses = [osrsOriginTransportStub.self]
        let upstreamSession = URLSession(configuration: upstreamConfiguration)
        let directory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(
            port: 0,
            cacheDirectory: directory,
            durableRefreshSession: upstreamSession
        )
        let port = try await server.startAsync()
        defer { server.stop() }
        let pageId = "explicit-warm-upstream"
        let generation = "explicit-warm-generation"
        _ = server.enableSaveMode(
            pageId: pageId,
            saveGeneration: generation,
            refreshFromNetwork: true
        )
        let proxyURL = try XCTUnwrap(URL(
            string: "http://127.0.0.1:\(port)/https/oldschool.runescape.wiki/images/Warm.png"
        ))
        let clientConfiguration = URLSessionConfiguration.ephemeral
        clientConfiguration.protocolClasses = []
        let (data, _) = try await URLSession(configuration: clientConfiguration).data(from: proxyURL)

        XCTAssertEqual(osrsOriginTransportStub.requestCount, 1)
        XCTAssertEqual(data.suffix(5), Data("FRESH".utf8))
        XCTAssertEqual(
            osrsOriginTransportStub.lastRequest?.cachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
        XCTAssertEqual(
            osrsOriginTransportStub.lastRequest?.value(forHTTPHeaderField: "Cache-Control"),
            "no-store, no-cache"
        )
        XCTAssertTrue(server.hasPersistedResponse(
            pageId: pageId,
            url: originURL.absoluteString,
            saveGeneration: generation
        ))
    }

    @MainActor
    func testCacheFirstOriginMissIgnoresStaleReachabilityButCacheOnlyDoesNot() async throws {
        osrsOriginTransportStub.reset()
        let upstreamConfiguration = URLSessionConfiguration.ephemeral
        upstreamConfiguration.protocolClasses = [osrsOriginTransportStub.self]
        let upstreamSession = URLSession(configuration: upstreamConfiguration)
        let server = LocalHTTPServer(
            port: 0,
            cacheDirectory: try makeTemporaryCacheDirectory(),
            originSession: upstreamSession
        )
        let port = try await server.startAsync()
        defer {
            NetworkManager.shared.isConnected = true
            server.stop()
        }
        NetworkManager.shared.isConnected = false
        let originURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/Reachable.png"))
        let proxyURL = try XCTUnwrap(URL(
            string: "http://127.0.0.1:\(port)/https/oldschool.runescape.wiki/images/Reachable.png"
        ))
        let clientConfiguration = URLSessionConfiguration.ephemeral
        clientConfiguration.urlCache = nil
        clientConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let client = URLSession(configuration: clientConfiguration)

        let cacheFirstOwner = server.setPageIdContext(
            pageId: "stale-path-cache-first",
            allowsOriginOnMiss: true
        )
        let (data, _) = try await client.data(from: proxyURL)
        XCTAssertEqual(data.suffix(5), Data("FRESH".utf8))
        XCTAssertEqual(osrsOriginTransportStub.requestCount, 1)
        server.disableMode(owner: cacheFirstOwner)

        let cacheOnlyOwner = server.setPageIdContext(
            pageId: "forced-offline-cache-only",
            allowsOriginOnMiss: false
        )
        let (_, cacheOnlyResponse) = try await client.data(from: proxyURL)
        XCTAssertEqual((cacheOnlyResponse as? HTTPURLResponse)?.statusCode, 503)
        XCTAssertEqual(osrsOriginTransportStub.requestCount, 1)
        server.disableMode(owner: cacheOnlyOwner)
    }

    func testPageScopedDeletionPreservesOtherSavedAndBrowsingNamespaces() throws {
        let cacheDirectory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: cacheDirectory)
        let url = "https://oldschool.runescape.wiki/images/shared.png"
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: url)),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        for pageId in ["saved-a", "saved-b", "page__w_browsing"] {
            server.cacheResponseDirect(
                pageId: pageId,
                url: url,
                data: Data(pageId.utf8),
                response: response
            )
        }

        let deletion = expectation(description: "page-scoped deletion")
        server.removeCachedResponses(pageId: "saved-a") { deletion.fulfill() }
        wait(for: [deletion], timeout: 2)

        XCTAssertFalse(server.hasPersistedResponse(pageId: "saved-a", url: url))
        XCTAssertTrue(server.hasPersistedResponse(pageId: "saved-b", url: url))
        XCTAssertTrue(server.hasPersistedResponse(pageId: "page__w_browsing", url: url))
    }

    func testAtomicRetryWriteFailurePreservesPreviouslyValidOfflineResource() throws {
        let cacheDirectory = try makeTemporaryCacheDirectory()
        var writeCount = 0
        let server = LocalHTTPServer(
            port: 0,
            cacheDirectory: cacheDirectory,
            diskWriter: { data, url in
                writeCount += 1
                if writeCount == 2 {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: url, options: .atomic)
            }
        )
        let pageId = "retry-same-id"
        let urlString = "https://oldschool.runescape.wiki/images/retry.png"
        let url = try XCTUnwrap(URL(string: urlString))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(pageId: pageId, url: urlString, data: Data("old-valid".utf8), response: response))
        XCTAssertFalse(server.cacheResponseDirect(pageId: pageId, url: urlString, data: Data("new-truncated".utf8), response: response))
        XCTAssertEqual(
            server.getCachedResponseForAsset(url: urlString, pageId: pageId)?.data,
            Data("old-valid".utf8),
            "A failed atomic replacement must not publish the uncommitted bytes to memory"
        )

        let relaunched = LocalHTTPServer(port: 0, cacheDirectory: cacheDirectory)
        let durable = relaunched.getCachedResponseForAsset(url: urlString, pageId: pageId)
        XCTAssertEqual(durable?.data, Data("old-valid".utf8))
    }

    func testDynamicServerStartPublishesBoundPort() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())

        let boundPort = try server.start()
        defer { server.stop() }

        XCTAssertNotEqual(boundPort, 0)
        XCTAssertEqual(server.listeningPort, boundPort)
    }

    @MainActor
    func testDelayedAsyncServerStartDoesNotBlockMainActorHeartbeat() async throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let startedAt = Date()
        let startup = Task { @MainActor in
            try await server.startAsync(startupDelayForTesting: 0.20)
        }
        defer {
            startup.cancel()
            server.stop()
        }

        // If startup parked MainActor on the legacy semaphore, this continuation could not run
        // until the listener became ready (or the two-second timeout elapsed).
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertNil(server.listeningPort)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.15)

        let boundPort = try await startup.value
        XCTAssertNotEqual(boundPort, 0)
        XCTAssertEqual(server.listeningPort, boundPort)
    }

    @MainActor
    func testConnectedSavedPageUsesCachedBytesBeforeUnreachableOrigin() async throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let boundPort = try server.start()
        defer {
            NetworkManager.shared.configureProxyRouting(enabled: false)
            server.stop()
        }
        let pageId = "saved-online-fallback"
        let originURL = try XCTUnwrap(URL(string: "https://unreachable.invalid/assets/saved.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: originURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        server.cacheResponseDirect(
            pageId: pageId,
            url: originURL.absoluteString,
            data: Data("durable-saved-bytes".utf8),
            response: response
        )
        _ = server.setPageIdContext(pageId: pageId)
        NetworkManager.shared.isConnected = true
        NetworkManager.shared.configureProxyRouting(
            enabled: true,
            port: Int(boundPort),
            allowsDirectFallback: true
        )

        let (data, _) = try await NetworkManager.shared.performDataRequest(
            url: originURL,
            retryCount: 0
        )
        XCTAssertEqual(data, Data("durable-saved-bytes".utf8))
    }

    func testCacheSessionTokenPreventsStaleTeardownFromChangingActivePage() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())

        let firstToken = server.enableSaveMode(pageId: "article-a")
        let secondToken = server.enableSaveMode(pageId: "article-b")

        server.disableMode(owner: firstToken)
        XCTAssertEqual(server.activeCachePageIdForTesting, "article-b")

        server.disableMode(owner: secondToken)
        XCTAssertNil(server.activeCachePageIdForTesting)
    }

    func testSpeculativeNoStoreHeaderCannotWriteUnderVisibleArticleOwner() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let articleAToken = server.enableSaveMode(pageId: "article-a")
        defer { server.disableMode(owner: articleAToken) }

        XCTAssertEqual(server.activeCachePageIdForTesting, "article-a")
        let requestForbidsStorage = LocalHTTPServer.requestForbidsOfflineStorage(headerLines: [
            "Host: 127.0.0.1",
            "X-OSRS-No-Offline-Store: 1"
        ])
        XCTAssertTrue(requestForbidsStorage)
        XCTAssertFalse(LocalHTTPServer.shouldPersistResponse(
            saveModeActive: true,
            requestForbidsStorage: requestForbidsStorage
        ), "Prewarm B must not persist a response or resource under active owner A")
        XCTAssertFalse(LocalHTTPServer.requestForbidsOfflineStorage(headerLines: [
            "Host: 127.0.0.1"
        ]))
        XCTAssertEqual(
            server.activeCachePageIdForTesting,
            "article-a",
            "Evaluating a no-store prewarm request must neither retarget nor tear down article A"
        )
    }

    func testSplitHTTPRequestHeaderIsBufferedAndParsedExactlyOnce() throws {
        var accumulator = osrsHTTPRequestHeaderAccumulator()
        XCTAssertEqual(
            accumulator.append(Data("GET /https/example.test/a HTTP/1.1\r\nX-OSRS-No-Off".utf8)),
            .awaitingMore
        )
        let result = accumulator.append(Data("line-Store: 1\r\nHost: 127.0.0.1\r\n\r\n".utf8))
        guard case .complete(let headerData) = result else {
            return XCTFail("The full split header should complete only after CRLFCRLF")
        }
        let header = try XCTUnwrap(String(data: headerData, encoding: .utf8))
        XCTAssertTrue(LocalHTTPServer.requestForbidsOfflineStorage(
            headerLines: header.components(separatedBy: "\r\n").dropFirst()
        ))
        XCTAssertEqual(accumulator.append(Data("ignored".utf8)), .alreadyComplete)

        var oversized = osrsHTTPRequestHeaderAccumulator()
        XCTAssertEqual(
            oversized.append(Data(repeating: 65, count: osrsHTTPRequestHeaderAccumulator.maximumHeaderBytes + 1)),
            .tooLarge
        )
    }

    func testExplicitSaveGenerationCannotBeSatisfiedByOlderSameKeyBytes() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let urlString = "https://oldschool.runescape.wiki/images/generation.png"
        let url = try XCTUnwrap(URL(string: urlString))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: "saved-generation",
            url: urlString,
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]),
            response: response,
            saveGeneration: "generation-1"
        ))
        XCTAssertTrue(server.hasPersistedResponse(
            pageId: "saved-generation",
            url: urlString,
            saveGeneration: "generation-1"
        ))
        XCTAssertFalse(server.hasPersistedResponse(
            pageId: "saved-generation",
            url: urlString,
            saveGeneration: "generation-2"
        ))
    }

    func testGenerationStagedRefreshFailurePreservesOldSnapshotAndSuccessPublishesWholeNewPath() async throws {
        let directory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let recordID = "saved-atomic-refresh"
        let oldPageId = "saved-atomic-refresh-old"
        let parseURL = try XCTUnwrap(ArticleViewModel.makeParseRequestURL(pageTitle: "Atomic refresh"))
        let firstImageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/atomic-a.png"))
        let secondImageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/atomic-b.png"))
        let parseResponse = try XCTUnwrap(HTTPURLResponse(
            url: parseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        let imageResponse = try XCTUnwrap(HTTPURLResponse(
            url: firstImageURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        let oldMain = Data(#"{"parse":{"text":{"*":"<p>old</p>"}}}"#.utf8)
        let oldImage = Data("old-image".utf8)
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: oldPageId,
            url: parseURL.absoluteString,
            data: oldMain,
            response: parseResponse
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: oldPageId,
            url: firstImageURL.absoluteString,
            data: oldImage,
            response: imageResponse
        ))

        let failedGeneration = "failed-generation"
        let failedStage = ArticleViewModel.offlineSaveStagingPageID(
            recordID: recordID,
            saveGeneration: failedGeneration
        )
        let newMain = Data(#"{"parse":{"text":{"*":"<img src=atomic-a.png><img src=atomic-b.png>"}}}"#.utf8)
        let pngA = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: failedStage,
            url: parseURL.absoluteString,
            data: newMain,
            response: parseResponse,
            saveGeneration: failedGeneration
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: failedStage,
            url: firstImageURL.absoluteString,
            data: pngA,
            response: imageResponse,
            saveGeneration: failedGeneration
        ))
        XCTAssertFalse(server.hasPersistedResponses(
            pageId: failedStage,
            urls: [parseURL.absoluteString, firstImageURL.absoluteString, secondImageURL.absoluteString],
            saveGeneration: failedGeneration
        ))

        await server.removeCachedResponsesAsync(pageId: failedStage)
        XCTAssertEqual(
            persistedResponse(
                in: directory,
                pageId: oldPageId,
                url: parseURL.absoluteString
            )?.data,
            oldMain
        )
        XCTAssertEqual(
            server.getCachedResponseForAsset(url: firstImageURL.absoluteString, pageId: oldPageId)?.data,
            oldImage,
            "A failed refresh must leave every published byte unchanged"
        )

        let successfulGeneration = "successful-generation"
        let successfulStage = ArticleViewModel.offlineSaveStagingPageID(
            recordID: recordID,
            saveGeneration: successfulGeneration
        )
        let secondImageResponse = try XCTUnwrap(HTTPURLResponse(
            url: secondImageURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        let pngB = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x02])
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: successfulStage,
            url: parseURL.absoluteString,
            data: newMain,
            response: parseResponse,
            saveGeneration: successfulGeneration
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: successfulStage,
            url: firstImageURL.absoluteString,
            data: pngA,
            response: imageResponse,
            saveGeneration: successfulGeneration
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: successfulStage,
            url: secondImageURL.absoluteString,
            data: pngB,
            response: secondImageResponse,
            saveGeneration: successfulGeneration
        ))
        XCTAssertTrue(server.hasPersistedResponses(
            pageId: successfulStage,
            urls: [parseURL.absoluteString, firstImageURL.absoluteString, secondImageURL.absoluteString],
            saveGeneration: successfulGeneration
        ))

        let retryable = SavedPage(
            id: recordID,
            title: "Atomic refresh",
            description: nil,
            url: URL(string: "https://oldschool.runescape.wiki/w/Atomic_refresh")!,
            thumbnailUrl: nil,
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: false,
            offlineDownloadDate: Date(timeIntervalSince1970: 1_735_732_900),
            offlineStatus: .outdated,
            offlineFileSize: 128,
            offlineLocalPath: oldPageId
        )
        let publishedByteCount = try XCTUnwrap(server.persistedByteCount(
            pageId: successfulStage,
            urls: [parseURL.absoluteString, firstImageURL.absoluteString, secondImageURL.absoluteString],
            saveGeneration: successfulGeneration
        ))
        let published = retryable.markingCurrentDurableSettlementAvailable(
            at: Date(timeIntervalSince1970: 1_735_733_000),
            offlineLocalPath: successfulStage,
            offlineFileSize: publishedByteCount
        )
        XCTAssertEqual(published.id, recordID)
        XCTAssertEqual(published.offlineCachePageId, successfulStage)
        XCTAssertTrue(published.hasCurrentDurableSettlement)
        XCTAssertEqual(published.offlineFileSize, publishedByteCount)
        XCTAssertEqual(
            persistedResponse(
                in: directory,
                pageId: published.offlineCachePageId,
                url: parseURL.absoluteString
            )?.data,
            newMain
        )
        XCTAssertEqual(
            server.getCachedResponseForAsset(url: secondImageURL.absoluteString, pageId: published.offlineCachePageId)?.data,
            pngB
        )
        XCTAssertEqual(
            persistedResponse(
                in: directory,
                pageId: oldPageId,
                url: parseURL.absoluteString
            )?.data,
            oldMain,
            "The old namespace may be removed only after the record publishes the complete new path"
        )
    }

    func testDeleteDuringGenerationStagingCannotRepublishRecordAndStageIsDisposable() async throws {
        let directory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let suiteName = "LocalHTTPResponseCacheTests-delete-race-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let repository = SavedPagesRepository(userDefaults: defaults)
        let recordID = "delete-race-record"
        let generation = "delete-race-generation"
        let stagePageId = ArticleViewModel.offlineSaveStagingPageID(
            recordID: recordID,
            saveGeneration: generation
        )
        let resourceURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/delete-race.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: resourceURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x03])
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: stagePageId,
            url: resourceURL.absoluteString,
            data: png,
            response: response,
            saveGeneration: generation
        ))

        let inFlight = SavedPage(
            id: recordID,
            title: "Delete race",
            description: nil,
            url: URL(string: "https://oldschool.runescape.wiki/w/Delete_race")!,
            thumbnailUrl: nil,
            savedDate: Date(),
            isOfflineAvailable: false,
            offlineDownloadDate: nil,
            offlineStatus: .downloading,
            offlineFileSize: nil,
            offlineLocalPath: "old-delete-race",
            pendingSettlementGeneration: generation
        )
        repository.addSavedPage(inFlight)
        repository.removeSavedPage(recordID)

        let candidate = inFlight.markingCurrentDurableSettlementAvailable(
            at: Date(),
            offlineLocalPath: stagePageId
        )
        XCTAssertFalse(repository.compareAndSwapOfflineSettlement(
            candidate,
            expectedGeneration: generation,
            expectedPriorCachePageId: inFlight.offlineLocalPath
        ))
        XCTAssertTrue(repository.getSavedPages().isEmpty, "A deleted record must not be resurrected")

        await server.removeCachedResponsesAsync(pageId: stagePageId)
        XCTAssertFalse(server.hasPersistedResponse(
            pageId: stagePageId,
            url: resourceURL.absoluteString,
            saveGeneration: generation
        ))
    }

    func testExplicitGIFHTMLResponseIsNotPersistedOrSettledWhileSVGXMLRemainsValid() async throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let pageId = "saved-response-validation"
        let generation = "validation-generation"
        let gifURL = try XCTUnwrap(URL(
            string: "https://oldschool.runescape.wiki/images/Captive.GIF?revision=2"
        ))
        let htmlResponse = try XCTUnwrap(HTTPURLResponse(
            url: gifURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "Text/HTML; charset=UTF-8"]
        ))
        let captiveHTML = Data("<!DOCTYPE HTML><html><body>Sign in</body></html>".utf8)

        XCTAssertFalse(server.cacheResponseDirect(
            pageId: pageId,
            url: gifURL.absoluteString,
            data: captiveHTML,
            response: htmlResponse,
            saveGeneration: generation
        ))
        XCTAssertFalse(server.hasPersistedResponse(
            pageId: pageId,
            url: gifURL.absoluteString,
            saveGeneration: generation
        ))

        do {
            _ = try await osrsOfflineArticleResourceSettlement.settle(
                html: #"<img src="/images/Captive.GIF?revision=2">"#
            ) { url in
                guard server.cacheResponseDirect(
                    pageId: pageId,
                    url: url.absoluteString,
                    data: captiveHTML,
                    response: htmlResponse,
                    saveGeneration: generation
                ), server.hasPersistedResponse(
                    pageId: pageId,
                    url: url.absoluteString,
                    saveGeneration: generation
                ) else {
                    throw osrsOfflineResourceSettlementError.requiredResourcesFailed(count: 1)
                }
                return captiveHTML
            }
            XCTFail("HTML returned for explicit GIF artwork must not settle the offline save")
        } catch let error as osrsOfflineResourceSettlementError {
            XCTAssertEqual(error, .requiredResourcesFailed(count: 1))
        }

        let svgURL = try XCTUnwrap(URL(
            string: "https://oldschool.runescape.wiki/images/legitimate.SVG?revision=3"
        ))
        let svgResponse = try XCTUnwrap(HTTPURLResponse(
            url: svgURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/svg+xml"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: svgURL.absoluteString,
            data: Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>"#.utf8),
            response: svgResponse,
            saveGeneration: generation
        ))
        XCTAssertTrue(server.hasPersistedResponse(
            pageId: pageId,
            url: svgURL.absoluteString,
            saveGeneration: generation
        ))
    }

    func testExplicitGIFRejectsEmptyAndTextGarbageButAcceptsValidMagic() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())
        let pageId = "saved-gif-validation"
        let generation = "gif-generation"
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/animation.GIF?rev=4"))

        let gifResponse = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/gif"]
        ))
        XCTAssertFalse(server.cacheResponseDirect(
            pageId: pageId,
            url: url.absoluteString,
            data: Data(),
            response: gifResponse,
            saveGeneration: generation
        ))

        let textResponse = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        ))
        XCTAssertFalse(server.cacheResponseDirect(
            pageId: pageId,
            url: url.absoluteString,
            data: Data("upstream unavailable".utf8),
            response: textResponse,
            saveGeneration: generation
        ))
        XCTAssertFalse(server.hasPersistedResponse(
            pageId: pageId,
            url: url.absoluteString,
            saveGeneration: generation
        ))

        XCTAssertTrue(server.cacheResponseDirect(
            pageId: pageId,
            url: url.absoluteString,
            data: Data("GIF89a".utf8) + Data(repeating: 0, count: 8),
            response: gifResponse,
            saveGeneration: generation
        ))
    }

    func testOwnerSwitchRejectsCapturedResponseInsteadOfStampingNewOwner() throws {
        let articleAOwner = LocalHTTPServerCacheSessionToken()
        let articleBOwner = LocalHTTPServerCacheSessionToken()

        XCTAssertTrue(LocalHTTPServer.shouldPersistCapturedResponse(
            capturedPageId: "article-a",
            capturedOwnerToken: articleAOwner,
            currentPageId: "article-a",
            currentOwnerToken: articleAOwner,
            saveModeActive: true
        ))
        XCTAssertFalse(LocalHTTPServer.shouldPersistCapturedResponse(
            capturedPageId: "article-a",
            capturedOwnerToken: articleAOwner,
            currentPageId: "article-b",
            currentOwnerToken: articleBOwner,
            saveModeActive: true
        ))
    }

    func testCancelledConnectionCancelsAndRemovesTrackedUpstreamRequest() {
        let registry = osrsCancellableRequestRegistry<String>()
        let request = FakeCancellableRequest()
        registry.insert(request, for: "connection")
        XCTAssertEqual(registry.count, 1)

        registry.cancel("connection")

        XCTAssertEqual(registry.count, 0)
        XCTAssertEqual(request.cancellationCount, 1)
        XCTAssertFalse(registry.finish("connection"), "A cancelled request completion must be ignored")
    }

    func testConnectionLifecycleRegistryDoesNotGrowAfterCompletion() {
        let registry = osrsObjectLifecycleRegistry<NSObject>()
        let first = NSObject()
        let second = NSObject()
        registry.insert(first)
        registry.insert(second)
        XCTAssertEqual(registry.count, 2)

        registry.remove(first)
        registry.remove(second)

        XCTAssertEqual(registry.count, 0)
    }

    func testConcurrentAccessKeepsResponsesReadable() throws {
        let cache = LocalHTTPResponseCache()
        let response = CachedHTTPResponse(
            url: "https://oldschool.runescape.wiki/w/Varrock",
            data: Data("ok".utf8),
            timestamp: Date(),
            pageId: "page",
            statusCode: 200,
            headers: ["Content-Type": "text/plain"]
        )

        let queue = DispatchQueue(label: "LocalHTTPResponseCacheTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let workerCount = 16
        let iterations = 500

        for worker in 0..<workerCount {
            group.enter()
            queue.async {
                for index in 0..<iterations {
                    let pageId = "page-\(index % 4)"
                    let key = "\(pageId)_GET_\(worker)-\(index)"
                    cache.set(response, forKey: key)
                    _ = cache.response(forKey: key)
                    _ = cache.keys(withPrefix: "\(pageId)_")
                    _ = cache.entries(withPrefix: "\(pageId)_")

                    if index % 11 == 0 {
                        cache.removeValue(forKey: key)
                    }
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        cache.set(response, forKey: "page-final_GET_final")
        XCTAssertEqual(cache.response(forKey: "page-final_GET_final")?.statusCode, 200)
        XCTAssertEqual(cache.keys(withPrefix: "page-final_"), ["page-final_GET_final"])
    }

    func testMemoryCacheEvictsByByteCostAndDiskReadsStayBounded() throws {
        let cache = LocalHTTPResponseCache(maximumByteCost: 1_200)
        for index in 0..<20 {
            cache.set(CachedHTTPResponse(
                url: "https://example.test/image-\(index).png",
                data: Data(repeating: UInt8(index), count: 400),
                timestamp: Date(),
                pageId: "browsing-memory",
                statusCode: 200,
                headers: [:]
            ), forKey: "browsing-memory_GET_\(index)")
        }
        XCTAssertLessThanOrEqual(cache.byteCost, 1_200)
        XCTAssertLessThan(cache.entries().count, 20)

        let directory = try makeTemporaryCacheDirectory()
        let writer = LocalHTTPServer(port: 0, cacheDirectory: directory)
        for index in 0..<80 {
            let url = try XCTUnwrap(URL(string: "https://example.test/disk-\(index).png"))
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            ))
            XCTAssertTrue(writer.cacheResponseDirect(
                pageId: "browsing-disk",
                url: url.absoluteString,
                data: Data(repeating: UInt8(index), count: 512 * 1024),
                response: response
            ))
        }
        let reader = LocalHTTPServer(port: 0, cacheDirectory: directory)
        for index in 0..<80 {
            let url = "https://example.test/disk-\(index).png"
            XCTAssertNotNil(reader.getCachedResponseForAsset(url: url, pageId: "browsing-disk"))
        }
        XCTAssertLessThanOrEqual(reader.memoryCacheByteCostForTesting, 24 * 1024 * 1024)
        XCTAssertLessThan(reader.memoryCacheEntryCountForTesting, 80)
    }

    func testPassiveCleanupRemovesBrowsingNamespaceButPreservesSavedNamespace() throws {
        let directory = try makeTemporaryCacheDirectory()
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://example.test/art.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: "browsing_deadbeef",
            url: url.absoluteString,
            data: Data("passive".utf8),
            response: response
        ))
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: "saved-owned-id",
            url: url.absoluteString,
            data: Data("saved".utf8),
            response: response
        ))

        server.cleanupPassiveResponses(maximumAge: .infinity, maximumTotalBytes: 0)

        XCTAssertFalse(server.hasPersistedResponse(pageId: "browsing_deadbeef", url: url.absoluteString))
        XCTAssertTrue(server.hasPersistedResponse(pageId: "saved-owned-id", url: url.absoluteString))
        let browsingKey = LocalHTTPServer.cacheKeyForRequest(
            pageId: "browsing_deadbeef",
            method: "GET",
            url: url.absoluteString
        )
        let savedKey = LocalHTTPServer.cacheKeyForRequest(
            pageId: "saved-owned-id",
            method: "GET",
            url: url.absoluteString
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(browsingKey).meta").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(savedKey).meta").path
        ))
    }

    func testStartupMaintenanceReturnsPromptlyWithManyLargeFiles() throws {
        let directory = try makeTemporaryCacheDirectory()
        let writer = LocalHTTPServer(port: 0, cacheDirectory: directory)
        for index in 0..<12 {
            let url = try XCTUnwrap(URL(string: "https://example.test/startup-\(index).png"))
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            ))
            XCTAssertTrue(writer.cacheResponseDirect(
                pageId: "browsing_startup",
                url: url.absoluteString,
                data: Data(repeating: UInt8(index), count: 1024 * 1024),
                response: response
            ))
        }

        let maintenance = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let finished = expectation(description: "background maintenance")
        let start = CFAbsoluteTimeGetCurrent()
        maintenance.performStartupMaintenanceAsync { finished.fulfill() }
        XCTAssertLessThan(
            CFAbsoluteTimeGetCurrent() - start,
            0.05,
            "Scheduling startup maintenance must not synchronously decode media files"
        )
        wait(for: [finished], timeout: 5)
    }

    private func makeTemporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalHTTPResponseCacheTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func validParsePayload(title: String) -> Data {
        Data("""
        {"parse":{"pageid":1,"title":"\(title)","displaytitle":"\(title)","revid":1,"text":{"*":"<p>text</p>"}}}
        """.utf8)
    }

    private func persistedResponse(
        in directory: URL,
        pageId: String,
        url: String
    ) -> CachedHTTPResponse? {
        let key = LocalHTTPServer.cacheKeyForRequest(pageId: pageId, method: "GET", url: url)
        let file = directory.appendingPathComponent("\(key).cache")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CachedHTTPResponse.self, from: data)
    }
}

private final class FakeCancellableRequest: osrsCancellableRequest {
    private(set) var cancellationCount = 0

    func cancel() {
        cancellationCount += 1
    }
}

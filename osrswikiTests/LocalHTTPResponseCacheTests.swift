//
//  LocalHTTPResponseCacheTests.swift
//  osrswikiTests
//

import XCTest
@testable import osrswiki

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

    func testDynamicServerStartPublishesBoundPort() throws {
        let server = LocalHTTPServer(port: 0, cacheDirectory: try makeTemporaryCacheDirectory())

        let boundPort = try server.start()
        defer { server.stop() }

        XCTAssertNotEqual(boundPort, 0)
        XCTAssertEqual(server.listeningPort, boundPort)
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
}

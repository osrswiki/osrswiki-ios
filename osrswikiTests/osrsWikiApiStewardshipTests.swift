import XCTest
@testable import osrswiki

final class osrsWikiApiStewardshipTests: XCTestCase {
    func testUserAgentIdentifiesAppPlatformContactAndSource() {
        let ua = osrsWikiApiStewardship.userAgent(version: "2.1.3", component: "url-session")
        XCTAssertTrue(ua.hasPrefix("OSRSWikiApp/2.1.3"))
        XCTAssertTrue(ua.contains("iOS"))
        XCTAssertTrue(ua.contains("url-session"))
        XCTAssertTrue(ua.contains(osrsWikiApiStewardship.contactEmail))
        XCTAssertTrue(ua.contains(osrsWikiApiStewardship.iosSource))
        XCTAssertEqual(osrsWikiApiStewardship.iosSource, "https://github.com/osrswiki/osrswiki-ios")
        XCTAssertFalse(ua.contains("Mozilla/5.0"))
        XCTAssertFalse(ua.contains("github.com/omiyawaki/"))
    }

    func testRetryAfterParsesDeltaSecondsAndHttpDate() {
        XCTAssertEqual(osrsWikiApiStewardship.retryAfterInterval(header: "2"), 2)
        XCTAssertEqual(osrsWikiApiStewardship.retryAfterInterval(header: "120"), 30)
        XCTAssertNil(osrsWikiApiStewardship.retryAfterInterval(header: ""))
        XCTAssertNil(osrsWikiApiStewardship.retryAfterInterval(header: "nope"))

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let header = "Wed, 15 Nov 2023 06:13:30 GMT"
        let interval = osrsWikiApiStewardship.retryAfterInterval(header: header, now: now)
        XCTAssertNotNil(interval)
        XCTAssertGreaterThanOrEqual(interval ?? -1, 0)
        XCTAssertLessThanOrEqual(interval ?? 31, osrsWikiApiStewardship.maxRetryAfter)
    }

    func testOnlyTooManyRequestsAndUnavailableAreRetried() {
        XCTAssertTrue(osrsWikiApiStewardship.shouldRetry(statusCode: 429))
        XCTAssertTrue(osrsWikiApiStewardship.shouldRetry(statusCode: 503))
        XCTAssertFalse(osrsWikiApiStewardship.shouldRetry(statusCode: 500))
        XCTAssertFalse(osrsWikiApiStewardship.shouldRetry(statusCode: 404))
    }

    func testWikiClientsUseIdentifiedUserAgentAndRetryAfter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("osrswiki")
        let network = try String(
            contentsOf: root.appendingPathComponent("Utils/NetworkManager.swift"),
            encoding: .utf8
        )
        let random = try String(
            contentsOf: root.appendingPathComponent("Repositories/osrsRandomPageRepository.swift"),
            encoding: .utf8
        )
        let local = try String(
            contentsOf: root.appendingPathComponent("Services/LocalHTTPServer.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(network.contains("osrsWikiApiStewardship.appUserAgent"))
        XCTAssertTrue(network.contains("retryAfterInterval(from:"))
        XCTAssertTrue(random.contains("osrsWikiApiStewardship.appUserAgent(\"random\")"))
        XCTAssertFalse(random.contains("Mozilla/5.0"))
        XCTAssertTrue(local.contains("osrsWikiApiStewardship.appUserAgent(\"local-http\")"))
        XCTAssertFalse(local.contains("osrswiki-ios/1.0"))
    }

    func testContactUsesBotInboxAndMediaWikiErrorsAreRetried() {
        XCTAssertEqual(osrsWikiApiStewardship.contactEmail, "osamu+osrswiki@mail.grokbot.com")
        XCTAssertFalse(osrsWikiApiStewardship.userAgent(version: "1.0").contains("icloud.com"))
        XCTAssertEqual(
            osrsWikiApiStewardship.mediaWikiRetryableErrorCode(in: #"{"error":{"code":"maxlag"}}"#),
            "maxlag"
        )
        XCTAssertEqual(
            osrsWikiApiStewardship.mediaWikiRetryableErrorCode(in: #"{"error":{"code":"ratelimited"}}"#),
            "ratelimited"
        )
        XCTAssertNil(osrsWikiApiStewardship.mediaWikiRetryableErrorCode(in: #"{"parse":{"title":"Varrock"}}"#))
        XCTAssertTrue(
            osrsWikiApiStewardship.shouldRetry(
                statusCode: 200,
                body: Data(#"{"error":{"code":"ratelimited"}}"#.utf8)
            )
        )
    }

    func testOrdinaryRequestsDoNotBustURLCache() throws {
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Varrock"))
        let ordinary = NetworkManager.ordinaryRequestForTesting(url: url)
        XCTAssertNil(ordinary.value(forHTTPHeaderField: "Cache-Control"))
        XCTAssertNil(ordinary.value(forHTTPHeaderField: "Pragma"))
        XCTAssertNil(ordinary.value(forHTTPHeaderField: "X-Cache-Bust"))
        XCTAssertNotEqual(ordinary.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)

        let explicit = NetworkManager.explicitOfflineRequestForTesting(url: url)
        XCTAssertEqual(explicit.value(forHTTPHeaderField: "Cache-Control"), "no-store, no-cache")
        XCTAssertEqual(explicit.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertNotNil(explicit.value(forHTTPHeaderField: "X-Cache-Bust"))
    }

    func testGeChartsInitUsesPricesV2AndHonorsCacheAndRetryAfter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chart = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/ge_charts_init.js"),
            encoding: .utf8
        )
        XCTAssertTrue(chart.contains("api/v2/osrs/timeseries"))
        XCTAssertTrue(chart.contains("lookback=1y"))
        XCTAssertFalse(chart.contains("api/v1/osrs"))
        XCTAssertTrue(chart.contains("cache: 'default'"))
        XCTAssertFalse(chart.contains("cache: 'no-cache'"))
        XCTAssertTrue(chart.contains("Retry-After"))
        XCTAssertTrue(chart.contains("CHART_CACHE_TTL_MS"))
        XCTAssertFalse(chart.contains("Api-User-Agent"))
        XCTAssertTrue(chart.contains("kick(false, false)"))
        XCTAssertFalse(chart.contains("kick(true)"))
        XCTAssertFalse(chart.contains("omiyawaki@icloud.com"))
        XCTAssertFalse(chart.contains("withTimeout(raw, 4000)"))
        XCTAssertFalse(chart.contains("const network = fetchPricesApi(url)"))
        XCTAssertTrue(chart.contains("__osrsGeChartPrefetch"))
        XCTAssertTrue(chart.contains("readPrefetchedSeries"))
        // Warm-path first view: never touch localStorage before the XHR.
        XCTAssertTrue(chart.contains("const memory = readChartMemory(itemId)"))
        XCTAssertFalse(chart.contains("readCachedSeries"))
        XCTAssertTrue(chart.contains("setTimeout(() => writeChartDisk"))
        XCTAssertTrue(
            chart.contains("if (allowNetwork === false) {\n      return readChartDisk(itemId) || [];\n    }")
        )
    }

    func testGeChartCachePrefetchIsMemoryOnlyAndExtractsItemIds() throws {
        let html = """
        <div class="GEChartBox">
          <div class="GEdataprices" data-itemid="4151"></div>
        </div>
        """
        XCTAssertEqual(osrsGeChartPriceCache.itemIDs(in: html), ["4151"])
        let url = try XCTUnwrap(osrsGeChartPriceCache.timeseriesURL(itemId: "4151"))
        osrsGeChartPriceCache.write(url: url, body: #"{"data":[{"timestamp":1,"avgHighPrice":2}]}"#)
        let script = osrsGeChartPriceCache.memoryPrefetchScript(itemIDs: ["4151"])
        XCTAssertTrue(script.contains("__osrsGeChartPrefetch"))
        XCTAssertTrue(script.contains("4151"))
        XCTAssertTrue(script.contains("avgHighPrice"))
        XCTAssertEqual(osrsGeChartPriceCache.readMemory(url: url)?.contains("avgHighPrice"), true)
    }

    func testIosChartFetchTextStaysOnCheapSyncXHR() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("osrswiki")
        let bridge = try String(
            contentsOf: root.appendingPathComponent("Services/osrsWebViewBridge.swift"),
            encoding: .utf8
        )
        let builder = try String(
            contentsOf: root.appendingPathComponent("Services/osrsPageHtmlBuilder.swift"),
            encoding: .utf8
        )
        let mapBridge = try String(
            contentsOf: root.appendingPathComponent("Assets/web/map_bridge.js"),
            encoding: .utf8
        )
        for source in [bridge, builder, mapBridge] {
            XCTAssertTrue(source.contains("XMLHttpRequest"))
            XCTAssertTrue(source.contains("xhr.open('GET', url, false)"))
            // Custom Api-User-Agent on sync XHR forces a CORS preflight.
            // The WebView User-Agent already carries the identified client.
            XCTAssertFalse(source.contains("xhr.setRequestHeader('Api-User-Agent'"))
            XCTAssertFalse(source.contains("'Api-User-Agent'"))
        }
        XCTAssertTrue(bridge.contains("rememberGeChart"))
        XCTAssertTrue(bridge.contains("__osrsGeChartPrefetch"))
        XCTAssertTrue(builder.contains("memoryPrefetchScript"))
        XCTAssertTrue(bridge.contains("readMemory"))
        XCTAssertTrue(bridge.contains("withTaskGroup"))
        XCTAssertFalse(bridge.contains("?? 1"))
    }

    func testPreparedWebViewIdentifiesApplicationNameAndNewsLeavesURLCacheAlone() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("osrswiki")
        let prepared = try String(
            contentsOf: root.appendingPathComponent("Services/osrsPreparedArticleWebViewStore.swift"),
            encoding: .utf8
        )
        let news = try String(
            contentsOf: root.appendingPathComponent("Repositories/NewsRepository.swift"),
            encoding: .utf8
        )
        let revision = try String(
            contentsOf: root.appendingPathComponent("Services/osrsSavedPageRevisionProbe.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(prepared.contains("applicationNameForUserAgent"))
        XCTAssertTrue(news.contains("bypassCache: false"))
        XCTAssertFalse(news.contains("bypassCache: true"))
        XCTAssertTrue(revision.contains("maxlag"))
        XCTAssertFalse(prepared.contains("osrswiki-ios/1.0"))
    }
}

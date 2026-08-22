import XCTest
@testable import osrswiki

final class osrsSavedPaintHtmlTests: XCTestCase {
    func testDetectsFullDocumentAndExtractsBody() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Varrock</title></head>
        <body>
        <h1 class="page-header">Varrock</h1>
        <p>The history section.</p>
        </body>
        </html>
        """
        XCTAssertTrue(osrsSavedPaintHtml.isFullDocument(html))
        let body = osrsSavedPaintHtml.extractBodyForToc(html)
        XCTAssertFalse(body.contains("page-header"))
        XCTAssertTrue(body.contains("The history section."))
        XCTAssertFalse(osrsSavedPaintHtml.isFullDocument("<p>body only</p>"))
    }

    func testAppliesLivePreferencesAndInlinesStylesheets() {
        let html = """
        <html class=""><head>
        <link rel="stylesheet" href="app-assets://localhost/styles/themes.css">
        <style id="osrs-article-reader-preferences">html:root { --osrs-article-user-text-scale: 1.000; }</style>
        </head><body class="">hello</body>
        """
        let inlined = osrsSavedPaintHtml.inlineLinkedFirstPaintCss(html) { path in
            XCTAssertEqual(path, "styles/themes.css")
            return "body{color:red}"
        }
        XCTAssertTrue(inlined.contains("data-osrs-inline-css=\"styles/themes.css\""))
        XCTAssertTrue(inlined.contains("body{color:red}"))
        XCTAssertFalse(inlined.contains("app-assets://localhost/styles/themes.css"))

        let live = osrsSavedPaintHtml.applyingLivePreferences(
            inlined,
            isDark: true,
            wrapEnabled: true,
            scaleCssValue: "1.150",
            chromeClearancePx: 12,
            bottomChromePx: 24,
            safeAreaTopPx: 8,
            safeAreaBottomPx: 4
        )
        XCTAssertTrue(live.contains("theme-osrs-dark"))
        XCTAssertTrue(live.contains("<html class=\"theme-osrs-dark") || live.contains("<html class=\"theme-osrs-dark "))
        XCTAssertTrue(live.contains("osrs-table-cells-wrap"))
        XCTAssertTrue(live.contains("--osrs-article-user-text-scale: 1.150"))
        XCTAssertTrue(live.contains("osrs-article-live-chrome"))
        XCTAssertTrue(live.contains("--osrs-article-chrome-clearance: 12px"))
    }

    func testInlinesDeferredStylesheetLinksAndIgnoresStylePreloads() {
        let html = """
        <html><head>
        <link rel="preload" as="style" href="app-assets://localhost/styles/wiki-integration.css">
        <link rel="stylesheet" href="app-assets://localhost/styles/wiki-integration.css" media="print" onload="osrsActivateDeferredStylesheet(this)" data-osrs-css="deferred" data-osrs-css-href="styles/wiki-integration.css">
        <link rel="stylesheet" href="app-assets://localhost/styles/themes.css" data-osrs-css="critical">
        <link rel="preload" href="app-assets://localhost/fonts/alegreya_bold.ttf" as="font" type="font/ttf" crossorigin="anonymous">
        </head><body></body></html>
        """
        var loaded: [String] = []
        let inlined = osrsSavedPaintHtml.inlineLinkedFirstPaintCss(html) { path in
            loaded.append(path)
            return path == "styles/wiki-integration.css" ? "table.infobox{color:red}" : "body{background:#e2dbc8}"
        }
        XCTAssertEqual(Set(loaded), Set(["styles/wiki-integration.css", "styles/themes.css"]))
        XCTAssertTrue(inlined.contains("data-osrs-inline-css=\"styles/wiki-integration.css\""))
        XCTAssertTrue(inlined.contains("table.infobox{color:red}"))
        XCTAssertTrue(inlined.contains("data-osrs-inline-css=\"styles/themes.css\""))
        XCTAssertTrue(inlined.contains("body{background:#e2dbc8}"))
        XCTAssertFalse(inlined.contains("rel=\"stylesheet\""))
        XCTAssertFalse(inlined.contains("as=\"style\""))
        XCTAssertTrue(inlined.contains("as=\"font\""))
        XCTAssertTrue(inlined.contains("alegreya_bold.ttf"))
    }

    func testLiveHtmlKeepsCriticalThemeCssBlockingAndDefersWikiIntegration() {
        let html = osrsPageHtmlBuilder().buildFullHtmlDocument(
            title: "Varrock",
            bodyContent: "<table class=\"infobox\"><tr><td>Capital</td></tr></table>",
            theme: osrsLightTheme(),
            includeAssetLinks: true,
            bakeChromeInsets: false
        )
        assertCriticalStylesheet(html, asset: "styles/themes.css")
        assertCriticalStylesheet(html, asset: "web/collapsible_tables.css")
        assertCriticalStylesheet(html, asset: "web/switch_infobox_styles.css")
        assertDeferredStylesheet(html, asset: "styles/wiki-integration.css")
        assertDeferredStylesheet(html, asset: "styles/fixes.css")
        assertDeferredStylesheet(html, asset: "styles/ios-article-aesthetics.css")
        XCTAssertTrue(html.contains("id=\"osrs-article-first-paint\""))
        XCTAssertTrue(html.contains("background-color: #e2dbc8"))
        XCTAssertTrue(html.contains("background-color: #28221d"))
        XCTAssertTrue(html.contains("osrsActivateDeferredStylesheet"))
        XCTAssertTrue(html.contains("Event: ParseReady"))
        XCTAssertTrue(html.contains("Event: FirstPaint"))
        let fixesIndex = html.range(of: "styles/fixes.css")
        let aestheticsIndex = html.range(of: "styles/ios-article-aesthetics.css")
        XCTAssertNotNil(fixesIndex)
        XCTAssertNotNil(aestheticsIndex)
        XCTAssertTrue(fixesIndex!.lowerBound < aestheticsIndex!.lowerBound)
    }

    private func assertCriticalStylesheet(_ html: String, asset: String) {
        let stylesheet = stylesheetLinks(in: html, asset: asset)
        XCTAssertTrue(
            stylesheet.contains(where: { $0.contains("rel=\"stylesheet\"") && $0.contains("data-osrs-css=\"critical\"") }),
            "expected blocking \(asset) in \(stylesheet)"
        )
        XCTAssertFalse(
            stylesheet.contains(where: { $0.contains("media=\"print\"") }),
            "critical \(asset) must not use media=print"
        )
    }

    private func assertDeferredStylesheet(_ html: String, asset: String) {
        let stylesheet = stylesheetLinks(in: html, asset: asset)
        XCTAssertTrue(
            stylesheet.contains(where: { $0.contains("rel=\"preload\"") && $0.contains("as=\"style\"") }),
            "expected preload for \(asset) in \(stylesheet)"
        )
        XCTAssertTrue(
            stylesheet.contains(where: {
                $0.contains("rel=\"stylesheet\"") &&
                $0.contains("media=\"print\"") &&
                $0.contains("data-osrs-css=\"deferred\"")
            }),
            "expected deferred stylesheet for \(asset) in \(stylesheet)"
        )
        XCTAssertFalse(
            stylesheet.contains(where: { $0.contains("rel=\"stylesheet\"") && !$0.contains("media=\"print\"") }),
            "deferred \(asset) must not be a blocking stylesheet"
        )
    }

    private func stylesheetLinks(in html: String, asset: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else { return nil }
            let tag = String(html[matchRange])
            return tag.contains(asset) ? tag : nil
        }
    }

    func testFirstPaintStyleIncludesBodyColorAndBackgroundFallbacks() {
        let style = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: 0,
            safeAreaTopPx: 0,
            safeAreaBottomPx: 0
        )
        XCTAssertTrue(style.contains("background-color: #e2dbc8"))
        XCTAssertTrue(style.contains("color: #000000"))
        XCTAssertTrue(style.contains("html.theme-osrs-dark"))
        XCTAssertTrue(style.contains("body.theme-osrs-dark"))
        XCTAssertTrue(style.contains("background-color: #28221d"))
        XCTAssertTrue(style.contains("--body-main: #28221d"))
        XCTAssertFalse(style.contains("var(--body-main, #e2dbc8)"))
        XCTAssertFalse(style.contains("min-width: min(18.75rem, 100%)"))
        XCTAssertTrue(style.contains("table.infobox-bonuses"))
        XCTAssertTrue(style.contains("table-layout: fixed"))
        let dark = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: 0,
            usesDarkTheme: true
        )
        let darkUnscoped = dark.components(separatedBy: "html.theme-osrs-dark").first ?? ""
        XCTAssertTrue(darkUnscoped.contains("background-color: #28221d"))
        XCTAssertTrue(darkUnscoped.contains("--body-main: #28221d"))
        let beforeNot = darkUnscoped.components(separatedBy: "html:not(.theme-osrs-dark)").first ?? ""
        XCTAssertFalse(beforeNot.contains("background-color: #e2dbc8"))
    }

    func testCopyCachedResponseReusesPriorGenerationBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/old.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        ))
        let bytes = Data("prior-generation-bytes".utf8)
        XCTAssertTrue(server.cacheResponseDirect(
            pageId: "old-gen",
            url: url.absoluteString,
            data: bytes,
            response: response
        ))
        let copied = server.copyCachedResponse(
            from: "old-gen",
            to: "new-gen",
            url: url.absoluteString,
            saveGeneration: "g2"
        )
        XCTAssertEqual(copied?.data, bytes)
        XCTAssertEqual(
            server.getCachedResponseForAsset(url: url.absoluteString, pageId: "new-gen")?.data,
            bytes
        )
    }

    func testPaintStoreRoundTripsHTML() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try osrsSavedPaintStore.write(pageId: "page-1", html: "<html>saved</html>", cacheDirectory: directory)
        XCTAssertEqual(osrsSavedPaintStore.read(pageId: "page-1", cacheDirectory: directory), "<html>saved</html>")
        osrsSavedPaintStore.remove(pageId: "page-1", cacheDirectory: directory)
        XCTAssertNil(osrsSavedPaintStore.read(pageId: "page-1", cacheDirectory: directory))
    }

    func testAssetReuseKeepsUnchangedUrls() throws {
        let old = try XCTUnwrap(URL(string: "https://wiki/old.png"))
        let new = try XCTUnwrap(URL(string: "https://wiki/new.png"))
        let partition = osrsSavedPageAssetReuse.partition(
            requiredUrls: [old, new, old],
            priorUrls: [old]
        )
        XCTAssertEqual(partition.reusedUrls, [old])
        XCTAssertEqual(partition.fetchUrls, [new])
    }

    func testCopySourcePageIdsPreferPriorThenSession() {
        XCTAssertEqual(
            osrsSavedPageAssetReuse.copySourcePageIds(priorPageId: "durable", sessionPageId: "browsing"),
            ["durable", "browsing"]
        )
        XCTAssertEqual(
            osrsSavedPageAssetReuse.copySourcePageIds(priorPageId: nil, sessionPageId: "browsing"),
            ["browsing"]
        )
        XCTAssertEqual(
            osrsSavedPageAssetReuse.copySourcePageIds(priorPageId: "same", sessionPageId: "same"),
            ["same"]
        )
    }

    func testCopyCachedResponseRejectsHtmlSessionAsset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = LocalHTTPServer(port: 0, cacheDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/old.png"))
        let cacheKey = LocalHTTPServer.cacheKeyForRequest(
            pageId: "browsing",
            method: "GET",
            url: url.absoluteString
        )
        let cached = CachedHTTPResponse(
            url: url.absoluteString,
            data: Data("<html>captive portal</html>".utf8),
            timestamp: Date(),
            pageId: "browsing",
            statusCode: 200,
            headers: ["Content-Type": "text/html"]
        )
        try JSONEncoder().encode(cached).write(
            to: directory.appendingPathComponent("\(cacheKey).cache"),
            options: .atomic
        )
        XCTAssertNil(
            server.copyCachedResponse(
                from: "browsing",
                to: "staging",
                url: url.absoluteString,
                saveGeneration: "g1"
            )
        )
    }
}

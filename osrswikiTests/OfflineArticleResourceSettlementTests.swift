import XCTest
@testable import osrswiki

final class OfflineArticleResourceSettlementTests: XCTestCase {
    private let html = """
    <p>Article text</p>
    <img src="/images/a.png">
    <img src="https://oldschool.runescape.wiki/images/a.png"
         srcset="//oldschool.runescape.wiki/images/b.png 1x,
                 /images/c.png 2x,
                 data:image/png;base64,embedded 3x">
    <img data-src="/images/d.png" data-srcset="/images/e.png 1x, /images/f.png 2x">
    <picture><source srcset="/images/g.webp 1x"></picture>
    <video poster="/images/h.jpg"></video>
    <div style="background-image: url('/images/i.png')"></div>
    """

    func testSavedPageURLPersistenceKeepsEscapedPathDelimitersAsPathData() throws {
        let original = try XCTUnwrap(URL(
            string: "https://oldschool.runescape.wiki/w/Question%3FMark%23Variant?redirect=A%23B"
        ))

        let persisted = ArticleViewModel.savedPageURLForPersistence(original)
        let components = try XCTUnwrap(URLComponents(
            url: persisted,
            resolvingAgainstBaseURL: false
        ))

        XCTAssertEqual(persisted.absoluteString, original.absoluteString)
        XCTAssertEqual(components.percentEncodedPath, "/w/Question%3FMark%23Variant")
        XCTAssertEqual(components.percentEncodedQuery, "redirect=A%23B")
        XCTAssertEqual(components.path, "/w/Question?Mark#Variant")
    }

    func testPlannerRequiresAllUniqueHTTPSourceAndResponsiveVariants() {
        let urls = osrsOfflineArticleResourceSettlement.requiredImageURLs(from: html)

        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://oldschool.runescape.wiki/images/a.png",
            "https://oldschool.runescape.wiki/images/b.png",
            "https://oldschool.runescape.wiki/images/c.png",
            "https://oldschool.runescape.wiki/images/d.png",
            "https://oldschool.runescape.wiki/images/e.png",
            "https://oldschool.runescape.wiki/images/f.png",
            "https://oldschool.runescape.wiki/images/g.webp",
            "https://oldschool.runescape.wiki/images/h.jpg",
            "https://oldschool.runescape.wiki/images/i.png"
        ])
    }

    func testArtworkAllowlistIncludesSVGAndImageObjectsButExcludesInteractiveMediaAndScripts() {
        let fixture = """
        <svg><image href="/images/vector.png"></image></svg>
        <object type="image/svg+xml" data="/images/object.svg"></object>
        <object type="text/html" data="/interactive/object.html"></object>
        <video src="/media/movie.mp4" poster="/images/poster.jpg"><source src="/media/movie.webm"></video>
        <audio src="/media/audio.ogg"><source src="/media/audio-alt.ogg"></audio>
        <iframe src="/interactive/frame"></iframe><embed src="/interactive/embed">
        <script>const fake = "url('/images/script-phantom.png')";</script>
        <style>.hero { background: url('/images/style-art.png') }</style>
        """

        XCTAssertEqual(
            osrsOfflineArticleResourceSettlement.requiredImageURLs(from: fixture).map(\.absoluteString),
            [
                "https://oldschool.runescape.wiki/images/object.svg",
                "https://oldschool.runescape.wiki/images/poster.jpg",
                "https://oldschool.runescape.wiki/images/style-art.png",
                "https://oldschool.runescape.wiki/images/vector.png"
            ]
        )
    }

    func testSVGAndStylesheetFragmentsDeduplicateToNetworkResourceIdentity() async throws {
        let fixture = """
        <img src="/images/sprite.svg#inventory">
        <svg><image xlink:href="/images/sprite.svg#equipment"></image></svg>
        <style>.icon { background:url('/images/sprite.svg#prayer') }</style>
        <style>.gradient { fill:url(#local-gradient) }</style>
        <img src="#local-image">
        <link rel="stylesheet" href="/styles/article.css#light">
        <link rel="stylesheet" href="/styles/article.css#dark">
        """

        XCTAssertEqual(
            osrsOfflineArticleResourceSettlement.requiredImageURLs(from: fixture).map(\.absoluteString),
            [
                "https://oldschool.runescape.wiki/images/sprite.svg",
                "https://oldschool.runescape.wiki/styles/article.css"
            ]
        )

        let requested = LockedURLStrings()
        let settled = try await osrsOfflineArticleResourceSettlement.settle(html: fixture) { url in
            await requested.append(url.absoluteString)
            return url.pathExtension.lowercased() == "css" ? Data("/* no dependencies */".utf8) : nil
        }
        XCTAssertEqual(settled.map(\.absoluteString), [
            "https://oldschool.runescape.wiki/images/sprite.svg",
            "https://oldschool.runescape.wiki/styles/article.css"
        ])
        let requestedValues = await requested.values
        XCTAssertEqual(requestedValues.count, 2)
        XCTAssertTrue(requestedValues.allSatisfy { URL(string: $0)?.fragment == nil })
    }

    func testLinkedStylesheetsRecursivelyDiscoverRelativeImportsAndArtwork() async throws {
        let html = """
        <link rel="stylesheet" href="/styles/root.css">
        <div style="background:url('/images/inline.png')"></div>
        """
        let rootCSS = """
        @import "nested/theme.css";
        .root { background-image: url('../images/root.png'); }
        """
        let nestedCSS = ".nested { background:url('../../images/nested.png') }"
        let requested = LockedURLStrings()

        let settled = try await osrsOfflineArticleResourceSettlement.settle(html: html) { url in
            await requested.append(url.absoluteString)
            switch url.path {
            case "/styles/root.css": return Data(rootCSS.utf8)
            case "/styles/nested/theme.css": return Data(nestedCSS.utf8)
            default: return nil
            }
        }

        XCTAssertEqual(Set(settled.map(\.absoluteString)), [
            "https://oldschool.runescape.wiki/styles/root.css",
            "https://oldschool.runescape.wiki/styles/nested/theme.css",
            "https://oldschool.runescape.wiki/images/inline.png",
            "https://oldschool.runescape.wiki/images/root.png",
            "https://oldschool.runescape.wiki/images/nested.png"
        ])
        let requestedValues = await requested.values
        XCTAssertEqual(Set(requestedValues), Set(settled.map(\.absoluteString)))
    }

    func testStylesheetFontFacesAreExcludedWhileBackgroundArtworkSettles() async throws {
        let stylesheet = """
        @font-face {
            font-family: "RuneScape";
            src: url('../fonts/runescape.woff2') format('woff2'),
                 url("../fonts/runescape.ttf?v=2") format('truetype');
        }
        .hero { background-image: url('../images/hero.webp'); }
        """
        let requested = LockedURLStrings()

        let settled = try await osrsOfflineArticleResourceSettlement.settle(
            html: #"<link rel="stylesheet" href="/styles/article.css">"#
        ) { url in
            await requested.append(url.absoluteString)
            return url.path == "/styles/article.css" ? Data(stylesheet.utf8) : nil
        }

        XCTAssertEqual(Set(settled.map(\.absoluteString)), [
            "https://oldschool.runescape.wiki/styles/article.css",
            "https://oldschool.runescape.wiki/images/hero.webp"
        ])
        let requestedValues = await requested.values
        XCTAssertEqual(Set(requestedValues), Set(settled.map(\.absoluteString)))
        XCTAssertFalse(requestedValues.contains { $0.contains("/fonts/") })
    }

    func testSettlementNeverExceedsTwoConcurrentDownloads() async throws {
        let probe = OfflineConcurrencyProbe()
        _ = try await osrsOfflineArticleResourceSettlement.settle(
            html: html,
            maximumConcurrency: 2
        ) { url in
            try await probe.download(url)
            return nil
        }
        let peakConcurrency = await probe.peakConcurrency
        XCTAssertEqual(peakConcurrency, 2)
    }

    func testDirectHTMLArtworkBeyondLegacyCapIsSettledExhaustively() async throws {
        let imageCount = 600
        let largeHTML = (0..<imageCount)
            .map { "<img src=\"/images/direct-\($0).png\">" }
            .joined()
        let probe = OfflineDownloadProbe()

        let settled = try await osrsOfflineArticleResourceSettlement.settle(html: largeHTML) { url in
            try await probe.download(url)
            return nil
        }

        XCTAssertEqual(settled.count, imageCount)
        let requested = await probe.requestedURLs
        XCTAssertEqual(Set(requested), Set(settled))
    }

    func testRecursiveStylesheetSafetyLimitFailsHonestly() async throws {
        let stylesheet = """
        .a { background:url('/images/a.png') }
        .b { background:url('/images/b.png') }
        .c { background:url('/images/c.png') }
        """

        do {
            _ = try await osrsOfflineArticleResourceSettlement.settle(
                html: #"<link rel="stylesheet" href="/styles/root.css">"#,
                maximumRecursiveStylesheetResources: 2
            ) { url in
                url.path == "/styles/root.css" ? Data(stylesheet.utf8) : nil
            }
            XCTFail("Crossing the recursive CSS dependency guard must fail the explicit save")
        } catch let error as osrsOfflineResourceSettlementError {
            XCTAssertEqual(error, .requiredResourcesFailed(count: 1))
        }
    }

    func testZeroResourceArticleIsAValidSettledSet() async throws {
        let probe = OfflineDownloadProbe()
        let settled = try await osrsOfflineArticleResourceSettlement.settle(
            html: "<p>Text-only article.</p>"
        ) { url in
            try await probe.download(url)
            return nil
        }

        XCTAssertTrue(settled.isEmpty)
        let requests = await probe.requestedURLs
        XCTAssertTrue(requests.isEmpty)
    }

    func testExistingPartialBrowsingCacheStillSettlesEveryUniqueResource() async throws {
        let probe = OfflineDownloadProbe(
            alreadyCached: ["https://oldschool.runescape.wiki/images/a.png"]
        )

        let settled = try await osrsOfflineArticleResourceSettlement.settle(html: html) { url in
            try await probe.download(url)
            return nil
        }

        XCTAssertEqual(settled.count, 9)
        let requested = await probe.requestedURLs
        let networkDownloadCount = await probe.networkDownloadCount
        XCTAssertEqual(Set(requested), Set(settled))
        XCTAssertEqual(networkDownloadCount, 8)
    }

    func testPartialFailureIsSanitizedAndRetryCanComplete() async throws {
        let failingURL = "https://oldschool.runescape.wiki/images/b.png"
        let probe = OfflineDownloadProbe(failingURLs: [failingURL])

        do {
            _ = try await osrsOfflineArticleResourceSettlement.settle(html: html) { url in
                try await probe.download(url)
                return nil
            }
            XCTFail("A required responsive image failure must fail offline settlement")
        } catch let error as osrsOfflineResourceSettlementError {
            XCTAssertEqual(error, .requiredResourcesFailed(count: 1))
            XCTAssertEqual(
                error.localizedDescription,
                "Some article images could not be saved for offline use. Please try again."
            )
            XCTAssertFalse(error.localizedDescription.contains("images/b.png"))
        }

        await probe.setFailingURLs([])
        let settled = try await osrsOfflineArticleResourceSettlement.settle(html: html) { url in
            try await probe.download(url)
            return nil
        }
        XCTAssertEqual(settled.count, 9)
    }

    func testCancellationStopsBoundedSettlement() async throws {
        let probe = OfflineDownloadProbe(delayNanoseconds: 5_000_000_000)
        let task = Task {
            try await osrsOfflineArticleResourceSettlement.settle(html: html) { url in
                try await probe.download(url)
                return nil
            }
        }

        for _ in 0..<40 {
            if await probe.requestedURLs.isEmpty == false { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation must not be converted into a successful or failed-resource save")
        } catch is CancellationError {
            // Expected.
        }
        let requestedCount = await probe.requestedURLs.count
        XCTAssertLessThan(requestedCount, 9)
    }

    @MainActor
    func testFailedMediaKeepsSaveControlRetryableAndReusesMetadataIdentity() {
        let failedPage = SavedPage(
            id: "failed-media-page",
            title: "Failed media",
            description: nil,
            url: URL(string: "https://oldschool.runescape.wiki/w/Failed_media")!,
            thumbnailUrl: nil,
            savedDate: Date(),
            isOfflineAvailable: false,
            offlineDownloadDate: nil,
            offlineStatus: .failed,
            offlineFileSize: nil,
            offlineLocalPath: nil
        )

        let state = ArticleViewModel.saveControlState(for: failedPage)
        XCTAssertFalse(state.isBookmarked, "The next tap must retry instead of remove")
        XCTAssertEqual(state.saveState, .error)
        XCTAssertEqual(state.progress, 0)
        XCTAssertEqual(
            ArticleViewModel.offlineSaveRecordID(existingIncompletePage: failedPage),
            failedPage.id,
            "A retry must update the existing failed record instead of adding a duplicate"
        )
    }

    @MainActor
    func testInterruptedSaveRelaunchRemainsRetryableAndReusesRecord() {
        for status in [
            SavedPage.OfflineStatus.notDownloaded,
            .downloading,
            .failed,
            .outdated
        ] {
            let interrupted = SavedPage(
                id: "interrupted-\(status.rawValue)",
                title: "Interrupted",
                description: nil,
                url: URL(string: "https://oldschool.runescape.wiki/w/Interrupted")!,
                thumbnailUrl: nil,
                savedDate: Date(),
                isOfflineAvailable: false,
                offlineDownloadDate: nil,
                offlineStatus: status,
                offlineFileSize: nil,
                offlineLocalPath: nil
            )
            let state = ArticleViewModel.saveControlState(for: interrupted)
            XCTAssertFalse(state.isBookmarked)
            XCTAssertEqual(state.saveState, .error)
            XCTAssertEqual(
                ArticleViewModel.offlineSaveRecordID(existingIncompletePage: interrupted),
                interrupted.id
            )
        }
    }

    @MainActor
    func testUnversionedAvailableControlRetriesAndFailedRefreshPreservesOldNamespace() {
        let legacy = SavedPage(
            id: "legacy-retry",
            title: "Legacy retry",
            description: "Keep me",
            url: URL(string: "https://oldschool.runescape.wiki/w/Legacy_retry")!,
            thumbnailUrl: nil,
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: true,
            offlineDownloadDate: Date(timeIntervalSince1970: 1_735_732_900),
            offlineStatus: .available,
            offlineFileSize: 2_048,
            offlineLocalPath: "legacy-retry"
        )
        let state = ArticleViewModel.saveControlState(for: legacy)
        XCTAssertFalse(state.isBookmarked)
        XCTAssertEqual(state.saveState, .error)

        let retryable = legacy.requiringDurableSettlementRefresh()
        XCTAssertEqual(ArticleViewModel.offlineSaveRecordID(existingIncompletePage: retryable), legacy.id)
        let failed = ArticleViewModel.failedOfflineSaveRecord(from: retryable)
        XCTAssertEqual(failed.id, legacy.id)
        XCTAssertEqual(failed.offlineStatus, .failed)
        XCTAssertEqual(failed.offlineLocalPath, legacy.offlineLocalPath)
        XCTAssertEqual(failed.offlineDownloadDate, legacy.offlineDownloadDate)
        XCTAssertEqual(failed.offlineFileSize, legacy.offlineFileSize)
        XCTAssertNil(failed.durableSettlementVersion)
        XCTAssertTrue(failed.canAttemptOfflineCacheRead)
        XCTAssertFalse(ArticleViewModel.saveControlState(for: failed).isBookmarked)

        let stagingPageId = ArticleViewModel.offlineSaveStagingPageID(
            recordID: retryable.id,
            saveGeneration: "refresh-generation"
        )
        let refreshed = retryable.markingCurrentDurableSettlementAvailable(
            at: Date(timeIntervalSince1970: 1_735_733_000),
            offlineLocalPath: stagingPageId
        )
        XCTAssertTrue(refreshed.hasCurrentDurableSettlement)
        XCTAssertTrue(refreshed.isAvailableOffline)
        XCTAssertEqual(refreshed.offlineCachePageId, stagingPageId)
        XCTAssertEqual(ArticleViewModel.saveControlState(for: refreshed).saveState, .saved)
    }

    func testCurrentSettlementMarkerIsWrittenOnlyAfterExactDurabilityGuard() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        let savedPagesSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/SavedPagesViewModel.swift"),
            encoding: .utf8
        )
        let durableGuard = try XCTUnwrap(source.range(of: "guard durableOfflineReady else"))
        let stagingIdentity = try XCTUnwrap(source.range(of: "let stagingPageId = Self.offlineSaveStagingPageID"))
        let markerCommit = try XCTUnwrap(source.range(of: "let updatedSavedPage = savedPage.markingCurrentDurableSettlementAvailable"))
        let repositoryPublish = try XCTUnwrap(source.range(of: "guard savedPagesRepository.compareAndSwapOfflineSettlement"))
        let stageRelease = try XCTUnwrap(source.range(of: "unpublishedStagingPageId = nil"))
        XCTAssertLessThan(stagingIdentity.lowerBound, durableGuard.lowerBound)
        XCTAssertLessThan(durableGuard.lowerBound, markerCommit.lowerBound)
        XCTAssertLessThan(markerCommit.lowerBound, repositoryPublish.lowerBound)
        XCTAssertLessThan(repositoryPublish.lowerBound, stageRelease.lowerBound)
        XCTAssertFalse(savedPagesSource.contains("downloadPageForOffline("))
        XCTAssertFalse(savedPagesSource.contains("updateSavedPageOfflineStatus("))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("platforms/ios/osrswiki.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root from \(#filePath)")
    }
}

private actor OfflineDownloadProbe {
    private var alreadyCached: Set<String>
    private var failingURLs: Set<String>
    private let delayNanoseconds: UInt64
    private(set) var requestedURLs: [URL] = []
    private(set) var networkDownloadCount = 0

    init(
        alreadyCached: Set<String> = [],
        failingURLs: Set<String> = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.alreadyCached = alreadyCached
        self.failingURLs = failingURLs
        self.delayNanoseconds = delayNanoseconds
    }

    func setFailingURLs(_ urls: Set<String>) {
        failingURLs = urls
    }

    func download(_ url: URL) async throws {
        requestedURLs.append(url)
        if alreadyCached.contains(url.absoluteString) {
            return
        }
        networkDownloadCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if failingURLs.contains(url.absoluteString) {
            throw URLError(.cannotLoadFromNetwork)
        }
    }
}

private actor LockedURLStrings {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor OfflineConcurrencyProbe {
    private var active = 0
    private(set) var peakConcurrency = 0

    func download(_ url: URL) async throws {
        active += 1
        peakConcurrency = max(peakConcurrency, active)
        try await Task.sleep(nanoseconds: 15_000_000)
        active -= 1
    }
}

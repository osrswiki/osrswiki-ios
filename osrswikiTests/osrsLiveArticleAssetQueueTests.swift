import XCTest
@testable import osrswiki

final class osrsLiveArticleAssetQueueTests: XCTestCase {
    private let infobox = URL(string: "https://oldschool.runescape.wiki/images/infobox.png")!
    private let lead = URL(string: "https://oldschool.runescape.wiki/images/lead.png")!
    private let rest = URL(string: "https://oldschool.runescape.wiki/images/row-30.png")!
    private let near = URL(string: "https://oldschool.runescape.wiki/images/near.png")!
    private let cached = URL(string: "https://oldschool.runescape.wiki/images/cached.png")!
    private let belowFold = URL(string: "https://oldschool.runescape.wiki/images/below-fold.png")!
    private let gloryPool = URL(string: "https://oldschool.runescape.wiki/images/glory-uncharged.png")!

    private var firstScreenHTML: String {
        var html = """
        <table class="infobox"><tr><td><img src="/images/infobox.png"></td></tr></table>
        <p><img src="/images/lead.png"></p>
        <h2>Combat stats</h2>
        """
        for index in 1...30 {
            html += "<img src=\"/images/row-\(index).png\">"
        }
        html += "<img src=\"/images/below-fold.png\">"
        return html
    }

    private var gloryHTML: String {
        """
        <table class="infobox infobox-switch" data-resource-class=".infobox-resources-glory">
          <tr><td>
            <img src="/images/glory-default.png">
            <span class="infobox-bonuses-image render-m"><img src="/images/glory-m.png"></span>
            <span class="infobox-bonuses-image render-f"><img src="/images/glory-f.png"></span>
          </td></tr>
        </table>
        <p>Lead text <img src="/images/glory-lead.png"></p>
        <h2>Combat stats</h2>
        <img src="/images/below-fold.png">
        <div class="infobox-resources-glory infobox-switch-resources">
          <div data-attr-param="version">
            <div data-attr-index="0"><img src="/images/glory-4.png"></div>
            <div data-attr-index="1"><img src="/images/glory-3.png"></div>
            <div data-attr-index="2"><img src="/images/glory-uncharged.png"></div>
          </div>
        </div>
        """
    }

    func testPartitionPutsFirstViewSlotAheadOfRemainder() {
        let required = osrsOfflineArticleResourceSettlement.requiredImageURLsInDocumentOrder(from: firstScreenHTML)
        let firstView = osrsOfflineArticleResourceSettlement.firstViewSlotURLs(from: firstScreenHTML)
        let plan = osrsLiveArticleAssetPlan.partition(required: required, firstView: firstView)

        XCTAssertTrue(firstView.contains(infobox))
        XCTAssertTrue(firstView.contains(lead))
        XCTAssertFalse(firstView.contains(belowFold))
        XCTAssertEqual(plan.high.first, infobox)
        XCTAssertTrue(plan.high.contains(lead))
        XCTAssertTrue(plan.low.contains(rest))
        XCTAssertFalse(plan.high.contains(rest))
        XCTAssertEqual(Set(plan.high + plan.low), Set(required))
        XCTAssertLessThanOrEqual(plan.high.count, osrsLiveArticleAssetPlan.firstViewCap)
    }

    func testFirstViewSlotIncludesSwitcherPoolAndGenderRenders() {
        let firstView = osrsOfflineArticleResourceSettlement.firstViewSlotURLs(from: gloryHTML)
        let required = osrsOfflineArticleResourceSettlement.requiredImageURLsInDocumentOrder(from: gloryHTML)
        let plan = osrsLiveArticleAssetPlan.partition(required: required, firstView: firstView)
        let expected = [
            "https://oldschool.runescape.wiki/images/glory-default.png",
            "https://oldschool.runescape.wiki/images/glory-m.png",
            "https://oldschool.runescape.wiki/images/glory-f.png",
            "https://oldschool.runescape.wiki/images/glory-4.png",
            "https://oldschool.runescape.wiki/images/glory-3.png",
            "https://oldschool.runescape.wiki/images/glory-uncharged.png",
            "https://oldschool.runescape.wiki/images/glory-lead.png"
        ].compactMap(URL.init(string:))

        for url in expected {
            XCTAssertTrue(firstView.contains(url), "missing first-view \(url)")
            XCTAssertTrue(plan.high.contains(url), "missing high \(url)")
        }
        XCTAssertFalse(firstView.contains(belowFold))
        XCTAssertFalse(plan.high.contains(belowFold))
        XCTAssertTrue(plan.low.contains(belowFold))
    }

    func testQueueSkipsCachedAndPromoteMovesLowToHigh() {
        let queue = osrsLiveArticleAssetQueue(isCached: { [cached] in $0 == cached })
        queue.load(
            high: [lead],
            low: [cached, rest, near]
        )
        queue.promote([near])
        XCTAssertEqual(queue.takeHigh(), near)
        XCTAssertEqual(queue.takeHigh(), lead)
        XCTAssertEqual(queue.takeLow(), rest)
        XCTAssertNil(queue.takeLow())
    }

    func testWarmerFetchesFirstViewBeforeRemainderAndSkipsCached() async {
        var fetched: [URL] = []
        let skip = URL(string: "https://oldschool.runescape.wiki/images/row-2.png")!
        let warmer = osrsLiveArticleAssetWarmer(
            pageId: "browsing_test",
            isCached: { $0 == skip },
            fetch: { url in
                fetched.append(url)
            },
            highConcurrency: 1,
            lowConcurrency: 0
        )
        await warmer.warm(html: firstScreenHTML)
        XCTAssertEqual(fetched.first, infobox)
        let firstIndex = fetched.firstIndex(of: lead) ?? .max
        let restIndex = fetched.firstIndex(of: rest) ?? .min
        XCTAssertLessThan(firstIndex, restIndex)
        XCTAssertFalse(fetched.contains(skip))
    }

    func testFirstViewWarmerFetchesSlotOnlyAndCancelDropsWork() async throws {
        var fetched: [URL] = []
        let started = expectation(description: "first fetch started")
        let warmer = osrsFirstViewAssetWarmer(
            pageId: "browsing_test",
            isCached: { _ in false },
            fetch: { url in
                fetched.append(url)
                if fetched.count == 1 {
                    started.fulfill()
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            },
            concurrency: 1
        )
        let task = Task {
            await warmer.warm(html: gloryHTML)
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        warmer.cancel()
        _ = await task.result
        XCTAssertEqual(fetched.count, 1)
        XCTAssertFalse(fetched.contains(belowFold))

        var completed: [URL] = []
        let completeWarmer = osrsFirstViewAssetWarmer(
            pageId: "browsing_test",
            isCached: { _ in false },
            fetch: { url in completed.append(url) },
            concurrency: 1
        )
        await completeWarmer.warm(html: gloryHTML)
        XCTAssertTrue(completed.contains(gloryPool))
        XCTAssertFalse(completed.contains(belowFold))

        var remainder: [URL] = []
        let remainderWarmer = osrsLiveArticleAssetWarmer(
            pageId: "browsing_test",
            isCached: { _ in false },
            fetch: { url in remainder.append(url) },
            highConcurrency: 1,
            lowConcurrency: 1
        )
        await remainderWarmer.warm(html: gloryHTML)
        XCTAssertTrue(remainder.contains(belowFold))

        let warmerSource = try String(
            contentsOf: try repositoryRoot()
                .appendingPathComponent("platforms/ios/osrswiki/Services/osrsFirstViewAssetWarmer.swift"),
            encoding: .utf8
        )
        let defaultOn = warmerSource
            .components(separatedBy: "narrowFirstViewportPaintedSet")
            .dropFirst()
            .first?
            .components(separatedBy: "} else {")
            .first ?? ""
        XCTAssertFalse(defaultOn.contains("requiredImageURLsInDocumentOrder"))
        XCTAssertTrue(defaultOn.contains("firstViewSlotURLs") || defaultOn.contains("firstView"))
    }

    func testCancelDropsRemainingWork() async {
        var fetched: [URL] = []
        let started = expectation(description: "first fetch started")
        let warmer = osrsLiveArticleAssetWarmer(
            pageId: "browsing_test",
            isCached: { _ in false },
            fetch: { url in
                fetched.append(url)
                if fetched.count == 1 {
                    started.fulfill()
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            },
            highConcurrency: 1,
            lowConcurrency: 0
        )
        let task = Task {
            await warmer.warm(html: firstScreenHTML)
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        warmer.cancel()
        _ = await task.result
        XCTAssertEqual(fetched.count, 1)
    }

    func testFirstViewportScriptMatchesSharedCopyAndDoesNotAssignDomSrc() throws {
        let root = try repositoryRoot()
        let shared = try String(contentsOf: root.appendingPathComponent("shared/js/first_viewport_assets.js"))
        let ios = try String(contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Assets/web/first_viewport_assets.js"))
        XCTAssertEqual(shared, ios)
        XCTAssertTrue(shared.contains("osrsCollectFirstViewportUrls"))
        XCTAssertTrue(shared.contains("data-attr-index"))
        XCTAssertTrue(shared.contains("osrsFirstViewComplete"))
        XCTAssertTrue(shared.contains("osrsNotifyFirstViewComplete"))
        XCTAssertTrue(shared.contains("osrsWatchFirstViewComplete"))
        XCTAssertTrue(shared.contains("__osrsFirstViewPainted"))
        XCTAssertTrue(shared.contains("domImageAlreadyDecoded"))
        XCTAssertTrue(shared.contains("naturalWidth"))
        XCTAssertTrue(shared.contains("new Image()"))
        XCTAssertTrue(shared.contains("notify(paintedUrls())"))
        XCTAssertTrue(shared.contains("function paintedUrls"))
        XCTAssertTrue(shared.contains("collectDefaultSwitcherPane"))
        XCTAssertTrue(shared.contains("chosenElementUrls"))
        XCTAssertTrue(shared.contains("var urls = paintedUrls()"))
        XCTAssertFalse(shared.contains("el.src ="))
        XCTAssertFalse(shared.contains("setAttribute('src'"))
    }

    func testLiveAssetWarmScriptYieldsToUserInteraction() throws {
        let root = try repositoryRoot()
        let shared = try String(contentsOf: root.appendingPathComponent("shared/js/live_article_asset_warm.js"))
        let ios = try String(contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Assets/web/live_article_asset_warm.js"))
        XCTAssertEqual(shared, ios)
        XCTAssertTrue(shared.contains("noteUserInteraction"))
        XCTAssertTrue(shared.contains("pointerdown"))
        XCTAssertTrue(shared.contains("touchmove"))
        XCTAssertTrue(shared.contains("interactionHoldMs = 750"))
        XCTAssertTrue(shared.contains("pause: true"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root")
    }
}

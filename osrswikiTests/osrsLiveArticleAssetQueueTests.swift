import XCTest
@testable import osrswiki

final class osrsLiveArticleAssetQueueTests: XCTestCase {
    private let infobox = URL(string: "https://oldschool.runescape.wiki/images/infobox.png")!
    private let lead = URL(string: "https://oldschool.runescape.wiki/images/row-1.png")!
    private let rest = URL(string: "https://oldschool.runescape.wiki/images/row-30.png")!
    private let near = URL(string: "https://oldschool.runescape.wiki/images/near.png")!
    private let cached = URL(string: "https://oldschool.runescape.wiki/images/cached.png")!

    private var firstScreenHTML: String {
        var html = "<table class=\"infobox\"><tr><td><img src=\"/images/infobox.png\"></td></tr></table>"
        for index in 1...30 {
            html += "<img src=\"/images/row-\(index).png\">"
        }
        return html
    }

    func testPartitionPutsInfoboxAndFirstScreenAheadOfRemainder() {
        let required = osrsOfflineArticleResourceSettlement.requiredImageURLsInDocumentOrder(from: firstScreenHTML)
        let infoboxURLs = osrsOfflineArticleResourceSettlement.infoboxImageURLs(from: firstScreenHTML)
        let plan = osrsLiveArticleAssetPlan.partition(required: required, infobox: infoboxURLs)

        XCTAssertEqual(infoboxURLs.first, infobox)
        XCTAssertEqual(plan.high.first, infobox)
        XCTAssertTrue(plan.high.contains(lead))
        XCTAssertTrue(plan.low.contains(rest))
        XCTAssertFalse(plan.high.contains(rest))
        XCTAssertEqual(Set(plan.high + plan.low), Set(required))
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

    func testWarmerFetchesFirstScreenBeforeRemainderAndSkipsCached() async {
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
}

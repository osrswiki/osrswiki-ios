import XCTest
@testable import osrswiki

@MainActor
final class HomeFeedParserRegressionTests: XCTestCase {
    func testHomeListPlainTextPreservesBlockBoundariesAndDecodesEntities() {
        XCTAssertEqual(
            osrsStringUtils.plainText(fromHTML: "<p>One &amp;amp; two</p><p>Three</p><br><ul><li>Four</li></ul>"),
            "One & two Three Four"
        )
    }

    override func tearDown() {
        NewsRepository.shared.clearCache()
        super.tearDown()
    }

    func testParsesLowerHomeSectionsWithNestedHeadingDivs() {
        let html = """
        <div class="mainpage-recent-updates tile-row">
            <div class="tile-halves">
                <div class="tile-top"><img src="/images/update.png" /></div>
                <div class="tile-bottom"><a href="/w/Update"><h2>Update title</h2><p>Intro</p><p>Update snippet</p></a></div>
            </div>
        </div>
        <div class="mainpage-contents tile-row"></div>
        <div class="mainpage-left">
            <div class="mainpage-popular tile-halves nomobile">
                <div class="tile-top">
                    <div class="popular-pages plainlist">
                        <div class="mw-heading mw-heading2"><h2 id="Popular_pages">Popular pages</h2></div>
                        <ul>
                            <li class="mp-popular-page-light"><a href="/w/Money_making_guide" title="Money making guide">Money making guide</a></li>
                        </ul>
                    </div>
                </div>
            </div>
            <div class="mainpage-wikinews tile plainlinks">
                <div class="mw-heading mw-heading2"><h2 id="Announcements">Announcements</h2></div>
                <dl>
                    <dt>24 March 2026</dt>
                    <dd><a href="/w/Forty_thousand" title="Forty thousand">Forty thousand</a> article milestone.</dd>
                </dl>
            </div>
            <div class="mainpage-onthisday tile nomobile">
                <p class="byline">5 July</p>
                <div class="mw-heading mw-heading2"><h2 id="On_this_day...">On this day...</h2></div>
                <div>
                    <ul><li><b>2023</b> - Game update: <a href="/w/Update" title="Update">Update</a></li></ul>
                </div>
            </div>
        </div>
        """

        let feed = NewsRepository.shared.parseWikiFeedForTesting(html)

        XCTAssertEqual(feed.recentUpdates.count, 1)
        XCTAssertEqual(feed.announcements.first?.date, "24 March 2026")
        XCTAssertEqual(feed.onThisDay?.title, "On this day...")
        XCTAssertEqual(feed.onThisDay?.events.count, 1)
        XCTAssertEqual(feed.popularPages.first?.title, "Money making guide")
    }

    func testInlineHomeLinksPrewarmOnlyInternalArticlesAfterViewportEntry() {
        let html = """
        <a href="https://example.com/external">External</a>
        <a href="/w/File:Icon.png">File namespace</a>
        <a href="/w/Internal_A">Internal A</a>
        <a href="https://oldschool.runescape.wiki/w/Internal_B">Internal B</a>
        """
        let urls = osrsHomeFeedArticleLinkExtractor.internalArticleURLs(in: html)
        XCTAssertEqual(urls.map(\.path), ["/w/Internal_A", "/w/Internal_B"])

        var visibility = osrsArticlePrewarmVisibilityGate()
        XCTAssertEqual(
            visibility.transition(
                .appeared(applicationIsActive: true, environmentAllowsPrewarm: true)
            ),
            .none,
            "Instantiation alone must not prewarm an offscreen announcement or event link"
        )
        XCTAssertEqual(visibility.transition(.visibilityChanged(true)), .schedule)
        XCTAssertEqual(visibility.transition(.visibilityChanged(false)), .cancel)
    }
}

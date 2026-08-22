import XCTest
@testable import osrswiki

final class osrsSearchPreviewTextTests: XCTestCase {
    func testSkipsCopyrightBoilerplateAndUsesFirstContentParagraph() {
        let html = """
        <p>This official news post is copied verbatim from the Old School RuneScape website.</p>
        <p>The Crusader Classic event starts tomorrow in the Grand Exchange.</p>
        """
        XCTAssertEqual(
            osrsSearchPreviewText.fromHtml(html),
            "The Crusader Classic event starts tomorrow in the Grand Exchange."
        )
    }

    func testPlainExtractWithoutIntroStillYieldsPreview() {
        let extract = "  Mortimer has returned to Varrock after a long absence from the city.  "
        XCTAssertEqual(
            osrsSearchPreviewText.fromPlainExtract(extract),
            "Mortimer has returned to Varrock after a long absence from the city."
        )
    }

    func testEmptyAndBoilerplateExtractsYieldNilUntilHtmlFallback() {
        XCTAssertNil(osrsSearchPreviewText.fromPlainExtract("This official news post is copied verbatim."))
        XCTAssertNil(osrsSearchPreviewText.fromPlainExtract("   "))
        let html = "<div class=\"infobox\"></div><p>Players can now claim the reward from Diango.</p>"
        XCTAssertEqual(
            osrsSearchPreviewText.fromHtml(html),
            "Players can now claim the reward from Diango."
        )
    }

    func testSkipsImageFallbackChromeAndUsesNextParagraph() {
        let html = """
        <p>If you can't see the asset above, click here.</p>
        <p>We'll be adding regional servers for South Africa, Japan and Australia.</p>
        """
        XCTAssertEqual(
            osrsSearchPreviewText.fromHtml(html),
            "We'll be adding regional servers for South Africa, Japan and Australia."
        )
    }

    func testTableOfContentsHeadingsAreNotUsableCandidates() {
        XCTAssertNil(osrsSearchPreviewText.fromCandidates("Contents", "Changelog", nil))
        XCTAssertEqual(
            osrsSearchPreviewText.fromHtml("<div>Contents</div><p>The Grand Exchange now supports bulk offers.</p>"),
            "The Grand Exchange now supports bulk offers."
        )
    }

    func testSkipsWikiTocMarkupAndPrefersBodySentence() {
        let html = """
        <div id="toc" class="toc"><ul><li>1 Wyrmscraig</li><li>2 Access</li></ul></div>
        <h2>Wyrmscraig</h2>
        <p>Players can now reach Wyrmscraig from the eastern coast after finishing Fallen From Grace.</p>
        """
        XCTAssertEqual(
            osrsSearchPreviewText.fromHtml(html),
            "Players can now reach Wyrmscraig from the eastern coast after finishing Fallen From Grace."
        )
        XCTAssertNil(osrsSearchPreviewText.fromPlainExtract("1 Wyrmscraig 2 Access to Wyrmscraig 3 Fallen From Grace"))
        XCTAssertNil(
            osrsSearchPreviewText.fromPlainExtract(
                "1 Changelog - June 3rd 1.1 Gathering QoL Improvements 1.2 Sailing Changes"
            )
        )
    }

    func testChromeOnlySnippetsAreNotUsableCandidates() {
        XCTAssertNil(osrsSearchPreviewText.fromCandidates("CLICK HERE TO SHOW THIS CONTENT", nil))
        XCTAssertEqual(
            osrsSearchPreviewText.fromCandidates(
                "CLICK HERE TO SHOW THIS CONTENT",
                "The Grand Exchange now supports bulk offers."
            ),
            "The Grand Exchange now supports bulk offers."
        )
    }

    func testDivOnlyCopyrightPageStillYieldsLaterSentence() {
        let html = """
        <div>This official news post is copied verbatim from the Old School RuneScape website. It was added on 26 May 2026.</div>
        <div>Time to huddle around the campfire as we share some updates with you.</div>
        """
        XCTAssertEqual(
            osrsSearchPreviewText.fromHtml(html),
            "Time to huddle around the campfire as we share some updates with you."
        )
    }
}

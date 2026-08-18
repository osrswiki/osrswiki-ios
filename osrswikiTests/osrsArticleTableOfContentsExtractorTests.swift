import XCTest
@testable import osrswiki

final class osrsArticleTableOfContentsExtractorTests: XCTestCase {
    func testExtractUsesASingleFloorDialectAndKeepsTheAuthoredHeadingId() {
        let html = """
        <div class="mw-heading mw-heading2">
            <h2 id="1st_floor2nd_floor">
                <span class="floornumber">
                    <span class="floornumber-gb">1<sup>st</sup> floor<sup class="floornumber-help">[UK]</sup></span>
                    <span class="floornumber-us noexcerpt">2<sup>nd</sup> floor<sup class="floornumber-help">[US]</sup></span>
                </span>
            </h2>
        </div>
        <div class="mw-heading mw-heading2">
            <h2 id="Basement">Basement</h2>
        </div>
        """

        let sections = osrsArticleTableOfContentsExtractor.extract(
            displayTitle: "Heroes' Guild",
            html: html,
            convention: .gb
        )

        XCTAssertEqual(sections.map(\.title), ["Heroes' Guild", "1st floor", "Basement"])
        XCTAssertEqual(sections.map(\.id), ["", "1st_floor2nd_floor", "Basement"])
        XCTAssertFalse(sections.contains { $0.title.contains("2nd") })
        XCTAssertFalse(sections.contains { $0.title.contains("[UK]") || $0.title.contains("[US]") })
    }

    func testExtractUsesUSFloorDialectWhenTheDeviceLocaleUsesUSFloors() {
        let html = """
        <div class="mw-heading mw-heading2">
            <h2 id="1st_floor2nd_floor">
                <span class="floornumber">
                    <span class="floornumber-gb">1<sup>st</sup> floor<sup class="floornumber-help">[UK]</sup></span>
                    <span class="floornumber-us noexcerpt">2<sup>nd</sup> floor<sup class="floornumber-help">[US]</sup></span>
                </span>
            </h2>
        </div>
        """

        let sections = osrsArticleTableOfContentsExtractor.extract(
            displayTitle: "Heroes' Guild",
            html: html,
            convention: .us
        )

        XCTAssertEqual(sections.map(\.title), ["Heroes' Guild", "2nd floor"])
        XCTAssertFalse(sections.contains { $0.title.contains("1st") })
    }
}

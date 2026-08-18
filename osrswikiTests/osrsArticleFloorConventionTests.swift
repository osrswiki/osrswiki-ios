import XCTest
@testable import osrswiki

final class osrsArticleFloorConventionTests: XCTestCase {
    func testUSEnglishAndCanadianLocalesUseUSFloorLabels() {
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_US")),
            .us
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_CA")),
            .us
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_PH")),
            .us
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "ja_JP")),
            .us
        )
        XCTAssertEqual(osrsArticleFloorConvention.us.bodyClass, "floornumber-setting-us")
        XCTAssertEqual(
            osrsArticleFloorConvention.us.hiddenDialectSelector,
            ".floornumber-gb, .floornumber-help"
        )
    }

    func testUKAndOtherLocalesUseTheWikiDefaultGBFloorLabels() {
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_GB")),
            .gb
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_AU")),
            .gb
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_NZ")),
            .gb
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.from(locale: Locale(identifier: "en_IE")),
            .gb
        )
        XCTAssertEqual(osrsArticleFloorConvention.gb.bodyClass, "floornumber-setting-gb")
    }

    func testAppearanceOverrideSelectsAnExplicitFloorDialect() {
        XCTAssertEqual(
            osrsArticleFloorConvention.current(
                mode: .gb,
                locale: Locale(identifier: "en_US")
            ),
            .gb
        )
        XCTAssertEqual(
            osrsArticleFloorConvention.current(
                mode: .us,
                locale: Locale(identifier: "en_GB")
            ),
            .us
        )
        XCTAssertEqual(
            osrsArticleFloorNumberingMode.auto.convention(locale: Locale(identifier: "en_US")),
            .us
        )
    }
}

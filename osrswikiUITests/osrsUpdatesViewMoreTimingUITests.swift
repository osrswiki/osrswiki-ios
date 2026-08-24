import XCTest

final class osrsUpdatesViewMoreTimingUITests: XCTestCase {
    func testColdViewMoreTapToFirstRow() throws {
        measureViewMore(label: "cold")
    }

    func testWarmViewMoreTapToFirstRow() throws {
        // Second independent launch; wiki HTTP cache is warm from the cold cell.
        measureViewMore(label: "warm")
    }

    private func measureViewMore(label: String, app: XCUIApplication? = nil, relaunch: Bool = true) {
        let app = app ?? {
            let launched = XCUIApplication()
            if relaunch {
                launched.terminate()
                launched.launch()
            }
            return launched
        }()
        _ = app.wait(for: .runningForeground, timeout: 8)
        revealAndTapViewMore(in: app, startClock: true)
    }

    private func revealAndTapViewMore(in app: XCUIApplication, startClock: Bool = false) {
        let viewMore = app.descendants(matching: .any)["home_updates_view_more"].firstMatch
        if !viewMore.waitForExistence(timeout: 4) || !viewMore.isHittable {
            let carousel = app.scrollViews["home_updates_carousel"].firstMatch
            if carousel.waitForExistence(timeout: 8) {
                for _ in 0..<8 {
                    carousel.swipeLeft()
                    if viewMore.isHittable { break }
                }
            }
        }
        XCTAssertTrue(viewMore.waitForExistence(timeout: 12), "View more should exist on Home")
        let t0 = Date()
        viewMore.tap()
        let row = firstUpdatesRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "First updates row should appear")
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        print("LOAD-MINMAX first_updates_list_visible elapsedMs=\(ms) source=ui-test")
        let searchUpdates = app.descendants(matching: .any)["Search updates"].firstMatch
        let field = app.descendants(matching: .any)["immediate_search_input"].firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 6) || searchUpdates.waitForExistence(timeout: 6),
            "Settled chrome must still say Search updates"
        )
    }

    private func firstUpdatesRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "search_result_row_"))
            .firstMatch
    }
}

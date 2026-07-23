import XCTest

final class RecentUpdatesTileVisualCaptureUITests: XCTestCase {
    private var evidenceDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["OSRS_RECENT_UPDATES_TILE_EVIDENCE_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("osrs-recent-updates-tile-evidence")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureRecentUpdatesTilePositions() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-seedHomeFeedForUITests",
            "-startTab",
            "news"
        ]
        app.launch()

        let updatesHeader = app.staticTexts["home_updates_section"]
        XCTAssertTrue(updatesHeader.waitForExistence(timeout: 20), "Updates section should render")

        let carousel = app.scrollViews["home_updates_carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5), "Updates carousel should render")

        try saveScreenshot(named: "pre-fix-xctest-updates-initial.png")
        try saveFrames(app: app, named: "pre-fix-xctest-frames-initial.txt")

        let cards = app.buttons.matching(identifier: "home_update_card")
        XCTAssertGreaterThanOrEqual(cards.count, 3, "Seeded Home feed should expose at least three update cards")

        let carouselFrame = carousel.frame
        let cardFrames = [
            cards.element(boundBy: 0).frame,
            cards.element(boundBy: 1).frame,
            cards.element(boundBy: 2).frame
        ]
        let heights = cardFrames.map(\.height)
        let heightSpread = (heights.max() ?? 0) - (heights.min() ?? 0)

        for (index, frame) in cardFrames.enumerated() {
            XCTAssertLessThanOrEqual(frame.maxY, carouselFrame.maxY + 2, "Update tile \(index) should not protrude below the carousel")
        }
        XCTAssertLessThanOrEqual(carouselFrame.height, 240, "Update tile carousel should stay near the Android recent-update card height")
        XCTAssertLessThanOrEqual(heightSpread, 24, "Update tiles should keep a consistent visual height")

        carousel.swipeLeft()
        Thread.sleep(forTimeInterval: 0.8)
        try saveScreenshot(named: "pre-fix-xctest-updates-after-one-swipe.png")
        try saveFrames(app: app, named: "pre-fix-xctest-frames-after-one-swipe.txt")

        carousel.swipeLeft()
        Thread.sleep(forTimeInterval: 0.8)
        try saveScreenshot(named: "pre-fix-xctest-updates-after-two-swipes.png")
        try saveFrames(app: app, named: "pre-fix-xctest-frames-after-two-swipes.txt")
    }

    private func saveScreenshot(named filename: String) throws {
        let url = evidenceDirectory.appendingPathComponent("raw").appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func saveFrames(app: XCUIApplication, named filename: String) throws {
        let url = evidenceDirectory.appendingPathComponent("text").appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("window=\(app.windows.firstMatch.frame)")
        let updatesHeader = app.staticTexts["home_updates_section"]
        let carousel = app.scrollViews["home_updates_carousel"]
        lines.append("updates_header=\(updatesHeader.frame)")
        lines.append("carousel=\(carousel.frame)")

        let cards = app.buttons.matching(identifier: "home_update_card")
        lines.append("card_count=\(cards.count)")
        for index in 0..<min(cards.count, 8) {
            let card = cards.element(boundBy: index)
            lines.append("card[\(index)].exists=\(card.exists)")
            lines.append("card[\(index)].frame=\(card.frame)")
            lines.append("card[\(index)].label=\(card.label)")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

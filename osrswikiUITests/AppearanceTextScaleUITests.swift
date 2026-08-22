import XCTest

final class AppearanceTextScaleUITests: XCTestCase {
    func testAppearanceTextScaleGrowsSettingsChromeImmediately() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab", "more",
            "-startMoreDestination", "appearance",
            "-forceThemeForUITests", "osrs_light",
            "-resetReaderPreferencesForUITests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 10))

        let sizeLabel = app.descendants(matching: .any)["appearance_article_text_size_label"].firstMatch
        XCTAssertTrue(sizeLabel.waitForExistence(timeout: 8))
        for _ in 0..<6 where !sizeLabel.isHittable {
            app.swipeUp()
        }
        let beforeHeight = sizeLabel.frame.height
        let beforeScreen = XCTAttachment(screenshot: app.screenshot())
        beforeScreen.name = "appearance-text-scale-100"
        beforeScreen.lifetime = .keepAlways
        add(beforeScreen)

        let slider = app.sliders["appearance_article_text_scale"]
        XCTAssertTrue(slider.waitForExistence(timeout: 8))
        for _ in 0..<6 where !slider.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(slider.isHittable, "Text-size slider must be reachable on Appearance")
        slider.adjust(toNormalizedSliderPosition: 1.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        XCTAssertTrue(
            app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 5),
            "Adjusting text size must stay on Appearance"
        )
        let afterLabel = app.descendants(matching: .any)["appearance_article_text_size_label"].firstMatch
        XCTAssertTrue(afterLabel.waitForExistence(timeout: 5), "Text-size label must remain in the tree after scaling")
        let afterHeight = afterLabel.frame.height
        let afterScreen = XCTAttachment(screenshot: app.screenshot())
        afterScreen.name = "appearance-text-scale-140"
        afterScreen.lifetime = .keepAlways
        add(afterScreen)

        XCTAssertGreaterThan(
            afterHeight,
            beforeHeight + 1,
            "Appearance chrome must grow with the text-size slider; article-only CSS is a partial application. before=\(beforeHeight) after=\(afterHeight)"
        )
    }
}

import UIKit
import XCTest

/// Regression: Appearance dark→light (and similar) must retint labels and ON
/// switches immediately, without leaving the page.
final class AppearanceThemeHotSwapUITests: XCTestCase {
    func testAppearanceDarkToLightHotSwapsLabelsNumberingAndOnSwitches() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab", "more",
            "-startMoreDestination", "appearance",
            "-forceThemeForUITests", "osrs_dark",
            "-resetReaderPreferencesForUITests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 10))

        let themeLabel = app.staticTexts["Theme"].firstMatch
        XCTAssertTrue(themeLabel.waitForExistence(timeout: 8))
        let themeValue = app.staticTexts["Dark"].firstMatch
        XCTAssertTrue(themeValue.waitForExistence(timeout: 8), "Theme value should read Dark")
        let floorValue = app.staticTexts["Auto detect"].firstMatch
        XCTAssertTrue(floorValue.waitForExistence(timeout: 8), "Floor numbering value should read Auto detect")
        let onSwitch = app.switches["appearance_swipe_right_back_toggle"]
        XCTAssertTrue(onSwitch.waitForExistence(timeout: 8))
        XCTAssertEqual(onSwitch.value as? String, "1", "Swipe-back should start ON")

        let darkThemeValue = try XCTUnwrap(themeValue.screenshot().image.cgImage)
        let darkFloorValue = try XCTUnwrap(floorValue.screenshot().image.cgImage)
        let darkSwitch = try XCTUnwrap(onSwitch.screenshot().image.cgImage)
        let darkScreen = XCTAttachment(screenshot: app.screenshot())
        darkScreen.name = "appearance-hotswap-before-dark"
        darkScreen.lifetime = .keepAlways
        add(darkScreen)

        let themePicker = app.descendants(matching: .any)["appearance_theme_picker"].firstMatch
        XCTAssertTrue(themePicker.waitForExistence(timeout: 8))
        themePicker.tap()
        let lightChoice = app.buttons["Light"].firstMatch.exists
            ? app.buttons["Light"].firstMatch
            : app.staticTexts["Light"].firstMatch
        XCTAssertTrue(lightChoice.waitForExistence(timeout: 5), "Theme menu should expose Light")
        lightChoice.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8),
            "Theme switch must stay on Appearance"
        )
        XCTAssertTrue(
            app.staticTexts["Light"].waitForExistence(timeout: 5) ||
                themePicker.label.contains("Light"),
            "Selected theme value should read Light immediately"
        )

        // Hot-swap is supposed to be immediate. Give the run loop a beat for
        // the live UIKit walk, but do not leave and re-enter the page.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let lightThemeValue = app.staticTexts["Light"].firstMatch
        XCTAssertTrue(lightThemeValue.waitForExistence(timeout: 5))
        let lightThemePixels = try XCTUnwrap(lightThemeValue.screenshot().image.cgImage)
        let lightFloorPixels = try XCTUnwrap(floorValue.screenshot().image.cgImage)
        let lightSwitch = try XCTUnwrap(onSwitch.screenshot().image.cgImage)
        let lightScreen = XCTAttachment(screenshot: app.screenshot())
        lightScreen.name = "appearance-hotswap-after-light"
        lightScreen.lifetime = .keepAlways
        add(lightScreen)

        XCTAssertTrue(
            hasDarkInk(lightThemePixels),
            "Picker values like Light/Dark must use light-theme ink immediately; cream-on-parchment is a regression"
        )
        XCTAssertTrue(
            hasDarkInk(lightFloorPixels),
            "Floor numbering values (Auto/UK/US) must use light-theme ink immediately"
        )
        XCTAssertFalse(
            imagesMatch(darkThemeValue, lightThemePixels),
            "Theme value pixels must change on dark→light without leave/re-enter"
        )
        XCTAssertFalse(
            imagesMatch(darkFloorValue, lightFloorPixels),
            "Floor numbering value pixels must change on dark→light without leave/re-enter"
        )
        XCTAssertFalse(
            imagesMatch(darkSwitch, lightSwitch),
            "ON switch must retint immediately so it is not a leftover dark-theme pill"
        )
        XCTAssertGreaterThan(
            contrastRange(lightSwitch),
            70,
            "ON switch must read as thumb-in-track after light hot-swap, not one uniform pill"
        )
    }
}

private func hasDarkInk(_ image: CGImage) -> Bool {
    inkLumaPercentile(image, percentile: 0.15) < 110
}

private func inkLumaPercentile(_ image: CGImage, percentile: Double) -> Int {
    let samples = sampledLumas(image)
    guard !samples.isEmpty else { return 255 }
    let sorted = samples.sorted()
    let index = min(sorted.count - 1, max(0, Int(Double(sorted.count) * percentile)))
    return sorted[index]
}

private func contrastRange(_ image: CGImage) -> Int {
    let samples = sampledLumas(image)
    guard let minLuma = samples.min(), let maxLuma = samples.max() else { return 0 }
    return maxLuma - minLuma
}

private func sampledLumas(_ image: CGImage) -> [Int] {
    let width = 32
    let height = 32
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return []
    }
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var lumas: [Int] = []
    lumas.reserveCapacity(width * height)
    for index in 0..<(width * height) {
        let offset = index * 4
        let alpha = Int(pixels[offset + 3])
        guard alpha > 16 else { continue }
        lumas.append((Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3)
    }
    return lumas
}

private func imagesMatch(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
    sampledLumas(lhs) == sampledLumas(rhs)
}

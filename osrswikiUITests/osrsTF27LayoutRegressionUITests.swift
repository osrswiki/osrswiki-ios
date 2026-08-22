import UIKit
import XCTest

/// Device-feedback regressions from iOS TF 27 / Android VC 33.
final class osrsTF27LayoutRegressionUITests: XCTestCase {
    func testMoreAppearanceSwipeBackDoesNotStackALeftGutter() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab", "more",
            "-startMoreDestination", "appearance"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 10))

        swipeBackFromAppearance(in: app)
        let more = app.descendants(matching: .any)["more_screen"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 8), "First swipe-back should return to More")
        XCTAssertLessThan(more.frame.minX, 8, "More must restore full-width chrome after swipe-back")

        let appearanceRow = app.descendants(matching: .any)["more_appearance"].firstMatch
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 6))
        appearanceRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8))

        swipeBackFromAppearance(in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 8), "Second swipe-back should return to More")
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 6))
        XCTAssertLessThan(
            appearanceRow.frame.minX,
            32,
            "Repeating swipe-back must not stack a left gutter"
        )
        XCTAssertGreaterThan(
            appearanceRow.frame.width,
            app.windows.firstMatch.frame.width * 0.55,
            "More rows must keep full-width chrome after stacked swipe-backs"
        )
    }

    func testMapFloorControlSitsAboveTheBottomBar() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab", "map"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["map_screen"].waitForExistence(timeout: 10))

        let floor = app.descendants(matching: .any)["realm_floor_control"].firstMatch
        XCTAssertTrue(floor.waitForExistence(timeout: 20), "Multi-plane realm should show the floor selector")

        let tabBar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch : app.otherElements["map_screen"]
        let bottomChromeMinY: CGFloat
        if app.tabBars.firstMatch.exists {
            bottomChromeMinY = app.tabBars.firstMatch.frame.minY
        } else {
            bottomChromeMinY = app.frame.maxY - 80
        }
        XCTAssertLessThanOrEqual(
            floor.frame.maxY,
            bottomChromeMinY + 4,
            "Floor control must sit above the map/tab bottom bar, not under it"
        )
        _ = tabBar
    }

    func testArticleAppearanceThemeReloadPaintsTheNewTheme() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-forceThemeForUITests", "osrs_light",
            "-startArticleTitle", "Amulet of glory",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Amulet_of_glory"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let webView = app.webViews["article_web_view"].exists
            ? app.webViews["article_web_view"]
            : app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "Glory article should open")
        waitUntilArticleSettles(webView)

        let lightLuma = averageLuma(try XCTUnwrap(webView.screenshot().image.cgImage))
        XCTAssertGreaterThan(lightLuma, 140, "Light theme Glory should paint parchment, not dark fill")

        let appearance = app.buttons["Appearance"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 8), "Article bottom-bar Appearance should exist")
        appearance.tap()
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8))

        let themePicker = app.descendants(matching: .any)["appearance_theme_picker"].firstMatch
        XCTAssertTrue(themePicker.waitForExistence(timeout: 8))
        themePicker.tap()
        let darkChoice = app.buttons["Dark"].firstMatch.exists
            ? app.buttons["Dark"].firstMatch
            : app.staticTexts["Dark"].firstMatch
        XCTAssertTrue(darkChoice.waitForExistence(timeout: 5))
        darkChoice.tap()

        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 4) {
            done.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(webView.waitForExistence(timeout: 8))

        openArticleOverflowMenu(in: app)
        let refresh = app.buttons["Refresh Page"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 6))
        refresh.tap()
        waitUntilArticleSettles(webView)

        let darkLuma = averageLuma(try XCTUnwrap(webView.screenshot().image.cgImage))
        XCTAssertLessThan(
            darkLuma,
            lightLuma - 20,
            "Reloading after Appearance dark must paint dark article colors, not the previous light first-paint"
        )
    }

    func testGloryInfoboxFitsTheSimulatorViewport() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startArticleTitle", "Amulet of glory",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Amulet_of_glory"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let webView = app.webViews["article_web_view"].exists
            ? app.webViews["article_web_view"]
            : app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))
        waitUntilArticleSettles(webView)

        XCTAssertLessThanOrEqual(
            webView.frame.width,
            app.frame.width + 1,
            "Glory article WebView must not overflow the viewport"
        )
        let screenshot = try XCTUnwrap(webView.screenshot().image.cgImage)
        XCTAssertGreaterThan(
            contrastRange(screenshot),
            24,
            "Glory must render article contrast, not a collapsed/malformed blank table fill"
        )
    }

    private func swipeBackFromAppearance(in app: XCUIApplication) {
        let screen = app.descendants(matching: .any)["appearance_screen"].firstMatch
        let start = screen.exists
            ? screen.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
            : app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
        let end = screen.exists
            ? screen.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.55))
            : app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.55))
        start.press(
            forDuration: 0.08,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(160),
            thenHoldForDuration: 0.05
        )
    }

    private func openArticleOverflowMenu(in app: XCUIApplication) {
        let ellipsis = app.buttons["ellipsis"].firstMatch
        if ellipsis.waitForExistence(timeout: 5) {
            ellipsis.tap()
            return
        }
        let more = app.buttons["More"].firstMatch
        if more.waitForExistence(timeout: 5) {
            more.tap()
            return
        }
        XCTFail("Article overflow menu button should exist")
    }

    private func waitUntilArticleSettles(_ webView: XCUIElement) {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if webView.exists, webView.frame.height > 100 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func averageLuma(_ image: CGImage) -> Double {
        let samples = sampledLumas(image)
        guard !samples.isEmpty else { return 0 }
        return Double(samples.reduce(0, +)) / Double(samples.count)
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
}

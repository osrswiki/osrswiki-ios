import UIKit
import XCTest

/// Article-presented Appearances: swipe-down stays dismissed, theme switch
/// leaves a navigable article, and More → Appearance still works.
final class osrsArticleAppearanceSheetUITests: XCTestCase {
    func testArticleAppearanceSwipeDownStaysDismissed() {
        let app = launchArticle()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let webView = articleWebView(in: app)
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "Article web view should open")
        waitUntilArticleSettles(webView)

        for cycle in 1...2 {
            openAppearanceFromArticle(in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8),
                "Cycle \(cycle): Appearances should present from the article"
            )
            swipeDownAppearanceSheet(in: app)
            let gone = waitForAbsence(app.descendants(matching: .any)["appearance_screen"], timeout: 6)
            if !gone {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "article-appearance-swipe-miss-cycle-\(cycle)"
                shot.lifetime = .keepAlways
                add(shot)
                XCTFail(
                    "Cycle \(cycle): XCUI swipe-down did not dismiss the sheet (grabber miss). Unit tests cover interactive dismiss intent."
                )
                dismissAppearance(in: app)
                continue
            }
            XCTAssertTrue(webView.waitForExistence(timeout: 8), "Cycle \(cycle): article web view remains")
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            XCTAssertFalse(
                app.descendants(matching: .any)["appearance_screen"].exists,
                "Cycle \(cycle): Appearances must not bounce back after dismiss"
            )
        }
    }

    func testArticleAppearanceThemeSwitchKeepsNavigableArticle() throws {
        let app = launchArticle()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let webView = articleWebView(in: app)
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "Article web view should open")
        waitUntilArticleSettles(webView)

        let themes = ["Dark", "Light", "Follow system"]
        for (index, themeName) in themes.enumerated() {
            openAppearanceFromArticle(in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8),
                "Theme \(themeName) should open Appearances"
            )
            pickTheme(themeName, in: app)
            dismissAppearance(in: app)
            XCTAssertTrue(
                waitForAbsence(app.descendants(matching: .any)["appearance_screen"], timeout: 6),
                "After \(themeName), Appearances should dismiss"
            )
            XCTAssertEqual(app.state, .runningForeground, "Theme \(themeName) must not kill the process")
            XCTAssertTrue(webView.waitForExistence(timeout: 8), "Article web view after \(themeName)")
            waitUntilArticleSettles(webView)
            let pixels = try XCTUnwrap(webView.screenshot().image.cgImage)
            XCTAssertGreaterThan(
                contrastRange(pixels),
                24,
                "Theme \(themeName) must paint article content, not a uniform empty fill"
            )
            let chrome = articleChrome(in: app)
            XCTAssertTrue(
                chrome.waitForExistence(timeout: 8),
                "Article chrome must remain after \(themeName)"
            )
            XCTAssertTrue(chrome.isHittable || app.buttons["Appearance"].firstMatch.isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "article-appearance-theme-\(index)-\(themeName.replacingOccurrences(of: " ", with: "-"))"
            shot.lifetime = .keepAlways
            add(shot)
        }

        openAppearanceFromArticle(in: app)
        pickTheme("Dark", in: app)
        dismissAppearance(in: app)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(webView.waitForExistence(timeout: 8))
        let secondPixels = try XCTUnwrap(webView.screenshot().image.cgImage)
        XCTAssertGreaterThan(contrastRange(secondPixels), 24)
    }

    func testMoreAppearanceStillPresentsChangesThemeAndReturns() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab", "more",
            "-startMoreDestination", "appearance",
            "-forceThemeForUITests", "osrs_light"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 10))

        let themePicker = app.descendants(matching: .any)["appearance_theme_picker"].firstMatch
        XCTAssertTrue(themePicker.waitForExistence(timeout: 8))
        themePicker.tap()
        let dark = app.buttons["Dark"].firstMatch.exists
            ? app.buttons["Dark"].firstMatch
            : app.staticTexts["Dark"].firstMatch
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        dark.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["appearance_screen"].waitForExistence(timeout: 8),
            "Theme switch on More Appearance must stay on the page"
        )

        if app.navigationBars.buttons["More"].firstMatch.waitForExistence(timeout: 3) {
            app.navigationBars.buttons["More"].firstMatch.tap()
        } else if app.buttons["Back"].firstMatch.waitForExistence(timeout: 2) {
            app.buttons["Back"].firstMatch.tap()
        } else {
            app.swipeRight()
        }
        let more = app.descendants(matching: .any)["more_screen"].firstMatch
        let appearanceRow = app.descendants(matching: .any)["more_appearance"].firstMatch
        XCTAssertTrue(
            more.waitForExistence(timeout: 8) || appearanceRow.waitForExistence(timeout: 8),
            "Leaving Appearance must return to More"
        )
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "more-appearance-regression"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launchArticle() -> XCUIApplication {
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
        return app
    }

    private func articleWebView(in app: XCUIApplication) -> XCUIElement {
        app.webViews["article_web_view"].exists ? app.webViews["article_web_view"] : app.webViews.firstMatch
    }

    private func articleChrome(in app: XCUIApplication) -> XCUIElement {
        if app.descendants(matching: .any)["article_bottom_bar"].firstMatch.exists {
            return app.descendants(matching: .any)["article_bottom_bar"].firstMatch
        }
        return app.buttons["Appearance"].firstMatch
    }

    private func openAppearanceFromArticle(in app: XCUIApplication) {
        let appearance = app.buttons["Appearance"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 10), "Article bottom-bar Appearance should exist")
        appearance.tap()
    }

    private func swipeDownAppearanceSheet(in app: XCUIApplication) {
        let window = app.windows.firstMatch.exists ? app.windows.firstMatch : app
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        let starts: [CGFloat] = [0.08, 0.04, 0.14]
        for y in starts {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            start.press(
                forDuration: 0.01,
                thenDragTo: end,
                withVelocity: XCUIGestureVelocity(2_400),
                thenHoldForDuration: 0
            )
            if waitForAbsence(app.descendants(matching: .any)["appearance_screen"], timeout: 1.2) {
                return
            }
        }
    }

    private func pickTheme(_ name: String, in app: XCUIApplication) {
        let themePicker = app.descendants(matching: .any)["appearance_theme_picker"].firstMatch
        XCTAssertTrue(themePicker.waitForExistence(timeout: 8))
        themePicker.tap()
        let choice = app.buttons[name].firstMatch.exists
            ? app.buttons[name].firstMatch
            : app.staticTexts[name].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Theme menu should expose \(name)")
        choice.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func dismissAppearance(in app: XCUIApplication) {
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) {
            done.tap()
        } else {
            swipeDownAppearanceSheet(in: app)
        }
    }

    private func waitUntilArticleSettles(_ webView: XCUIElement) {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if webView.exists, webView.frame.height > 100 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return !element.exists
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
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: 32))
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

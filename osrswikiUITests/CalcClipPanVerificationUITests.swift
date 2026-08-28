import XCTest

/// Throwaway device-verification driver for job calc-clip-pan-ip (4325).
/// It only produces deterministic gestures; the verdicts are read from the
/// `-osrsCalcProbeLog` dump afterwards. Delete before land unless promoted.
final class CalcClipPanVerificationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(article: String, url: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsCalcProbeLog",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab", "search",
            "-startArticleTitle", article,
            "-startArticleURL", url,
            "-allowProxyStartupDuringTests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        return app
    }

    private func drag(_ app: XCUIApplication, fromY: CGFloat, toY: CGFloat, x: CGFloat = 0.7) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: fromY))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: toY))
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.05)
        Thread.sleep(forTimeInterval: 0.8)
    }

    func testAgilityPanThroughGrid() throws {
        let app = launch(
            article: "Calculator:Agility",
            url: "https://oldschool.runescape.wiki/w/Calculator:Agility"
        )
        // Cold first open: let the calc install and the probe observe the
        // cold DOM race (flash check lives in this window of the log).
        Thread.sleep(forTimeInterval: 14)

        // Scroll the calculator into view (these are article-scroll controls).
        for _ in 0..<3 {
            drag(app, fromY: 0.75, toY: 0.35, x: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        // Pan grid across the calc region; the probe log classifies each.
        drag(app, fromY: 0.30, toY: 0.20)
        drag(app, fromY: 0.20, toY: 0.30)
        drag(app, fromY: 0.45, toY: 0.35)
        drag(app, fromY: 0.35, toY: 0.45)
        drag(app, fromY: 0.60, toY: 0.50)
        drag(app, fromY: 0.75, toY: 0.65)
        Thread.sleep(forTimeInterval: 1)

        // Control interactivity must survive the hit-testing change: tapping
        // a field should still focus it and raise the keyboard.
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5), field.isHittable {
            field.tap()
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertGreaterThan(
                app.keyboards.count, 0,
                "tapping a calc field must still focus it after the hit-test change"
            )
            // Residual documentation: a drag starting on the field.
            let fieldStart = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let fieldEnd = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            fieldStart.press(forDuration: 0.08, thenDragTo: fieldEnd, withVelocity: 300, thenHoldForDuration: 0.05)
            Thread.sleep(forTimeInterval: 1)
            if app.keyboards.buttons["Hide keyboard"].firstMatch.exists {
                app.keyboards.buttons["Hide keyboard"].firstMatch.tap()
            } else {
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            }
        }
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
    }

    func testCombatIntrinsicHeight() throws {
        let app = launch(
            article: "Calculator:Combat level",
            url: "https://oldschool.runescape.wiki/w/Calculator:Combat_level"
        )
        Thread.sleep(forTimeInterval: 12)
        for _ in 0..<2 {
            drag(app, fromY: 0.75, toY: 0.40, x: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)
        drag(app, fromY: 0.45, toY: 0.35)
        drag(app, fromY: 0.60, toY: 0.50)
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
    }
}

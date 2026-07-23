//
//  IOS02WebKitBridgeSmokeUITests.swift
//  osrswikiUITests
//

import XCTest

final class IOS02WebKitBridgeSmokeUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 10
    private let articleLoadTimeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTrustedArticleLoadsWithHardenedWebKitBridge() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "search",
            "-startArticleTitle",
            "Varrock",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/Varrock",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: articleLoadTimeout))
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists)
    }
}

//
//  SavedPagesNavigationTest.swift
//  osrswikiUITests
//
//  Created for testing saved pages in-app navigation fix
//  Ensures saved pages open in ArticleView instead of external Safari browser
//

import XCTest

class SavedPagesNavigationTest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-startTab", "saved",
            "-resetSavedPagesForUITests",
            "-seedSavedPagesForUITests"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 10), "Seeded saved page should be visible")
    }

    func testSavedPageOpensInAppNotSafari() throws {
        // CRITICAL TEST: Ensure saved pages use in-app navigation instead of opening Safari

        print("🧪 Starting saved pages navigation test")

        let savedTab = tabButton(identifier: "saved_tab", label: "Saved tab")
        XCTAssertTrue(savedTab.exists, "Saved tab should exist")

        let savedHeader = app.staticTexts["Saved"]
        XCTAssertTrue(savedHeader.exists, "Saved header should exist")

        print("🧪 Saved pages navigation structure verified")

        let beforeTapState = app.state
        app.staticTexts["Varrock"].tap()

        let articleWebView = app.webViews.firstMatch
        XCTAssertTrue(articleWebView.waitForExistence(timeout: 20), "Tapping a saved page should open an in-app article WebView")
        XCTAssertEqual(beforeTapState, app.state, "Should remain in the same app, not switch to Safari")
    }

    func testSavedPagesViewModelHasAppState() throws {
        // Test that verifies our fix is in place by checking the navigation structure

        let savedTab = tabButton(identifier: "saved_tab", label: "Saved tab")
        savedTab.tap()

        // Verify the saved pages view loads correctly
        // This indirectly tests that our AppState injection is working
        let savedHeader = app.staticTexts["Saved"]
        XCTAssertTrue(savedHeader.exists, "Saved header should be present")

        let searchSavedPages = app.buttons["Search saved pages"]
        XCTAssertTrue(searchSavedPages.waitForExistence(timeout: 5), "Saved pages search entry point should exist")
        searchSavedPages.tap()

        let searchDestination = app.staticTexts["Search Saved Pages"]
        XCTAssertTrue(searchDestination.waitForExistence(timeout: 5), "Saved pages search should navigate through saved AppState")
    }

    func testNavigationStackIntegrity() throws {
        // Test to ensure saved pages are properly integrated with the navigation system

        let savedTab = tabButton(identifier: "saved_tab", label: "Saved tab")
        savedTab.tap()

        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5), "Saved tab content should be visible")

        // Verify other tabs are accessible (indicating navigation is not broken)
        let homeTab = tabButton(identifier: "news_tab", label: "Home tab")
        let mapTab = tabButton(identifier: "map_tab", label: "Map tab")

        XCTAssertTrue(homeTab.exists, "Home tab should be accessible")
        XCTAssertTrue(mapTab.exists, "Map tab should be accessible")

        // Quick test: switch to another tab and back
        homeTab.tap()
        XCTAssertTrue(app.buttons["Search OSRS Wiki"].waitForExistence(timeout: 10), "Should switch to Home tab")

        savedTab.tap()
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 5), "Should switch back to Saved tab")

        print("🧪 Navigation stack integrity verified")
    }

    private func tabButton(identifier: String, label: String) -> XCUIElement {
        let byIdentifier = app.buttons[identifier]
        if byIdentifier.waitForExistence(timeout: 5) {
            return byIdentifier
        }

        let byLabel = app.buttons[label]
        if byLabel.waitForExistence(timeout: 1) {
            return byLabel
        }

        return app.buttons[label.replacingOccurrences(of: " tab", with: "")]
    }
}

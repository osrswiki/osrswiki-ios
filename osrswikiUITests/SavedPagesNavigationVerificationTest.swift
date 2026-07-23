//
//  SavedPagesNavigationVerificationTest.swift
//  osrswikiUITests
//
//  Created for iOS Saved Pages Navigation Fix Testing
//

import XCTest

/// Test to verify that saved pages navigation works correctly and loads in-app instead of Safari
final class SavedPagesNavigationVerificationTest: XCTestCase {

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

        print("🧪 SavedPagesNavigationVerificationTest: App launched")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App failed to launch properly")
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 10), "Seeded saved page should be visible")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Test that saved pages tab can be accessed and displays properly
    func testSavedPagesTabAccess() throws {
        print("🧪 Testing saved pages tab access")

        // Navigate to saved pages tab
        let savedTabButton = findSavedPagesTab()
        XCTAssertTrue(savedTabButton.exists, "Saved pages tab button should exist")

        print("🧪 Tapping saved pages tab")
        savedTabButton.tap()

        // Give time for tab to load
        Thread.sleep(forTimeInterval: 2.0)

        // Verify we're on the saved pages screen
        XCTAssertTrue(app.staticTexts["Varrock"].exists, "Seeded saved page should be visible")

        print("✅ SavedPagesNavigationVerificationTest: Successfully accessed saved pages tab")
    }

    /// Test that if saved pages exist, tapping them opens in-app ArticleView instead of Safari
    func testSavedPageInAppNavigation() throws {
        print("🧪 Testing saved page in-app navigation")

        // Navigate to saved pages tab
        let savedTabButton = findSavedPagesTab()
        savedTabButton.tap()
        Thread.sleep(forTimeInterval: 2.0)

        let firstSavedPage = app.staticTexts["Varrock"]
        XCTAssertTrue(firstSavedPage.waitForExistence(timeout: 5), "Seeded saved page should exist")

        print("🧪 Tapping first saved page to test navigation")
        firstSavedPage.tap()

        let articleWebView = app.webViews.firstMatch
        XCTAssertTrue(articleWebView.waitForExistence(timeout: 20), "Expected to find article WebView after tapping saved page")
        XCTAssertTrue(app.state == .runningForeground, "App should remain in foreground (not switched to Safari)")
    }

    /// Test the error handling - verify error messages are shown instead of white screen
    func testSavedPagesErrorHandling() throws {
        print("🧪 Testing saved pages error handling")

        // Navigate to saved pages tab
        let savedTabButton = findSavedPagesTab()
        savedTabButton.tap()
        Thread.sleep(forTimeInterval: 2.0)

        let firstSavedPage = app.staticTexts["Varrock"]
        XCTAssertTrue(firstSavedPage.waitForExistence(timeout: 5), "Seeded saved page should exist")
        firstSavedPage.tap()

        let errorText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Failed to Load'")).firstMatch
        let retryButton = app.buttons["Retry"]
        let articleWebView = app.webViews.firstMatch
        let loadedOrHandled = articleWebView.waitForExistence(timeout: 20) ||
            errorText.waitForExistence(timeout: 1) ||
            retryButton.waitForExistence(timeout: 1)

        XCTAssertTrue(loadedOrHandled, "Saved page should either load in-app or show a visible error state")
    }

    // MARK: - Helper Methods

    /// Find the saved pages tab button using various possible identifiers
    private func findSavedPagesTab() -> XCUIElement {
        // Try different ways to find the saved pages tab
        let possibleIdentifiers = [
            "saved_tab",
            "Saved tab",
            "Saved",
            "SavedPages",
            "Saved Pages"
        ]

        for identifier in possibleIdentifiers {
            let tabButton = app.buttons[identifier]
            if tabButton.exists {
                print("🧪 Found saved pages tab with identifier: \(identifier)")
                return tabButton
            }
        }

        // Try by position if identifiers don't work (assuming it's typically the 3rd tab)
        let tabButtons = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '_tab'"))
        if tabButtons.count > 1 {
            let secondTab = tabButtons.element(boundBy: 1)
            if secondTab.exists {
                print("🧪 Found saved pages tab by position (2nd custom tab)")
                return secondTab
            }
        }

        // Fallback - return first matching button even if it might not be the right one
        print("⚠️ Could not find saved pages tab by identifier or position, using fallback")
        return app.buttons["saved_tab"]
    }
}

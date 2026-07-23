//
//  SavedPagesUICleanupTest.swift
//  osrswikiUITests
//
//  Created for testing saved pages UI cleanup changes
//

import XCTest

class SavedPagesUICleanupTest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-startTab", "saved",
            "-resetSavedPagesForUITests"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")
        XCTAssertTrue(app.staticTexts["No Saved Pages"].waitForExistence(timeout: 10), "Saved empty state should be visible")
    }

    func testSavedTabTitleIsShortened() {
        // Navigate to the Saved tab
        let savedTab = tabButton(identifier: "saved_tab", label: "Saved tab")
        XCTAssertTrue(savedTab.exists, "Saved tab should exist")
        savedTab.tap()

        // Wait for the view to load
        Thread.sleep(forTimeInterval: 2)

        // Check that the header title is "Saved" (not "Saved Pages")
        let savedTitle = app.staticTexts["Saved"]
        XCTAssertTrue(savedTitle.exists, "Header should show 'Saved' title")

        // Verify that "Saved Pages" text doesn't exist
        let savedPagesTitle = app.staticTexts["Saved Pages"]
        XCTAssertFalse(savedPagesTitle.exists, "Header should not show 'Saved Pages' title")
    }

    func testBrowseWikiButtonRemoved() {
        // Navigate to the Saved tab
        let savedTab = tabButton(identifier: "saved_tab", label: "Saved tab")
        XCTAssertTrue(savedTab.exists, "Saved tab should exist")
        savedTab.tap()

        // Wait for the view to load
        Thread.sleep(forTimeInterval: 2)

        // Verify the empty state is shown (bookmark icon and "No Saved Pages" text)
        let noSavedPagesText = app.staticTexts["No Saved Pages"]
        XCTAssertTrue(noSavedPagesText.exists, "Empty state should show 'No Saved Pages'")

        let emptyStateDescription = app.staticTexts["Save pages while browsing to build your personal reading list"]
        XCTAssertTrue(emptyStateDescription.exists, "Empty state should show description text")

        // Verify that "Browse Wiki" button does NOT exist
        let browseWikiButton = app.buttons["Browse Wiki"]
        XCTAssertFalse(browseWikiButton.exists, "Browse Wiki button should not exist")
    }

    func testEmptyStateLayoutWithoutButton() {
        // Navigate to the Saved tab
        let savedTab = tabButton(identifier: "saved_tab", label: "Saved tab")
        savedTab.tap()

        Thread.sleep(forTimeInterval: 2)

        // Check that the empty state shows the bookmark icon
        let bookmarkIcon = app.images.containing(NSPredicate(format: "identifier CONTAINS 'bookmark'")).firstMatch
        XCTAssertTrue(bookmarkIcon.exists || app.otherElements.containing(NSPredicate(format: "identifier CONTAINS 'bookmark'")).firstMatch.exists, "Empty state should show bookmark icon")

        // Verify the key text elements exist
        XCTAssertTrue(app.staticTexts["No Saved Pages"].exists, "Should show 'No Saved Pages' text")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'personal reading list'")).firstMatch.exists, "Should show description about building reading list")

        // Most importantly: verify Browse Wiki button is gone
        XCTAssertFalse(app.buttons["Browse Wiki"].exists, "Browse Wiki button should be completely removed")
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

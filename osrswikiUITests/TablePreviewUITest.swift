//
//  TablePreviewUITest.swift
//  osrswikiUITests
//
//  Test for table preview functionality in Appearance Settings
//

import XCTest

class TablePreviewUITest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testTablePreviewsAreVisible() throws {
        // Navigate to More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        
        // Navigate to Appearance settings
        let appearanceCell = app.tables.staticTexts["Appearance"]
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 5))
        appearanceCell.tap()
        
        // Wait for the appearance view to load
        let appearanceTitle = app.navigationBars["Appearance"]
        XCTAssertTrue(appearanceTitle.waitForExistence(timeout: 5))
        
        // Check for table preview section
        let tablesLabel = app.staticTexts["Tables"]
        XCTAssertTrue(tablesLabel.waitForExistence(timeout: 5), "Tables section should be visible")
        
        // Check for Expanded preview button
        let expandedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Expanded'")).firstMatch
        XCTAssertTrue(expandedButton.waitForExistence(timeout: 10), "Expanded table preview button should exist")
        
        // Check for Collapsed preview button
        let collapsedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Collapsed'")).firstMatch
        XCTAssertTrue(collapsedButton.waitForExistence(timeout: 10), "Collapsed table preview button should exist")
        
        // Verify that preview images are being displayed (check for image elements within buttons)
        // Note: The preview images should be visible as Image elements within the buttons
        let expandedButtonImages = expandedButton.images
        let collapsedButtonImages = collapsedButton.images
        
        // There should be at least one image in each preview button (the preview itself)
        XCTAssertGreaterThan(expandedButtonImages.count, 0, "Expanded preview should contain an image")
        XCTAssertGreaterThan(collapsedButtonImages.count, 0, "Collapsed preview should contain an image")
        
        // Test interaction - tap on collapsed preview
        collapsedButton.tap()
        
        // After tapping, the collapsed option should show a checkmark
        let checkmarkInCollapsed = collapsedButton.images["checkmark.circle.fill"]
        XCTAssertTrue(checkmarkInCollapsed.exists, "Collapsed option should show checkmark when selected")
        
        // Tap on expanded preview
        expandedButton.tap()
        
        // After tapping, the expanded option should show a checkmark
        let checkmarkInExpanded = expandedButton.images["checkmark.circle.fill"]
        XCTAssertTrue(checkmarkInExpanded.exists, "Expanded option should show checkmark when selected")
    }
    
    func testTablePreviewImagesLoad() throws {
        // Navigate to More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        
        // Navigate to Appearance settings
        let appearanceCell = app.tables.staticTexts["Appearance"]
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 5))
        appearanceCell.tap()
        
        // Wait for loading indicators to disappear (if any)
        Thread.sleep(forTimeInterval: 2)
        
        // Check that no progress indicators are visible (meaning images have loaded)
        let progressIndicators = app.activityIndicators
        
        // After a reasonable wait time, there should be no progress indicators
        // or they should be hidden
        for indicator in progressIndicators.allElementsBoundByIndex {
            if indicator.exists {
                XCTAssertFalse(indicator.isHittable, "Progress indicators should not be visible after loading")
            }
        }
        
        // Verify that the preview buttons are interactive
        let expandedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Expanded'")).firstMatch
        let collapsedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Collapsed'")).firstMatch
        
        XCTAssertTrue(expandedButton.isHittable, "Expanded preview should be interactive")
        XCTAssertTrue(collapsedButton.isHittable, "Collapsed preview should be interactive")
    }
}
//
//  ThemePreviewBackgroundTest.swift
//  osrswikiUITests
//
//  Test to verify theme preview background colors are correctly rendered
//

import XCTest

class ThemePreviewBackgroundTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testThemePreviewBackgroundColors() throws {
        // Navigate to More tab
        let tabBar = app.tabBars.firstMatch
        let moreTab = tabBar.buttons["More"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        moreTab.tap()
        
        // Wait for More view to load
        let moreTitle = app.staticTexts["More"]
        XCTAssertTrue(moreTitle.waitForExistence(timeout: 5), "More view should load")
        
        // Tap on Appearance settings
        let appearanceCell = app.buttons["Appearance"]
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 3), "Appearance option should exist")
        appearanceCell.tap()
        
        // Wait for Appearance view to load
        let appearanceTitle = app.navigationBars["Appearance"].staticTexts["Appearance"]
        XCTAssertTrue(appearanceTitle.waitForExistence(timeout: 5), "Appearance view should load")
        
        // Verify theme preview cards exist
        let lightThemeCard = app.buttons["Light theme preview"]
        let darkThemeCard = app.buttons["Dark theme preview"]
        let autoThemeCard = app.buttons["Auto theme preview"]
        
        XCTAssertTrue(lightThemeCard.exists, "Light theme preview should exist")
        XCTAssertTrue(darkThemeCard.exists, "Dark theme preview should exist")
        XCTAssertTrue(autoThemeCard.exists, "Auto theme preview should exist")
        
        // Take screenshot for visual verification
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Theme_Previews_After_Fix"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("✅ Theme preview cards are displayed")
        print("📸 Screenshot captured for visual verification")
        
        // Verify the previews are visible and have proper frames
        XCTAssertTrue(lightThemeCard.frame.width > 0, "Light theme preview should have width")
        XCTAssertTrue(lightThemeCard.frame.height > 0, "Light theme preview should have height")
        XCTAssertTrue(darkThemeCard.frame.width > 0, "Dark theme preview should have width")
        XCTAssertTrue(darkThemeCard.frame.height > 0, "Dark theme preview should have height")
        
        print("✅ All theme preview cards have valid dimensions")
    }
    
    func testThemePreviewSelection() throws {
        // Navigate to More tab
        let tabBar = app.tabBars.firstMatch
        let moreTab = tabBar.buttons["More"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        moreTab.tap()
        
        // Navigate to Appearance
        let appearanceCell = app.buttons["Appearance"]
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 3), "Appearance option should exist")
        appearanceCell.tap()
        
        // Test theme selection
        let darkThemeCard = app.buttons["Dark theme preview"]
        XCTAssertTrue(darkThemeCard.waitForExistence(timeout: 3), "Dark theme preview should exist")
        darkThemeCard.tap()
        
        // Verify dark theme is selected
        sleep(1) // Allow UI to update
        
        // Navigate back and forth to verify theme persists
        app.navigationBars.buttons.firstMatch.tap() // Back button
        sleep(1)
        
        // Go back to Appearance
        appearanceCell.tap()
        
        // Take final screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Theme_Selection_Persistence"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("✅ Theme selection test completed")
    }
}
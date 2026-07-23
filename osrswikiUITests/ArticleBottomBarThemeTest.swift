//
//  ArticleBottomBarThemeTest.swift
//  osrswikiUITests
//
//  Test to verify article bottom bar respects theme changes
//

import XCTest

final class ArticleBottomBarThemeTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testArticleBottomBarDarkThemeConsistency() throws {
        // Navigate to More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        
        // Navigate to Appearance settings
        let appearanceCell = app.cells["Appearance"]
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 5))
        appearanceCell.tap()
        
        // Switch to Dark theme
        let darkThemeOption = app.cells["Dark"]
        XCTAssertTrue(darkThemeOption.waitForExistence(timeout: 5))
        darkThemeOption.tap()
        
        // Go back to More tab
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }
        
        // Navigate to Search tab to access articles
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        searchTab.tap()
        
        // Search for an article
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Varrock")
        
        // Tap search button or dismiss keyboard
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        } else {
            app.keyboards.buttons["search"].tap()
        }
        
        // Wait for search results
        sleep(2)
        
        // Tap on first search result to open article
        let firstResult = app.cells.element(boundBy: 0)
        if firstResult.waitForExistence(timeout: 5) {
            firstResult.tap()
        }
        
        // Wait for article to load
        sleep(3)
        
        // Take screenshot to verify article bottom bar is in dark theme
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Article_Bottom_Bar_Dark_Theme"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Verify bottom bar elements exist
        XCTAssertTrue(app.buttons["Save"].exists || app.staticTexts["Save"].exists, "Save button should exist in article bottom bar")
        XCTAssertTrue(app.buttons["Find"].exists || app.staticTexts["Find"].exists, "Find button should exist in article bottom bar")
        XCTAssertTrue(app.buttons["Appearance"].exists || app.staticTexts["Appearance"].exists, "Appearance button should exist in article bottom bar")
        XCTAssertTrue(app.buttons["Contents"].exists || app.staticTexts["Contents"].exists, "Contents button should exist in article bottom bar")
    }
    
    func testArticleBottomBarLightThemeConsistency() throws {
        // Navigate to More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        
        // Navigate to Appearance settings
        let appearanceCell = app.cells["Appearance"]
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 5))
        appearanceCell.tap()
        
        // Switch to Light theme
        let lightThemeOption = app.cells["Light"]
        XCTAssertTrue(lightThemeOption.waitForExistence(timeout: 5))
        lightThemeOption.tap()
        
        // Go back to More tab
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }
        
        // Navigate to Search tab to access articles
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        searchTab.tap()
        
        // Search for an article
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Lumbridge")
        
        // Tap search button or dismiss keyboard
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        } else {
            app.keyboards.buttons["search"].tap()
        }
        
        // Wait for search results
        sleep(2)
        
        // Tap on first search result to open article
        let firstResult = app.cells.element(boundBy: 0)
        if firstResult.waitForExistence(timeout: 5) {
            firstResult.tap()
        }
        
        // Wait for article to load
        sleep(3)
        
        // Take screenshot to verify article bottom bar is in light theme
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Article_Bottom_Bar_Light_Theme"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Verify bottom bar elements exist
        XCTAssertTrue(app.buttons["Save"].exists || app.staticTexts["Save"].exists, "Save button should exist in article bottom bar")
        XCTAssertTrue(app.buttons["Find"].exists || app.staticTexts["Find"].exists, "Find button should exist in article bottom bar")
        XCTAssertTrue(app.buttons["Appearance"].exists || app.staticTexts["Appearance"].exists, "Appearance button should exist in article bottom bar")
        XCTAssertTrue(app.buttons["Contents"].exists || app.staticTexts["Contents"].exists, "Contents button should exist in article bottom bar")
    }
}
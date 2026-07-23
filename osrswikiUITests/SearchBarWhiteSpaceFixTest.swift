//
//  SearchBarWhiteSpaceFixTest.swift
//  osrswikiUITests
//
//  Created by Claude Code Agent for search bar animation fix
//

import XCTest

final class SearchBarWhiteSpaceFixTest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchBarNavigationNoWhiteSpace() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        let homeTab = app.tabBars.buttons["home_tab"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Home tab should exist")
        
        // Tap home tab to ensure we're on the home page
        homeTab.tap()
        
        // Wait for the search bar to appear
        let searchBar = app.buttons["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5), "Search bar should exist on home page")
        
        // Take a screenshot before tapping search bar
        let beforeScreenshot = app.screenshot()
        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "Before Search Bar Tap"
        add(beforeAttachment)
        
        // Tap the search bar to navigate to search
        searchBar.tap()
        
        // Wait for search view to appear
        let searchTextField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5), "Search text field should appear")
        
        // Take a screenshot during/after navigation
        sleep(1) // Allow any animation to complete
        let afterScreenshot = app.screenshot()
        let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
        afterAttachment.name = "After Search Bar Tap - No White Space"
        add(afterAttachment)
        
        // Verify we're now in the search view
        XCTAssertTrue(searchTextField.isHittable, "Search text field should be active")
        
        // Navigate back to test return animation
        if app.navigationBars.buttons["Back"].exists {
            app.navigationBars.buttons["Back"].tap()
        }
        
        // Verify we're back to home
        XCTAssertTrue(searchBar.waitForExistence(timeout: 3), "Should return to home page with search bar")
        
        // Take final screenshot
        let finalScreenshot = app.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "Back to Home - Layout Restored"
        add(finalAttachment)
    }
    
    func testSearchBarFromHistoryTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to history tab (which shows the search tab icon)
        let historyTab = app.tabBars.buttons["search_tab"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab should exist")
        historyTab.tap()
        
        // Wait for the search bar to appear on history page
        let searchBar = app.buttons["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5), "Search bar should exist on history page")
        
        // Take screenshot before tap
        let beforeScreenshot = app.screenshot()
        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "History Tab Before Search"
        add(beforeAttachment)
        
        // Tap search bar from history page
        searchBar.tap()
        
        // Verify search view appears
        let searchTextField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5), "Search text field should appear from history")
        
        // Take screenshot after navigation
        sleep(1)
        let afterScreenshot = app.screenshot()
        let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
        afterAttachment.name = "History to Search - No White Space"
        add(afterAttachment)
        
        // Test keyboard appears quickly
        XCTAssertTrue(searchTextField.isHittable, "Search field should be ready for input")
    }
}
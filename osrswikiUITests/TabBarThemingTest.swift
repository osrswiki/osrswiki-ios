//
//  TabBarThemingTest.swift
//  osrswikiUITests
//
//  Created for tab bar theming investigation
//

import XCTest

final class TabBarThemingTest: XCTestCase {
    
    func testNavigateToSavedTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        let homeTab = app.tabBars.buttons["newspaper.fill"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Home tab should exist")
        
        // Navigate to Saved tab
        let savedTab = app.tabBars.buttons["bookmark"]
        XCTAssertTrue(savedTab.exists, "Saved tab should exist")
        savedTab.tap()
        
        // Wait a moment for tab transition
        sleep(2)
    }
    
    func testNavigateToSearchTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        let homeTab = app.tabBars.buttons.element(boundBy: 0)  // First button (Home)
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Home tab should exist")
        
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons.element(boundBy: 2)  // Third button (Search)
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait a moment for tab transition
        sleep(2)
    }
}
//
//  TabBarStressTestSimple.swift
//  osrswikiUITests
//
//  Simplified test for tab bar crash reproduction
//

import XCTest

final class TabBarStressTestSimple: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    /// Simple test to verify tab bar structure and perform stress test
    func testTabBarRapidSwitching() throws {
        // Wait for app to fully launch
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find all buttons in the app that might be tab buttons
        let allButtons = app.buttons
        print("Found \(allButtons.count) buttons")
        
        // Print all button labels for debugging
        for i in 0..<min(allButtons.count, 20) {
            let button = allButtons.element(boundBy: i)
            if button.exists {
                print("Button \(i): label='\(button.label)', identifier='\(button.identifier)'")
            }
        }
        
        // Try to find tab buttons by common patterns
        let homeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Home'")).firstMatch
        let searchButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
        let mapButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Map'")).firstMatch
        let savedButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Saved'")).firstMatch
        let moreButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'More'")).firstMatch
        
        // Verify at least some tabs exist
        let tabsFound = [homeButton, searchButton, mapButton, savedButton, moreButton].filter { $0.exists }
        print("Found \(tabsFound.count) tab buttons")
        XCTAssertGreaterThan(tabsFound.count, 0, "Should find at least one tab button")
        
        // Navigate to More > Appearance to trigger preview loading
        if moreButton.exists {
            moreButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            // Try to find Appearance cell
            let appearanceCell = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Appearance'")).firstMatch
            if appearanceCell.waitForExistence(timeout: 2) {
                appearanceCell.tap()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        
        // Navigate to Search to trigger keyboard
        if searchButton.exists {
            searchButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            // Try to type in search field
            let searchField = app.searchFields.firstMatch
            if searchField.exists {
                searchField.tap()
                searchField.typeText("test")
            }
        }
        
        // Now perform rapid tab switching stress test
        print("Starting rapid tab switching stress test...")
        
        for i in 0..<50 {
            // Randomly select a tab
            let tabs = tabsFound.shuffled()
            if let randomTab = tabs.first, randomTab.exists && randomTab.isHittable {
                randomTab.tap()
                // Very short delay to simulate rapid tapping
                Thread.sleep(forTimeInterval: 0.02)
            }
            
            if i % 10 == 0 {
                print("Completed \(i) tab switches")
            }
        }
        
        print("Stress test completed")
        
        // Verify app hasn't crashed
        XCTAssertTrue(app.exists, "App should still be running after stress test")
        
        // Try one more navigation to verify responsiveness
        if homeButton.exists {
            homeButton.tap()
            XCTAssertTrue(app.exists, "App should still be responsive")
        }
    }
    
    /// Test concurrent operations with heavy loading
    func testConcurrentHeavyOperations() throws {
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find tab buttons
        let searchButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
        let mapButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Map'")).firstMatch
        let moreButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'More'")).firstMatch
        
        // Start map loading
        if mapButton.exists {
            mapButton.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        // Start search with keyboard
        if searchButton.exists {
            searchButton.tap()
            let searchField = app.searchFields.firstMatch
            if searchField.waitForExistence(timeout: 2) {
                searchField.tap()
                searchField.typeText("dragon slayer quest guide")
            }
        }
        
        // Navigate to appearance settings
        if moreButton.exists {
            moreButton.tap()
            let appearanceCell = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Appearance'")).firstMatch
            if appearanceCell.waitForExistence(timeout: 2) {
                appearanceCell.tap()
            }
        }
        
        // Now rapidly switch tabs while everything is loading
        let allTabs = [searchButton, mapButton, moreButton].filter { $0.exists }
        
        for _ in 0..<30 {
            for tab in allTabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    Thread.sleep(forTimeInterval: 0.01) // Minimal delay
                }
            }
        }
        
        // Verify app stability
        XCTAssertTrue(app.exists, "App should survive concurrent operations")
    }
}
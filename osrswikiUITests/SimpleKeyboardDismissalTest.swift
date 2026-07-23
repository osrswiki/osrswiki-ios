//
//  SimpleKeyboardDismissalTest.swift
//  osrswikiUITests
//
//  Simplified test for keyboard dismissal behavior
//

import XCTest

class SimpleKeyboardDismissalTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testKeyboardDismissalInHistorySearchFlow() throws {
        // Step 1: Navigate to the Search/History tab (3rd tab, index 2)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should exist")
        
        // Get all tab buttons
        let tabButtons = tabBar.buttons
        XCTAssertTrue(tabButtons.count >= 3, "Should have at least 3 tabs")
        
        // Tap the 3rd tab (History/Search)
        let historyTab = tabButtons.element(boundBy: 2)
        historyTab.tap()
        
        // Step 2: Wait for the History view to load
        Thread.sleep(forTimeInterval: 1.0)
        
        // Step 3: Tap on the search bar to open DedicatedSearchView
        // The search bar might be a button or text field
        let searchBarButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
        let searchTextField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'Search'")).firstMatch
        
        if searchBarButton.exists {
            searchBarButton.tap()
        } else if searchTextField.exists {
            searchTextField.tap()
        } else {
            // Try to find any clickable element with "Search" in it
            let searchElements = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Search' OR placeholderValue CONTAINS[c] 'Search'"))
            if searchElements.count > 0 {
                searchElements.firstMatch.tap()
            }
        }
        
        // Step 4: Wait for DedicatedSearchView to load
        Thread.sleep(forTimeInterval: 1.5)
        
        // Step 5: Find the search field in DedicatedSearchView and type
        let dedicatedSearchField = app.textFields.firstMatch
        if dedicatedSearchField.waitForExistence(timeout: 5) {
            dedicatedSearchField.tap()
            
            // Step 6: Type something to activate keyboard
            dedicatedSearchField.typeText("Test")
            
            // Step 7: Verify keyboard is visible
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.exists, "Keyboard should be visible after typing")
            
            // Step 8: Navigate back
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists {
                backButton.tap()
            } else {
                // Try swipe gesture
                app.swipeRight()
            }
            
            // Step 9: Wait and verify keyboard is dismissed
            Thread.sleep(forTimeInterval: 1.0)
            XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed after navigation")
            
            // Step 10: Verify we're back in History view
            XCTAssertTrue(tabBar.exists, "Tab bar should be visible again")
        }
    }
    
    func testKeyboardDismissalBetweenTabs() throws {
        // This test verifies keyboard doesn't persist between tab switches
        
        // Navigate to History tab
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should exist")
        
        let historyTab = tabBar.buttons.element(boundBy: 2)
        historyTab.tap()
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Try to activate any search field
        let searchElements = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Search' OR placeholderValue CONTAINS[c] 'Search'"))
        if searchElements.count > 0 {
            searchElements.firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Type if we found a text field
            if app.textFields.count > 0 {
                app.textFields.firstMatch.typeText("Test")
                
                // Check keyboard
                let keyboard = app.keyboards.firstMatch
                
                // Switch to another tab
                let homeTab = tabBar.buttons.element(boundBy: 0)
                homeTab.tap()
                
                Thread.sleep(forTimeInterval: 0.5)
                
                // Verify keyboard is gone
                XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed when switching tabs")
            }
        }
    }
}
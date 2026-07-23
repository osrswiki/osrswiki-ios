//
//  KeyboardDismissalTest.swift
//  osrswikiUITests
//
//  Tests for keyboard dismissal when navigating from search views
//

import XCTest

class KeyboardDismissalTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testKeyboardDismissalOnNavigationFromSearchTab() throws {
        // Navigate to Search/History tab (3rd tab)
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 2) {
            searchTab.tap()
        } else {
            // Try using index if label doesn't work
            let searchTabAlt = app.tabBars.buttons.element(boundBy: 2)
            if searchTabAlt.waitForExistence(timeout: 2) {
                searchTabAlt.tap()
            } else {
                // Last resort: try all tabs to find the right one
                let tabButtons = app.tabBars.buttons
                XCTAssertTrue(tabButtons.count >= 3, "Should have at least 3 tabs")
                tabButtons.element(boundBy: 2).tap()
            }
        }
        
        // Now tap on the search bar to open DedicatedSearchView
        let searchBar = app.otherElements["Search OSRS Wiki"]
        if !searchBar.exists {
            // Try to find any text field
            let anySearchField = app.textFields.firstMatch
            if anySearchField.waitForExistence(timeout: 5) {
                anySearchField.tap()
            } else {
                // Try buttons with search text
                let searchButton = app.buttons["Search OSRS Wiki"]
                XCTAssertTrue(searchButton.waitForExistence(timeout: 5), "Search bar should exist")
                searchButton.tap()
            }
        } else {
            searchBar.tap()
        }
        
        // Wait for dedicated search view to load
        Thread.sleep(forTimeInterval: 1.0)
        
        // Now find the actual search field in DedicatedSearchView
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist in DedicatedSearchView")
        
        // Tap search field to activate keyboard
        searchField.tap()
        
        // Verify keyboard is shown
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2), "Keyboard should appear")
        
        // Type search query
        searchField.typeText("Woodcutting")
        
        // Wait for search results
        let searchResults = app.cells.firstMatch
        XCTAssertTrue(searchResults.waitForExistence(timeout: 5), "Search results should appear")
        
        // Tap on a search result to navigate
        searchResults.tap()
        
        // Wait for article view to load
        let articleView = app.webViews.firstMatch
        XCTAssertTrue(articleView.waitForExistence(timeout: 10), "Article view should load")
        
        // Navigate back
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        } else {
            // Try swipe back gesture
            app.swipeRight()
        }
        
        // Verify we're back on search view
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Should return to search view")
        
        // Verify keyboard is dismissed
        XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed after navigation")
        
        // Verify no white space artifact (check view hierarchy)
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        
        // Check that the search view is properly displayed without keyboard artifacts
        let searchView = app.otherElements["SearchView"]
        if searchView.exists {
            let frame = searchView.frame
            XCTAssertTrue(frame.height > 0, "Search view should have proper height")
        }
    }
    
    func testKeyboardDismissalOnBackButtonFromDedicatedSearch() throws {
        // Navigate to Search/History tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 2) {
            searchTab.tap()
        } else {
            app.tabBars.buttons.element(boundBy: 2).tap()
        }
        
        // Open dedicated search by tapping search bar
        let searchBar = app.buttons["Search OSRS Wiki"]
        if !searchBar.waitForExistence(timeout: 5) {
            // Try text fields
            let searchField = app.textFields["Search OSRS Wiki"]
            if searchField.exists {
                searchField.tap()
            } else {
                app.textFields.firstMatch.tap()
            }
        } else {
            searchBar.tap()
        }
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // If dedicated search view is available, test it
        // This would be triggered by tapping a "Search" button in the app
        // For now, we'll test the main search view behavior
        
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
        
        // Activate keyboard
        searchField.tap()
        
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2), "Keyboard should appear")
        
        // Type something
        searchField.typeText("Test")
        
        // Navigate to another tab
        let homeTab = app.tabBars.buttons["Home"]
        if !homeTab.exists {
            // Try alternate identifier (first tab)
            let homeTabAlt = app.tabBars.buttons.element(boundBy: 0)
            XCTAssertTrue(homeTabAlt.exists, "Home tab should exist")
            homeTabAlt.tap()
        } else {
            homeTab.tap()
        }
        
        // Navigate back to search
        if app.tabBars.buttons["Search"].exists {
            app.tabBars.buttons["Search"].tap()
        } else {
            app.tabBars.buttons.element(boundBy: 2).tap()
        }
        
        // Verify keyboard is not automatically shown
        XCTAssertFalse(keyboard.exists, "Keyboard should not persist across tab changes")
    }
    
    func testKeyboardDismissalOnSearchResultSelection() throws {
        // Navigate to Search/History tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 2) {
            searchTab.tap()
        } else {
            app.tabBars.buttons.element(boundBy: 2).tap()
        }
        
        // Open dedicated search
        let searchBar = app.buttons["Search OSRS Wiki"]
        if !searchBar.waitForExistence(timeout: 5) {
            app.textFields.firstMatch.tap()
        } else {
            searchBar.tap()
        }
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Wait for search view
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
        
        // Activate keyboard and search
        searchField.tap()
        
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2), "Keyboard should appear")
        
        searchField.typeText("Varrock")
        
        // Wait for search results
        let searchResults = app.cells.firstMatch
        XCTAssertTrue(searchResults.waitForExistence(timeout: 5), "Search results should appear")
        
        // Select a result
        searchResults.tap()
        
        // Verify keyboard is dismissed immediately
        XCTAssertFalse(keyboard.exists, "Keyboard should dismiss when selecting a search result")
        
        // Wait for article to load
        let articleView = app.webViews.firstMatch
        XCTAssertTrue(articleView.waitForExistence(timeout: 10), "Article should load")
    }
    
    func testNoKeyboardArtifactsAfterMultipleNavigations() throws {
        // Navigate to Search/History tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 2) {
            searchTab.tap()
        } else {
            app.tabBars.buttons.element(boundBy: 2).tap()
        }
        
        // Open dedicated search
        let searchBar = app.buttons["Search OSRS Wiki"]
        if !searchBar.waitForExistence(timeout: 5) {
            app.textFields.firstMatch.tap()
        } else {
            searchBar.tap()
        }
        
        Thread.sleep(forTimeInterval: 1.0)
        
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
        
        // Perform multiple search and navigation cycles
        for i in 0..<3 {
            // Activate keyboard
            searchField.tap()
            
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 2), "Keyboard should appear on iteration \(i)")
            
            // Clear and type new search
            if searchField.value as? String != "" {
                searchField.buttons["Clear text"].tap()
            }
            searchField.typeText("Test \(i)")
            
            // Wait briefly
            Thread.sleep(forTimeInterval: 0.5)
            
            // Navigate to another tab
            let savedTab = app.tabBars.buttons["Saved"]
            if !savedTab.exists {
                app.tabBars.buttons.element(boundBy: 1).tap()
            } else {
                savedTab.tap()
            }
            
            // Come back to search
            if app.tabBars.buttons["Search"].exists {
                app.tabBars.buttons["Search"].tap()
            } else {
                app.tabBars.buttons.element(boundBy: 2).tap()
            }
            
            // Verify no keyboard artifacts
            XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed on iteration \(i)")
        }
        
        // Final check for view integrity
        let searchView = app.otherElements.matching(identifier: "SearchView").firstMatch
        if searchView.exists {
            XCTAssertTrue(searchView.frame.height > 0, "Search view should maintain proper dimensions")
        }
    }
}
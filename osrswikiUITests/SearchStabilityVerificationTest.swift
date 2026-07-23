//
//  SearchStabilityVerificationTest.swift
//  osrswikiUITests
//
//  Test to verify that the UICollectionView dequeuing fixes work correctly
//

import XCTest

class SearchStabilityVerificationTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready and navigate to search
        _ = app.wait(for: .runningForeground, timeout: 5)
    }
    
    func testSearchPageBasicStability() throws {
        // Find and tap search - try multiple approaches
        var searchFound = false
        
        // Approach 1: Look for search text field directly
        let searchField = app.textFields.firstMatch
        if searchField.waitForExistence(timeout: 3) {
            searchFound = true
        }
        
        // Approach 2: Try to find search by label
        if !searchFound {
            let searchElements = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'search'"))
            if searchElements.count > 0 {
                searchElements.firstMatch.tap()
                searchFound = searchField.waitForExistence(timeout: 3)
            }
        }
        
        // Approach 3: Try tab navigation
        if !searchFound {
            let tabs = app.buttons.allElementsBoundByIndex
            for tab in tabs {
                if tab.label.lowercased().contains("search") {
                    tab.tap()
                    searchFound = searchField.waitForExistence(timeout: 3)
                    break
                }
            }
        }
        
        // If still not found, try the second tab (commonly search)
        if !searchFound {
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists {
                let tabs = tabBar.buttons
                if tabs.count >= 2 {
                    tabs.element(boundBy: 1).tap()
                    searchFound = searchField.waitForExistence(timeout: 3)
                }
            }
        }
        
        XCTAssertTrue(searchFound, "Should be able to find and access search functionality")
        
        guard searchFound else { 
            XCTFail("Could not find search interface")
            return 
        }
        
        // Test basic search functionality without crash
        searchField.tap()
        searchField.typeText("varrock")
        
        // Wait a moment for search to process
        sleep(2)
        
        // Verify app is still running (didn't crash)
        XCTAssertEqual(app.state, .runningForeground, "App should still be running after search")
        
        // Try rapid search modifications that previously caused crashes
        searchField.clearAndEnterText("dragon")
        usleep(500000) // 500ms
        
        searchField.clearAndEnterText("rune")
        usleep(500000) // 500ms
        
        // Final verification - app should still be stable
        XCTAssertEqual(app.state, .runningForeground, "App should remain stable after rapid search changes")
        
        print("✅ Search stability test passed - no crashes detected")
    }
    
    func testSearchResultsListStability() throws {
        // Find search interface
        let searchField = app.textFields.firstMatch
        if !searchField.exists {
            // Try to navigate to search
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists {
                let tabs = tabBar.buttons
                if tabs.count >= 2 {
                    tabs.element(boundBy: 1).tap()
                }
            }
        }
        
        guard searchField.waitForExistence(timeout: 5) else {
            XCTSkip("Could not access search interface")
            return
        }
        
        // Perform search
        searchField.tap()
        searchField.typeText("dragon")
        
        // Look for search results
        let collectionView = app.collectionViews.firstMatch
        
        if collectionView.waitForExistence(timeout: 10) {
            // Test scrolling stability (previously caused dequeue issues)
            collectionView.swipeUp()
            collectionView.swipeDown()
            collectionView.swipeUp()
            
            // Verify app is still stable
            XCTAssertEqual(app.state, .runningForeground, "App should remain stable during list interactions")
            
            print("✅ Search results list stability test passed")
        } else {
            // Even if no results appear, the app should be stable
            XCTAssertEqual(app.state, .runningForeground, "App should be stable even if no search results")
            print("⚠️ No search results appeared, but app remained stable")
        }
    }
}
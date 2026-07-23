//
//  CollectionViewDequeueReproductionTest.swift
//  osrswikiUITests
//
//  Created to reproduce the specific UICollectionView cell dequeuing crash:
//  NSInternalInconsistencyException: Expected dequeued view to be returned to the collection view
//

import XCTest

class CollectionViewDequeueReproductionTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should exist")
        
        // Navigate to Search tab - try different possible identifiers
        let searchTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search'")).firstMatch
        if !searchTab.exists {
            // Fallback to second tab if "Search" not found by name
            let tabs = app.tabBars.buttons
            if tabs.count >= 2 {
                tabs.element(boundBy: 1).tap() // Typically the second tab is search
            } else {
                XCTFail("Could not find search tab")
            }
        } else {
            searchTab.tap()
        }
        
        // Wait for search interface to load
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
    }
    
    func testUICollectionViewCellDequeuingCrash() throws {
        // This test reproduces the exact crash scenario described in the stack trace
        
        let searchField = app.textFields.firstMatch
        searchField.tap()
        
        // Type search term that will return results
        searchField.typeText("varrock")
        
        // Wait for search results to start loading
        let searchResultsContainer = app.collectionViews.firstMatch
        XCTAssertTrue(searchResultsContainer.waitForExistence(timeout: 5), "Search results should load")
        
        // The crash occurs when cells are being dequeued but not properly returned
        // This is triggered by rapid state changes while the collection view is updating
        
        // Trigger 1: Rapid search term modification while results are loading
        searchField.clearAndEnterText("dragon")
        
        // Give just enough time for first results to appear but not complete
        usleep(300000) // 300ms - critical timing window
        
        // Trigger 2: Modify search again while previous search is still processing
        searchField.clearAndEnterText("rune")
        
        // Trigger 3: Rapid scrolling during list updates (causes onAppear conflicts)
        if searchResultsContainer.exists {
            for i in 1...5 {
                searchResultsContainer.swipeUp()
                usleep(50000) // 50ms - very fast to trigger race conditions
                searchResultsContainer.swipeDown()
                usleep(50000)
            }
        }
        
        // Wait for results to stabilize
        let cells = searchResultsContainer.cells
        XCTAssertTrue(cells.count > 0, "Should have search result cells")
        
        // Trigger 4: Try to tap a cell while list might still be updating
        if cells.count > 0 {
            let firstCell = cells.firstMatch
            firstCell.tap()
            
            // If we get here without crashing, the fix is working
            XCTAssertTrue(app.state == .runningForeground, "App should still be running")
        }
    }
    
    func testLoadMoreResultsDequeueIssue() throws {
        // Test the "Load More Results" functionality that can trigger dequeue issues
        
        let searchField = app.textFields.firstMatch
        searchField.tap()
        searchField.typeText("dragon")
        
        let searchResults = app.collectionViews.firstMatch
        XCTAssertTrue(searchResults.waitForExistence(timeout: 5))
        
        // Scroll to trigger "Load More Results"
        for _ in 1...3 {
            searchResults.swipeUp()
        }
        
        // Look for Load More button
        let loadMoreButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'load more' OR label CONTAINS[c] 'more results'")).firstMatch
        
        if loadMoreButton.waitForExistence(timeout: 3) {
            // Rapidly tap load more and interact with list (triggers dequeue conflicts)
            loadMoreButton.tap()
            
            // Immediately scroll while more results are loading
            searchResults.swipeUp()
            usleep(100000) // 100ms
            searchResults.swipeDown()
            
            // Try to interact with cells while "Load More" is processing
            let cells = searchResults.cells
            if cells.count > 0 {
                cells.firstMatch.tap()
            }
        }
        
        // Should not crash
        XCTAssertTrue(app.state == .runningForeground)
    }
    
    func testStableIDCollisionScenario() throws {
        // Test if the "stable ID" approach is actually working
        // The SearchView uses: .id("\\(result.id)-\\(searchText.hashValue)")
        
        let searchField = app.textFields.firstMatch
        
        // Search for terms that might have hash collisions or cause ID conflicts
        let searchTerms = ["var", "varro", "varrock", "varroc", "varrok"]
        
        for term in searchTerms {
            searchField.clearAndEnterText(term)
            
            // Let results load briefly
            usleep(200000) // 200ms
            
            // Check that list still exists and is stable
            let searchResults = app.collectionViews.firstMatch
            if searchResults.exists {
                let cellCount = searchResults.cells.count
                print("📊 Search term '\(term)' returned \(cellCount) cells")
            }
        }
        
        // Final verification
        XCTAssertTrue(app.state == .runningForeground, "App should remain stable")
    }
}

// Note: clearText() extension already exists in SearchCrashReproductionTest.swift
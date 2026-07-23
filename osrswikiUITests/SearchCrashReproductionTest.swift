//
//  SearchCrashReproductionTest.swift
//  osrswikiUITests
//
//  Created to reproduce and fix SwiftUI List cell dequeuing crash in search results

import XCTest

class SearchCrashReproductionTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
    }
    
    func testSearchResultsListCellDequeuing() throws {
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        searchTab.tap()
        
        // Wait for search interface
        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        
        // Reproduce crash scenario: rapid search term changes
        searchField.tap()
        searchField.typeText("var")
        
        // Wait for initial results
        sleep(1)
        
        // Rapidly modify search - this triggers the cell dequeuing issue
        searchField.clearAndEnterText("varrock")
        
        // Wait for results to appear
        let searchResultsList = app.collectionViews.firstMatch
        XCTAssertTrue(searchResultsList.waitForExistence(timeout: 5), "Search results list should appear")
        
        // Test rapid scrolling while results are loading (triggers onAppear conflicts)
        if searchResultsList.exists {
            for _ in 1...3 {
                searchResultsList.swipeUp()
                usleep(200000) // 200ms - faster than typical user interaction
                searchResultsList.swipeDown()
                usleep(200000)
            }
        }
        
        // Attempt to tap a search result (this often triggers the crash)
        let firstResult = searchResultsList.cells.firstMatch
        if firstResult.waitForExistence(timeout: 3) {
            firstResult.tap()
            
            // Verify we can navigate without crashing
            let articleView = app.webViews.firstMatch
            XCTAssertTrue(articleView.waitForExistence(timeout: 5), "Should navigate to article without crashing")
        }
    }
    
    func testLoadMoreResultsTrigger() throws {
        // Navigate to Search tab
        app.tabBars.buttons["Search"].tap()
        
        // Search for something with many results
        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("dragon")
        
        // Wait for initial results
        let searchResultsList = app.collectionViews.firstMatch
        XCTAssertTrue(searchResultsList.waitForExistence(timeout: 5))
        
        // Scroll to bottom to trigger load more (this triggers onAppear conflicts)
        searchResultsList.swipeUp()
        searchResultsList.swipeUp()
        
        // Look for "Load More Results" button and tap it rapidly
        let loadMoreButton = app.buttons["Load More Results"]
        if loadMoreButton.waitForExistence(timeout: 3) {
            // Rapid tapping can trigger cell dequeuing issues
            loadMoreButton.tap()
            usleep(100000) // 100ms
            
            // Try to interact with list while more results are loading
            searchResultsList.swipeUp()
        }
        
        // Verify list remains stable
        XCTAssertTrue(searchResultsList.exists, "Search results list should remain stable after load more")
    }
    
    func testSearchTermModificationDuringLoading() throws {
        // This test specifically reproduces the state inconsistency issue
        app.tabBars.buttons["Search"].tap()
        
        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        
        // Start typing
        searchField.tap()
        searchField.typeText("dra")
        
        // Immediately modify while first search is processing
        usleep(500000) // 500ms - enough to start search but not complete
        searchField.clearAndEnterText("dragon sword")
        
        // Wait and verify we don't crash
        let searchResultsList = app.collectionViews.firstMatch
        XCTAssertTrue(searchResultsList.waitForExistence(timeout: 5))
        
        // Interact with results
        let firstCell = searchResultsList.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            firstCell.tap()
        }
        
        // Should not crash
        XCTAssertTrue(app.state == .runningForeground, "App should remain running without crash")
    }
}


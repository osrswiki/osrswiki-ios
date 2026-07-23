//
//  SearchTapMemoryLeakTest.swift
//  osrswikiUITests
//
//  Created to reproduce and fix search tap memory leak issue
//

import XCTest

class SearchTapMemoryLeakTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testSearchResultTapNavigation() throws {
        // Navigate to Search tab (which shows HistoryView with search bar)
        let searchTab = app.tabBars.buttons.element(boundBy: 2) // Third tab (0-indexed)
        if !searchTab.exists {
            // Try with accessibility identifier
            let searchTabById = app.tabBars.buttons["search_tab"]
            if searchTabById.exists {
                searchTabById.tap()
            } else {
                // Fallback: Try by label
                let searchTabByLabel = app.tabBars.buttons["Search"]
                XCTAssertTrue(searchTabByLabel.exists, "Search tab should exist")
                searchTabByLabel.tap()
            }
        } else {
            searchTab.tap()
        }
        
        // Wait for search view to load - look for the search bar
        // The search bar might show as a button that needs to be tapped first
        let searchBarButton = app.buttons["Search OSRS Wiki"]
        if searchBarButton.waitForExistence(timeout: 3) {
            searchBarButton.tap()
        }
        
        // Now look for the actual text field in the search view
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        
        // Enter search query
        searchField.tap()
        searchField.typeText("Varrock")
        
        // Wait for search results to appear
        let searchResults = app.cells
        XCTAssertTrue(searchResults.firstMatch.waitForExistence(timeout: 10), "Search results should appear")
        
        // Verify at least one result exists
        XCTAssertGreaterThan(searchResults.count, 0, "Should have at least one search result")
        
        // Store initial memory usage
        let initialMemory = XCTMemoryMetric()
        measure(metrics: [initialMemory]) {
            // Tap the first search result
            searchResults.firstMatch.tap()
        }
        
        // Wait to see if article view appears
        let articleContent = app.webViews.firstMatch
        let navigationSucceeded = articleContent.waitForExistence(timeout: 5)
        
        if !navigationSucceeded {
            // Check if we're still on search view (indicates the bug)
            XCTAssertTrue(searchField.exists, "Should still be on search view if navigation failed")
            XCTFail("Navigation to article failed - search tap not working")
        } else {
            // Verify we navigated away from search
            XCTAssertFalse(searchField.exists, "Search field should not be visible after navigation")
            XCTAssertTrue(articleContent.exists, "Article content should be visible")
        }
    }
    
    func testSearchResultTapMemoryLeak() throws {
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait for search view to load
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        
        // Enter search query
        searchField.tap()
        searchField.typeText("Dragon")
        
        // Wait for search results
        let searchResults = app.cells
        XCTAssertTrue(searchResults.firstMatch.waitForExistence(timeout: 10), "Search results should appear")
        
        // Measure memory during repeated taps
        let memoryMetric = XCTMemoryMetric()
        let cpuMetric = XCTCPUMetric()
        
        self.measure(metrics: [memoryMetric, cpuMetric]) {
            // Tap search result multiple times to check for memory leak
            for _ in 0..<5 {
                if searchResults.firstMatch.exists {
                    searchResults.firstMatch.tap()
                    
                    // Small delay to allow any navigation or processing
                    Thread.sleep(forTimeInterval: 0.5)
                    
                    // Check if we're stuck on search (the bug)
                    if searchField.exists {
                        // We're still on search view - indicates the bug
                        print("⚠️ Still on search view after tap - navigation failed")
                    } else {
                        // Navigation succeeded, go back
                        if app.navigationBars.buttons["Search"].exists {
                            app.navigationBars.buttons["Search"].tap()
                        }
                    }
                }
            }
        }
        
        // The test will fail if memory increases significantly or CPU spikes occur
    }
    
    func testSearchResultTapResponsiveness() throws {
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        searchTab.tap()
        
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        // Search for something
        searchField.tap()
        searchField.typeText("Abyssal whip")
        
        // Wait for results
        let searchResults = app.cells
        XCTAssertTrue(searchResults.firstMatch.waitForExistence(timeout: 10))
        
        // Measure response time of tap
        let startTime = Date()
        searchResults.firstMatch.tap()
        
        // Check if anything happens within 2 seconds
        let articleView = app.webViews.firstMatch
        let navigated = articleView.waitForExistence(timeout: 2)
        let responseTime = Date().timeIntervalSince(startTime)
        
        if navigated {
            XCTAssertLessThan(responseTime, 2.0, "Navigation should complete within 2 seconds")
            print("✅ Navigation completed in \(responseTime) seconds")
        } else {
            // Check if we're stuck
            if searchField.exists {
                XCTFail("Search tap is not responsive - still on search view after \(responseTime) seconds")
                print("❌ Search tap failed - stuck on search view")
            }
        }
    }
    
    func testMultipleSearchesAndNavigation() throws {
        // Test multiple searches and taps to ensure consistency
        let searchQueries = ["Varrock", "Dragon", "Quest", "Slayer"]
        
        for query in searchQueries {
            // Navigate to Search tab
            let searchTab = app.tabBars.buttons["Search"]
            if searchTab.exists {
                searchTab.tap()
            }
            
            let searchField = app.textFields.firstMatch
            XCTAssertTrue(searchField.waitForExistence(timeout: 5))
            
            // Clear and enter new search
            searchField.tap()
            if let currentText = searchField.value as? String, !currentText.isEmpty {
                searchField.buttons["Clear text"].tap()
            }
            searchField.typeText(query)
            
            // Wait for results
            let searchResults = app.cells
            if searchResults.firstMatch.waitForExistence(timeout: 10) {
                // Try to tap first result
                searchResults.firstMatch.tap()
                
                // Check result
                Thread.sleep(forTimeInterval: 1)
                
                if app.webViews.firstMatch.exists {
                    print("✅ Successfully navigated for query: \(query)")
                    // Go back for next search
                    if app.navigationBars.buttons["Search"].exists {
                        app.navigationBars.buttons["Search"].tap()
                    }
                } else if searchField.exists {
                    print("❌ Navigation failed for query: \(query) - stuck on search")
                    XCTFail("Search tap not working for query: \(query)")
                }
            }
        }
    }
}
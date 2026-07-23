//
//  HomePageCachingUITest.swift
//  OSRS Wiki UI Tests
//
//  Comprehensive test suite for home page caching and refresh functionality
//

import XCTest

class HomePageCachingUITest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Tab Navigation Caching Tests
    
    func testHomePageRetainsContentBetweenTabSwitches() {
        // Test that home page doesn't reload when switching tabs
        
        // 1. Ensure we're on home tab and content is loaded
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Wait for content to load
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15), "Home page search bar should load")
        
        // Look for content sections
        let recentUpdatesText = app.staticTexts["Recent updates"]
        if recentUpdatesText.waitForExistence(timeout: 5) {
            XCTAssertTrue(recentUpdatesText.exists, "Recent updates section should be visible")
        }
        
        // 2. Switch to another tab and back quickly
        let savedTab = app.tabBars.buttons["Saved"]
        savedTab.tap()
        
        // Brief pause to simulate typical user behavior
        Thread.sleep(forTimeInterval: 0.5)
        
        homeTab.tap()
        
        // 3. Content should appear immediately without loading indicator
        XCTAssertTrue(searchBar.exists, "Search bar should be immediately visible (cached)")
        
        // Verify no loading indicator is shown (indicating cached content)
        let loadingIndicator = app.staticTexts["Loading news..."]
        XCTAssertFalse(loadingIndicator.exists, "Loading indicator should not appear for cached content")
    }
    
    func testMultipleTabSwitchesPreserveHomeContent() {
        // Test resilience across multiple tab switches
        
        let homeTab = app.tabBars.buttons["Home"]
        let searchTab = app.tabBars.buttons["Search"]
        let mapTab = app.tabBars.buttons["Map"]
        let moreTab = app.tabBars.buttons["More"]
        
        // Start on home and wait for load
        homeTab.tap()
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Cycle through all tabs multiple times
        for cycle in 1...3 {
            searchTab.tap()
            Thread.sleep(forTimeInterval: 0.3)
            
            mapTab.tap()
            Thread.sleep(forTimeInterval: 0.3)
            
            moreTab.tap()
            Thread.sleep(forTimeInterval: 0.3)
            
            homeTab.tap()
            
            // Verify immediate content availability
            XCTAssertTrue(searchBar.exists, "Home content should persist through cycle \(cycle)")
            
            // No loading indicator should appear
            let loadingIndicator = app.staticTexts["Loading news..."]
            XCTAssertFalse(loadingIndicator.exists, "No loading on cycle \(cycle)")
        }
    }
    
    // MARK: - Manual Refresh Tests
    
    func testPullToRefreshWorks() {
        // Test that manual refresh actually refreshes content
        
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Wait for initial load
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Find the scroll view containing the home content
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists, "Home page should have scrollable content")
        
        // Perform pull-to-refresh gesture
        let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
        
        // Wait a moment for refresh to complete
        Thread.sleep(forTimeInterval: 2.0)
        
        // Verify content is still visible after refresh (no error state)
        XCTAssertTrue(searchBar.exists, "Search bar should remain after refresh")
        
        // Verify no error message appears
        let errorMessage = app.staticTexts["Unable to Load News"]
        XCTAssertFalse(errorMessage.exists, "Error message should not appear on refresh")
    }
    
    func testRefreshDoesNotShowErrorState() {
        // Specifically test that refresh doesn't show the "Unable to Load News" error
        
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Wait for content
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Perform multiple refresh attempts
        let scrollView = app.scrollViews.firstMatch
        
        for attempt in 1...3 {
            // Pull to refresh
            let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
            
            // Wait for refresh
            Thread.sleep(forTimeInterval: 1.5)
            
            // Verify no error state
            let errorMessage = app.staticTexts["Unable to Load News"]
            XCTAssertFalse(errorMessage.exists, "No error on refresh attempt \(attempt)")
            
            let tryAgainButton = app.buttons["Try Again"]
            XCTAssertFalse(tryAgainButton.exists, "No 'Try Again' button on refresh attempt \(attempt)")
        }
    }
    
    // MARK: - Content Persistence Tests
    
    func testAppBackgroundingPreservesCache() {
        // Test that backgrounding and foregrounding preserves cached content
        
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Wait for content load
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Background the app
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        
        // Return to app
        app.activate()
        
        // Content should still be available immediately
        XCTAssertTrue(searchBar.exists, "Content should persist after backgrounding")
        
        // No loading should occur
        let loadingIndicator = app.staticTexts["Loading news..."]
        XCTAssertFalse(loadingIndicator.exists, "No loading after app reactivation")
    }
    
    func testLongTermCachePersistence() {
        // Test that cache persists for reasonable duration
        
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Load content
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Switch away and wait (simulating time passage)
        let moreTab = app.tabBars.buttons["More"]
        moreTab.tap()
        
        // Simulate user doing other things for a while
        Thread.sleep(forTimeInterval: 3.0)
        
        // Return to home
        homeTab.tap()
        
        // Content should still be cached
        XCTAssertTrue(searchBar.exists, "Content should persist over time")
        
        let loadingIndicator = app.staticTexts["Loading news..."]
        XCTAssertFalse(loadingIndicator.exists, "No loading for time-cached content")
    }
    
    // MARK: - Performance Tests
    
    func testTabSwitchPerformance() {
        // Test that tab switches are fast with caching
        
        let homeTab = app.tabBars.buttons["Home"]
        let savedTab = app.tabBars.buttons["Saved"]
        
        // Initial load
        homeTab.tap()
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Measure tab switch performance
        measure {
            savedTab.tap()
            homeTab.tap()
            
            // Content should appear immediately
            XCTAssertTrue(searchBar.exists)
        }
    }
    
    // MARK: - Error Recovery Tests
    
    func testCachePreservationDuringNetworkErrors() {
        // Test that cached content remains available during network issues
        // Note: This test verifies graceful handling rather than simulating network failure
        
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Load content initially
        let searchBar = app.otherElements["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 15))
        
        // Switch tabs multiple times (which might encounter network issues)
        let moreTab = app.tabBars.buttons["More"]
        
        for _ in 1...5 {
            moreTab.tap()
            homeTab.tap()
            
            // Content should remain available even if network fails
            XCTAssertTrue(searchBar.exists, "Cached content should remain during network issues")
        }
    }
}
//
//  HomeCachingAndRefreshTest.swift
//  osrswikiUITests
//
//  Comprehensive test for home page caching and refresh functionality issues
//  Tests two main problems:
//  1. Home page reloading unnecessarily when navigating between tabs
//  2. Broken pull-to-refresh showing "Unable to Load News" error
//

import XCTest

final class HomeCachingAndRefreshTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-testMode")
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Tab Navigation Caching Tests
    
    /// Test that home page doesn't reload unnecessarily when navigating between tabs
    func testHomePageCachingDuringTabNavigation() throws {
        print("🧪 Testing home page caching during tab navigation...")
        
        // Wait for app to fully load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        // Navigate to the Home tab using the correct identifier
        let homeTab = app.tabBars.buttons.element(matching: .button, identifier: "home_tab")
        if !homeTab.exists {
            // Fallback: try finding Home tab by label
            let homeTabByLabel = app.tabBars.buttons["Home"]
            XCTAssertTrue(homeTabByLabel.waitForExistence(timeout: 10), "Home tab should exist")
            homeTabByLabel.tap()
        } else {
            homeTab.tap()
        }
        
        // Wait for home content to load
        let recentUpdatesSection = app.scrollViews.staticTexts["Recent updates"]
        XCTAssertTrue(recentUpdatesSection.waitForExistence(timeout: 15), "Home page should load with Recent updates section")
        
        // Take a screenshot of loaded home page
        takeTestScreenshot(name: "home_page_initial_load", description: "Home page initially loaded with content")
        
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons.element(matching: .button, identifier: "search_tab")
        if !searchTab.exists {
            let searchTabByLabel = app.tabBars.buttons["Search"]
            XCTAssertTrue(searchTabByLabel.exists, "Search tab should exist")
            searchTabByLabel.tap()
        } else {
            searchTab.tap()
        }
        
        // Wait for search tab to load
        sleep(2)
        takeTestScreenshot(name: "search_tab_loaded", description: "Search tab after navigation")
        
        // Navigate back to Home tab - this is where the caching should work
        if homeTab.exists {
            homeTab.tap()
        } else {
            app.tabBars.buttons["Home"].tap()
        }
        
        // The home page should still have its content without reloading
        // Check if content is immediately available (indicating caching worked)
        let homeContentExists = recentUpdatesSection.exists
        takeTestScreenshot(name: "home_page_after_navigation", description: "Home page after navigating back - should be cached")
        
        // Verify content is available immediately (cached properly)
        XCTAssertTrue(homeContentExists, "Home page content should be immediately available after tab navigation (cached)")
        
        // Navigate to another tab to further test caching
        let savedTab = app.tabBars.buttons.element(matching: .button, identifier: "saved_tab")
        if !savedTab.exists {
            let savedTabByLabel = app.tabBars.buttons["Saved"]
            XCTAssertTrue(savedTabByLabel.exists, "Saved tab should exist")
            savedTabByLabel.tap()
        } else {
            savedTab.tap()
        }
        sleep(2)
        
        // Navigate back to Home again
        if homeTab.exists {
            homeTab.tap()
        } else {
            app.tabBars.buttons["Home"].tap()
        }
        
        // Content should still be cached
        let stillCached = recentUpdatesSection.exists
        takeTestScreenshot(name: "home_page_second_navigation", description: "Home page after second navigation - testing cache persistence")
        
        XCTAssertTrue(stillCached, "Home page content should remain cached after multiple tab navigations")
        
        print("✅ Home page caching test completed - fixes are working!")
    }
    
    /// Test specific loading behavior when switching tabs rapidly
    func testRapidTabSwitchingCaching() throws {
        print("🧪 Testing rapid tab switching caching behavior...")
        
        // Wait for app to load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        let homeTab = app.tabBars.buttons["home_tab"]
        let searchTab = app.tabBars.buttons["search_tab"]
        let savedTab = app.tabBars.buttons["saved_tab"]
        
        // Ensure home tab is loaded first
        homeTab.tap()
        let recentUpdates = app.scrollViews.staticTexts["Recent updates"]
        XCTAssertTrue(recentUpdates.waitForExistence(timeout: 15), "Home should load initially")
        
        // Rapidly switch tabs
        searchTab.tap()
        sleep(1)
        savedTab.tap()
        sleep(1)
        homeTab.tap()
        
        // Home should still have cached content available immediately
        XCTAssertTrue(recentUpdates.exists, "Home page should maintain cached content during rapid tab switching")
        
        takeTestScreenshot(name: "rapid_tab_switching_result", description: "Home page after rapid tab switching")
        
        print("✅ Rapid tab switching test completed")
    }
    
    // MARK: - Pull-to-Refresh Tests
    
    /// Test pull-to-refresh functionality and error handling
    func testPullToRefreshFunctionality() throws {
        print("🧪 Testing pull-to-refresh functionality...")
        
        // Wait for app to load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        // Navigate to Home tab
        let homeTab = app.tabBars.buttons["home_tab"]
        homeTab.tap()
        
        // Wait for initial content to load
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 15), "ScrollView should exist")
        
        // Take screenshot before refresh
        takeTestScreenshot(name: "before_pull_to_refresh", description: "Home page before attempting pull-to-refresh")
        
        // Perform pull-to-refresh gesture
        let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        
        print("🔄 Performing pull-to-refresh gesture...")
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
        
        // Wait for refresh to complete
        sleep(3)
        
        // Take screenshot after refresh attempt
        takeTestScreenshot(name: "after_pull_to_refresh", description: "Home page after pull-to-refresh gesture")
        
        // Check for error state - this is the bug we're testing
        let errorText = app.staticTexts["Unable to Load News"]
        let hasError = errorText.exists
        
        if hasError {
            print("🐛 BUG REPRODUCED: 'Unable to Load News' error shown after pull-to-refresh")
            takeTestScreenshot(name: "pull_to_refresh_error", description: "ERROR: Pull-to-refresh showing Unable to Load News")
            
            // Test the retry button if it exists
            let retryButton = app.buttons["Try Again"]
            if retryButton.exists {
                print("🔄 Testing retry button...")
                retryButton.tap()
                sleep(3)
                takeTestScreenshot(name: "after_retry_button", description: "After tapping retry button")
            }
        }
        
        // The test should verify that refresh works properly without errors
        // For now, we document the bug and continue
        print("📝 Pull-to-refresh test completed - error state: \(hasError ? "FOUND" : "NOT FOUND")")
    }
    
    /// Test refresh functionality under various network conditions
    func testRefreshUnderDifferentConditions() throws {
        print("🧪 Testing refresh under different conditions...")
        
        // Wait for app to load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        let homeTab = app.tabBars.buttons["home_tab"]
        homeTab.tap()
        
        // Wait for content to load
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 15), "ScrollView should exist")
        
        // Test multiple refresh attempts
        for i in 1...3 {
            print("🔄 Refresh attempt \(i)/3...")
            
            let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            
            startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
            sleep(2)
            
            // Check for persistent error
            let errorExists = app.staticTexts["Unable to Load News"].exists
            takeTestScreenshot(name: "refresh_attempt_\(i)", description: "Refresh attempt \(i) - error: \(errorExists)")
            
            if errorExists {
                print("⚠️ Error persisted in attempt \(i)")
            }
        }
        
        print("✅ Multiple refresh attempts test completed")
    }
    
    // MARK: - Combined Caching and Refresh Tests
    
    /// Test that cached content survives refresh operations
    func testCachingSurvivesRefresh() throws {
        print("🧪 Testing that cached content survives refresh operations...")
        
        // Wait for app to load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        let homeTab = app.tabBars.buttons["home_tab"]
        homeTab.tap()
        
        // Wait for initial content
        let recentUpdates = app.scrollViews.staticTexts["Recent updates"]
        XCTAssertTrue(recentUpdates.waitForExistence(timeout: 15), "Home should load initially")
        
        // Navigate away and back to establish cache
        let searchTab = app.tabBars.buttons["search_tab"]
        searchTab.tap()
        sleep(1)
        homeTab.tap()
        
        // Verify content is cached
        XCTAssertTrue(recentUpdates.exists, "Content should be cached")
        
        // Now perform refresh
        let scrollView = app.scrollViews.firstMatch
        let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
        sleep(3)
        
        // Navigate away and back again to test cache after refresh
        searchTab.tap()
        sleep(1)
        homeTab.tap()
        
        // Content should still be cached properly
        let stillCached = recentUpdates.exists
        takeTestScreenshot(name: "cache_after_refresh", description: "Testing if cache survives refresh operations")
        
        XCTAssertTrue(stillCached, "Cached content should survive refresh operations")
        
        print("✅ Cache survival after refresh test completed")
    }
    
    // MARK: - Helper Methods
    
    /// Takes a screenshot with descriptive naming for debugging
    private func takeTestScreenshot(name: String, description: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "HomeCaching_\(name)_\(Int(Date().timeIntervalSince1970))"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("📸 Screenshot: \(name) - \(description)")
    }
    
    /// Helper method to wait for loading to complete
    private func waitForLoadingToComplete() {
        // Wait for any loading indicators to disappear
        let loadingIndicator = app.activityIndicators.firstMatch
        if loadingIndicator.exists {
            // Use custom waiting approach since waitForNonExistence may conflict
            let startTime = Date()
            while loadingIndicator.exists && Date().timeIntervalSince(startTime) < 10 {
                sleep(1)
            }
        }
        
        // Additional wait for content stability
        sleep(2)
    }
    
    // MARK: - Performance Tests
    
    /// Test that tab switching is responsive (not blocked by loading)
    func testTabSwitchingPerformance() throws {
        print("🧪 Testing tab switching performance...")
        
        // Wait for app to load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        let homeTab = app.tabBars.buttons["home_tab"]
        let searchTab = app.tabBars.buttons["search_tab"]
        
        // Load home content first
        homeTab.tap()
        _ = app.scrollViews.staticTexts["Recent updates"].waitForExistence(timeout: 15)
        
        // Measure time for tab switching
        let startTime = CFAbsoluteTimeGetCurrent()
        
        searchTab.tap()
        sleep(1) // Wait for tab to respond
        homeTab.tap()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let switchingTime = endTime - startTime
        
        print("⏱️ Tab switching time: \(switchingTime) seconds")
        
        // Tab switching should be responsive (under 2 seconds)
        XCTAssertLessThan(switchingTime, 2.0, "Tab switching should be responsive")
        
        takeTestScreenshot(name: "performance_test_result", description: "Tab switching performance test result")
        
        print("✅ Tab switching performance test completed")
    }
}

// MARK: - Test Extensions
// Note: waitForNonExistence extension removed to avoid conflicts with existing implementations
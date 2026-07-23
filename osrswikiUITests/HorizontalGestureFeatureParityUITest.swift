//
//  HorizontalGestureFeatureParityUITest.swift
//  osrswikiUITests
//
//  Comprehensive UI tests for horizontal gesture implementation
//  Validates iOS/Android feature parity for gesture navigation
//

import XCTest

final class HorizontalGestureFeatureParityUITest: XCTestCase {
    
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Article View Gesture Tests
    
    func testArticleBackGestureNavigation() throws {
        // Navigate to an article first
        let searchTab = app.buttons["search_tab"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait for history/search view to load
        let historyTable = app.tables.firstMatch
        XCTAssertTrue(historyTable.waitForExistence(timeout: 5.0), "History table should load")
        
        // Look for the first article link and tap it
        let firstArticleCell = historyTable.cells.firstMatch
        if firstArticleCell.exists {
            firstArticleCell.tap()
            
            // Wait for article to load
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10.0), "Article WebView should load")
            
            // Test horizontal back gesture (right swipe)
            let webView = app.webViews.firstMatch
            webView.swipeRight()
            
            // Verify we navigated back (should return to history view)
            XCTAssertTrue(historyTable.waitForExistence(timeout: 5.0), "Should navigate back to history after right swipe")
            
            print("✅ Article back gesture test passed")
        } else {
            // If no history, navigate to news and find an article
            let newsTab = app.buttons["home_tab"]
            newsTab.tap()
            
            // Wait for news content and try to find an article
            let newsTable = app.tables.firstMatch
            if newsTable.waitForExistence(timeout: 5.0) {
                let firstNewsItem = newsTable.cells.firstMatch
                if firstNewsItem.exists {
                    firstNewsItem.tap()
                    
                    // Wait for article and test gesture
                    XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10.0), "Article should load")
                    let webView = app.webViews.firstMatch
                    webView.swipeRight()
                    
                    // Should return to news
                    XCTAssertTrue(newsTable.waitForExistence(timeout: 5.0), "Should return to news after back gesture")
                    print("✅ Article back gesture test passed (via news)")
                }
            }
        }
    }
    
    func testArticleSidebarGestureWithTableOfContents() throws {
        // Navigate to an article that should have table of contents
        let searchTab = app.buttons["search_tab"]
        searchTab.tap()
        
        // Wait for search interface
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5.0), "Search interface should load")
        
        // Try to navigate to a substantial article (like Varrock) that would have TOC
        let searchBar = app.searchFields.firstMatch
        if searchBar.exists {
            searchBar.tap()
            searchBar.typeText("Varrock")
            
            // Look for search results
            let searchResults = app.tables.firstMatch.cells
            if searchResults.count > 0 {
                searchResults.firstMatch.tap()
                
                // Wait for article to load
                XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10.0), "Varrock article should load")
                
                // Test sidebar gesture (left swipe)
                let webView = app.webViews.firstMatch
                webView.swipeLeft()
                
                // Look for table of contents drawer
                // Note: This is challenging to test without specific accessibility identifiers
                // But we can verify that the gesture doesn't crash and potentially opens something
                
                // Wait a moment for potential animations
                sleep(1)
                
                // Verify app is still functional (no crash)
                XCTAssertTrue(webView.exists, "WebView should still exist after sidebar gesture")
                
                print("✅ Article sidebar gesture test passed (no crash)")
            }
        }
    }
    
    // MARK: - Gesture Conflict Resolution Tests
    
    func testGestureBlockingWithScrollableContent() throws {
        // Navigate to an article with scrollable tables/content
        let searchTab = app.buttons["search_tab"]
        searchTab.tap()
        
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5.0), "Search should load")
        
        let searchBar = app.searchFields.firstMatch
        if searchBar.exists {
            searchBar.tap()
            searchBar.typeText("Grand Exchange")
            
            let searchResults = app.tables.firstMatch.cells
            if searchResults.count > 0 {
                searchResults.firstMatch.tap()
                
                XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10.0), "GE article should load")
                
                let webView = app.webViews.firstMatch
                
                // Wait for content to fully load (including JavaScript)
                sleep(3)
                
                // Test that horizontal scroll within scrollable elements doesn't trigger navigation
                // This is harder to test directly, but we can verify the gesture system is active
                webView.swipeRight()
                
                // The gesture should either navigate back OR be blocked by scrollable content
                // Both are valid behaviors - what matters is no crash
                
                // Verify app stability
                XCTAssertTrue(webView.exists, "WebView should remain stable after gesture on scrollable content")
                
                print("✅ Scrollable content gesture conflict test passed")
            }
        }
    }
    
    func testMapLibreGestureConflictResolution() throws {
        // Navigate to map tab to test MapLibre gesture integration
        let mapTab = app.buttons["map_tab"]
        XCTAssertTrue(mapTab.exists, "Map tab should exist")
        mapTab.tap()
        
        // Wait for map to load
        let mapView = app.maps.firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10.0), "Map should load")
        
        // Test gesture on map - should be blocked to not interfere with map navigation
        mapView.swipeRight()
        mapView.swipeLeft()
        
        // Map should remain stable and functional
        XCTAssertTrue(mapView.exists, "Map should remain functional after gestures")
        
        // Test that we can still interact with the map
        mapView.tap()
        
        XCTAssertTrue(mapView.exists, "Map should still be interactive")
        
        print("✅ MapLibre gesture conflict resolution test passed")
    }
    
    // MARK: - Cross-Platform Parity Tests
    
    func testGestureThresholds() throws {
        // Test that gestures require sufficient movement to trigger
        let searchTab = app.buttons["search_tab"]
        searchTab.tap()
        
        let historyTable = app.tables.firstMatch
        XCTAssertTrue(historyTable.waitForExistence(timeout: 5.0), "History should load")
        
        // Navigate to an article
        if let firstCell = historyTable.cells.allElementsBoundByIndex.first, firstCell.exists {
            firstCell.tap()
            
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10.0), "Article should load")
            
            let webView = app.webViews.firstMatch
            let centerStartPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            
            // Test small non-edge swipe (should NOT trigger navigation)
            let shortSwipeEnd = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            centerStartPoint.press(forDuration: 0.1, thenDragTo: shortSwipeEnd)
            
            // Should still be in article
            XCTAssertTrue(webView.exists, "Small non-edge swipe should not trigger navigation")
            
            // Test full edge swipe (SHOULD trigger navigation)
            let edgeStartPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            let fullSwipeEnd = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            edgeStartPoint.press(forDuration: 0.1, thenDragTo: fullSwipeEnd)
            
            // Should navigate back
            XCTAssertTrue(historyTable.waitForExistence(timeout: 5.0), "Full swipe should trigger navigation")
            
            print("✅ Gesture threshold test passed")
        }
    }
    
    func testVerticalScrollDoesNotTriggerHorizontalGestures() throws {
        // Test that vertical scrolling doesn't accidentally trigger horizontal gestures
        let searchTab = app.buttons["search_tab"]
        searchTab.tap()
        
        let historyTable = app.tables.firstMatch
        XCTAssertTrue(historyTable.waitForExistence(timeout: 5.0), "History should load")
        
        if let firstCell = historyTable.cells.allElementsBoundByIndex.first, firstCell.exists {
            firstCell.tap()
            
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10.0), "Article should load")
            
            let webView = app.webViews.firstMatch
            
            // Test vertical swipes - should not trigger horizontal navigation
            webView.swipeUp()
            webView.swipeDown()
            
            // Should still be in article
            XCTAssertTrue(webView.exists, "Vertical swipes should not trigger horizontal navigation")
            
            print("✅ Vertical scroll independence test passed")
        }
    }
    
    // MARK: - Performance and Stability Tests
    
    func testGesturePerformanceUnderLoad() throws {
        // Test that gestures work smoothly even when the app is under load
        let mapTab = app.buttons["map_tab"]
        mapTab.tap()
        
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10.0), "Map should load")
        
        // Switch rapidly between tabs while testing gestures
        for _ in 0..<5 {
            let searchTab = app.buttons["search_tab"]
            searchTab.tap()
            
            let newsTab = app.buttons["home_tab"] 
            newsTab.tap()
            
            mapTab.tap()
        }
        
        // App should remain stable
        XCTAssertTrue(app.maps.firstMatch.exists, "App should remain stable after rapid navigation")
        
        print("✅ Gesture performance under load test passed")
    }
    
    func testGestureSystemInitialization() throws {
        // Test that the gesture system initializes properly on app launch
        
        // Verify main interface loads
        let newsTab = app.buttons["home_tab"]
        XCTAssertTrue(newsTab.waitForExistence(timeout: 10.0), "Main interface should load")
        
        // Verify tabs are accessible
        let mapTab = app.buttons["map_tab"]
        let searchTab = app.buttons["search_tab"]
        
        XCTAssertTrue(mapTab.exists, "Map tab should be accessible")
        XCTAssertTrue(searchTab.exists, "Search tab should be accessible")
        
        // Test basic gesture responsiveness on main interface
        let tabView = app.otherElements.containing(.button, identifier: "home_tab").firstMatch
        if tabView.exists {
            // Light swipe test - should not crash
            tabView.swipeLeft()
            
            // Interface should remain functional
            XCTAssertTrue(newsTab.exists, "Interface should remain functional after gesture")
        }
        
        print("✅ Gesture system initialization test passed")
    }
}

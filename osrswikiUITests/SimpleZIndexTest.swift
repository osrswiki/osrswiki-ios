import XCTest

final class SimpleZIndexTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        Thread.sleep(forTimeInterval: 3.0)
    }
    
    func testBasicNavigationToArticleWithMap() throws {
        print("🔍 Simple Z-Index Test: Basic navigation to article with potential map widget")
        
        // Navigate to Search tab - try multiple ways to find it
        var searchTabTapped = false
        
        // Method 1: Try "Search" button
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
            searchTabTapped = true
            print("✅ Tapped Search tab via 'Search' identifier")
        } else {
            // Method 2: Try tab bar buttons by index
            let tabButtons = app.tabBars.buttons
            print("📊 Found \(tabButtons.count) tab bar buttons")
            
            // Usually Search is the second tab (index 1)
            if tabButtons.count >= 2 {
                let secondTab = tabButtons.element(boundBy: 1)
                if secondTab.exists {
                    secondTab.tap()
                    searchTabTapped = true
                    print("✅ Tapped Search tab via index 1")
                }
            }
            
            // Method 3: Try searching for any tappable element with "search" in accessibility info
            if !searchTabTapped {
                let allButtons = app.descendants(matching: .button)
                for i in 0..<min(10, allButtons.count) {
                    let button = allButtons.element(boundBy: i)
                    let label = button.label.lowercased()
                    if label.contains("search") {
                        button.tap()
                        searchTabTapped = true
                        print("✅ Tapped Search tab via accessibility search")
                        break
                    }
                }
            }
        }
        
        XCTAssertTrue(searchTabTapped, "Should be able to navigate to Search tab")
        Thread.sleep(forTimeInterval: 2.0)
        
        // Look for search field
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            
            // Search for "Lumbridge" - known to have maps
            searchField.typeText("Lumbridge")
            print("✅ Typed 'Lumbridge' in search")
            Thread.sleep(forTimeInterval: 2.0)
            
            // Look for search results and tap first one
            let cells = app.cells
            if cells.count > 0 {
                let firstCell = cells.firstMatch
                if firstCell.exists {
                    firstCell.tap()
                    print("✅ Tapped first search result")
                    Thread.sleep(forTimeInterval: 5.0) // Wait for article to load
                    
                    // Take screenshot to see current state
                    takeScreenshot(name: "lumbridge_article_loaded", description: "Lumbridge article with potential MapLibre widget")
                    
                    // Look for any WebView content
                    let webView = app.webViews.firstMatch
                    if webView.exists {
                        print("✅ WebView found - article loaded")
                        
                        // Try scrolling to reveal more content
                        webView.swipeUp()
                        Thread.sleep(forTimeInterval: 2.0)
                        
                        // Take another screenshot after scrolling
                        takeScreenshot(name: "after_scroll", description: "After scrolling in article")
                        
                        // Try tapping in various areas that might contain infobox
                        let tapPoints = [
                            CGVector(dx: 0.8, dy: 0.3),  // Right side where infoboxes usually are
                            CGVector(dx: 0.85, dy: 0.4),
                            CGVector(dx: 0.9, dy: 0.2)
                        ]
                        
                        for (index, point) in tapPoints.enumerated() {
                            print("👆 Tapping at point \(index + 1): \(point)")
                            webView.coordinate(withNormalizedOffset: point).tap()
                            Thread.sleep(forTimeInterval: 3.0) // Give time for any widget to appear
                            
                            takeScreenshot(name: "tap_\(index + 1)", description: "After tap \(index + 1) at \(point)")
                        }
                        
                        // Final state
                        takeScreenshot(name: "final_state", description: "Final state after all interactions")
                        
                    } else {
                        print("❌ No WebView found")
                        XCTFail("WebView should be available for article content")
                    }
                } else {
                    print("❌ First cell doesn't exist")
                    XCTFail("Search results should be available")
                }
            } else {
                print("❌ No cells found")
                takeScreenshot(name: "no_search_results", description: "No search results found")
                XCTFail("Search should return results")
            }
        } else {
            print("❌ Search field not found")
            takeScreenshot(name: "no_search_field", description: "Search field not found")
            XCTFail("Search field should be available")
        }
        
        print("🏁 Test completed - check screenshots and console logs")
    }
    
    private func takeScreenshot(name: String, description: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Screenshot saved: \(name) - \(description)")
    }
}
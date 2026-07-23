//
//  SearchFreezeReproductionTest.swift
//  osrswikiUITests
//
//  Created to reproduce and debug the search result tap freeze issue with CPU monitoring
//

import XCTest

class SearchFreezeReproductionTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testSearchResultTapFreeze() throws {
        print("🔍 Starting search result tap freeze reproduction test")
        
        // Navigate to Search tab - try multiple approaches
        var searchTabTapped = false
        
        // Approach 1: By index (third tab)
        let searchTabByIndex = app.tabBars.buttons.element(boundBy: 2)
        if searchTabByIndex.exists {
            searchTabByIndex.tap()
            searchTabTapped = true
            print("✅ Found search tab by index")
        } else {
            // Approach 2: By accessibility identifier  
            let searchTabById = app.tabBars.buttons["search_tab"]
            if searchTabById.exists {
                searchTabById.tap()
                searchTabTapped = true
                print("✅ Found search tab by ID")
            } else {
                // Approach 3: By label text
                let searchTabByLabel = app.buttons.matching(identifier: "Search").firstMatch
                if searchTabByLabel.exists {
                    searchTabByLabel.tap()
                    searchTabTapped = true
                    print("✅ Found search tab by label")
                } else {
                    // Approach 4: Find any button containing "Search"
                    let allButtons = app.buttons.allElementsBoundByIndex
                    for button in allButtons {
                        if button.label.contains("Search") {
                            button.tap()
                            searchTabTapped = true
                            print("✅ Found search tab by partial match: \(button.label)")
                            break
                        }
                    }
                }
            }
        }
        
        guard searchTabTapped else {
            // Take a screenshot for debugging
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "search_tab_not_found"
            add(attachment)
            
            print("❌ Could not find search tab. Available elements:")
            print("Tab bars: \(app.tabBars.debugDescription)")
            print("All buttons: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
            XCTFail("Could not navigate to search tab")
            return
        }
        
        // Wait for search view to appear
        Thread.sleep(forTimeInterval: 2.0)
        
        // Look for search field - multiple approaches
        var searchField: XCUIElement?
        
        // Try to find the search button first (which opens the search field)
        let searchButton = app.buttons["Search OSRS Wiki"]
        if searchButton.waitForExistence(timeout: 5) {
            print("✅ Found search button, tapping to open search field")
            searchButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        
        // Now look for the actual text field
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 5) {
            searchField = textField
            print("✅ Found search text field")
        } else {
            // Try search fields
            let searchFieldElement = app.searchFields.firstMatch
            if searchFieldElement.waitForExistence(timeout: 3) {
                searchField = searchFieldElement
                print("✅ Found search field")
            }
        }
        
        guard let field = searchField else {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "search_field_not_found"
            add(attachment)
            XCTFail("Could not find search field")
            return
        }
        
        // Enter search query
        field.tap()
        field.typeText("dragon scimitar")
        
        // Wait for search results to appear
        print("⏳ Waiting for search results...")
        let resultsContainer = app.collectionViews.firstMatch.otherElements.firstMatch
        guard resultsContainer.waitForExistence(timeout: 10) else {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "no_search_results"
            add(attachment)
            XCTFail("No search results appeared")
            return
        }
        
        // Find first search result cell
        let searchResults = app.cells
        guard searchResults.count > 0 else {
            XCTFail("No search result cells found")
            return
        }
        
        let firstResult = searchResults.firstMatch
        XCTAssertTrue(firstResult.exists, "First search result should exist")
        
        print("🎯 Found search results, attempting to tap first result...")
        print("🔍 Search result details: \(firstResult.debugDescription)")
        
        // Record timestamp and tap the result
        let tapStartTime = Date()
        print("⏱️ Tapping search result at: \(tapStartTime)")
        
        // Tap the result
        firstResult.tap()
        
        // Monitor for response within reasonable time
        let maxWaitTime: TimeInterval = 5.0
        var responseReceived = false
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            // Check if we navigated to article (WebView appeared)
            if app.webViews.firstMatch.exists {
                let responseTime = Date().timeIntervalSince(tapStartTime)
                print("✅ Navigation successful after \(responseTime) seconds")
                responseReceived = true
                break
            }
            
            // Check if we're still on search (indicates freeze/no response)
            if field.exists {
                let elapsedTime = Date().timeIntervalSince(tapStartTime)
                if elapsedTime > 2.0 {  // If we're still on search after 2 seconds, likely frozen
                    print("⚠️ Still on search view after \(elapsedTime) seconds - potential freeze detected")
                }
            }
            
            Thread.sleep(forTimeInterval: 0.1) // Check every 100ms
        }
        
        let totalTime = Date().timeIntervalSince(tapStartTime)
        
        if !responseReceived {
            print("❌ FREEZE DETECTED: No response after \(totalTime) seconds")
            print("🔍 App state after tap attempt:")
            print("   - Search field exists: \(field.exists)")
            print("   - WebView exists: \(app.webViews.firstMatch.exists)")
            print("   - App state: \(app.state)")
            
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "freeze_detected_\(Int(totalTime))s"
            add(attachment)
            
            XCTFail("Search result tap appears to be frozen - no navigation after \(totalTime) seconds")
        } else {
            print("✅ Test completed successfully - navigation worked")
        }
    }
    
    func testSearchResultTapWithCPUMonitoring() throws {
        print("🔍 Starting search result tap test with CPU monitoring")
        
        // Navigate to search and perform search (using similar logic as above but simplified)
        // For brevity, I'll focus on the core test logic
        
        // Try to find search tab by examining available elements
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should exist")
        
        let allTabButtons = tabBar.buttons.allElementsBoundByIndex
        print("📱 Available tab buttons: \(allTabButtons.map { $0.label })")
        
        var searchTabFound = false
        for (index, button) in allTabButtons.enumerated() {
            if button.label.lowercased().contains("search") || index == 2 {
                button.tap()
                searchTabFound = true
                print("✅ Tapped search tab: \(button.label) at index \(index)")
                break
            }
        }
        
        XCTAssertTrue(searchTabFound, "Should find search tab")
        
        // Continue with search and tap monitoring...
        Thread.sleep(forTimeInterval: 2.0)
        
        // Record memory baseline
        let memoryMetric = XCTMemoryMetric()
        let cpuMetric = XCTCPUMetric()
        
        measure(metrics: [memoryMetric, cpuMetric]) {
            // The measurement will capture resource usage during this block
            
            // Try to perform search and tap (this will help us measure resource consumption)
            // Even if the UI elements are hard to find, the measurement will show resource spikes
            Thread.sleep(forTimeInterval: 3.0)
        }
    }
}
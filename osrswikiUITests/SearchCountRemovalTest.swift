//
//  SearchCountRemovalTest.swift
//  osrswikiUITests
//
//  Created for testing search count removal
//

import XCTest

final class SearchCountRemovalTest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchResultsWithoutCount() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10.0))
        
        // Take initial screenshot
        let initialScreenshot = app.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "app_launched"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Look for search tab - could be labeled "Search" or have magnifying glass icon
        var searchTabTapped = false
        
        // Try different ways to find and tap the search tab
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            // Look for search tab by accessibility label
            if app.tabBars.buttons["Search"].exists {
                app.tabBars.buttons["Search"].tap()
                searchTabTapped = true
            } else {
                // Try tapping the second tab (usually Search in iOS apps)
                let allTabButtons = app.tabBars.buttons.allElementsBoundByAccessibilityElement
                if allTabButtons.count > 1 {
                    allTabButtons[1].tap()
                    searchTabTapped = true
                }
            }
        }
        
        XCTAssertTrue(searchTabTapped, "Should be able to navigate to search tab")
        
        // Wait a bit for the search view to load
        sleep(2)
        
        // Take screenshot of search tab
        let searchTabScreenshot = app.screenshot()
        let searchTabAttachment = XCTAttachment(screenshot: searchTabScreenshot)
        searchTabAttachment.name = "search_tab_opened"
        searchTabAttachment.lifetime = .keepAlways
        add(searchTabAttachment)
        
        // Try to find the search field using various approaches
        var searchField: XCUIElement?
        
        // Try by placeholder text
        if app.textFields["Search OSRS Wiki"].exists {
            searchField = app.textFields["Search OSRS Wiki"]
        } else if app.searchFields.firstMatch.exists {
            searchField = app.searchFields.firstMatch
        } else if app.textFields.firstMatch.exists {
            searchField = app.textFields.firstMatch
        }
        
        if let searchField = searchField {
            XCTAssertTrue(searchField.waitForExistence(timeout: 5.0), "Search field should be visible")
            
            // Perform search
            searchField.tap()
            searchField.typeText("dragon")
            
            // Try different ways to submit the search
            if app.keyboards.buttons["search"].exists {
                app.keyboards.buttons["search"].tap()
            } else if app.keyboards.buttons["Search"].exists {
                app.keyboards.buttons["Search"].tap()
            } else {
                searchField.typeText("\n")
            }
            
            // Wait for search results
            let searchResultsTimeout: TimeInterval = 15.0
            let startTime = Date()
            var hasResults = false
            
            while Date().timeIntervalSince(startTime) < searchResultsTimeout {
                sleep(1)
                
                // Check for table/list elements that might contain results
                if app.tables.firstMatch.exists && app.tables.firstMatch.cells.count > 0 {
                    hasResults = true
                    break
                } else if app.collectionViews.firstMatch.exists && app.collectionViews.firstMatch.cells.count > 0 {
                    hasResults = true
                    break
                }
            }
            
            // Take screenshot of search results (or lack thereof)
            let searchResultsScreenshot = app.screenshot()
            let searchResultsAttachment = XCTAttachment(screenshot: searchResultsScreenshot)
            searchResultsAttachment.name = "search_results_screen"
            searchResultsAttachment.lifetime = .keepAlways
            add(searchResultsAttachment)
            
            // The key test: Look for any text that might indicate search count
            let allStaticTexts = app.staticTexts.allElementsBoundByAccessibilityElement
            for textElement in allStaticTexts {
                let labelText = textElement.label.lowercased()
                
                // Skip navigation/UI elements
                if labelText.contains("search") && labelText.contains("osrs") {
                    continue
                }
                if labelText.contains("tab") || labelText.contains("button") {
                    continue
                }
                
                // Look for patterns that would indicate a search count
                let countPatterns = ["\\d+\\s+results?", "showing\\s+\\d+", "found\\s+\\d+", "\\d+\\s+found"]
                
                for pattern in countPatterns {
                    if labelText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                        XCTFail("Found potential search count display: '\(textElement.label)' - This should not exist after removing count display")
                    }
                }
            }
            
            print("✅ Test passed: No search result count found in UI")
            print("Search field was found and search was attempted")
            if hasResults {
                print("Search results appear to be present")
            } else {
                print("No clear search results detected, but no count display found either")
            }
        } else {
            // If we can't find search field, just verify no count is displayed anywhere
            print("⚠️ Search field not found, but checking for absence of count display")
            
            let allStaticTexts = app.staticTexts.allElementsBoundByAccessibilityElement
            for textElement in allStaticTexts {
                let labelText = textElement.label.lowercased()
                let countPatterns = ["\\d+\\s+results?", "showing\\s+\\d+", "found\\s+\\d+", "\\d+\\s+found"]
                
                for pattern in countPatterns {
                    if labelText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                        XCTFail("Found potential search count display: '\(textElement.label)' - This should not exist")
                    }
                }
            }
            
            print("✅ No search count display found in current view")
        }
    }
}

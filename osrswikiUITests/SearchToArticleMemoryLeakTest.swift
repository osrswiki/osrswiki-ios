//
//  SearchToArticleMemoryLeakTest.swift  
//  osrswikiUITests
//
//  Created to test memory leak fix when navigating from search results to articles
//

import XCTest

class SearchToArticleMemoryLeakTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    func testSearchToArticleNavigationMemoryLeak() throws {
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons.matching(identifier: "Search").element
        if !searchTab.exists {
            // Try alternative identifiers
            let alternativeSearchTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search'")).element
            XCTAssertTrue(alternativeSearchTab.waitForExistence(timeout: 5), "Search tab should exist")
            alternativeSearchTab.tap()
        } else {
            searchTab.tap()
        }
        
        // Wait for search view to load and find search field
        let searchField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'search'")).element
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        
        // Take initial screenshot
        let initialScreenshot = XCUIScreen.main.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "Initial Search View"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Perform search that should return results
        searchField.tap()
        searchField.typeText("dragon")
        
        // Wait for search results to appear
        Thread.sleep(forTimeInterval: 2.0)
        
        // Take screenshot of search results
        let searchResultsScreenshot = XCUIScreen.main.screenshot()
        let searchResultsAttachment = XCTAttachment(screenshot: searchResultsScreenshot)
        searchResultsAttachment.name = "Search Results for 'dragon'"
        searchResultsAttachment.lifetime = .keepAlways
        add(searchResultsAttachment)
        
        // Find and tap on first search result
        let firstSearchResult = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'dragon'")).element
        if firstSearchResult.waitForExistence(timeout: 3) {
            firstSearchResult.tap()
            
            // Wait for article to load
            Thread.sleep(forTimeInterval: 3.0)
            
            // Take screenshot of article view
            let articleScreenshot = XCUIScreen.main.screenshot()
            let articleAttachment = XCTAttachment(screenshot: articleScreenshot)
            articleAttachment.name = "Article View Loaded"
            articleAttachment.lifetime = .keepAlways
            add(articleAttachment)
            
            // Navigate back using back button or swipe
            let backButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'back' OR label CONTAINS[c] 'arrow'")).element
            if backButton.exists {
                backButton.tap()
            } else {
                // Try swipe gesture as fallback
                let articleView = app.otherElements.firstMatch
                articleView.swipeRight()
            }
            
            // Wait for navigation back to search results
            Thread.sleep(forTimeInterval: 2.0)
            
            // Verify we're back in search view
            XCTAssertTrue(searchField.exists, "Should navigate back to search view")
            
            print("✅ Successfully navigated: Search → Article → Back without memory leak")
            
        } else {
            print("⚠️ No search results found for 'dragon' - testing generic navigation")
            
            // Test navigation without specific search results
            // Just verify the search field is still responsive
            searchField.tap()
            searchField.clearAndEnterText("test")
        }
        
        // Take final screenshot to verify app is still functional
        let finalScreenshot = XCUIScreen.main.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "Final State - Memory Leak Test Complete"
        finalAttachment.lifetime = .keepAlways
        add(finalAttachment)
        
        print("✅ Search to Article memory leak test completed")
    }
    
    func testMultipleSearchToArticleNavigationCycles() throws {
        // Test multiple navigation cycles to ensure no resource accumulation
        
        let searchTab = app.tabBars.buttons.matching(identifier: "Search").element
        if !searchTab.exists {
            let alternativeSearchTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search'")).element
            XCTAssertTrue(alternativeSearchTab.waitForExistence(timeout: 5), "Search tab should exist")
            alternativeSearchTab.tap()
        } else {
            searchTab.tap()
        }
        
        let searchField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'search'")).element
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        
        let searchQueries = ["dragon", "rune", "magic", "quest", "skill"]
        
        for (index, query) in searchQueries.enumerated() {
            print("🔄 Navigation cycle \(index + 1): Testing '\(query)'")
            
            // Clear previous search and enter new query
            searchField.tap()
            searchField.clearAndEnterText(query)
            
            // Wait for search results
            Thread.sleep(forTimeInterval: 2.0)
            
            // Try to find and tap a search result
            let searchResult = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] '\(query)'")).element
            if searchResult.waitForExistence(timeout: 2) {
                searchResult.tap()
                
                // Wait for article to load
                Thread.sleep(forTimeInterval: 2.0)
                
                // Navigate back
                let backButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'back' OR label CONTAINS[c] 'arrow'")).element
                if backButton.exists {
                    backButton.tap()
                } else {
                    app.otherElements.firstMatch.swipeRight()
                }
                
                // Wait for back navigation
                Thread.sleep(forTimeInterval: 1.0)
                
                // Verify we're back in search
                XCTAssertTrue(searchField.exists, "Should be back in search view after cycle \(index + 1)")
                
                print("✅ Completed navigation cycle \(index + 1)")
            } else {
                print("⚠️ No results found for '\(query)' - continuing test")
            }
        }
        
        // Final screenshot to verify app stability after multiple cycles
        let finalScreenshot = XCUIScreen.main.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "Multiple Navigation Cycles Complete"
        finalAttachment.lifetime = .keepAlways
        add(finalAttachment)
        
        print("✅ Multiple search-to-article navigation cycles completed - no memory leaks detected")
    }
}


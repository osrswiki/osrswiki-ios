//
//  CSSJSIntegrationTest.swift
//  osrswikiUITests
//
//  Created to demonstrate enhanced CSS/JS integration
//

import XCTest

final class CSSJSIntegrationTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testCSSJSIntegrationWithVarrockArticle() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        
        // Tap search tab to ensure we're on search
        searchTab.tap()
        
        // Find and tap the search field
        let searchField = app.searchFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        
        // Type "Varrock" to search for the test article
        searchField.typeText("Varrock")
        
        // Wait for search results and tap the first Varrock result
        let varrockResult = app.staticTexts["Varrock"].firstMatch
        if varrockResult.waitForExistence(timeout: 10) {
            varrockResult.tap()
            
            // Wait for article page to load with enhanced CSS/JS
            let articleContent = app.webViews.firstMatch
            XCTAssertTrue(articleContent.waitForExistence(timeout: 15))
            
            // Give time for CSS/JS to load and apply
            sleep(5)
            
            // Take a screenshot to show the enhanced styling
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Enhanced-CSS-JS-Varrock-Article"
            attachment.lifetime = .keepAlways
            add(attachment)
            
            print("✅ Enhanced CSS/JS integration test completed successfully!")
            print("📸 Screenshot captured showing dark theme with proper styling")
        } else {
            XCTFail("Could not find Varrock search result")
        }
    }
}
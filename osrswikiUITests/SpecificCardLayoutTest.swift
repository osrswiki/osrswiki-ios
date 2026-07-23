//
//  SpecificCardLayoutTest.swift
//  osrswikiUITests
//
//  Specific test for Recent Updates card layout verification
//

import XCTest

final class SpecificCardLayoutTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testRecentUpdatesCardDimensions() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Home tab
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        homeTab.tap()
        
        // Wait for content to load
        let recentUpdatesText = app.staticTexts["RECENT UPDATES"]
        XCTAssertTrue(recentUpdatesText.waitForExistence(timeout: 10))
        
        // Look for any content that suggests Recent Updates cards
        // Recent Updates are usually tappable, so they might be buttons or other elements
        let allElements = app.descendants(matching: .any)
        print("Total UI elements found: \(allElements.count)")
        
        // Look for any elements containing "PoH", "Recode", "Fixes", etc.
        var cardElementsFound = 0
        for i in 0..<min(allElements.count, 100) {
            let element = allElements.element(boundBy: i)
            if element.exists {
                let label = element.label
                if label.contains("PoH") || label.contains("Recode") || label.contains("Fix") || 
                   label.contains("Varlamore") || label.contains("Game update") {
                    let frame = element.frame
                    print("RECENT UPDATE CARD FOUND:")
                    print("  Label: '\(label)'")
                    print("  Frame: x=\(frame.origin.x), y=\(frame.origin.y)")  
                    print("  Dimensions: w=\(frame.width), h=\(frame.height)")
                    print("  Element type: \(element.elementType)")
                    
                    // Verify the card has reasonable dimensions
                    XCTAssertGreaterThan(frame.height, 180, "Card height should be > 180px, got \(frame.height)")
                    XCTAssertLessThan(frame.height, 250, "Card height should be < 250px, got \(frame.height)")
                    XCTAssertGreaterThan(frame.width, 250, "Card width should be > 250px, got \(frame.width)")
                    
                    cardElementsFound += 1
                }
            }
        }
        
        print("Total Recent Updates card elements found: \(cardElementsFound)")
        XCTAssertGreaterThan(cardElementsFound, 0, "Should find at least one Recent Updates card")
    }
}
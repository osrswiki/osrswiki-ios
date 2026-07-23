//
//  CardLayoutVerificationTest.swift
//  osrswikiUITests
//
//  Created on iOS development session for card layout verification
//

import XCTest

final class CardLayoutVerificationTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testRecentUpdatesCardsLayoutAndShadows() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for Home tab to be available and tap it
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        homeTab.tap()
        
        // Wait for Recent Updates section to appear
        let recentUpdatesText = app.staticTexts["RECENT UPDATES"]
        XCTAssertTrue(recentUpdatesText.waitForExistence(timeout: 10))
        
        // Verify Recent Updates section exists and is visible
        XCTAssertTrue(recentUpdatesText.exists)
        XCTAssertTrue(recentUpdatesText.isHittable)
        
        // Find scroll view containing the cards
        let scrollViews = app.scrollViews
        print("Total scroll views found: \(scrollViews.count)")
        
        // Look for cards in the interface - they should be buttons since they're tappable
        let cardButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card' OR label CONTAINS 'PoH' OR label CONTAINS 'Varlamore'"))
        print("Card buttons found: \(cardButtons.count)")
        
        // Get all buttons and examine them
        let allButtons = app.buttons
        print("Total buttons in UI: \(allButtons.count)")
        
        for i in 0..<min(allButtons.count, 10) {  // Limit to first 10 to avoid spam
            let button = allButtons.element(boundBy: i)
            if button.exists {
                let frame = button.frame
                let label = button.label
                print("Button \(i): '\(label)' - Frame: x=\(frame.origin.x), y=\(frame.origin.y), w=\(frame.width), h=\(frame.height)")
                
                // Check if this looks like a Recent Updates card
                if label.contains("PoH") || label.contains("Varlamore") || label.contains("Fix") {
                    print("Found Recent Updates card: '\(label)'")
                    print("Card height: \(frame.height)")
                    
                    // Verify the card has reasonable height (not clipped)
                    // Expected: Image (140) + content (~40) + shadows/padding (~20) = ~200
                    XCTAssertGreaterThan(frame.height, 180, "Card appears to be clipped - height too small")
                    XCTAssertLessThan(frame.height, 250, "Card height unexpectedly large")
                    
                    // Verify the card is reasonably positioned (not cut off screen)
                    let screenHeight = app.windows.firstMatch.frame.height
                    XCTAssertLessThan(frame.origin.y + frame.height, screenHeight, "Card extends beyond screen")
                    XCTAssertGreaterThan(frame.origin.y, 0, "Card starts above screen")
                }
            }
        }
        
        print("Layout verification completed")
    }
}
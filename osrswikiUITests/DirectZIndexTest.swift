//
//  DirectZIndexTest.swift
//  osrswikiUITests
//
//  Direct test to debug MapLibre z-index issue
//

import XCTest
import WebKit

final class DirectZIndexTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    /// Direct test: Create an article with MapLibre widget and check z-index
    func testDirectMapLibreZIndex() throws {
        print("🧪 DIRECT Z-INDEX TEST: Creating article with MapLibre widget")
        
        app.launch()
        Thread.sleep(forTimeInterval: 3.0)
        
        // Navigate to search to trigger article loading
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
        } else {
            // Try index-based access
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists {
                let buttons = tabBar.buttons
                if buttons.count > 2 {
                    buttons.element(boundBy: 2).tap() // Usually search is 3rd tab
                }
            }
        }
        
        Thread.sleep(forTimeInterval: 2.0)
        
        // Search for a location that should have a map - "Varrock" is a major city
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            searchField.tap()
            searchField.typeText("Varrock")
            Thread.sleep(forTimeInterval: 1.0)
            
            // Select first result
            let firstResult = app.tables.cells.firstMatch
            if firstResult.exists {
                firstResult.tap()
                Thread.sleep(forTimeInterval: 5.0) // Wait for article and any maps to load
                
                print("📄 Article loaded, checking for navigation elements...")
                
                // Take screenshot for manual inspection
                takeScreenshot(name: "varrock_article_zindex", description: "Varrock article with potential MapLibre widget")
                
                // Check navigation accessibility
                let navigationElements = app.navigationBars
                for nav in navigationElements.allElementsBoundByIndex {
                    print("🧭 Navigation element: \(nav.identifier)")
                    print("   Frame: \(nav.frame)")
                    print("   Hittable: \(nav.isHittable)")
                    print("   Exists: \(nav.exists)")
                }
                
                // Check buttons in navigation
                let navButtons = app.navigationBars.buttons
                for button in navButtons.allElementsBoundByIndex {
                    print("🔘 Nav button: \(button.identifier)")
                    print("   Frame: \(button.frame)")
                    print("   Hittable: \(button.isHittable)")
                }
                
                // Look for any elements that might be MapLibre-related
                let allElements = app.descendants(matching: .any)
                for element in allElements.allElementsBoundByIndex {
                    let identifier = element.identifier.lowercased()
                    if identifier.contains("map") || identifier.contains("kartographer") {
                        print("🗺️ Map-related element found: \(element.identifier)")
                        print("   Frame: \(element.frame)")
                        print("   Hittable: \(element.isHittable)")
                    }
                }
                
                // Core test: Try to tap the top area where navigation should be
                let topCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.05))
                print("🎯 Attempting to tap top-left area (where back button should be)")
                topCoordinate.tap()
                
                Thread.sleep(forTimeInterval: 1.0)
                
                // If we're still on the same page, the tap might have been intercepted by a map
                let currentPageTitle = app.navigationBars.staticTexts.firstMatch.label
                print("📄 Current page after tap: \(currentPageTitle)")
                
                // Final screenshot
                takeScreenshot(name: "after_top_tap", description: "After attempting to tap top navigation area")
            }
        }
        
        // This test is mainly for debugging - we'll analyze via screenshots
        XCTAssertTrue(true, "Direct z-index test completed - check screenshots for analysis")
    }
    
    /// Alternative test: Search for different locations to find one with maps
    func testMultipleLocationSearch() throws {
        print("🔍 LOCATION SEARCH TEST: Finding articles with MapLibre widgets")
        
        app.launch()
        Thread.sleep(forTimeInterval: 3.0)
        
        // Navigate to search
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
        } else {
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists {
                let buttons = tabBar.buttons
                if buttons.count > 2 {
                    buttons.element(boundBy: 2).tap()
                }
            }
        }
        
        Thread.sleep(forTimeInterval: 2.0)
        
        // Try multiple location searches
        let locations = ["Varrock", "Lumbridge", "Draynor Village", "Falador", "Grand Exchange"]
        
        for location in locations {
            print("🔍 Searching for: \(location)")
            
            let searchField = app.searchFields.firstMatch
            if searchField.exists {
                searchField.tap()
                
                // Clear existing text
                searchField.press(forDuration: 1.0)
                if app.menuItems["Select All"].exists {
                    app.menuItems["Select All"].tap()
                }
                
                searchField.typeText(location)
                Thread.sleep(forTimeInterval: 1.0)
                
                let firstResult = app.tables.cells.firstMatch
                if firstResult.exists {
                    firstResult.tap()
                    Thread.sleep(forTimeInterval: 3.0)
                    
                    // Take screenshot for each location
                    takeScreenshot(name: "location_\(location.replacingOccurrences(of: " ", with: "_").lowercased())", 
                                 description: "Article for \(location)")
                    
                    // Check for navigation accessibility
                    let backButton = app.navigationBars.buttons.firstMatch
                    print("📍 \(location) - Back button hittable: \(backButton.isHittable)")
                    
                    // Go back to search
                    if backButton.exists && backButton.isHittable {
                        backButton.tap()
                        Thread.sleep(forTimeInterval: 1.0)
                    }
                }
            }
        }
        
        XCTAssertTrue(true, "Multiple location search completed")
    }
    
    private func takeScreenshot(name: String, description: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Screenshot: \(name) - \(description)")
    }
}
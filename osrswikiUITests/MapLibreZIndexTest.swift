//
//  MapLibreZIndexTest.swift
//  osrswikiUITests
//
//  TDD test to verify MapLibre widgets DO NOT draw over the top bar
//

import XCTest

final class MapLibreZIndexTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        Thread.sleep(forTimeInterval: 3.0)
    }
    
    /// TEST: This test should FAIL until the z-index issue is properly fixed
    func testMapLibreWidgetDoesNotDrawOverTopBar() throws {
        print("🧪 TDD TEST: MapLibre widgets should NOT draw over top bar")
        
        // Step 1: Navigate to an article that contains a MapLibre widget
        // First tap the Search tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
        } else {
            let searchTabAlt = app.tabBars.buttons.element(boundBy: 2) // Usually 3rd tab
            searchTabAlt.tap()
        }
        
        Thread.sleep(forTimeInterval: 2.0)
        
        // Search for "Lumbridge" - a location that should have a map widget
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            searchField.tap()
            searchField.typeText("Lumbridge")
            Thread.sleep(forTimeInterval: 1.0)
            
            // Tap the first search result
            let firstResult = app.tables.cells.firstMatch
            if firstResult.exists {
                firstResult.tap()
                Thread.sleep(forTimeInterval: 5.0) // Wait for article to load
            }
        }
        
        // Step 2: Take screenshot for visual verification
        takeScreenshot(name: "maplibre_zindex_test", description: "Testing if MapLibre widget draws over top bar")
        
        // Step 3: Check if navigation elements are accessible (not covered by map)
        // The back button should be tappable if it's not covered by the map
        let backButton = app.navigationBars.buttons.firstMatch
        let navigationBar = app.navigationBars.firstMatch
        
        print("🔍 Navigation bar exists: \(navigationBar.exists)")
        print("🔍 Navigation bar hittable: \(navigationBar.isHittable)")
        print("🔍 Back button exists: \(backButton.exists)")
        print("🔍 Back button hittable: \(backButton.isHittable)")
        
        // Step 4: Look for MapLibre-related elements
        let allElements = app.descendants(matching: .any)
        var mapElementFound = false
        
        for element in allElements.allElementsBoundByIndex {
            let identifier = element.identifier
            if identifier.contains("map") || identifier.contains("MapLibre") || identifier.contains("osrs") {
                print("🗺️ Found potential map element: \(identifier)")
                print("   Frame: \(element.frame)")
                mapElementFound = true
            }
        }
        
        // Step 5: Test the core assertion - navigation should be accessible
        if navigationBar.exists {
            XCTAssertTrue(navigationBar.isHittable, 
                         "❌ FAILED: Navigation bar is not hittable - likely covered by MapLibre widget")
            print("✅ Navigation bar is accessible")
        }
        
        if backButton.exists {
            XCTAssertTrue(backButton.isHittable, 
                         "❌ FAILED: Back button is not hittable - likely covered by MapLibre widget")
            print("✅ Back button is accessible")
        }
        
        // Step 6: Additional check - try to tap the navigation area
        let topBarArea = CGRect(x: 0, y: 0, width: app.frame.width, height: 100)
        let topBarCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        
        // This should work if the top bar is not covered
        topBarCoordinate.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        print("🎯 TDD TEST COMPLETE - If test failed, MapLibre widget is drawing over top bar")
    }
    
    /// Helper test to find articles with MapLibre widgets
    func testFindArticleWithMapWidget() throws {
        print("🔍 HELPER TEST: Finding article with MapLibre widget")
        
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
        } else {
            let searchTabAlt = app.tabBars.buttons.element(boundBy: 2)
            searchTabAlt.tap()
        }
        
        Thread.sleep(forTimeInterval: 2.0)
        
        // Try several location-based searches
        let searchTerms = ["Lumbridge", "Varrock", "Falador", "Draynor", "Edgeville"]
        
        for searchTerm in searchTerms {
            let searchField = app.searchFields.firstMatch
            if searchField.exists {
                searchField.tap()
                searchField.clearText()
                searchField.typeText(searchTerm)
                Thread.sleep(forTimeInterval: 1.0)
                
                let firstResult = app.tables.cells.firstMatch
                if firstResult.exists {
                    print("🔍 Testing search term: \(searchTerm)")
                    firstResult.tap()
                    Thread.sleep(forTimeInterval: 3.0)
                    
                    // Take screenshot to see what loaded
                    takeScreenshot(name: "search_\(searchTerm.lowercased())", 
                                 description: "Article for \(searchTerm)")
                    
                    // Go back for next search
                    let backButton = app.navigationBars.buttons.firstMatch
                    if backButton.exists {
                        backButton.tap()
                        Thread.sleep(forTimeInterval: 1.0)
                    }
                }
            }
        }
        
        XCTAssertTrue(true, "Search exploration complete")
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

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else {
            return
        }
        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
    }
}
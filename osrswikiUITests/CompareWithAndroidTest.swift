//
//  CompareWithAndroidTest.swift
//  osrswikiUITests
//
//  Test to click dragon scimitar and capture results for comparison
//

import XCTest

final class CompareWithAndroidTest: XCTestCase {
    
    func testDragonScimitarSearch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        Thread.sleep(forTimeInterval: 3)
        
        // Take screenshot of initial state
        let initialScreenshot = XCUIScreen.main.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "01-ios-search-ready"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Look for "dragon scimitar" button in recent searches and tap it
        let dragonScimitarButton = app.buttons["dragon scimitar"]
        if dragonScimitarButton.exists {
            print("✅ Found dragon scimitar button - tapping it")
            dragonScimitarButton.tap()
            
            // Wait for search results to load
            Thread.sleep(forTimeInterval: 5)
            
            let searchResultsScreenshot = XCUIScreen.main.screenshot()
            let searchResultsAttachment = XCTAttachment(screenshot: searchResultsScreenshot)
            searchResultsAttachment.name = "02-ios-dragon-scimitar-results"
            searchResultsAttachment.lifetime = .keepAlways
            add(searchResultsAttachment)
            
            print("✅ Captured iOS dragon scimitar search results - compare with Android!")
        } else {
            print("❌ Could not find dragon scimitar button - trying manual search")
            
            // Fallback to manual search
            let searchField = app.textFields.firstMatch
            if searchField.exists {
                searchField.tap()
                Thread.sleep(forTimeInterval: 1)
                
                // Clear and type dragon scimitar
                if let currentText = searchField.value as? String, !currentText.isEmpty {
                    let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentText.count)
                    searchField.typeText(deleteString)
                }
                searchField.typeText("dragon scimitar")
                searchField.typeText("\n")
                Thread.sleep(forTimeInterval: 5)
                
                let manualSearchScreenshot = XCUIScreen.main.screenshot()
                let manualSearchAttachment = XCTAttachment(screenshot: manualSearchScreenshot)
                manualSearchAttachment.name = "03-ios-manual-dragon-scimitar"
                manualSearchAttachment.lifetime = .keepAlways
                add(manualSearchAttachment)
            }
        }
        
        print("✅ iOS dragon scimitar test completed - check screenshots for orange highlighting")
    }
}
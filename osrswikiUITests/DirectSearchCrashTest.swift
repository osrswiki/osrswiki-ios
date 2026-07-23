//
//  DirectSearchCrashTest.swift
//  osrswikiUITests
//
//  Created to directly reproduce and fix the search crash
//

import XCTest

class DirectSearchCrashTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready
        _ = app.wait(for: .runningForeground, timeout: 10)
    }
    
    func testDirectSearchCrashReproduction() throws {
        // Try to find the search tab directly by examining the actual UI
        print("🔍 Available buttons: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
        print("🔍 Available static texts: \(app.staticTexts.allElementsBoundByIndex.map { $0.label })")
        print("🔍 Available text fields: \(app.textFields.allElementsBoundByIndex.map { $0.label })")
        
        // Try to find any search-related element
        let allElements = app.descendants(matching: .any)
        var searchElements: [XCUIElement] = []
        
        for i in 0..<min(20, allElements.count) {
            let element = allElements.element(boundBy: i)
            let label = element.label.lowercased()
            if label.contains("search") {
                searchElements.append(element)
                print("🎯 Found search element: \(element.elementType) - '\(element.label)'")
            }
        }
        
        // Try to tap the first search element
        if let searchElement = searchElements.first {
            searchElement.tap()
            sleep(1) // Wait for navigation
            
            // Now look for search text field
            let searchField = app.textFields.firstMatch
            if searchField.waitForExistence(timeout: 5) {
                print("✅ Found search field, attempting search")
                searchField.tap()
                searchField.typeText("varrock")
                
                // Wait for results and potential crash
                sleep(3)
                
                // If we get here, no crash occurred
                print("✅ Search completed without crash")
                XCTAssertTrue(app.state == .runningForeground, "App should still be running")
            } else {
                XCTFail("Could not find search text field after navigation")
            }
        } else {
            XCTFail("Could not find any search-related UI elements")
        }
    }
}
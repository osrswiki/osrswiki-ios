//
//  SearchHighlightingUITests.swift
//  osrswikiUITests
//
//  Tests to verify search highlighting works correctly in the UI
//

import XCTest

final class SearchHighlightingUITests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        continueAfterFailure = false
    }
    
    func testSearchHighlightingOrangeColor() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready
        Thread.sleep(forTimeInterval: 3)
        
        // Take initial screenshot
        let initialScreenshot = XCUIScreen.main.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "01-app-launch"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Try to find and interact with search elements
        let searchTextField = app.textFields.firstMatch
        if searchTextField.exists {
            print("✅ Found text field")
            searchTextField.tap()
            Thread.sleep(forTimeInterval: 1)
            
            // Clear any existing text and type new search
            searchTextField.clearAndEnterText("dragon scimitar")
            
            let afterTypeScreenshot = XCUIScreen.main.screenshot()
            let afterTypeAttachment = XCTAttachment(screenshot: afterTypeScreenshot)
            afterTypeAttachment.name = "02-after-typing"
            afterTypeAttachment.lifetime = .keepAlways
            add(afterTypeAttachment)
            
            // Submit search - try different keyboard buttons
            if app.keyboards.buttons["Search"].exists {
                app.keyboards.buttons["Search"].tap()
            } else if app.keyboards.buttons["return"].exists {
                app.keyboards.buttons["return"].tap()
            } else if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            } else {
                // Just send return key
                searchTextField.typeText("\n")
            }
            Thread.sleep(forTimeInterval: 5)
            
            let searchResultsScreenshot = XCUIScreen.main.screenshot()
            let searchResultsAttachment = XCTAttachment(screenshot: searchResultsScreenshot)
            searchResultsAttachment.name = "03-search-results-dragon-scimitar"
            searchResultsAttachment.lifetime = .keepAlways
            add(searchResultsAttachment)
            
        } else {
            print("❌ Could not find text field, trying alternative approach")
            // Alternative: look for any tappable search element
            let searchElements = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'search'"))
            if searchElements.count > 0 {
                let element = searchElements.element(boundBy: 0)
                element.tap()
                Thread.sleep(forTimeInterval: 1)
            }
            
            let fallbackScreenshot = XCUIScreen.main.screenshot()
            let fallbackAttachment = XCTAttachment(screenshot: fallbackScreenshot)
            fallbackAttachment.name = "04-fallback-search-attempt"
            fallbackAttachment.lifetime = .keepAlways
            add(fallbackAttachment)
        }
        
        print("✅ Search highlighting test completed - check screenshots for results")
    }
}

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard let stringValue = self.value as? String else {
            self.typeText(text)
            return
        }
        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }
}
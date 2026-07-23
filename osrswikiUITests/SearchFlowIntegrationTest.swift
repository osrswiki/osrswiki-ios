//
//  SearchFlowIntegrationTest.swift
//  osrswikiUITests
//
//  Integration test to verify search flow works without crashes
//

import XCTest

class SearchFlowIntegrationTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready
        _ = app.wait(for: .runningForeground, timeout: 10)
    }
    
    func testSearchFlowWithoutCrash() throws {
        // Step 1: Navigate to Search tab
        print("🔍 Step 1: Looking for Search tab")
        
        // Try multiple ways to find Search tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 5) {
            print("✅ Found Search tab in tab bar")
            searchTab.tap()
        } else {
            // Alternative: Look for any button with "Search" label
            let searchButton = app.buttons["Search"].firstMatch
            if searchButton.exists {
                print("✅ Found Search button")
                searchButton.tap()
            } else {
                print("⚠️ Could not find Search tab/button, trying to proceed anyway")
            }
        }
        
        // Step 2: Look for search input field
        print("🔍 Step 2: Looking for search input field")
        sleep(1) // Give UI time to transition
        
        // Try multiple selectors for search field
        var searchField: XCUIElement?
        
        // Try text field with placeholder
        let textFieldWithPlaceholder = app.textFields["Search OSRS Wiki"]
        if textFieldWithPlaceholder.waitForExistence(timeout: 3) {
            searchField = textFieldWithPlaceholder
            print("✅ Found search field by placeholder")
        }
        
        // Try any text field
        if searchField == nil {
            let anyTextField = app.textFields.firstMatch
            if anyTextField.waitForExistence(timeout: 3) {
                searchField = anyTextField
                print("✅ Found a text field")
            }
        }
        
        // Try search field
        if searchField == nil {
            let searchFieldElement = app.searchFields.firstMatch
            if searchFieldElement.waitForExistence(timeout: 3) {
                searchField = searchFieldElement
                print("✅ Found a search field")
            }
        }
        
        // Step 3: Perform search if we found a field
        if let searchField = searchField {
            print("🔍 Step 3: Performing search for 'varrock'")
            searchField.tap()
            searchField.typeText("varrock")
            
            // Wait for search results
            print("⏳ Waiting for search results...")
            sleep(3)
            
            // Step 4: Verify app didn't crash
            XCTAssertEqual(app.state, .runningForeground, "App should still be running after search")
            print("✅ App is still running - no crash!")
            
            // Step 5: Look for search results (optional verification)
            let cells = app.cells
            if cells.count > 0 {
                print("✅ Found \(cells.count) search result cells")
                
                // Check if any cell contains "Varrock" to verify highlighting might be working
                let firstCell = cells.firstMatch
                if firstCell.exists {
                    print("📱 First cell exists - search results displayed successfully")
                }
            } else {
                print("⚠️ No search result cells found, but app didn't crash")
            }
            
        } else {
            print("❌ Could not find any search input field")
            XCTFail("Search field not found - cannot complete test")
        }
        
        // Final verification
        XCTAssertEqual(app.state, .runningForeground, "App should remain stable throughout search flow")
        print("✅✅✅ Search flow completed successfully without crash!")
    }
    
    func testRapidSearchWithoutCrash() throws {
        // Test rapid search queries to stress test the fix
        print("🚀 Starting rapid search stress test")
        
        // Navigate to search
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 5) {
            searchTab.tap()
        }
        
        // Find search field
        let searchField = app.textFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else {
            XCTFail("Search field not found")
            return
        }
        
        // Perform rapid searches
        let searchTerms = ["v", "va", "var", "varr", "varro", "varroc", "varrock"]
        
        for (index, term) in searchTerms.enumerated() {
            print("🔍 Rapid search \(index + 1)/\(searchTerms.count): '\(term)'")
            
            searchField.tap()
            
            // Clear previous text
            if index > 0 {
                searchField.tap()
                let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: searchTerms[index - 1].count)
                searchField.typeText(deleteString)
            }
            
            // Type new character
            if index == 0 {
                searchField.typeText(term)
            } else {
                let newChar = String(term.last!)
                searchField.typeText(newChar)
            }
            
            // Brief pause to let search execute
            usleep(200000) // 200ms
            
            // Verify app didn't crash
            XCTAssertEqual(app.state, .runningForeground, "App should survive rapid search: '\(term)'")
        }
        
        print("✅✅✅ Rapid search stress test passed - no crashes!")
    }
}
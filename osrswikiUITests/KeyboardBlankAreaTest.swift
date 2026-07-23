//
//  KeyboardBlankAreaTest.swift
//  osrswikiUITests
//
//  Test to detect the blank keyboard area issue
//

import XCTest

class KeyboardBlankAreaTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testManualReproductionSteps() throws {
        // Wait for app to fully load
        Thread.sleep(forTimeInterval: 2.0)
        
        print("Step 1: Navigate to Search/History tab")
        // The app uses CustomTabBar with buttons, not standard TabBar
        // Look for the Search button
        let searchTabButton = app.buttons["Search"]
        if searchTabButton.waitForExistence(timeout: 5) {
            print("Found Search tab button")
            searchTabButton.tap()
        } else {
            // Try finding by text
            let searchText = app.staticTexts["Search"]
            if searchText.exists {
                print("Found Search text, tapping parent")
                searchText.tap()
            } else {
                print("WARNING: Could not find Search tab")
            }
        }
        Thread.sleep(forTimeInterval: 1.0)
        
        print("Step 2: Find and tap search bar")
        // The search bar in HistoryView that opens DedicatedSearchView
        let searchBar = app.buttons["Search OSRS Wiki"]
        if searchBar.exists {
            print("Found search bar button")
            searchBar.tap()
        } else {
            // Try to find it as a text field
            let searchField = app.textFields["Search OSRS Wiki"]
            if searchField.exists {
                print("Found search text field")
                searchField.tap()
            } else {
                // Try any element with Search in the label
                let anySearch = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
                if anySearch.exists {
                    print("Found search element: \(anySearch.debugDescription)")
                    anySearch.tap()
                } else {
                    XCTFail("Could not find search bar")
                }
            }
        }
        
        Thread.sleep(forTimeInterval: 2.0)
        
        print("Step 3: Type in the search field")
        // Now we should be in DedicatedSearchView
        let dedicatedSearchField = app.textFields.firstMatch
        if dedicatedSearchField.exists {
            dedicatedSearchField.tap()
            dedicatedSearchField.typeText("Woodcutting")
            
            print("Step 4: Verify keyboard is shown")
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.exists, "Keyboard should be visible")
            
            // Get keyboard frame for comparison
            let keyboardFrame = keyboard.frame
            print("Keyboard frame: \(keyboardFrame)")
            
            Thread.sleep(forTimeInterval: 1.0)
            
            print("Step 5: Wait for search results")
            // Wait for search results to appear
            let firstCell = app.cells.firstMatch
            if firstCell.waitForExistence(timeout: 5) {
                print("Search results appeared")
                
                print("Step 6: Tap on a search result")
                firstCell.tap()
                
                Thread.sleep(forTimeInterval: 3.0)
                
                print("Step 7: Navigate back")
                // Try to find back button
                let backButton = app.navigationBars.buttons.firstMatch
                if backButton.exists {
                    print("Using back button")
                    backButton.tap()
                } else {
                    print("Using swipe gesture")
                    app.swipeRight()
                }
                
                Thread.sleep(forTimeInterval: 2.0)
                
                print("Step 8: Check for blank area")
                // The keyboard should be gone
                XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed")
                
                // Check if there's a blank area where keyboard was
                // We'll check if the view hierarchy has proper layout
                let window = app.windows.firstMatch
                let windowFrame = window.frame
                print("Window frame after navigation: \(windowFrame)")
                
                // Check if the search view is properly visible
                let historyView = app.otherElements["History"]
                if historyView.exists {
                    let historyFrame = historyView.frame
                    print("History view frame: \(historyFrame)")
                    
                    // The blank area would manifest as incorrect view sizing
                    // If there's a blank area, the view wouldn't fill the screen properly
                    let expectedHeight = windowFrame.height - 100 // Allow for tab bar
                    XCTAssertGreaterThan(historyFrame.height, expectedHeight * 0.8, 
                                         "View should fill most of the screen, not have a blank keyboard area")
                }
            }
        } else {
            XCTFail("Could not find search field in DedicatedSearchView")
        }
    }
    
    func testKeyboardAreaAfterNavigation() throws {
        // Simplified test focusing on the exact issue
        
        // Navigate to Search tab (using custom tab bar)
        let searchButton = app.buttons["Search"]
        if searchButton.waitForExistence(timeout: 5) {
            searchButton.tap()
        } else {
            app.staticTexts["Search"].tap()
        }
        Thread.sleep(forTimeInterval: 1.0)
        
        // Open search (tap the search bar)
        let searchBarButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Search OSRS'")).firstMatch
        if searchBarButton.exists {
            searchBarButton.tap()
        } else {
            app.textFields.firstMatch.tap()
        }
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Type to show keyboard
        let textField = app.textFields.firstMatch
        if textField.exists {
            textField.tap()
            textField.typeText("test")
            
            // Record keyboard state
            let keyboard = app.keyboards.firstMatch
            let keyboardExistedBefore = keyboard.exists
            
            // Navigate back to trigger the issue
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            } else {
                app.swipeRight()
            }
            
            Thread.sleep(forTimeInterval: 1.0)
            
            // Verify keyboard is gone
            XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed after navigation")
            
            // Check view layout
            let mainView = app.windows.firstMatch
            let viewHeight = mainView.frame.height
            
            // If there's a blank area, the usable view height would be reduced
            // The view should use the full available height
            XCTAssertTrue(viewHeight > 800, "View should have full height, not truncated by blank keyboard area")
            
            print("Test completed - keyboard existed before: \(keyboardExistedBefore), view height after: \(viewHeight)")
        }
    }
}
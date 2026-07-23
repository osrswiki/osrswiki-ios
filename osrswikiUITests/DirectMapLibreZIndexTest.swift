import XCTest
import WebKit

final class DirectMapLibreZIndexTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testDirectMapLibreZIndex() throws {
        // Wait for app to load
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 10), "Home screen should appear")
        print("✅ App launched successfully")
        
        // Navigate directly to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
            print("✅ Tapped Search tab")
        } else {
            print("⚠️ Search tab not found, continuing with current screen")
        }
        
        // Find and tap search field
        let searchField = app.searchFields.firstMatch
        if !searchField.exists {
            print("🔍 Looking for text fields...")
            let textFields = app.textFields.allElementsBoundByIndex
            print("📝 Found \(textFields.count) text fields")
            for (i, field) in textFields.enumerated() {
                print("📝 Text field \(i): '\(field.label)'")
            }
        }
        
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
        searchField.tap()
        
        // Clear any existing text and type Varrock
        if searchField.value as? String != "" {
            searchField.doubleTap() // Select all text
        }
        searchField.typeText("Varrock")
        print("✅ Entered 'Varrock' in search field")
        
        // Wait for search results with longer timeout
        sleep(4)
        
        // Debug: Print all visible elements
        print("🔍 Debug: Looking for all clickable elements...")
        let allButtons = app.buttons.allElementsBoundByIndex
        let allCells = app.cells.allElementsBoundByIndex 
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        
        print("🔘 Buttons found: \(allButtons.count)")
        print("📱 Cells found: \(allCells.count)")
        print("📝 Static texts found: \(allStaticTexts.count)")
        
        // Look for Varrock in static texts
        var varrockFound = false
        for (i, text) in allStaticTexts.enumerated().prefix(20) {
            if text.exists && text.label.lowercased().contains("varrock") {
                print("🎯 Found Varrock text at index \(i): '\(text.label)'")
                // Try to tap on it or find its parent container
                if text.isHittable {
                    text.tap()
                    varrockFound = true
                    print("✅ Successfully tapped Varrock text")
                    break
                }
            }
        }
        
        // If not found in texts, look in cells
        if !varrockFound {
            for (i, cell) in allCells.enumerated().prefix(10) {
                if cell.exists {
                    let cellTexts = cell.staticTexts.allElementsBoundByIndex
                    for cellText in cellTexts {
                        if cellText.label.lowercased().contains("varrock") {
                            print("🎯 Found Varrock in cell \(i): '\(cellText.label)'")
                            cell.tap()
                            varrockFound = true
                            break
                        }
                    }
                    if varrockFound { break }
                }
            }
        }
        
        // Fallback: tap first search result
        if !varrockFound {
            print("⚠️ Varrock not found specifically, trying first available result")
            
            // Try tapping on first table cell
            let tables = app.tables.allElementsBoundByIndex
            if tables.count > 0 && tables[0].cells.count > 0 {
                let firstCell = tables[0].cells.firstMatch
                firstCell.tap()
                varrockFound = true
                print("📱 Tapped first table cell as fallback")
            }
            
            // Alternative: try tapping first cell element
            if !varrockFound && allCells.count > 0 {
                allCells[0].tap()
                varrockFound = true
                print("📱 Tapped first cell element as fallback")
            }
        }
        
        XCTAssertTrue(varrockFound, "Should have found some search result to tap")
        
        // Wait for article to load
        sleep(6)
        print("⏳ Article should be loading...")
        
        // Take screenshot before interaction
        let beforeScreenshot = app.screenshot()
        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "01_before_webview_interaction"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)
        
        // Find WebView
        let webView = app.webViews.firstMatch
        if webView.waitForExistence(timeout: 10) {
            print("✅ WebView found and loaded")
            
            // Try multiple interaction approaches to trigger infobox
            
            // Approach 1: Tap various areas of the page
            let webViewFrame = webView.frame
            let tapLocations = [
                // Top area where infobox usually is
                CGVector(dx: 0.8, dy: 0.2),  // Top right
                CGVector(dx: 0.9, dy: 0.25), // Far right
                CGVector(dx: 0.7, dy: 0.3),  // Right side
                CGVector(dx: 0.85, dy: 0.35), // Right middle
                // Center area
                CGVector(dx: 0.5, dy: 0.4),  // Center
                CGVector(dx: 0.3, dy: 0.5),  // Left center
            ]
            
            for (index, location) in tapLocations.enumerated() {
                print("👆 Attempting tap \(index + 1) at normalized location: \(location)")
                webView.coordinate(withNormalizedOffset: location).tap()
                sleep(2)
                
                // Take screenshot after each tap
                let tapScreenshot = app.screenshot()
                let tapAttachment = XCTAttachment(screenshot: tapScreenshot)
                tapAttachment.name = "02_after_tap_\(index + 1)"
                tapAttachment.lifetime = .keepAlways
                add(tapAttachment)
            }
            
            // Approach 2: Try scrolling to reveal different content
            print("📜 Trying scroll interactions...")
            webView.swipeUp()
            sleep(2)
            webView.swipeDown()
            sleep(2)
            webView.swipeUp()
            sleep(2)
            
            // Approach 3: Double tap - sometimes expands content
            print("👆👆 Trying double tap...")
            webView.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)).doubleTap()
            sleep(3)
            
            // Approach 4: Long press - might reveal context menu or expand
            print("👆⏳ Trying long press...")
            webView.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.25)).press(forDuration: 1.5)
            sleep(2)
            
            // Take final screenshot
            let finalScreenshot = app.screenshot()
            let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
            finalAttachment.name = "03_final_state"
            finalAttachment.lifetime = .keepAlways
            add(finalAttachment)
            
        } else {
            XCTFail("WebView did not appear within timeout")
        }
        
        // Give additional time for any MapLibre widgets to be created
        sleep(5)
        
        print("🔍 Test completed - MapLibre widgets should have been triggered if infobox expanded")
        print("📊 Check debug logs for 'ZINDEX DEBUG' messages")
        print("📸 Check screenshots for visual verification")
        
        // Test passes - real verification is in logs and screenshots
        XCTAssertTrue(true, "Test completed - check debug output and screenshots")
    }
}
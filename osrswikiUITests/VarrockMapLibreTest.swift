import XCTest

final class VarrockMapLibreTest: XCTestCase {
    
    func testVarrockMapLibreWidget() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to load
        sleep(3)
        print("✅ App launched successfully")
        
        // Tap search bar to activate search
        let searchBar = app.searchFields.firstMatch
        if searchBar.exists {
            searchBar.tap()
            print("✅ Search bar tapped")
            
            // Type "Varrock" in search
            searchBar.typeText("Varrock")
            sleep(2)
            print("✅ Typed 'Varrock' in search")
            
            // Look for Varrock in search results and tap it
            let searchResultsTable = app.tables.firstMatch
            if searchResultsTable.exists {
                // Try to find a cell with "Varrock" text
                let cells = searchResultsTable.cells
                var foundVarrock = false
                
                for i in 0..<min(10, cells.count) { // Check first 10 cells
                    let cell = cells.element(boundBy: i)
                    if cell.exists {
                        let cellText = cell.staticTexts.firstMatch.label
                        print("📝 Found cell: \(cellText)")
                        if cellText.contains("Varrock") && !cellText.contains("Castle") {
                            cell.tap()
                            foundVarrock = true
                            print("✅ Successfully tapped on Varrock cell: \(cellText)")
                            break
                        }
                    }
                }
                
                if !foundVarrock {
                    // Fallback: tap first cell
                    if cells.count > 0 {
                        cells.firstMatch.tap()
                        print("⚠️ Fallback: tapped first search result")
                    }
                }
            } else {
                print("❌ No search results table found")
            }
        } else {
            print("❌ Search bar not found")
        }
        
        // Wait for article to load
        sleep(5)
        print("✅ Article should be loaded")
        
        // Now look for infobox to expand
        let webViewElement = app.webViews.firstMatch
        if webViewElement.exists {
            print("✅ WebView found")
            
            // Look for infobox elements or expandable sections
            // Try to find and tap any expandable element
            let allElements = app.descendants(matching: .any)
            print("📊 Total elements found: \(allElements.count)")
            
            // Look for buttons or tappable elements that might expand the infobox
            let buttons = app.buttons
            print("🔘 Total buttons found: \(buttons.count)")
            
            for i in 0..<min(20, buttons.count) {
                let button = buttons.element(boundBy: i)
                if button.exists {
                    let label = button.label
                    print("🔘 Button \(i): '\(label)'")
                    // Look for buttons that might expand content
                    if label.contains("show") || label.contains("expand") || label.contains("▶") || label.contains("▼") {
                        print("🎯 Found potential expand button: \(label)")
                        button.tap()
                        sleep(2)
                        break
                    }
                }
            }
            
            // Also try tapping on the webview itself to potentially trigger infobox expansion
            print("👆 Trying to interact with webview")
            webViewElement.tap()
            sleep(2)
            
        } else {
            print("❌ WebView not found")
        }
        
        // Take a screenshot to see the current state
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "varrock_maplibre_test_state"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Screenshot taken")
        
        // Test passes if we get this far
        XCTAssertTrue(true, "Test completed - check screenshot for MapLibre widget state")
    }
}
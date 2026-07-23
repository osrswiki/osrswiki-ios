import XCTest

final class TableStyleTest: XCTestCase {
    
    func testNavigateToVarrockAndCheckTables() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        Thread.sleep(forTimeInterval: 3)
        
        // Take screenshot of initial state
        let initialScreenshot = XCUIScreen.main.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "01-app-launched"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Search for Varrock manually
        let searchField = app.textFields.firstMatch
        if searchField.exists {
            searchField.tap()
            Thread.sleep(forTimeInterval: 1)
            searchField.typeText("Varrock")
            Thread.sleep(forTimeInterval: 2)
            searchField.typeText("\n")
            Thread.sleep(forTimeInterval: 3)
            
            let searchResultsScreenshot = XCUIScreen.main.screenshot()
            let searchResultsAttachment = XCTAttachment(screenshot: searchResultsScreenshot)
            searchResultsAttachment.name = "02-varrock-search-results"
            searchResultsAttachment.lifetime = .keepAlways
            add(searchResultsAttachment)
            
            // Look for Varrock in search results and tap the first one
            let searchResults = app.tables.cells
            if searchResults.count > 0 {
                let firstResult = searchResults.element(boundBy: 0)
                firstResult.tap()
                Thread.sleep(forTimeInterval: 5)
                
                let varrockPageScreenshot = XCUIScreen.main.screenshot()
                let varrockPageAttachment = XCTAttachment(screenshot: varrockPageScreenshot)
                varrockPageAttachment.name = "03-varrock-page-with-tables"
                varrockPageAttachment.lifetime = .keepAlways
                add(varrockPageAttachment)
                
                print("✅ Successfully navigated to Varrock page and captured table screenshot")
            } else {
                print("❌ No search results found for Varrock")
            }
        } else {
            print("❌ Could not find search field")
        }
    }
}
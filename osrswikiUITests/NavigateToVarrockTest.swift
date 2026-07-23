import XCTest

final class NavigateToVarrockTest: XCTestCase {
    
    func testNavigateToVarrock() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to load
        sleep(2)
        
        // Look for Varrock in the search results and tap it
        let varrockElement = app.staticTexts["Varrock"]
        if varrockElement.exists {
            varrockElement.tap()
            print("Successfully tapped on Varrock")
        } else {
            // Try tapping on any search result that contains Varrock
            let searchResults = app.tables.cells
            for i in 0..<searchResults.count {
                let cell = searchResults.element(boundBy: i)
                if cell.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Varrock'")).count > 0 {
                    cell.tap()
                    print("Successfully tapped on Varrock cell")
                    break
                }
            }
        }
        
        // Wait for navigation to complete
        sleep(3)
    }
}

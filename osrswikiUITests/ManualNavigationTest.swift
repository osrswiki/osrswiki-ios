import XCTest

final class ManualNavigationTest: XCTestCase {
    
    func testManualNavigationToArticle() throws {
        // Launch the app
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to fully load
        sleep(3)
        
        // Tap on Varrock search result if it exists
        let varrockText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Varrock'")).firstMatch
        if varrockText.exists {
            varrockText.tap()
            print("Successfully tapped Varrock")
            
            // Wait for article to load
            sleep(4)
            
            // Keep the app open so we can take a screenshot
            print("Article should now be loaded - ready for screenshot verification")
            
            // Keep the test running for a bit to allow manual verification
            sleep(5)
        } else {
            print("Varrock not found, trying alternative approach")
            
            // Try searching for something
            let searchField = app.textFields["Search OSRS Wiki"]
            if searchField.exists {
                searchField.tap()
                searchField.typeText("Dragon")
                
                // Press search
                app.keyboards.buttons["Search"].tap()
                
                // Wait for results
                sleep(2)
                
                // Tap first result
                let firstResult = app.tables.cells.firstMatch
                if firstResult.exists {
                    firstResult.tap()
                    print("Tapped on first search result")
                    sleep(4)
                }
            }
        }
    }
}

import XCTest

final class SearchBarFixesTest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSearchBarTextCorrection() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Wait for the app to load and navigate to news tab
        let newsTab = app.tabBars.buttons["News"]
        XCTAssertTrue(newsTab.waitForExistence(timeout: 10))
        newsTab.tap()
        
        // Wait for news content to load
        sleep(3)
        
        // Look for any article link to navigate to article view
        let firstLink = app.links.firstMatch
        if firstLink.waitForExistence(timeout: 10) {
            firstLink.tap()
            
            // Now we should be on an article page - look for the search bar text
            let searchBarText = app.staticTexts["Search OSRS Wiki"]
            XCTAssertTrue(searchBarText.waitForExistence(timeout: 10), "Search bar should display 'Search OSRS Wiki' (not 'Search OSRSWiki')")
            print("✅ Search bar text is correctly displaying 'Search OSRS Wiki'")
        } else {
            XCTFail("Could not find any article links to navigate to")
        }
    }
    
    func testSearchBarNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Navigate to an article page first
        let newsTab = app.tabBars.buttons["News"]
        XCTAssertTrue(newsTab.waitForExistence(timeout: 10))
        newsTab.tap()
        
        sleep(3)
        
        let firstLink = app.links.firstMatch
        if firstLink.waitForExistence(timeout: 10) {
            firstLink.tap()
            
            // Look for the search bar and tap it
            let searchBarButton = app.buttons.containing(.staticText, identifier: "Search OSRS Wiki").firstMatch
            if searchBarButton.waitForExistence(timeout: 10) {
                searchBarButton.tap()
                
                // Verify we navigate to search view
                let searchTextField = app.textFields["Search OSRS Wiki"]
                XCTAssertTrue(searchTextField.waitForExistence(timeout: 10), "Should navigate to search view when search bar is tapped")
                print("✅ Search bar navigation is working - app navigates to search view")
                
                // Verify the search field placeholder is also correct
                XCTAssertTrue(searchTextField.placeholderValue == "Search OSRS Wiki", "Search field placeholder should be 'Search OSRS Wiki'")
                print("✅ Search field placeholder text is correct")
            } else {
                XCTFail("Could not find search bar button to tap")
            }
        } else {
            XCTFail("Could not find any article links to navigate to")
        }
    }
}
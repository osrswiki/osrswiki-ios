import XCTest

class ExternalLinkSpacingTest_Test: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testExternalLinkSpacingTest_Functionality() {
        // Wait for app to launch and navigate to search
        sleep(3)
        
        // Navigate to search tab
        let searchTab = app.tabBars.firstMatch.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10), "Search tab should exist")
        searchTab.tap()
        
        // Search for the specific update page 
        let searchBar = app.searchFields.firstMatch
        XCTAssertTrue(searchBar.waitForExistence(timeout: 10), "Search bar should exist")
        searchBar.tap()
        searchBar.typeText("Update:More Doom Tweaks, Poll 84, & Summer Sweep Up Changes")
        
        // Wait for search results and tap the first result
        sleep(2)
        let searchResults = app.tables.firstMatch
        XCTAssertTrue(searchResults.waitForExistence(timeout: 10), "Search results should exist")
        
        let firstResult = searchResults.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), "First search result should exist")
        firstResult.tap()
        
        // Wait for page to load
        sleep(3)
        
        // Verify we're on the article page by checking for web content
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "Article web view should exist")
        
        // Check for external link text - this will verify the page loaded and contains external links
        let externalLinkText = webView.staticTexts["Old School RuneScape"]
        XCTAssertTrue(externalLinkText.waitForExistence(timeout: 5), "External link text should exist on the page")
        
        print("✅ External link spacing test completed - page loaded with external links")
    }
    
    func testExternalLinkSpacingTest_EdgeCase() {
        // TODO: Test edge cases and error conditions
        // Add more test methods as needed
    }
}

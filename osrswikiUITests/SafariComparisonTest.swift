import XCTest

final class SafariComparisonTest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCaptureWKWebViewAnalysis() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        sleep(3)
        
        // Navigate to search
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10))
        searchTab.tap()
        
        // Search for Varrock
        let searchField = app.textFields["Search OSRSWiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Varrock")
        
        // Wait for search results and tap Varrock
        sleep(2)
        let varrockResult = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Varrock'")).firstMatch
        XCTAssertTrue(varrockResult.waitForExistence(timeout: 10))
        varrockResult.tap()
        
        // Wait for page to load and debugging to complete
        print("🔍 Waiting for Varrock page to load and analysis to complete...")
        sleep(10) // Give time for the debugging script to run
        
        // Take a screenshot for reference
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "WKWebView_Varrock_Analysis"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("✅ WKWebView analysis test completed")
        print("📄 Check console output for debugging results")
        print("📁 Check app Documents directory for wkwebview-analysis.json")
    }
}
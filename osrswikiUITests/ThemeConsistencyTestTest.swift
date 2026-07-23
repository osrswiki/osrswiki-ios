import XCTest

class ThemeConsistencyTest_Test: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testThemeConsistencyTest_Functionality() {
        // Wait for app to load
        let tabBar = app.tabBars.firstMatch
        XCTAssert(tabBar.waitForExistence(timeout: 5), "Tab bar should appear")
        
        // Navigate to More tab
        let moreTab = tabBar.buttons["More"]
        XCTAssert(moreTab.waitForExistence(timeout: 3), "More tab should exist")
        moreTab.tap()
        
        // Verify More view loads
        let moreTitle = app.navigationBars["More"]
        XCTAssert(moreTitle.waitForExistence(timeout: 3), "More navigation title should appear")
        
        // Navigate to Appearance settings
        let appearanceRow = app.cells.containing(.staticText, identifier: "Appearance").firstMatch
        XCTAssert(appearanceRow.waitForExistence(timeout: 3), "Appearance row should exist")
        appearanceRow.tap()
        
        // Verify Appearance settings loads
        let appearanceTitle = app.navigationBars["Appearance"]
        XCTAssert(appearanceTitle.waitForExistence(timeout: 3), "Appearance navigation title should appear")
        
        // Find and tap dark theme card (rightmost card)
        let darkThemeCard = app.buttons.containing(.staticText, identifier: "Dark").firstMatch
        XCTAssert(darkThemeCard.waitForExistence(timeout: 5), "Dark theme card should exist")
        darkThemeCard.tap()
        
        // Wait a moment for theme change to process
        sleep(2)
        
        // Navigate back to More tab
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }
        
        // Wait for More view to appear
        XCTAssert(moreTitle.waitForExistence(timeout: 3), "Should return to More view")
        
        // Success if we reach this point without navigation jumping issues
        print("✅ Theme consistency test completed - navigation remained stable")
    }
    
    func testThemeConsistencyTest_EdgeCase() {
        // TODO: Test edge cases and error conditions
        // Add more test methods as needed
    }
}

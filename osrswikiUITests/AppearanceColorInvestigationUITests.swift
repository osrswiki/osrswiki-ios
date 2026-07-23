import XCTest

final class AppearanceColorInvestigationUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
    }
    
    func testNavigateToMoreTab() throws {
        // Tap on More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        moreTab.tap()
        
        // Wait for More page to load - try different ways to detect it
        let tabBarButtons = app.tabBars.buttons
        XCTAssertTrue(tabBarButtons.count > 0, "Should have tab bar buttons")
        
        // Give it a moment after tapping
        sleep(2)
    }
    
    func testNavigateToAppearancePage() throws {
        // First go to More tab
        let moreTab = app.tabBars.buttons["More"]
        moreTab.tap()
        sleep(2)
        
        // Look for any cell that might be the appearance setting
        // We'll try multiple approaches
        let tables = app.tables
        XCTAssertTrue(tables.count > 0, "Should have tables on More page")
        
        // Try to find Appearance in different ways
        let appearanceCells = app.cells.matching(NSPredicate(format: "label CONTAINS 'Appearance'"))
        if appearanceCells.count > 0 {
            let appearanceCell = appearanceCells.element(boundBy: 0)
            appearanceCell.tap()
            sleep(2)
        }
    }
}
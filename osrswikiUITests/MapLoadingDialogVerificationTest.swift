import XCTest

class MapLoadingDialogVerificationTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testMapTabDoesNotShowLoadingDialog() {
        // Navigate to Map tab
        let mapTab = app.tabBars.buttons["Map"]
        XCTAssertTrue(mapTab.exists, "Map tab should exist")
        mapTab.tap()
        
        // Wait a brief moment for any potential loading dialog
        sleep(1)
        
        // Verify no loading dialog is present
        let loadingText = app.staticTexts["Loading map..."]
        XCTAssertFalse(loadingText.exists, "Loading map dialog should not be present")
        
        // Verify map controls are visible (indicating map is displayed)
        let floorControls = app.buttons.matching(identifier: "chevron.up").firstMatch
        XCTAssertTrue(floorControls.waitForExistence(timeout: 2), "Map floor controls should be visible")
    }
    
    func testMapTabSwitchingNoLoadingFlash() {
        // Start on home tab
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Switch to map tab
        let mapTab = app.tabBars.buttons["Map"]
        mapTab.tap()
        
        // Immediately check for loading dialog
        let loadingText = app.staticTexts["Loading map..."]
        XCTAssertFalse(loadingText.exists, "Loading dialog should not appear when switching to map")
        
        // Switch back to home
        homeTab.tap()
        
        // Switch back to map again
        mapTab.tap()
        
        // Verify no loading dialog on second switch
        XCTAssertFalse(loadingText.exists, "Loading dialog should not appear on repeated navigation")
    }
}
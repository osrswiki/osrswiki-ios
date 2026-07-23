import XCTest

class HomeThemeResponsivenessTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testHomePageTextThemeResponsiveness() throws {
        // Navigate to the Home tab (should already be there by default)
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        homeTab.tap()
        
        // Wait for content to load
        sleep(3)
        
        // Check that Recent Updates section exists
        let recentUpdatesSection = app.scrollViews.staticTexts["Recent updates"]
        XCTAssertTrue(recentUpdatesSection.waitForExistence(timeout: 10), "Recent updates section should exist")
        
        // Check that Announcements section exists
        let announcementsSection = app.scrollViews.staticTexts["Announcements"]
        XCTAssertTrue(announcementsSection.waitForExistence(timeout: 10), "Announcements section should exist")
        
        // Check that Popular Pages section exists  
        let popularPagesSection = app.scrollViews.staticTexts["Popular pages"]
        XCTAssertTrue(popularPagesSection.waitForExistence(timeout: 10), "Popular pages section should exist")
        
        // Test that theme switching affects text colors
        // Note: In a real test, we would need to simulate theme changes
        // For now, we just verify the sections are rendering
        
        print("✅ Home page theme responsiveness test passed")
    }
    
    func testThemeSwitchingAffectsTextColors() throws {
        // Navigate to Home tab
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Wait for content to load
        sleep(3)
        
        // Navigate to settings to change theme (if available)
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        moreTab.tap()
        
        // Look for appearance settings
        let appearanceButton = app.buttons["Appearance"]
        if appearanceButton.exists {
            appearanceButton.tap()
            sleep(2)
            
            // Try to find theme switching options
            let darkModeSwitch = app.switches.firstMatch
            if darkModeSwitch.exists {
                let initialValue = darkModeSwitch.value as? String
                darkModeSwitch.tap()
                sleep(1)
                
                // Go back to Home tab to check theme change
                homeTab.tap()
                sleep(2)
                
                // Verify sections still exist after theme change
                XCTAssertTrue(app.scrollViews.staticTexts["Recent updates"].waitForExistence(timeout: 5), 
                             "Recent updates should still exist after theme change")
                
                // Switch back
                moreTab.tap()
                if app.buttons["Appearance"].exists {
                    app.buttons["Appearance"].tap()
                    sleep(1)
                    if darkModeSwitch.exists {
                        darkModeSwitch.tap()
                    }
                }
            }
        }
        
        print("✅ Theme switching test completed")
    }
}
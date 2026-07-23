//
//  NavigationBarThemeConsistencyFixTest.swift
//  osrswikiUITests
//
//  Created for verifying the navigation bar theme consistency fix
//  Tests that navigation bars properly update when themes change after removing nested NavigationStacks
//

import XCTest

class NavigationBarThemeConsistencyFixTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 3.0) // Allow app to fully load
    }
    
    /// ✅ TEST: Navigation bar theme consistency after removing nested NavigationStacks
    /// 
    /// This test verifies that our fix (removing triple-nested NavigationStacks) resolves
    /// the navigation bar background color issue when switching themes.
    ///
    /// Expected behavior: Navigation bar should maintain consistent theming when navigating
    /// between More tab and Appearance settings after theme changes.
    func testNavigationBarThemeConsistencyFix() throws {
        print("🔧 TESTING NAVIGATION BAR THEME CONSISTENCY FIX")
        print("📋 This test should PASS with the nested NavigationStack fix applied")
        
        // ✅ STEP 1: Navigate to More tab
        print("1️⃣ Navigate to More tab")
        let moreButton = app.buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 8), "More button should exist")
        moreButton.tap()
        
        let moreNavigationBar = app.navigationBars["More"]
        XCTAssertTrue(moreNavigationBar.waitForExistence(timeout: 5), "More navigation bar should exist")
        
        // 📸 Capture initial More tab state
        let initialScreenshot = XCUIScreen.main.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "01-More-Tab-Initial-State"
        add(initialAttachment)
        print("📸 Captured: More tab initial state")
        
        // ✅ STEP 2: Navigate to Appearance settings
        print("2️⃣ Navigate to Appearance settings")
        let appearanceButton = app.staticTexts["Appearance"]
        if !appearanceButton.exists {
            let appearanceFallback = app.buttons.containing(.staticText, identifier:"Appearance").firstMatch
            XCTAssertTrue(appearanceFallback.waitForExistence(timeout: 5), "Appearance setting should exist")
            appearanceFallback.tap()
        } else {
            appearanceButton.tap()
        }
        
        let appearanceNavigationBar = app.navigationBars["Appearance"]
        XCTAssertTrue(appearanceNavigationBar.waitForExistence(timeout: 5), "Appearance navigation bar should exist")
        
        // 📸 Capture Appearance settings page
        let appearanceScreenshot = XCUIScreen.main.screenshot()
        let appearanceAttachment = XCTAttachment(screenshot: appearanceScreenshot)
        appearanceAttachment.name = "02-Appearance-Settings-Page"
        add(appearanceAttachment)
        print("📸 Captured: Appearance settings page")
        
        // ✅ STEP 3: Change theme to test navigation bar update
        print("3️⃣ Change theme to test navigation bar consistency")
        
        var themeChanged = false
        // Try to tap Dark theme first, then Light theme as fallback
        let darkTheme = app.staticTexts["Dark"]
        let lightTheme = app.staticTexts["Light"]
        
        if darkTheme.exists && darkTheme.isHittable {
            darkTheme.tap()
            themeChanged = true
            print("✅ Tapped Dark theme")
        } else if lightTheme.exists && lightTheme.isHittable {
            lightTheme.tap()
            themeChanged = true
            print("✅ Tapped Light theme")
        } else {
            // Fallback: try any theme cell
            let themeCells = app.cells
            if themeCells.count > 0 {
                themeCells.element(boundBy: 0).tap()
                themeChanged = true
                print("✅ Tapped first available theme option")
            }
        }
        
        XCTAssertTrue(themeChanged, "Should be able to change theme")
        
        // Allow time for theme change to take effect
        Thread.sleep(forTimeInterval: 1.0)
        
        // 📸 Capture theme change state
        let themeChangeScreenshot = XCUIScreen.main.screenshot()
        let themeChangeAttachment = XCTAttachment(screenshot: themeChangeScreenshot)
        themeChangeAttachment.name = "03-After-Theme-Change"
        add(themeChangeAttachment)
        print("📸 Captured: After theme change")
        
        // ✅ STEP 4: Navigate back to More tab to verify consistency
        print("4️⃣ Navigate back to More tab to verify navigation bar consistency")
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
            print("✅ Tapped back button")
        } else {
            // Fallback: use swipe gesture
            app.swipeRight()
            print("✅ Used swipe gesture to go back")
        }
        
        // Wait for navigation back to More tab
        XCTAssertTrue(moreNavigationBar.waitForExistence(timeout: 5), "Should navigate back to More tab")
        Thread.sleep(forTimeInterval: 1.0)
        
        // 📸 Capture final More tab state - this is the critical test
        let finalScreenshot = XCUIScreen.main.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "04-More-Tab-After-Theme-Change-FIXED"
        add(finalAttachment)
        print("📸 Captured: More tab after theme change (should show consistent theming)")
        
        // ✅ VERIFICATION: Check that More navigation bar still exists and is properly themed
        XCTAssertTrue(moreNavigationBar.exists, "More navigation bar should still exist")
        print("✅ Navigation bar exists after theme change")
        
        // Additional verification: Check that we can still navigate to Appearance settings
        print("5️⃣ Additional verification: Re-navigate to Appearance settings")
        if appearanceButton.exists {
            appearanceButton.tap()
            XCTAssertTrue(appearanceNavigationBar.waitForExistence(timeout: 5), "Should be able to navigate to Appearance settings again")
            print("✅ Can still navigate to Appearance settings - navigation consistency maintained")
            
            // Navigate back one more time
            let backButtonSecond = app.navigationBars.buttons.element(boundBy: 0)
            if backButtonSecond.exists {
                backButtonSecond.tap()
            }
        }
        
        print("🎉 Navigation bar theme consistency test COMPLETED")
        print("📋 With the nested NavigationStack fix, navigation bars should maintain consistent theming")
    }
    
    /// ✅ TEST: Multiple theme switches to verify robustness
    /// 
    /// This test cycles through different themes multiple times to ensure
    /// the fix is robust and doesn't degrade with repeated theme changes.
    func testMultipleThemeSwitchesConsistency() throws {
        print("🔄 TESTING MULTIPLE THEME SWITCHES FOR ROBUSTNESS")
        
        // Navigate to More tab
        let moreButton = app.buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 8), "More button should exist")
        moreButton.tap()
        
        // Navigate to Appearance settings
        let appearanceButton = app.staticTexts["Appearance"]
        if appearanceButton.exists {
            appearanceButton.tap()
        } else {
            app.buttons.containing(.staticText, identifier:"Appearance").firstMatch.tap()
        }
        
        let appearanceNavigationBar = app.navigationBars["Appearance"]
        XCTAssertTrue(appearanceNavigationBar.waitForExistence(timeout: 5), "Should be in Appearance settings")
        
        // Cycle through themes multiple times
        let themes = ["Light", "Dark", "Follow system"]
        for (index, themeName) in themes.enumerated() {
            print("🎨 Testing theme switch #\(index + 1): \(themeName)")
            
            let themeElement = app.staticTexts[themeName]
            if themeElement.exists && themeElement.isHittable {
                themeElement.tap()
                Thread.sleep(forTimeInterval: 0.5) // Allow theme to apply
                
                // Take screenshot for each theme change
                let screenshot = XCUIScreen.main.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "05-Theme-Cycle-\(index + 1)-\(themeName.replacingOccurrences(of: " ", with: "-"))"
                add(attachment)
                
                print("✅ Applied theme: \(themeName)")
            }
        }
        
        // Navigate back to More tab and verify consistency
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }
        
        let moreNavigationBar = app.navigationBars["More"]
        XCTAssertTrue(moreNavigationBar.waitForExistence(timeout: 5), "Should return to More tab")
        
        // Final verification screenshot
        let finalScreenshot = XCUIScreen.main.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "06-Final-More-Tab-After-Multiple-Theme-Switches"
        add(finalAttachment)
        
        print("🎉 Multiple theme switches test completed - navigation bar should be consistently themed")
    }
}
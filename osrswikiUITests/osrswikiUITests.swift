//
//  OSRS_WikiUITests.swift
//  OSRS WikiUITests
//
//  Created by Osamu Miyawaki on 7/29/25.
//

import XCTest

final class osrswikiUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    @MainActor
    func testNavigateToMoreTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the tab bar to appear
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        
        // Tap the More tab
        let moreTab = tabBar.buttons["More"]
        XCTAssertTrue(moreTab.exists)
        moreTab.tap()
        
        // Wait for the More view to appear
        let moreNavigationBar = app.navigationBars["More"]
        XCTAssertTrue(moreNavigationBar.waitForExistence(timeout: 5))
        
        // Take a screenshot
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "More Tab Screenshot"
        add(screenshot)
    }
    
    @MainActor
    func testNavigateToAppearanceSettings() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to More tab
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let moreTab = tabBar.buttons["More"]
        moreTab.tap()
        
        // Tap on Appearance settings
        let appearanceRow = app.buttons["Appearance"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        appearanceRow.tap()
        
        // Wait for Appearance view to load
        let appearanceNav = app.navigationBars["Appearance"]
        XCTAssertTrue(appearanceNav.waitForExistence(timeout: 5))
        
        // Take screenshot of Appearance Settings
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Appearance Settings Screenshot"
        add(screenshot)
    }

    @MainActor
    func testMoreSectionNavigationConsistency() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to More tab
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let moreTab = tabBar.buttons["More"]
        moreTab.tap()
        
        // Test About page navigation
        let aboutRow = app.buttons["About"]
        XCTAssertTrue(aboutRow.waitForExistence(timeout: 5))
        aboutRow.tap()
        
        // Verify About page has proper navigation bar with back button and title
        let aboutNavBar = app.navigationBars["About"]
        XCTAssertTrue(aboutNavBar.waitForExistence(timeout: 5), "About page should have navigation bar with title")
        let aboutBackButton = aboutNavBar.buttons.firstMatch
        XCTAssertTrue(aboutBackButton.exists, "About page should have back button")
        
        // Take screenshot of About page
        let aboutScreenshot = XCTAttachment(screenshot: app.screenshot())
        aboutScreenshot.name = "About Page Navigation"
        add(aboutScreenshot)
        
        // Go back
        aboutBackButton.tap()
        
        // Test Appearance page navigation  
        let appearanceRow = app.buttons["Appearance"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        appearanceRow.tap()
        
        // Verify Appearance page has proper navigation bar
        let appearanceNavBar = app.navigationBars["Appearance"]  
        XCTAssertTrue(appearanceNavBar.waitForExistence(timeout: 5), "Appearance page should have navigation bar with title")
        let appearanceBackButton = appearanceNavBar.buttons.firstMatch
        XCTAssertTrue(appearanceBackButton.exists, "Appearance page should have back button")
        
        // Take screenshot of Appearance page
        let appearanceScreenshot = XCTAttachment(screenshot: app.screenshot())
        appearanceScreenshot.name = "Appearance Page Navigation"
        add(appearanceScreenshot)
        
        // Go back
        appearanceBackButton.tap()
        
        // Test Donate page navigation
        let donateRow = app.buttons["Donate"]
        XCTAssertTrue(donateRow.waitForExistence(timeout: 5))
        donateRow.tap()
        
        // Verify Donate page has proper navigation bar
        let donateNavBar = app.navigationBars["Donate"]
        XCTAssertTrue(donateNavBar.waitForExistence(timeout: 5), "Donate page should have navigation bar with title")
        let donateBackButton = donateNavBar.buttons.firstMatch
        XCTAssertTrue(donateBackButton.exists, "Donate page should have back button")
        
        // Take screenshot of Donate page
        let donateScreenshot = XCTAttachment(screenshot: app.screenshot())
        donateScreenshot.name = "Donate Page Navigation"
        add(donateScreenshot)
        
        // Go back
        donateBackButton.tap()
        
        // Test Send Feedback page navigation
        let feedbackRow = app.buttons["Send Feedback"]
        XCTAssertTrue(feedbackRow.waitForExistence(timeout: 5))
        feedbackRow.tap()
        
        // Verify Send Feedback page has proper navigation bar
        let feedbackNavBar = app.navigationBars["Send Feedback"]
        XCTAssertTrue(feedbackNavBar.waitForExistence(timeout: 5), "Send Feedback page should have navigation bar with title")
        let feedbackBackButton = feedbackNavBar.buttons.firstMatch
        XCTAssertTrue(feedbackBackButton.exists, "Send Feedback page should have back button")
        
        // Take screenshot of Send Feedback page
        let feedbackScreenshot = XCTAttachment(screenshot: app.screenshot())
        feedbackScreenshot.name = "Send Feedback Page Navigation"
        add(feedbackScreenshot)
        
        // Go back to complete test
        feedbackBackButton.tap()
        
        // Final screenshot showing More tab with all navigation tested
        let finalScreenshot = XCTAttachment(screenshot: app.screenshot())
        finalScreenshot.name = "More Tab After Navigation Testing"
        add(finalScreenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

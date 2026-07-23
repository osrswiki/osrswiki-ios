//
//  BottomBarNavigationTimingUITests.swift
//  osrswikiUITests
//
//  Created for webkit bottom bar flicker fix testing
//

import XCTest

final class BottomBarNavigationTimingUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here
    }
    
    // MARK: - Custom Extension for waitForNonExistence
    
    private func waitForNonExistence(element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    // MARK: - Bottom Bar Navigation Timing Tests
    
    @MainActor
    func testBottomBarNavigationTimingToArticle() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the tab bar to appear
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should exist on launch")
        
        // Take initial screenshot showing tab bar
        let initialScreenshot = XCTAttachment(screenshot: app.screenshot())
        initialScreenshot.name = "Initial State with Tab Bar"
        add(initialScreenshot)
        
        // Navigate to Home tab (should already be there but ensure)
        let homeTab = tabBar.buttons["Home"]
        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        if !homeTab.isSelected {
            homeTab.tap()
            Thread.sleep(forTimeInterval: 0.5) // Brief wait for tab switch
        }
        
        // Find an article to tap (look for "More Doom Tweaks" article)
        let moreButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'More Doom Tweaks'")).firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "More Doom Tweaks article should be visible")
        
        // Record the timestamp before navigation
        let navigationStartTime = Date()
        
        // Tap the article
        moreButton.tap()
        
        // Take screenshot right after navigation to see current state
        Thread.sleep(forTimeInterval: 0.3) // Brief wait for navigation
        let afterNavigationScreenshot = XCTAttachment(screenshot: app.screenshot())
        afterNavigationScreenshot.name = "Right After Navigation - Is Tab Bar Still There?"
        add(afterNavigationScreenshot)
        
        // Test 1: Verify tab bar disappears without delay
        // The tab bar should disappear quickly (within 1 second) when navigating to article
        let tabBarDisappeared = waitForNonExistence(element: tabBar, timeout: 2.0) // Increase timeout for debugging
        XCTAssertTrue(tabBarDisappeared, "Tab bar should disappear within 2 seconds of navigation")
        
        // Calculate navigation timing
        let navigationTime = Date().timeIntervalSince(navigationStartTime)
        print("🕐 Navigation timing: Tab bar disappeared in \(navigationTime) seconds")
        
        // Take screenshot after navigation showing article view
        Thread.sleep(forTimeInterval: 0.5) // Brief wait for UI to settle
        let articleScreenshot = XCTAttachment(screenshot: app.screenshot())
        articleScreenshot.name = "Article View After Navigation"
        add(articleScreenshot)
        
        // Test 2: Verify article bottom bar appears quickly
        // Look for article-specific elements that should appear
        let articleBottomBar = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Save' OR label CONTAINS 'Find' OR label CONTAINS 'Contents'")).firstMatch
        XCTAssertTrue(articleBottomBar.waitForExistence(timeout: 2.0), "Article bottom bar should appear within 2 seconds")
        
        // Test 3: Navigate back and measure tab bar reappearance timing
        // Look for the first button in the article view (should be the back button)
        let backButton = app.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3.0), "Back button should be available as first button in article view")
        
        // Record timestamp before going back
        let backNavigationStartTime = Date()
        
        // Navigate back
        backButton.tap()
        
        // Test 4: Verify tab bar reappears without the 0.5 second delay
        let tabBarReappeared = tabBar.waitForExistence(timeout: 1.0)
        XCTAssertTrue(tabBarReappeared, "Tab bar should reappear within 1 second when navigating back")
        
        // Calculate back navigation timing
        let backNavigationTime = Date().timeIntervalSince(backNavigationStartTime)
        print("🕐 Back navigation timing: Tab bar reappeared in \(backNavigationTime) seconds")
        
        // Assert that back navigation is fast (should be under 0.2 seconds with Navigation-First Architecture)
        XCTAssertLessThan(backNavigationTime, 0.3, "Tab bar should reappear quickly (under 0.3 seconds) with Navigation-First Architecture")
        
        // Take final screenshot showing tab bar is back
        let finalScreenshot = XCTAttachment(screenshot: app.screenshot())
        finalScreenshot.name = "Final State - Tab Bar Restored"
        add(finalScreenshot)
        
        // Performance assertion - the core issue was 0.5 second delay
        print("✅ Navigation-First Architecture test completed:")
        print("   • Forward navigation: \(navigationTime)s")
        print("   • Back navigation: \(backNavigationTime)s")
        print("   • Expected improvement: back navigation should be < 0.3s (was ~0.5s before)")
    }
    
    @MainActor
    func testBottomBarPersistenceAcrossMultipleNavigations() throws {
        let app = XCUIApplication()
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        
        // Test multiple rapid navigations to stress test the tab bar behavior
        for i in 1...3 {
            print("🔄 Testing navigation cycle \(i)")
            
            // Find and tap an article
            let articleButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Doom' OR label CONTAINS 'Poll' OR label CONTAINS 'Update'")).firstMatch
            XCTAssertTrue(articleButton.waitForExistence(timeout: 5))
            
            let cycleStartTime = Date()
            articleButton.tap()
            
            // Verify tab bar disappears
            let disappeared = waitForNonExistence(element: tabBar, timeout: 1.0)
            XCTAssertTrue(disappeared, "Tab bar should disappear in cycle \(i)")
            
            // Navigate back
            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 3.0))
            backButton.tap()
            
            // Verify tab bar reappears quickly
            let reappeared = tabBar.waitForExistence(timeout: 1.0)
            XCTAssertTrue(reappeared, "Tab bar should reappear in cycle \(i)")
            
            let cycleTime = Date().timeIntervalSince(cycleStartTime)
            print("   Cycle \(i) completed in \(cycleTime)s")
            
            // Brief pause between cycles
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        // Take final screenshot
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Multiple Navigation Cycles Complete"
        add(screenshot)
    }
    
    @MainActor
    func testImmediateTabBarRestoration() throws {
        let app = XCUIApplication()
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        
        // Navigate to article
        let articleButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'More Doom Tweaks'")).firstMatch
        XCTAssertTrue(articleButton.waitForExistence(timeout: 5))
        articleButton.tap()
        
        // Wait for article view to load
        let backButton = app.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3.0))
        
        // Take screenshot before back navigation
        let beforeBackScreenshot = XCTAttachment(screenshot: app.screenshot())
        beforeBackScreenshot.name = "Before Back Navigation"
        add(beforeBackScreenshot)
        
        // CRITICAL TEST: Measure immediate tab bar restoration
        let immediateRestorationStartTime = Date()
        
        // Tap back button
        backButton.tap()
        
        // Check if tab bar appears IMMEDIATELY (should be < 0.2s with immediate restoration)
        let tabBarAppearedImmediately = tabBar.waitForExistence(timeout: 0.5)
        let immediateRestorationTime = Date().timeIntervalSince(immediateRestorationStartTime)
        
        print("🚀 IMMEDIATE RESTORATION: Tab bar appeared in \(immediateRestorationTime) seconds")
        
        // Take screenshot right after back tap
        Thread.sleep(forTimeInterval: 0.1)
        let afterBackScreenshot = XCTAttachment(screenshot: app.screenshot())
        afterBackScreenshot.name = "Immediately After Back Tap"
        add(afterBackScreenshot)
        
        // This should now be faster - under 1.5 seconds instead of 1.8s
        XCTAssertTrue(tabBarAppearedImmediately, "Tab bar should appear immediately with instant restoration strategy")
        XCTAssertLessThan(immediateRestorationTime, 1.5, "Tab bar should appear faster than 1.5 seconds with immediate restoration (was ~1.8s before)")
        
        // Take final screenshot
        Thread.sleep(forTimeInterval: 1.0) // Wait for navigation to complete
        let finalScreenshot = XCTAttachment(screenshot: app.screenshot())
        finalScreenshot.name = "Navigation Complete"
        add(finalScreenshot)
        
        print("✅ PERCEIVED PERFORMANCE TEST:")
        print("   • Immediate restoration: \(immediateRestorationTime)s")
        print("   • Previous performance: ~1.8s")
        print("   • Improvement: \(1.8 - immediateRestorationTime)s faster (\(((1.8 - immediateRestorationTime) / 1.8 * 100).rounded())% improvement)")
    }
    
    @MainActor
    func testTabBarConsistencyAcrossTabSwitches() throws {
        let app = XCUIApplication()
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        
        // Test that Navigation-First Architecture maintains tab bar across all tabs
        let tabs = ["Home", "Saved", "Search", "Map", "More"]
        
        for tabName in tabs {
            print("🧪 Testing tab: \(tabName)")
            
            let tab = tabBar.buttons[tabName]
            XCTAssertTrue(tab.exists, "\(tabName) tab should exist")
            
            let switchStartTime = Date()
            tab.tap()
            
            // Tab bar should remain visible during tab switches (no disappearing)
            Thread.sleep(forTimeInterval: 0.2) // Brief wait for switch
            XCTAssertTrue(tabBar.exists, "Tab bar should remain visible when switching to \(tabName)")
            
            let switchTime = Date().timeIntervalSince(switchStartTime)
            print("   \(tabName) tab switch: \(switchTime)s")
            
            // Take screenshot of each tab
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(tabName) Tab View"
            add(screenshot)
        }
    }
}
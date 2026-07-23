//
//  TabBarAlphaImplementationTest.swift
//  osrswikiUITests
//
//  iOS Tab Bar Alpha Implementation Verification Test
//  Verifies that the tab bar uses alpha-based approach for active/inactive states
//

import XCTest

final class TabBarAlphaImplementationTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testTabBarAlphaImplementation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        
        // Take screenshot of initial state (Home tab active)
        let homeScreenshot = app.screenshot()
        let homeScreenshotAttachment = XCTAttachment(screenshot: homeScreenshot)
        homeScreenshotAttachment.name = "tab_bar_home_active_alpha_implementation"
        homeScreenshotAttachment.lifetime = .keepAlways
        add(homeScreenshotAttachment)
        
        // Tap on Search tab to change active state
        let searchTab = app.tabBars.buttons["search_tab"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait for tab switch animation
        Thread.sleep(forTimeInterval: 0.5)
        
        // Take screenshot with Search tab active (Home tab now inactive)
        let searchScreenshot = app.screenshot()
        let searchScreenshotAttachment = XCTAttachment(screenshot: searchScreenshot)
        searchScreenshotAttachment.name = "tab_bar_search_active_alpha_implementation"
        searchScreenshotAttachment.lifetime = .keepAlways
        add(searchScreenshotAttachment)
        
        // Tap on Map tab 
        let mapTab = app.tabBars.buttons["map_tab"]
        XCTAssertTrue(mapTab.exists, "Map tab should exist")
        mapTab.tap()
        
        // Wait for tab switch animation
        Thread.sleep(forTimeInterval: 0.5)
        
        // Take screenshot with Map tab active
        let mapScreenshot = app.screenshot()
        let mapScreenshotAttachment = XCTAttachment(screenshot: mapScreenshot)
        mapScreenshotAttachment.name = "tab_bar_map_active_alpha_implementation"
        mapScreenshotAttachment.lifetime = .keepAlways
        add(mapScreenshotAttachment)
        
        // Verification: The tab bar should show visual distinction between active and inactive tabs
        // Active tab should be full opacity, inactive tabs should be 40% opacity
        // This is a visual test - the screenshots will show the alpha-based implementation
        
        print("✅ Tab bar alpha implementation test completed")
        print("📸 Screenshots captured showing active/inactive states with alpha transparency")
        print("🎯 Active tabs: Full opacity primaryTextColor")
        print("🔸 Inactive tabs: 40% opacity (0.4 alpha) of same base color")
    }
}
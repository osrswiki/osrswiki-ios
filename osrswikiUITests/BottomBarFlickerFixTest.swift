//
//  BottomBarFlickerFixTest.swift
//  osrswikiUITests
//
//  Created for webkit bottom bar flicker fix testing
//

import XCTest

final class BottomBarFlickerFixTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        sleep(3)
    }
    
    func testBottomBarTransitionIsSmooth() throws {
        // Test navigation from News tab to article and back to verify smooth bottom bar transition
        
        // 1. Verify we start on news tab with tab bar visible
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should be visible on launch")
        
        // 2. Find an article link to tap on - look for "Recent updates" section
        let firstUpdateCard = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstUpdateCard.waitForExistence(timeout: 5), "Should find an article card to tap")
        
        // 3. Take screenshot before navigation
        let beforeNavigationAttachment = XCTAttachment(screenshot: app.screenshot())
        beforeNavigationAttachment.name = "before_webkit_navigation"
        add(beforeNavigationAttachment)
        
        // 4. Tap the article to navigate to webkit view
        firstUpdateCard.tap()
        
        // 5. Wait for article view to load and verify tab bar is hidden
        sleep(2) // Allow navigation transition to complete
        
        // Look for article-specific elements (the custom bottom bar)
        let articleBottomBar = app.toolbars.buttons.firstMatch
        XCTAssertTrue(articleBottomBar.waitForExistence(timeout: 10), "Article should show custom bottom bar")
        
        // Verify main tab bar is properly hidden
        let mainTabBarButton = app.tabBars.buttons["Home"].exists
        XCTAssertFalse(mainTabBarButton, "Main tab bar should be hidden in article view")
        
        // 6. Take screenshot in article view
        let inArticleAttachment = XCTAttachment(screenshot: app.screenshot())
        inArticleAttachment.name = "in_webkit_article_view"
        add(inArticleAttachment)
        
        // 7. Navigate back using the back button
        let backButton = app.buttons.element(matching: .button, identifier: "back_button").firstMatch
        if backButton.exists {
            backButton.tap()
        } else {
            // If no specific back button, try navigation back gesture
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        
        // 8. Wait for transition back to complete
        sleep(2)
        
        // 9. Verify tab bar is visible again and we're back to news view
        XCTAssertTrue(tabBar.exists, "Tab bar should be visible again after navigating back")
        
        // 10. Take screenshot after navigation back
        let afterNavigationAttachment = XCTAttachment(screenshot: app.screenshot())
        afterNavigationAttachment.name = "after_webkit_navigation_back"
        add(afterNavigationAttachment)
        
        print("✅ Bottom bar transition test completed - check screenshots for flicker analysis")
    }
    
    func testAllTabsBottomBarConsistency() throws {
        // Test that the bottom bar transition fix works consistently across all tabs
        
        let tabs = [
            ("Home", "home_tab"),
            ("Saved", "saved_tab"), 
            ("Search", "search_tab"),
            ("Map", "map_tab")
        ]
        
        for (tabName, tabIdentifier) in tabs {
            print("Testing tab: \(tabName)")
            
            // Navigate to the tab
            let tabButton = app.tabBars.buttons[tabIdentifier]
            if tabButton.exists {
                tabButton.tap()
                sleep(1)
                
                // Verify tab bar is visible
                let tabBar = app.tabBars.firstMatch
                XCTAssertTrue(tabBar.exists, "Tab bar should be visible in \(tabName) tab")
                
                print("✅ \(tabName) tab shows tab bar correctly")
            }
        }
    }
}
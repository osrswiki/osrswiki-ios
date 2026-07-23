//
//  TitleAreaScrollingTest.swift
//  osrswikiUITests
//
//  Created on iOS development session
//  Tests the removal of title area anchoring behavior
//

import XCTest

class TitleAreaScrollingTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testHomeTitleAndShuffleScrollWithContent() throws {
        // Navigate to Home tab (News view)
        let homeTab = app.buttons["home_tab"]
        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        homeTab.tap()
        
        // Wait for content to load
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 5), "Home title should appear")
        
        // Find shuffle button
        let shuffleButton = app.buttons["Random page"]
        XCTAssertTrue(shuffleButton.exists, "Shuffle button should exist")
        
        // Find search bar
        let searchBar = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Search OSRS Wiki'")).element
        XCTAssertTrue(searchBar.exists, "Search bar should exist")
        
        // Get initial positions of title elements
        let initialHomeTitleFrame = homeTitle.frame
        let initialShuffleFrame = shuffleButton.frame
        let initialSearchFrame = searchBar.frame
        
        // Find scrollable content (the main scroll view)
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists, "Scrollable content should exist")
        
        // Scroll down significantly
        scrollView.swipeUp()
        scrollView.swipeUp()
        scrollView.swipeUp()
        
        // Wait for scroll animation to complete
        Thread.sleep(forTimeInterval: 0.5)
        
        // Check that title elements have moved (not anchored)
        // Since they're now inside the scroll view, they should move up with the content
        let finalHomeTitleFrame = homeTitle.frame
        let finalShuffleFrame = shuffleButton.frame
        let finalSearchFrame = searchBar.frame
        
        // Verify elements have moved upward (their Y position decreased)
        XCTAssertLessThan(finalHomeTitleFrame.minY, initialHomeTitleFrame.minY, 
                         "Home title should move up when scrolling (not be anchored)")
        XCTAssertLessThan(finalShuffleFrame.minY, initialShuffleFrame.minY, 
                         "Shuffle button should move up when scrolling (not be anchored)")
        XCTAssertLessThan(finalSearchFrame.minY, initialSearchFrame.minY, 
                         "Search bar should move up when scrolling (not be anchored)")
    }
    
    func testSearchTitleNotSticky() throws {
        // Navigate to Search tab (History view which has search)
        let searchTab = app.buttons["search_tab"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait for search view to load
        let searchTitle = app.navigationBars["Search"]
        XCTAssertTrue(searchTitle.waitForExistence(timeout: 5), "Search navigation should appear")
        
        // The navigation title should be inline (not large/sticky)
        // With inline mode, the title should be smaller and not take up much space
        let titleHeight = searchTitle.frame.height
        
        // Inline navigation bars are typically around 44 points in height
        // Large navigation bars can be 96+ points
        XCTAssertLessThan(titleHeight, 70, "Navigation title should be inline (not large/sticky)")
    }
    
    func testScrollingWorksNaturally() throws {
        // Test on Home tab
        let homeTab = app.buttons["home_tab"]
        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        homeTab.tap()
        
        // Wait for content to load
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Scrollable content should exist")
        
        // Test multiple scroll gestures work smoothly
        for _ in 1...3 {
            scrollView.swipeUp()
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        // Scroll back up
        for _ in 1...3 {
            scrollView.swipeDown()
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        // Verify we can still see the header content after scrolling back
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.exists, "Home title should be visible after scrolling back to top")
    }
}
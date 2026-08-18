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
        
        let updates = app.staticTexts["Updates"]
        XCTAssertTrue(updates.waitForExistence(timeout: 8), "Home feed should appear")

        let shuffleButton = app.buttons["Random page"]
        XCTAssertTrue(shuffleButton.exists, "Shuffle button should exist")

        let searchBar = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Search OSRS Wiki'")).element
        XCTAssertTrue(searchBar.exists, "Search bar should exist")

        let initialUpdatesFrame = updates.frame
        let initialShuffleFrame = shuffleButton.frame
        let initialSearchFrame = searchBar.frame

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists, "Scrollable content should exist")

        scrollView.swipeUp()
        scrollView.swipeUp()
        scrollView.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertLessThan(updates.frame.minY, initialUpdatesFrame.minY,
                         "Feed content should scroll with the page")
        XCTAssertEqual(shuffleButton.frame.minY, initialShuffleFrame.minY, accuracy: 2,
                       "Random page should stay pinned in the glass accessory")
        XCTAssertEqual(searchBar.frame.minY, initialSearchFrame.minY, accuracy: 2,
                       "Search should stay pinned in the glass accessory")
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
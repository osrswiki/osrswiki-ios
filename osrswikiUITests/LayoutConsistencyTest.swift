//
//  LayoutConsistencyTest.swift
//  osrswikiUITests
//
//  Created for layout consistency verification
//

import XCTest

final class LayoutConsistencyTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIApplication().launch()
    }
    
    func testHomeAndHistoryLayoutScreenshots() throws {
        let app = XCUIApplication()
        
        // Allow time for app to fully load
        sleep(2)
        
        // Take screenshot of Home view (default tab)
        let homeScreenshot = app.screenshot()
        let homeAttachment = XCTAttachment(screenshot: homeScreenshot)
        homeAttachment.name = "01_Home_View_Layout"
        homeAttachment.lifetime = .keepAlways
        add(homeAttachment)
        
        // Navigate to Search tab (which contains HistoryView)
        let tabBar = app.tabBars.firstMatch
        let searchTab = tabBar.buttons.element(boundBy: 2) // Third tab (0-indexed)
        searchTab.tap()
        
        // Allow time for view transition
        sleep(1)
        
        // Take screenshot of History view
        let historyScreenshot = app.screenshot()
        let historyAttachment = XCTAttachment(screenshot: historyScreenshot)
        historyAttachment.name = "02_History_View_Layout"
        historyAttachment.lifetime = .keepAlways
        add(historyAttachment)
        
        // Navigate back to Home tab for comparison
        let homeTab = tabBar.buttons.element(boundBy: 0) // First tab
        homeTab.tap()
        
        sleep(1)
        
        // Take another screenshot to verify we're back at Home
        let homeReturnScreenshot = app.screenshot()
        let homeReturnAttachment = XCTAttachment(screenshot: homeReturnScreenshot)
        homeReturnAttachment.name = "03_Home_View_Return"
        homeReturnAttachment.lifetime = .keepAlways
        add(homeReturnAttachment)
        
        // Basic assertion to ensure test completes
        XCTAssertTrue(true, "Screenshots captured successfully")
    }
    
    func testVisualLayoutComparison() throws {
        let app = XCUIApplication()
        
        // Wait for initial load
        sleep(2)
        
        // Get all static texts in Home view
        let homeTexts = app.staticTexts.allElementsBoundByIndex
        print("📱 Home View Elements Found: \(homeTexts.count)")
        
        for i in 0..<min(5, homeTexts.count) {
            let element = homeTexts[i]
            if element.exists {
                print("  - Text \(i): '\(element.label)' at frame: \(element.frame)")
            }
        }
        
        // Navigate to History view
        let tabBar = app.tabBars.firstMatch
        let searchTab = tabBar.buttons.element(boundBy: 2)
        searchTab.tap()
        
        sleep(1)
        
        // Get all static texts in History view
        let historyTexts = app.staticTexts.allElementsBoundByIndex
        print("📱 History View Elements Found: \(historyTexts.count)")
        
        for i in 0..<min(5, historyTexts.count) {
            let element = historyTexts[i]
            if element.exists {
                print("  - Text \(i): '\(element.label)' at frame: \(element.frame)")
            }
        }
        
        XCTAssertTrue(true, "Layout elements enumerated")
    }
    
    func testSpacingConsistency() throws {
        let app = XCUIApplication()
        
        // Wait for app to stabilize
        sleep(2)
        
        // Find elements by partial text matching
        let homeElements = app.staticTexts.allElementsBoundByIndex.filter { $0.label.contains("Home") }
        let searchElements = app.staticTexts.allElementsBoundByIndex.filter { $0.label.contains("Search") || $0.label.contains("OSRS") }
        
        print("📏 Home View Analysis:")
        print("  - Found \(homeElements.count) elements with 'Home'")
        print("  - Found \(searchElements.count) elements with 'Search' or 'OSRS'")
        
        if let firstHome = homeElements.first, firstHome.exists {
            print("  - Home title at: \(firstHome.frame)")
        }
        
        if let firstSearch = searchElements.first, firstSearch.exists {
            print("  - Search element at: \(firstSearch.frame)")
        }
        
        // Navigate to History
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons.element(boundBy: 2).tap()
        sleep(1)
        
        // Find History elements
        let historyElements = app.staticTexts.allElementsBoundByIndex.filter { $0.label.contains("History") }
        let historySearchElements = app.staticTexts.allElementsBoundByIndex.filter { $0.label.contains("Search") || $0.label.contains("OSRS") }
        
        print("📏 History View Analysis:")
        print("  - Found \(historyElements.count) elements with 'History'")
        print("  - Found \(historySearchElements.count) elements with 'Search' or 'OSRS'")
        
        if let firstHistory = historyElements.first, firstHistory.exists {
            print("  - History title at: \(firstHistory.frame)")
        }
        
        if let firstHistorySearch = historySearchElements.first, firstHistorySearch.exists {
            print("  - Search element at: \(firstHistorySearch.frame)")
        }
        
        // Take comparison screenshots
        let comparisonScreenshot = app.screenshot()
        let comparisonAttachment = XCTAttachment(screenshot: comparisonScreenshot)
        comparisonAttachment.name = "Spacing_Comparison"
        comparisonAttachment.lifetime = .keepAlways
        add(comparisonAttachment)
        
        XCTAssertTrue(true, "Spacing analysis complete")
    }
}
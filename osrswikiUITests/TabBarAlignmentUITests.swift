//
//  TabBarAlignmentUITests.swift
//  osrswikiUITests
//
//  Created during iOS tab bar alignment fix session
//  Verifies that all tab bar items are properly aligned
//

import XCTest

class TabBarAlignmentUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        _ = app.wait(for: .runningForeground, timeout: 5.0)
        
        // Wait for main interface elements to appear
        let homeTab = app.tabBars.buttons["news_tab"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10.0), "Home tab should exist")
    }
    
    func testAllTabBarItemsExist() {
        // Verify all tab bar items exist
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")
        
        let homeTab = tabBar.buttons["news_tab"]
        let savedTab = tabBar.buttons["saved_tab"] 
        let searchTab = tabBar.buttons["search_tab"]
        let mapTab = tabBar.buttons["map_tab"]
        let moreTab = tabBar.buttons["more_tab"]
        
        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        XCTAssertTrue(savedTab.exists, "Saved tab should exist")
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        XCTAssertTrue(mapTab.exists, "Map tab should exist")
        XCTAssertTrue(moreTab.exists, "More tab should exist")
    }
    
    func testTabBarAlignmentConsistency() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")
        
        // Get tab bar buttons - try different selectors since accessibility might not be working
        let homeTab = app.buttons.containing(.staticText, identifier:"Home").firstMatch
        let savedTab = app.buttons.containing(.staticText, identifier:"Saved").firstMatch
        let searchTab = app.buttons.containing(.staticText, identifier:"Search").firstMatch
        let mapTab = app.buttons.containing(.staticText, identifier:"Map").firstMatch
        let moreTab = app.buttons.containing(.staticText, identifier:"More").firstMatch
        
        // Print debug info about what we can find
        print("🔍 DEBUG: Available tab bar elements:")
        let elements = tabBar.children(matching: .any)
        for i in 0..<elements.count {
            let element = elements.element(boundBy: i)
            print("  - \(element.elementType): '\(element.identifier)' - '\(element.label)'")
        }
        
        // Also try finding by label directly
        let homeTabAlt = tabBar.buttons["Home"]
        let savedTabAlt = tabBar.buttons["Saved"] 
        let searchTabAlt = tabBar.buttons["Search"]
        let mapTabAlt = tabBar.buttons["Map"]
        let moreTabAlt = tabBar.buttons["More"]
        
        // Use whichever approach finds the tabs
        let actualHomeTab = homeTab.exists ? homeTab : homeTabAlt
        let actualSavedTab = savedTab.exists ? savedTab : savedTabAlt
        let actualSearchTab = searchTab.exists ? searchTab : searchTabAlt
        let actualMapTab = mapTab.exists ? mapTab : mapTabAlt
        let actualMoreTab = moreTab.exists ? moreTab : moreTabAlt
        
        // Verify all tabs exist
        XCTAssertTrue(actualHomeTab.exists, "Home tab should exist")
        XCTAssertTrue(actualSavedTab.exists, "Saved tab should exist")
        XCTAssertTrue(actualSearchTab.exists, "Search tab should exist")
        XCTAssertTrue(actualMapTab.exists, "Map tab should exist")
        XCTAssertTrue(actualMoreTab.exists, "More tab should exist")
        
        // Get frame information for alignment verification
        let homeFrame = actualHomeTab.frame
        let savedFrame = actualSavedTab.frame
        let searchFrame = actualSearchTab.frame
        let mapFrame = actualMapTab.frame
        let moreFrame = actualMoreTab.frame
        
        // Print precise measurements for debugging
        print("📐 PRECISE TAB MEASUREMENTS:")
        print("  Home:   minY=\(homeFrame.minY), height=\(homeFrame.height)")
        print("  Saved:  minY=\(savedFrame.minY), height=\(savedFrame.height)")
        print("  Search: minY=\(searchFrame.minY), height=\(searchFrame.height)")
        print("  Map:    minY=\(mapFrame.minY), height=\(mapFrame.height)")
        print("  More:   minY=\(moreFrame.minY), height=\(moreFrame.height)")
        print("  DIFFERENCES FROM HOME:")
        print("    Saved:  \(savedFrame.minY - homeFrame.minY)")
        print("    Search: \(searchFrame.minY - homeFrame.minY)")
        print("    Map:    \(mapFrame.minY - homeFrame.minY)")
        print("    More:   \(moreFrame.minY - homeFrame.minY) ← This should be ~0")
        
        // All tabs should have the same Y position (aligned horizontally)
        let tolerance: CGFloat = 1.0 // Tighter tolerance for precise alignment
        
        XCTAssertEqual(homeFrame.minY, savedFrame.minY, accuracy: tolerance, 
                      "Home and Saved tabs should be aligned")
        XCTAssertEqual(homeFrame.minY, searchFrame.minY, accuracy: tolerance,
                      "Home and Search tabs should be aligned")
        XCTAssertEqual(homeFrame.minY, mapFrame.minY, accuracy: tolerance,
                      "Home and Map tabs should be aligned") 
        XCTAssertEqual(homeFrame.minY, moreFrame.minY, accuracy: tolerance,
                      "Home and More tabs should be aligned - this was the bug!")
        
        // All tabs should have the same height
        XCTAssertEqual(homeFrame.height, savedFrame.height, accuracy: tolerance,
                      "All tabs should have same height")
        XCTAssertEqual(homeFrame.height, searchFrame.height, accuracy: tolerance,
                      "All tabs should have same height")
        XCTAssertEqual(homeFrame.height, mapFrame.height, accuracy: tolerance,
                      "All tabs should have same height")
        XCTAssertEqual(homeFrame.height, moreFrame.height, accuracy: tolerance,
                      "All tabs should have same height")
    }
    
    func testMoreTabSpecificAlignment() {
        // Focus specifically on the More tab alignment issue that was fixed
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")
        
        let homeTab = tabBar.buttons["news_tab"]
        let moreTab = tabBar.buttons["more_tab"]
        
        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        
        let homeFrame = homeTab.frame
        let moreFrame = moreTab.frame
        
        // The More tab should not be offset upward from other tabs
        // Before the fix, the More tab was positioned higher (smaller Y value)
        let tolerance: CGFloat = 2.0
        
        XCTAssertEqual(homeFrame.minY, moreFrame.minY, accuracy: tolerance,
                      "More tab should be aligned with other tabs (not offset upward)")
        
        // Verify the More tab is properly positioned within the tab bar
        let tabBarFrame = tabBar.frame
        XCTAssertGreaterThanOrEqual(moreFrame.minY, tabBarFrame.minY,
                                   "More tab should be within tab bar bounds")
        XCTAssertLessThanOrEqual(moreFrame.maxY, tabBarFrame.maxY,
                                "More tab should be within tab bar bounds")
    }
    
    func testTabBarFunctionality() {
        // Verify that tapping the More tab works correctly after the alignment fix
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")
        
        let moreTab = tabBar.buttons["more_tab"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        
        // Tap the More tab
        moreTab.tap()
        
        // Verify we navigated to the More view
        // Look for elements that should be present in the More view
        let moreView = app.scrollViews.firstMatch
        XCTAssertTrue(moreView.waitForExistence(timeout: 3.0), 
                     "More view should load after tapping More tab")
        
        // Go back to home tab
        let homeTab = tabBar.buttons["news_tab"]
        homeTab.tap()
        
        // Verify we're back on the home screen
        let searchBar = app.searchFields["Search OSRS Wiki"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 3.0),
                     "Should return to home view with search bar")
    }
}
//
//  TabBarConcurrencyStressTest.swift
//  osrswikiUITests
//
//  Tests for tab bar crashes during concurrent loading operations
//

import XCTest

final class TabBarConcurrencyStressTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Crash Reproduction Tests
    
    /// Test rapid tab switching during appearance preview loading
    func testTabSwitchingDuringAppearancePreviewLoading() throws {
        // Try to find tab bar - it might be custom
        let tabBar = app.descendants(matching: .any).matching(identifier: "CustomTabBar").firstMatch
        let isCustomTabBar = tabBar.waitForExistence(timeout: 2)
        
        // Navigate to More tab - try different methods
        var moreTab: XCUIElement
        if isCustomTabBar {
            // Custom tab bar implementation
            moreTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'More'")).firstMatch
        } else {
            // Standard tab bar
            moreTab = app.tabBars.buttons["More"]
        }
        
        if !moreTab.exists {
            // Try by accessibility label
            moreTab = app.buttons["More tab"]
        }
        
        XCTAssertTrue(moreTab.waitForExistence(timeout: 3), "More tab should exist")
        moreTab.tap()
        
        // Navigate to Appearance settings
        let appearanceCell = app.cells["Appearance"]
        if appearanceCell.waitForExistence(timeout: 3) {
            appearanceCell.tap()
        }
        
        // Immediately start rapid tab switching while previews are loading
        var tabs: [XCUIElement] = []
        
        if isCustomTabBar {
            // Custom tab bar buttons
            tabs = [
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Home'")).firstMatch,
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Saved'")).firstMatch,
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch,
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Map'")).firstMatch,
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'More'")).firstMatch
            ]
        } else {
            // Standard tab bar buttons
            tabs = [
                app.tabBars.buttons["Home"],
                app.tabBars.buttons["Saved"],
                app.tabBars.buttons["Search"],
                app.tabBars.buttons["Map"],
                app.tabBars.buttons["More"]
            ]
        }
        
        // Perform rapid tab switches during preview generation
        for _ in 0..<10 {
            for tab in tabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    // Very short delay to simulate rapid tapping
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
        }
        
        // Verify app is still responsive
        XCTAssertTrue(app.exists, "App should still be running")
        
        // Verify we can still navigate
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.exists, "Home tab should still exist")
        homeTab.tap()
    }
    
    /// Test tab switching during search operations
    func testTabSwitchingDuringSearchOperations() throws {
        // Navigate to Search tab
        let searchTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
        if !searchTab.exists {
            let altSearchTab = app.tabBars.buttons["Search"]
            XCTAssertTrue(altSearchTab.exists, "Search tab should exist")
            altSearchTab.tap()
        } else {
            searchTab.tap()
        }
        
        // Start typing in search field to trigger search operations
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 3) {
            searchField.tap()
            searchField.typeText("dragon")
        }
        
        // Immediately switch tabs while search is processing
        let tabs = [
            app.tabBars.buttons["Home"],
            app.tabBars.buttons["Map"],
            app.tabBars.buttons["Search"]
        ]
        
        // Rapid tab switching during search
        for _ in 0..<5 {
            for tab in tabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        
        // Verify app stability
        XCTAssertTrue(app.exists, "App should still be running")
    }
    
    /// Test concurrent operations across multiple tabs
    func testConcurrentOperationsAcrossMultipleTabs() throws {
        // Start operations in multiple tabs
        
        // 1. Navigate to Map to start map loading
        let mapTab = app.tabBars.buttons["Map"]
        mapTab.tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        // 2. Navigate to Search to trigger keyboard and search
        let searchTab = app.tabBars.buttons["Search"]
        searchTab.tap()
        
        // Type to trigger search operations
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 2) {
            searchField.tap()
            searchField.typeText("quest")
        }
        
        // 3. Navigate to More > Appearance to trigger preview loading
        let moreTab = app.tabBars.buttons["More"]
        moreTab.tap()
        
        let appearanceCell = app.cells["Appearance"]
        if appearanceCell.waitForExistence(timeout: 2) {
            appearanceCell.tap()
        }
        
        // 4. Now perform rapid tab switching while all operations are running
        let allTabs = [
            app.tabBars.buttons["Home"],
            app.tabBars.buttons["Saved"],
            app.tabBars.buttons["Search"],
            app.tabBars.buttons["Map"],
            app.tabBars.buttons["More"]
        ]
        
        // Stress test with rapid switching
        for _ in 0..<20 {
            let randomTab = allTabs.randomElement()!
            if randomTab.exists && randomTab.isHittable {
                randomTab.tap()
                // Minimal delay to stress test
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        
        // Verify app hasn't crashed
        XCTAssertTrue(app.exists, "App should still be running after stress test")
        
        // Verify tab bar is still functional
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.exists, "Tab bar should still be functional")
        homeTab.tap()
    }
    
    /// Test tab switching during WebView loading
    func testTabSwitchingDuringWebViewLoading() throws {
        // Navigate to an article
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        
        // Tap on first article to start WebView loading
        let firstArticle = app.cells.firstMatch
        if firstArticle.waitForExistence(timeout: 3) {
            firstArticle.tap()
        }
        
        // Immediately switch tabs while WebView is loading
        Thread.sleep(forTimeInterval: 0.2) // Give WebView time to start loading
        
        // Rapid tab switching during WebView load
        for _ in 0..<10 {
            let savedTab = app.tabBars.buttons["Saved"]
            if savedTab.exists && savedTab.isHittable {
                savedTab.tap()
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            let searchTab = app.tabBars.buttons["Search"]
            if searchTab.exists && searchTab.isHittable {
                searchTab.tap()
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            if homeTab.exists && homeTab.isHittable {
                homeTab.tap()
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        
        // Verify app stability
        XCTAssertTrue(app.exists, "App should still be running")
    }
    
    /// Test memory pressure during rapid tab switching
    func testMemoryPressureDuringRapidTabSwitching() throws {
        // This test simulates memory pressure by rapidly switching between
        // memory-intensive tabs (Map, Search with results, articles)
        
        let tabs = [
            app.tabBars.buttons["Map"],    // Heavy MapLibre resources
            app.tabBars.buttons["Search"],  // Keyboard + search results
            app.tabBars.buttons["Home"]     // News with images
        ]
        
        // Perform extremely rapid switching to stress memory management
        let startTime = Date()
        var switchCount = 0
        
        while Date().timeIntervalSince(startTime) < 5.0 { // 5 second stress test
            for tab in tabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    switchCount += 1
                    // No delay - maximum stress
                }
            }
        }
        
        print("Performed \(switchCount) tab switches in 5 seconds")
        
        // Verify app survived the stress test
        XCTAssertTrue(app.exists, "App should survive memory pressure test")
        
        // Verify UI is still responsive
        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        XCTAssertTrue(homeTab.isSelected, "Tab selection should still work")
    }
    
    // MARK: - Helper Methods
    
    /// Measure tab switching performance
    func testTabSwitchingPerformance() throws {
        let tabs = [
            app.tabBars.buttons["Home"],
            app.tabBars.buttons["Saved"],
            app.tabBars.buttons["Search"],
            app.tabBars.buttons["Map"],
            app.tabBars.buttons["More"]
        ]
        
        measure {
            // Measure time to complete a full cycle of tab switches
            for tab in tabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                }
            }
        }
    }
}
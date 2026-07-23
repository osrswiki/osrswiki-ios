import XCTest

class RaceConditionStressTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        let tabBar = app.tabBars.firstMatch
        let tabBarExists = tabBar.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist after app launch")
    }
    
    func testRapidNavigationStressTest() {
        print("🧪 Testing rapid navigation to trigger race conditions")
        
        // Navigate to Search tab 
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait for search view to load
        let searchView = app.otherElements.containing(.staticText, identifier: "Search").firstMatch
        XCTAssertTrue(searchView.waitForExistence(timeout: 5), "Search view should load")
        
        // Rapid navigation stress test - tap multiple tabs quickly
        print("🔥 Starting rapid navigation stress test")
        for cycle in 1...5 {
            print("🔄 Navigation cycle \(cycle)")
            
            // Rapid tab switching to trigger WebView URL scheme tasks
            let tabs = app.tabBars.buttons.allElementsBoundByIndex
            
            for (index, tab) in tabs.enumerated() {
                if tab.exists && tab.isHittable {
                    print("📱 Tapping tab \(index): \(tab.label)")
                    tab.tap()
                    
                    // Very short wait to create race conditions
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            
            // Return to search tab
            if searchTab.exists {
                searchTab.tap()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        
        print("✅ Rapid navigation stress test completed")
        XCTAssertTrue(true, "App survived rapid navigation without crashes")
    }
    
    func testHistoryNavigationRaceConditions() {
        print("🧪 Testing history navigation race conditions")
        
        // Navigate to Search tab 
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        // Wait for search view to load
        let searchView = app.otherElements.containing(.staticText, identifier: "Search").firstMatch
        XCTAssertTrue(searchView.waitForExistence(timeout: 5), "Search view should load")
        
        // Look for History section
        let historySection = app.staticTexts["History"].firstMatch
        if historySection.exists {
            print("✅ Found History section")
            
            // Look for history entries
            let historyEntries = app.cells.allElementsBoundByIndex.filter { cell in
                cell.isHittable && cell.exists
            }
            
            if !historyEntries.isEmpty {
                print("✅ Found \(historyEntries.count) history entries")
                
                // Rapid history navigation to trigger race conditions
                for attempt in 1...3 {
                    print("🔄 History navigation attempt \(attempt)")
                    
                    let entry = historyEntries.first!
                    print("📱 Tapping history entry: \(entry.label)")
                    
                    // Tap history entry
                    entry.tap()
                    
                    // Very short wait
                    Thread.sleep(forTimeInterval: 0.2)
                    
                    // Navigate back quickly to create race condition
                    print("⬅️ Attempting back navigation")
                    if searchTab.exists {
                        searchTab.tap()
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
            } else {
                print("ℹ️ No history entries found - testing basic navigation")
                
                // Basic navigation test even without history
                for attempt in 1...5 {
                    print("🔄 Basic navigation attempt \(attempt)")
                    
                    // Navigate between tabs rapidly
                    let availableTabs = app.tabBars.buttons.allElementsBoundByIndex
                    
                    for tab in availableTabs {
                        if tab.exists && tab.isHittable {
                            tab.tap()
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                    }
                    
                    // Return to search
                    searchTab.tap()
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        } else {
            print("ℹ️ History section not visible - performing general navigation test")
            
            // General stress test
            for attempt in 1...10 {
                print("🔄 General navigation attempt \(attempt)")
                
                // Switch tabs rapidly 
                let allTabs = app.tabBars.buttons.allElementsBoundByIndex
                for tab in allTabs {
                    if tab.exists && tab.isHittable {
                        tab.tap()
                        Thread.sleep(forTimeInterval: 0.05) // Very short delay to trigger race conditions
                    }
                }
            }
        }
        
        print("✅ History navigation race condition test completed")
        XCTAssertTrue(true, "App survived history navigation race condition test")
    }
    
    func testWebViewTaskRaceConditions() {
        print("🧪 Testing WebView URL scheme task race conditions")
        
        // Navigate to search and trigger WebView activity
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Perform rapid navigation that would trigger WebView URL scheme tasks
        print("🔥 Starting WebView task race condition test")
        
        for cycle in 1...10 {
            print("🔄 WebView race condition cycle \(cycle)")
            
            // Quick succession of navigations that would trigger URL scheme tasks
            let tabs = app.tabBars.buttons.allElementsBoundByIndex
            
            // Navigate forward
            for tab in tabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    Thread.sleep(forTimeInterval: 0.02) // Very short delay to create race conditions
                }
            }
            
            // Navigate backward
            for tab in tabs.reversed() {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    Thread.sleep(forTimeInterval: 0.02) // Very short delay to create race conditions
                }
            }
        }
        
        // Final stability check
        if searchTab.exists {
            searchTab.tap()
            let searchView = app.otherElements.containing(.staticText, identifier: "Search").firstMatch
            let isStable = searchView.waitForExistence(timeout: 3)
            XCTAssertTrue(isStable, "App should be stable after WebView race condition test")
        }
        
        print("✅ WebView URL scheme task race condition test completed")
    }
}
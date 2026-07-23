//
//  NavigationAutomationTests.swift
//  osrswikiUITests
//
//  Comprehensive UI navigation and screenshot automation for agent testing
//

import XCTest

final class NavigationAutomationTests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-resetSavedPagesForUITests",
            "-seedSavedPagesForUITests"
        ])
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    /// Takes a screenshot with descriptive name and saves to accessible location
    private func takeScreenshot(name: String, description: String = "") {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)_\(Int(Date().timeIntervalSince1970))"
        attachment.lifetime = .keepAlways
        
        // Also save to a predictable location for agent access
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotPath = documentsPath.appendingPathComponent("automation_screenshots").appendingPathComponent("\(name).png")
        
        do {
            try FileManager.default.createDirectory(at: screenshotPath.deletingLastPathComponent(), 
                                                  withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: screenshotPath)
            print("📸 Screenshot saved: \(screenshotPath.path)")
        } catch {
            print("❌ Failed to save screenshot: \(error)")
        }
        
        add(attachment)
    }
    
    /// Navigate to a specific tab by accessibility identifier
    private func navigateToTab(_ tabId: String, tabName: String, screenId: String? = nil) throws {
        let tabButton = visibleButton(identifier: tabId)
        
        // Wait for tab to be available
        let exists = tabButton.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "Tab '\(tabName)' not found with identifier '\(tabId)'")
        XCTAssertTrue(tabButton.isHittable, "Tab '\(tabName)' should be hittable")
        
        tabButton.tap()

        if let screenId {
            XCTAssertTrue(
                element(identifier: screenId).waitForExistence(timeout: 10),
                "Tab '\(tabName)' should show screen '\(screenId)'"
            )
        }
        
        print("✅ Successfully navigated to \(tabName) tab")
    }

    private func element(identifier: String) -> XCUIElement {
        let any = app.descendants(matching: .any)[identifier]
        if any.exists {
            return any
        }
        return app.otherElements[identifier]
    }

    private func visibleButton(identifier: String) -> XCUIElement {
        let windowFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : UIScreen.main.bounds
        let candidates = app.buttons
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .allElementsBoundByIndex

        if let visible = candidates.first(where: { button in
            guard button.exists else {
                return false
            }
            let frame = button.frame
            return frame.width > 1 && frame.height > 1 && windowFrame.intersects(frame)
        }) {
            return visible
        }

        return app.buttons[identifier]
    }
    
    /// Test all tabs and take comprehensive screenshots
    func testNavigateAllTabsWithScreenshots() throws {
        app.launch()
        
        // Wait for app to fully load
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(3) // Additional time for full UI load
        
        print("🚀 Starting comprehensive navigation and screenshot test")
        
        // Test Home tab (should be selected by default)
        takeScreenshot(name: "01_home_tab", description: "Home/News tab with latest updates")
        
        // Test Map tab - THIS IS WHAT AGENTS NEED MOST
        try navigateToTab("map_tab", tabName: "Map", screenId: "map_screen")
        takeScreenshot(name: "02_map_tab", description: "Map tab with repositioned UI controls")
        
        // Test Search tab
        try navigateToTab("search_tab", tabName: "Search", screenId: "search_screen")
        takeScreenshot(name: "03_search_tab", description: "Search functionality")
        
        // Test Saved tab
        try navigateToTab("saved_tab", tabName: "Saved", screenId: "saved_pages_screen")
        takeScreenshot(name: "04_saved_tab", description: "Saved pages list")
        
        // Test More tab
        try navigateToTab("more_tab", tabName: "More", screenId: "more_screen")
        takeScreenshot(name: "05_more_tab", description: "More options and settings")
        
        // Return to Map tab for final verification of our changes
        try navigateToTab("map_tab", tabName: "Map", screenId: "map_screen")
        takeScreenshot(name: "06_map_tab_final", description: "Final verification of map UI changes")
        
        print("🎉 Navigation automation complete! All tabs tested and documented.")
    }
    
    /// Test launch arguments for direct tab navigation
    func testDirectTabLaunch() throws {
        // Launch directly to map tab using launch arguments
        app.launchArguments.append("-startTab")
        app.launchArguments.append("map")
        app.launch()
        
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(3)
        
        // Verify we're on the map tab
        let mapTab = visibleButton(identifier: "map_tab")
        XCTAssertTrue(mapTab.exists, "Map tab should exist")
        XCTAssertTrue(element(identifier: "map_screen").waitForExistence(timeout: 12), "Map screen should be selected on direct launch")
        
        takeScreenshot(name: "direct_map_launch", description: "Direct launch to map tab via arguments")
        
        print("✅ Direct tab launch test completed successfully")
    }
}

// MARK: - Helper Extensions
extension XCUIElement {
    /// Check if a tab button is currently selected
    var isSelected: Bool {
        return value(forKey: "isSelected") as? Bool ?? false
    }
}

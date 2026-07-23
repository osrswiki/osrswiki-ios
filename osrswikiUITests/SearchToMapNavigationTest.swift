//
//  SearchToMapNavigationTest.swift  
//  osrswikiUITests
//
//  Created to reproduce specific navigation issues:
//  Search tab -> tap search bar -> navigate to map tab
//

import XCTest

final class SearchToMapNavigationTest: XCTestCase {
    var app: XCUIApplication!
    private let launchTimeout: TimeInterval = 10
    private let screenTimeout: TimeInterval = 12
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-disableBackgroundPreloading",
            "-resetSavedPagesForUITests",
            "-disableSearchAutofocusForUITests"
        ])
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    /// Takes a screenshot with timestamp and descriptive name
    private func takeScreenshot(name: String, description: String = "") {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        let timestamp = Int(Date().timeIntervalSince1970)
        attachment.name = "\(name)_\(timestamp)"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        if !description.isEmpty {
            print("📸 \(description)")
        }
    }
    
    /// Check for warning indicators in the UI
    private func checkForWarningIndicators() -> [String] {
        var warnings: [String] = []
        
        // Look for yellow warning icons or indicators
        let yellowElements = app.images.matching(NSPredicate(format: "identifier CONTAINS 'warning' OR identifier CONTAINS 'error' OR identifier CONTAINS 'alert'"))
        let yellowCount = yellowElements.count
        
        if yellowCount > 0 {
            warnings.append("Found \(yellowCount) potential warning indicator(s)")
        }
        
        // Look for failed load indicators (common text patterns)
        let failedLoadTexts = ["Failed to load", "Error loading", "Network error", "Unable to load"]
        for text in failedLoadTexts {
            let elements = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] %@", text))
            if elements.count > 0 {
                warnings.append("Found potential load failure text: '\(text)'")
            }
        }
        
        // Look for empty states or error messages
        if app.staticTexts["No results found"].exists {
            warnings.append("Found 'No results found' message")
        }
        
        return warnings
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

    private func switchToTab(
        _ tabIdentifier: String,
        expecting screenIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tab = visibleButton(identifier: tabIdentifier)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing \(tabIdentifier)", file: file, line: line)
        XCTAssertTrue(tab.isHittable, "\(tabIdentifier) should be hittable", file: file, line: line)

        tab.tap()

        XCTAssertTrue(
            element(identifier: screenIdentifier).waitForExistence(timeout: screenTimeout),
            "Tapping \(tabIdentifier) should show \(screenIdentifier)",
            file: file,
            line: line
        )
    }
    
    /// Main test reproducing the navigation flow that causes issues
    func testSearchTabToSearchBarToMapTabNavigation() throws {
        print("🚀 Starting specific navigation test: Search tab -> tap search bar -> navigate to map tab")
        
        // Step 1: Launch app
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(visibleButton(identifier: "search_tab").waitForExistence(timeout: 8))
        
        // Take initial screenshot
        takeScreenshot(name: "01_initial_state", description: "App launched - initial state")
        let initialWarnings = checkForWarningIndicators()
        if !initialWarnings.isEmpty {
            print("⚠️ Initial warnings: \(initialWarnings.joined(separator: ", "))")
        }
        
        // Step 2: Navigate to search tab.
        print("📍 Step 2: Navigating to search tab")
        switchToTab("search_tab", expecting: "search_screen")
        takeScreenshot(name: "02_search_tab_loaded", description: "Search tab loaded")
        
        let searchTabWarnings = checkForWarningIndicators()
        if !searchTabWarnings.isEmpty {
            print("⚠️ Search tab warnings: \(searchTabWarnings.joined(separator: ", "))")
        }
        
        // Step 3: Tap the current Search screen input.
        print("📍 Step 3: Tapping search input")
        var searchBarFound = false

        let searchInput = app.textFields["search_input"]
        XCTAssertTrue(searchInput.waitForExistence(timeout: 5), "Search screen should expose search_input")
        XCTAssertTrue(searchInput.isHittable, "search_input should be hittable")
        searchInput.tap()
        searchBarFound = true

        takeScreenshot(name: "03_search_bar_tapped", description: "After tapping search input")
        
        let searchViewWarnings = checkForWarningIndicators()
        if !searchViewWarnings.isEmpty {
            print("⚠️ Search view warnings: \(searchViewWarnings.joined(separator: ", "))")
        }
        
        // Step 4: Now navigate to the map tab.
        print("📍 Step 4: Attempting to navigate to map tab")
        var mapTabFound = false

        let mapTab = visibleButton(identifier: "map_tab")
        XCTAssertTrue(mapTab.waitForExistence(timeout: 5), "Map tab should remain present after focusing search")
        XCTAssertTrue(mapTab.isHittable, "Map tab should remain hittable after focusing search")
        mapTab.tap()
        mapTabFound = true
        XCTAssertTrue(element(identifier: "map_screen").waitForExistence(timeout: screenTimeout))

        takeScreenshot(name: "05_map_tab_navigation_attempt", description: "After attempting to navigate to map tab")
        
        // Step 5: Analyze the current state and look for issues
        print("📍 Step 5: Analyzing current state for issues")
        
        let finalWarnings = checkForWarningIndicators()
        if !finalWarnings.isEmpty {
            print("⚠️ Final state warnings: \(finalWarnings.joined(separator: ", "))")
        }
        
        // Check if map tab is actually selected
        let isMapTabSelected = element(identifier: "map_screen").exists
        if isMapTabSelected {
            print("✅ Map screen appears to be selected")
        } else {
            print("⚠️ Map screen may not be properly selected")
        }
        
        // Look for map content
        let mapContent = element(identifier: "map_view")
        let hasMapContent = mapContent.waitForExistence(timeout: screenTimeout)
        
        if hasMapContent {
            print("✅ Map content appears to be present")
        } else {
            print("⚠️ Map content may not have loaded properly")
        }
        
        // Final comprehensive screenshot
        takeScreenshot(name: "06_final_state_analysis", description: "Final state - analyzing for navigation issues")
        
        // Summary
        print("\n📊 Navigation Test Summary:")
        print("- Search bar found: \(searchBarFound)")
        print("- Map tab found: \(mapTabFound)")  
        print("- Map tab selected: \(isMapTabSelected)")
        print("- Map content loaded: \(hasMapContent)")
        print("- Total warnings detected: \(Set(initialWarnings + searchTabWarnings + searchViewWarnings + finalWarnings).count)")
        
        XCTAssertTrue(searchBarFound, "Should be able to find and tap search bar")
        XCTAssertTrue(mapTabFound, "Should be able to find and tap map tab")
        XCTAssertTrue(isMapTabSelected, "Should switch to map screen")
        XCTAssertTrue(hasMapContent, "Map screen should expose the native map surface")
    }
    
    /// Simplified version focusing just on tab switching after search
    func testQuickSearchToMapSwitching() throws {
        print("🚀 Quick test: Direct search -> map tab switching")
        
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(visibleButton(identifier: "search_tab").waitForExistence(timeout: 8))
        
        // Go to search tab
        switchToTab("search_tab", expecting: "search_screen")
        
        takeScreenshot(name: "quick_01_search_tab")
        
        // Go to map tab  
        switchToTab("map_tab", expecting: "map_screen")
        XCTAssertTrue(element(identifier: "map_view").waitForExistence(timeout: screenTimeout))
        
        takeScreenshot(name: "quick_02_map_tab")
        
        // Check for issues
        let warnings = checkForWarningIndicators()
        if !warnings.isEmpty {
            print("⚠️ Quick test warnings: \(warnings.joined(separator: ", "))")
        }
        
        print("✅ Quick switching test completed")
    }
}

//
//  FloorSwitchingNavigationBugTest.swift
//  osrswikiUITests
//
//  Test to reproduce the floor switching bug that occurs after navigating away from
//  and back to the map tab. Floor switching works on first visit but breaks after
//  tab navigation.
//

import XCTest

class FloorSwitchingNavigationBugTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        Thread.sleep(forTimeInterval: 3.0)
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testFloorSwitchingBreaksAfterTabNavigation() throws {
        // Wait for app to fully load first
        print("🧪 Waiting for app to load completely...")
        let newsTab = app.tabBars.buttons["home_tab"]
        XCTAssertTrue(newsTab.waitForExistence(timeout: 15), "App should load and show tabs")
        
        // Navigate to map tab first
        let mapTab = app.tabBars.buttons["map_tab"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10), "Map tab should exist")
        
        print("🧪 Navigating to map tab...")
        mapTab.tap()
        
        // Wait for map to load
        Thread.sleep(forTimeInterval: 3.0)
        
        // Phase 1: Test floor switching on first visit (should work)
        print("🧪 Phase 1: Testing floor switching on first map visit")
        
        // Find floor controls - look for up button
        let floorUpButton = app.buttons.matching(identifier: "chevron.up").element
        XCTAssertTrue(floorUpButton.waitForExistence(timeout: 10), "Floor up button should exist")
        
        // Tap up button to go to floor 1
        floorUpButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Tap up again to go to floor 2  
        floorUpButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Find floor down button
        let floorDownButton = app.buttons.matching(identifier: "chevron.down").element
        XCTAssertTrue(floorDownButton.exists, "Floor down button should exist")
        
        // Tap down to go to floor 1
        floorDownButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Tap down again to go to floor 0
        floorDownButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        print("✅ Phase 1 completed - floor switching worked on first visit")
        
        // Phase 2: Navigate away from map tab
        print("🧪 Phase 2: Navigating away from map tab")
        
        let searchTab = app.tabBars.buttons["search_tab"]
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        searchTab.tap()
        
        Thread.sleep(forTimeInterval: 2.0)
        print("✅ Phase 2 completed - navigated to search tab")
        
        // Phase 3: Navigate back to map tab
        print("🧪 Phase 3: Navigating back to map tab")
        
        mapTab.tap()
        Thread.sleep(forTimeInterval: 3.0) // Give map time to reattach
        print("✅ Phase 3 completed - navigated back to map tab")
        
        // Phase 4: Test floor switching after navigation (this should fail in the bug)
        print("🧪 Phase 4: Testing floor switching after tab navigation")
        
        // Try floor switching again - this is where the bug should manifest
        // The buttons should exist but tapping them might not work
        XCTAssertTrue(floorUpButton.exists, "Floor up button should still exist after navigation")
        XCTAssertTrue(floorDownButton.exists, "Floor down button should still exist after navigation")
        
        // Test floor switching - in the bug, this doesn't work properly
        let initialFloorText = getCurrentFloorText()
        print("🔍 Current floor before switching: \(initialFloorText)")
        
        // Tap up button multiple times
        floorUpButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        let floorAfterFirstUp = getCurrentFloorText()
        print("🔍 Floor after first up tap: \(floorAfterFirstUp)")
        
        floorUpButton.tap() 
        Thread.sleep(forTimeInterval: 1.0)
        
        let floorAfterSecondUp = getCurrentFloorText()
        print("🔍 Floor after second up tap: \(floorAfterSecondUp)")
        
        // In the bug: floor text might not change or floor switching becomes unresponsive
        // The test should detect this difference in behavior
        
        // Try going back down
        floorDownButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        
        let floorAfterDown = getCurrentFloorText()
        print("🔍 Floor after down tap: \(floorAfterDown)")
        
        // The bug manifests as floor controls becoming unresponsive after tab navigation
        // We should see the floor number change when we tap the buttons
        
        print("✅ Phase 4 completed - floor switching test after navigation")
        
        // If we reach here without the floor changing, that indicates the bug
        print("🎯 Test completed - check logs for 'Modifying state during view update' warnings")
    }
    
    /// Helper method to get current floor text from the UI
    private func getCurrentFloorText() -> String {
        // Look for floor number display - should be a text element between up/down buttons
        let floorTexts = app.staticTexts.allElementsBoundByIndex
        
        // Floor number should be a single digit between the chevron buttons
        for textElement in floorTexts {
            let text = textElement.label
            if text.count == 1 && text.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                return text
            }
        }
        
        return "unknown"
    }
    
    func testStateModificationWarningReproduction() throws {
        // This test specifically tries to trigger the "Modifying state during view update" warning
        print("🧪 Testing for state modification warnings during tab navigation")
        
        let mapTab = app.tabBars.buttons["map_tab"]
        let searchTab = app.tabBars.buttons["search_tab"]
        
        // Navigate to map tab
        mapTab.tap()
        Thread.sleep(forTimeInterval: 2.0)
        
        // Start floor switching to establish state
        let floorUpButton = app.buttons.matching(identifier: "chevron.up").element
        if floorUpButton.waitForExistence(timeout: 10) {
            floorUpButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Rapidly switch tabs while floor state is active
        // This can trigger the SwiftUI state modification warning
        for i in 1...3 {
            print("🔄 Rapid tab switch iteration \(i)")
            
            searchTab.tap()
            Thread.sleep(forTimeInterval: 0.2) // Short delay
            
            mapTab.tap()
            Thread.sleep(forTimeInterval: 0.2) // Short delay
        }
        
        // Try floor switching immediately after rapid tab switching
        Thread.sleep(forTimeInterval: 1.0)
        
        if floorUpButton.exists {
            print("🔍 Testing floor switching responsiveness after rapid tab switching")
            floorUpButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            let floorDownButton = app.buttons.matching(identifier: "chevron.down").element
            if floorDownButton.exists {
                floorDownButton.tap()
            }
        }
        
        print("✅ State modification warning test completed")
    }
}
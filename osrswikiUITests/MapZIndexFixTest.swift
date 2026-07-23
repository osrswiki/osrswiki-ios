//
//  MapZIndexFixTest.swift
//  osrswikiUITests
//
//  Test to verify that MapLibre widgets no longer draw over the top bar
//

import XCTest

final class MapZIndexFixTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully load
        Thread.sleep(forTimeInterval: 2.0)
    }
    
    func testMapHeaderVisible() throws {
        print("🔍 Testing Map Header Visibility - Z-Index Fix Verification")
        
        // Navigate to Map tab
        let mapTab = app.tabBars.buttons["Map"]
        if !mapTab.exists {
            // Try alternative identifiers
            let mapTabAlt = app.tabBars.buttons["map_tab"] 
            XCTAssertTrue(mapTabAlt.exists, "Map tab should exist")
            mapTabAlt.tap()
        } else {
            mapTab.tap()
        }
        
        // Wait for map view to load
        Thread.sleep(forTimeInterval: 3.0)
        
        // Check that "Map" header text exists and is visible
        let mapHeader = app.staticTexts["Map"]
        XCTAssertTrue(mapHeader.exists, "Map header should exist")
        XCTAssertTrue(mapHeader.isHittable, "Map header should be visible and not covered by map content")
        
        print("✅ Map header is visible and accessible")
        
        // Verify header is in the expected location (top of screen)
        let headerFrame = mapHeader.frame
        print("📍 Map header frame: \(headerFrame)")
        
        // Header should be near the top of the screen
        XCTAssertLessThan(headerFrame.origin.y, 150, "Map header should be near the top of the screen")
        
        // Take screenshot for visual verification
        takeScreenshot(name: "map_header_visible", description: "Map header visible above MapLibre content")
        
        print("🎉 Map Z-Index fix verification complete")
    }
    
    func testMapContentDoesNotCoverHeader() throws {
        print("🔍 Testing Map Content Positioning - Header Not Covered")
        
        // Navigate to Map tab
        let mapTab = app.tabBars.buttons["Map"]
        if !mapTab.exists {
            let mapTabAlt = app.tabBars.buttons["map_tab"]
            XCTAssertTrue(mapTabAlt.exists, "Map tab should exist")
            mapTabAlt.tap()
        } else {
            mapTab.tap()
        }
        
        // Wait for map to load
        Thread.sleep(forTimeInterval: 3.0)
        
        // Verify both header and map content are visible
        let mapHeader = app.staticTexts["Map"]
        XCTAssertTrue(mapHeader.exists, "Map header should exist")
        XCTAssertTrue(mapHeader.isHittable, "Map header should be accessible (not covered)")
        
        // Look for map-related elements that should be below the header
        let mapControls = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS[cd] 'floor' OR label CONTAINS[cd] 'zoom'"))
        
        if mapControls.count > 0 {
            let headerBottom = mapHeader.frame.origin.y + mapHeader.frame.size.height
            
            // Map controls should be below the header
            for control in mapControls.allElementsBoundByIndex {
                if control.exists && control.frame.size.height > 0 {
                    XCTAssertGreaterThan(control.frame.origin.y, headerBottom, 
                                      "Map control should be positioned below the header")
                }
            }
        }
        
        print("✅ Map content properly positioned below header")
    }
    
    private func takeScreenshot(name: String, description: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Screenshot saved: \(name) - \(description)")
    }
}
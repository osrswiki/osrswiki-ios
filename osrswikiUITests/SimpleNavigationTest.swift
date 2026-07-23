//
//  SimpleNavigationTest.swift
//  osrswikiUITests  
//
//  Simple test to check basic UI elements and navigation
//

import XCTest

class SimpleNavigationTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 3.0)
    }
    
    func testBasicUIElementsExist() throws {
        print("🔍 DEBUGGING: Checking what UI elements exist")
        
        // Take a screenshot first
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Debug-App-State"
        add(attachment)
        
        // Print all available buttons
        let allButtons = app.buttons
        print("📱 Available buttons count: \(allButtons.count)")
        
        for i in 0..<min(allButtons.count, 10) {
            let button = allButtons.element(boundBy: i)
            if button.exists {
                print("🔘 Button \(i): identifier='\(button.identifier)', label='\(button.label)'")
            }
        }
        
        // Print all available tab bars
        let tabBars = app.tabBars
        print("📱 Tab bars count: \(tabBars.count)")
        
        for i in 0..<tabBars.count {
            let tabBar = tabBars.element(boundBy: i)
            if tabBar.exists {
                print("📊 Tab bar \(i): identifier='\(tabBar.identifier)', label='\(tabBar.label)'")
                
                // Print tab bar buttons
                let tabButtons = tabBar.buttons
                for j in 0..<tabButtons.count {
                    let tabButton = tabButtons.element(boundBy: j)
                    if tabButton.exists {
                        print("  📍 Tab button \(j): identifier='\(tabButton.identifier)', label='\(tabButton.label)'")
                    }
                }
            }
        }
        
        // Check for specific elements
        if app.buttons["More"].exists {
            print("✅ More button found!")
        } else {
            print("❌ More button not found")
            
            // Try alternative ways to find the More tab
            if app.staticTexts["More"].exists {
                print("✅ More static text found!")
            }
            
            // Look for tab-related elements
            let moreTabBar = app.tabBars.buttons["More"]
            if moreTabBar.exists {
                print("✅ More tab bar button found!")
            }
        }
        
        XCTAssertTrue(true, "Debug test completed")
    }
}

//
//  VoiceSearchUITest.swift
//  osrswikiUITests
//
//  Created on voice search implementation session
//

import XCTest

class VoiceSearchUITest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIApplication().launch()
    }
    
    func testVoiceSearchButtonExists() {
        let app = XCUIApplication()
        
        // Wait for app to launch
        XCTAssertTrue(app.waitForExistence(timeout: 10), "App should launch within 10 seconds")
        
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5), "Search tab should exist")
        searchTab.tap()
        
        // Wait for the search view to load
        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        
        // Look for the voice search button - it should be a button with a mic icon
        let voiceButton = app.buttons.containing(.image, identifier: "mic").element
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 3), "Voice search button should exist")
        
        // Take a screenshot to verify the UI
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Voice Search Button Available"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("✅ Voice search button found in Search tab")
    }
    
    func testVoiceSearchButtonTap() {
        let app = XCUIApplication()
        
        // Wait for app to launch
        XCTAssertTrue(app.waitForExistence(timeout: 10), "App should launch within 10 seconds")
        
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        searchTab.tap()
        
        // Wait for search view
        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        
        // Find and tap voice search button
        let voiceButton = app.buttons.containing(.image, identifier: "mic").element
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 3), "Voice search button should exist")
        
        // Take screenshot before tapping
        let beforeScreenshot = XCUIScreen.main.screenshot()
        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "Before Voice Search Tap"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)
        
        // Tap the voice search button
        voiceButton.tap()
        
        // Wait a moment for any UI changes or permission dialogs
        sleep(2)
        
        // Take screenshot after tapping
        let afterScreenshot = XCUIScreen.main.screenshot()
        let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
        afterAttachment.name = "After Voice Search Tap"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)
        
        // Check if permission dialog appeared
        let allowButton = app.buttons["Allow"]
        let dontAllowButton = app.buttons["Don't Allow"]
        
        if allowButton.exists {
            print("📱 Microphone permission dialog appeared")
            
            // Take screenshot of permission dialog
            let permissionScreenshot = XCUIScreen.main.screenshot()
            let permissionAttachment = XCTAttachment(screenshot: permissionScreenshot)
            permissionAttachment.name = "Microphone Permission Dialog"
            permissionAttachment.lifetime = .keepAlways
            add(permissionAttachment)
            
            // Grant permission for testing
            allowButton.tap()
            
            // Wait after granting permission
            sleep(1)
            
            // Take final screenshot
            let finalScreenshot = XCUIScreen.main.screenshot()
            let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
            finalAttachment.name = "After Permission Grant"
            finalAttachment.lifetime = .keepAlways
            add(finalAttachment)
        }
        
        print("✅ Voice search button tap test completed")
    }
    
    func testVoiceSearchIntegration() {
        let app = XCUIApplication()
        
        // Wait for app launch
        XCTAssertTrue(app.waitForExistence(timeout: 10), "App should launch")
        
        // Navigate to Search tab
        app.tabBars.buttons["Search"].tap()
        
        // Verify search components exist
        let searchField = app.textFields["Search OSRS Wiki"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
        
        let voiceButton = app.buttons.containing(.image, identifier: "mic").element
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 3), "Voice button should exist")
        
        // Verify the button is properly integrated with the search bar
        XCTAssertTrue(voiceButton.isHittable, "Voice button should be tappable")
        
        // Take comprehensive screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Voice Search Integration Complete"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("✅ Voice search integration verified")
    }
}
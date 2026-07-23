//
//  FontVerificationTest.swift
//  osrswikiUITests
//
//  Created for font verification testing
//

import XCTest

final class FontVerificationTest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFontFixesOnHomePage() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to fully load
        sleep(3)
        
        // Take a screenshot of the home page to verify fonts
        let homeScreenshot = XCTAttachment(screenshot: app.screenshot())
        homeScreenshot.name = "Home Page with Font Fixes"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)
        
        // Wait for content to load
        sleep(2)
        
        // Take another screenshot after content loads
        let contentScreenshot = XCTAttachment(screenshot: app.screenshot())
        contentScreenshot.name = "Home Page Content Loaded"
        contentScreenshot.lifetime = .keepAlways
        add(contentScreenshot)
        
        print("✅ Font verification test completed successfully")
    }
}
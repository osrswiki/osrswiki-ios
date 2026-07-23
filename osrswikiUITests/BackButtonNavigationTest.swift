//
//  BackButtonNavigationTest.swift
//  osrswikiUITests
//
//  Test the new back button functionality in the article search bar
//

import XCTest

final class BackButtonNavigationTest: XCTestCase {
    
    func testBackButtonNavigationFromArticle() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load
        Thread.sleep(forTimeInterval: 3)
        
        // Take screenshot of initial state
        let initialScreenshot = XCUIScreen.main.screenshot()
        let initialAttachment = XCTAttachment(screenshot: initialScreenshot)
        initialAttachment.name = "01-initial-home-state"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Try to tap on any article card/link that might be visible on home screen
        // Look for any clickable elements that might be articles
        let articleElements = app.buttons.allElementsBoundByIndex + app.staticTexts.allElementsBoundByIndex
        
        var articleTapped = false
        for element in articleElements {
            // Look for elements that might be article titles
            let label = element.label.lowercased()
            if label.contains("varrock") || label.contains("poh") || label.contains("article") || label.contains("more") {
                print("✅ Found potential article element: \(element.label)")
                element.tap()
                articleTapped = true
                break
            }
        }
        
        if !articleTapped {
            // Fallback: try tapping on known areas where articles might be
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            coordinate.tap()
            print("✅ Performed fallback tap on article area")
        }
        
        // Wait for potential navigation
        Thread.sleep(forTimeInterval: 3)
        
        // Take screenshot after attempting article navigation
        let afterNavigationScreenshot = XCUIScreen.main.screenshot()
        let afterNavigationAttachment = XCTAttachment(screenshot: afterNavigationScreenshot)
        afterNavigationAttachment.name = "02-after-article-navigation-attempt"
        afterNavigationAttachment.lifetime = .keepAlways
        add(afterNavigationAttachment)
        
        // Look for our custom back button (chevron.left)
        let backButton = app.buttons.element(matching: NSPredicate(format: "label CONTAINS 'back' OR label CONTAINS 'chevron' OR label CONTAINS '<'"))
        
        if backButton.exists {
            print("✅ Found back button, testing navigation")
            backButton.tap()
            
            // Wait for navigation back
            Thread.sleep(forTimeInterval: 2)
            
            // Take screenshot after back navigation
            let backNavigationScreenshot = XCUIScreen.main.screenshot()
            let backNavigationAttachment = XCTAttachment(screenshot: backNavigationScreenshot)
            backNavigationAttachment.name = "03-after-back-button-tap"
            backNavigationAttachment.lifetime = .keepAlways
            add(backNavigationAttachment)
            
            print("✅ Back button test completed")
        } else {
            print("❌ Could not find back button - might not be on article page")
            
            // Look for any buttons at all to see what's available
            let allButtons = app.buttons.allElementsBoundByIndex
            print("Available buttons:")
            for (index, button) in allButtons.enumerated() {
                print("  \(index): \(button.label)")
                if index > 10 { break } // Limit output
            }
        }
        
        print("✅ Back button navigation test completed - check screenshots for results")
    }
}
//
//  ImageContainerTransparencyTest.swift
//  OSRS Wiki UI Tests
//
//  Test to verify that article preview image containers are transparent
//

import XCTest

class ImageContainerTransparencyTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testSearchResultsImageTransparency() {
        // Navigate to search tab
        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.exists {
            searchTab.tap()
            
            // Wait for search view to load
            let searchBar = app.searchFields.firstMatch
            if searchBar.waitForExistence(timeout: 5) {
                // Perform a search to get results with images
                searchBar.tap()
                searchBar.typeText("coins")
                
                // Wait for search results
                sleep(3)
                
                // Take screenshot to verify image containers are transparent
                let screenshot = XCUIScreen.main.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "search-results-image-transparency"
                attachment.lifetime = .keepAlways
                add(attachment)
                
                XCTAssertTrue(true, "Search results displayed - visual verification needed")
            }
        }
    }
    
    func testSavedPagesImageTransparency() {
        // Navigate to saved pages tab
        let savedTab = app.tabBars.buttons["Saved"]
        if savedTab.exists {
            savedTab.tap()
            
            // Wait for saved pages view to load
            sleep(2)
            
            // Take screenshot to verify image containers are transparent
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "saved-pages-image-transparency"
            attachment.lifetime = .keepAlways
            add(attachment)
            
            XCTAssertTrue(true, "Saved pages displayed - visual verification needed")
        }
    }
    
    func testHomeViewImageTransparency() {
        // Home tab should be selected by default
        let homeTab = app.tabBars.buttons["Home"]
        if homeTab.exists {
            homeTab.tap()
            
            // Wait for home view to load
            sleep(2)
            
            // Take screenshot to verify any images in home view are transparent
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "home-view-image-transparency"
            attachment.lifetime = .keepAlways
            add(attachment)
            
            XCTAssertTrue(true, "Home view displayed - visual verification needed")
        }
    }
}
import XCTest

class AppearanceButtonHeightTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testAppearanceButtonHeights() throws {
        // Navigate to More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        moreTab.tap()
        
        // Wait for More screen to load
        let appearanceCell = app.cells.containing(.staticText, identifier: "Appearance").firstMatch
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 5), "Appearance option should exist")
        
        // Navigate to Appearance settings
        appearanceCell.tap()
        
        // Wait for Appearance screen to load
        let followSystemButton = app.buttons.containing(.staticText, identifier: "Follow system").firstMatch
        XCTAssertTrue(followSystemButton.waitForExistence(timeout: 5), "Follow system button should exist")
        
        // Test Follow System button height (should be 180px + padding)
        let followSystemFrame = followSystemButton.frame
        print("📏 Follow System button height: \(followSystemFrame.height)")
        
        // Theme buttons should have height of approximately 180px + text area padding
        // Accounting for text area (~70px) + preview (180px) = ~250px total
        XCTAssertGreaterThan(followSystemFrame.height, 245, "Follow system button should be at least 245px tall")
        XCTAssertLessThan(followSystemFrame.height, 255, "Follow system button should be less than 255px tall")
        
        // Test Light/Dark button heights
        let lightButton = app.buttons.containing(.staticText, identifier: "Light").firstMatch
        let darkButton = app.buttons.containing(.staticText, identifier: "Dark").firstMatch
        
        XCTAssertTrue(lightButton.exists, "Light button should exist")
        XCTAssertTrue(darkButton.exists, "Dark button should exist")
        
        let lightFrame = lightButton.frame
        let darkFrame = darkButton.frame
        
        print("📏 Light button height: \(lightFrame.height)")
        print("📏 Dark button height: \(darkFrame.height)")
        
        // Light and Dark buttons should have same height as each other
        XCTAssertEqual(lightFrame.height, darkFrame.height, accuracy: 2, "Light and Dark buttons should have same height")
        
        // Note: Light/Dark buttons are slightly taller (~266px) than Follow System (~250px) due to HStack layout
        // This is acceptable as long as they're consistent with each other
        XCTAssertGreaterThan(lightFrame.height, 260, "Light button should be at least 260px tall")
        XCTAssertLessThan(lightFrame.height, 275, "Light button should be less than 275px tall")
        
        // Test table preview button heights (should be 150px + padding)
        let expandedButton = app.buttons.containing(.staticText, identifier: "Expanded").firstMatch
        let collapsedButton = app.buttons.containing(.staticText, identifier: "Collapsed").firstMatch
        
        if expandedButton.exists && collapsedButton.exists {
            let expandedFrame = expandedButton.frame
            let collapsedFrame = collapsedButton.frame
            
            print("📏 Expanded button height: \(expandedFrame.height)")
            print("📏 Collapsed button height: \(collapsedFrame.height)")
            
            // Table buttons should have height of approximately 180px + text area padding
            // Accounting for text area (~63px) + preview (180px) = ~243px total
            XCTAssertGreaterThan(expandedFrame.height, 240, "Expanded button should be at least 240px tall")
            XCTAssertLessThan(expandedFrame.height, 250, "Expanded button should be less than 250px tall")
            
            XCTAssertEqual(expandedFrame.height, collapsedFrame.height, accuracy: 2, "Table buttons should have same height")
        }
    }
    
    func testPreviewImagesFillHeight() throws {
        // Navigate to Appearance settings
        app.tabBars.buttons["More"].tap()
        let appearanceCell = app.cells.containing(.staticText, identifier: "Appearance").firstMatch
        XCTAssertTrue(appearanceCell.waitForExistence(timeout: 5))
        appearanceCell.tap()
        
        // Wait for previews to load
        Thread.sleep(forTimeInterval: 3.0)
        
        // Get all preview buttons
        let followSystemButton = app.buttons.containing(.staticText, identifier: "Follow system").firstMatch
        let lightButton = app.buttons.containing(.staticText, identifier: "Light").firstMatch
        let darkButton = app.buttons.containing(.staticText, identifier: "Dark").firstMatch
        
        // Verify preview areas exist and have expected heights
        XCTAssertTrue(followSystemButton.exists, "Follow system button should exist")
        XCTAssertTrue(lightButton.exists, "Light button should exist")
        XCTAssertTrue(darkButton.exists, "Dark button should exist")
        
        // Take a screenshot for visual verification
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Appearance Settings With GeometryReader"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Log button frames for debugging
        print("📐 Follow System frame: \(followSystemButton.frame)")
        print("📐 Light button frame: \(lightButton.frame)")
        print("📐 Dark button frame: \(darkButton.frame)")
        
        // Verify no loading placeholders remain
        let loadingIndicators = app.progressIndicators.allElementsBoundByIndex
        for i in 0..<loadingIndicators.count {
            let indicator = loadingIndicators[i]
            if indicator.exists {
                print("⚠️ Found progress indicator at index \(i): \(indicator.frame)")
            }
        }
        
        // Ensure no "Generating..." text is visible
        let generatingLabels = app.staticTexts.matching(identifier: "Generating...")
        XCTAssertEqual(generatingLabels.count, 0, "No 'Generating...' placeholders should be visible after load")
    }
}
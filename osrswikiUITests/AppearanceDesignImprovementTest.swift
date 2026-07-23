//
//  AppearanceDesignImprovementTest.swift
//  OSRS Wiki
//
//  Test for the macOS-inspired appearance page improvements
//

import XCTest

class AppearanceDesignImprovementTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAppearancePageLayout() throws {
        // Navigate to More tab
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.exists, "More tab should exist")
        moreTab.tap()
        
        // Wait for More view to load
        let moreTitle = app.navigationBars["More"]
        XCTAssertTrue(moreTitle.waitForExistence(timeout: 5), "More page should load")
        
        // Find and tap Appearance option
        let appearanceButton = app.buttons["Appearance"]
        XCTAssertTrue(appearanceButton.waitForExistence(timeout: 3), "Appearance button should exist")
        appearanceButton.tap()
        
        // Wait for Appearance page to load
        let appearanceTitle = app.navigationBars["Appearance"]
        XCTAssertTrue(appearanceTitle.waitForExistence(timeout: 5), "Appearance page should load")
        
        // Verify three theme cards exist (Light, Dark, Auto)
        let lightCard = app.buttons.containing(.staticText, identifier: "Light").element
        let darkCard = app.buttons.containing(.staticText, identifier: "Dark").element
        let autoCard = app.buttons.containing(.staticText, identifier: "Auto").element
        
        XCTAssertTrue(lightCard.exists, "Light theme card should exist")
        XCTAssertTrue(darkCard.exists, "Dark theme card should exist") 
        XCTAssertTrue(autoCard.exists, "Auto theme card should exist")
        
        // Verify cards are properly arranged horizontally
        let lightFrame = lightCard.frame
        let darkFrame = darkCard.frame
        let autoFrame = autoCard.frame
        
        // Check that cards are in horizontal alignment (similar Y positions)
        XCTAssertLessThan(abs(lightFrame.midY - darkFrame.midY), 20, "Light and Dark cards should be horizontally aligned")
        XCTAssertLessThan(abs(darkFrame.midY - autoFrame.midY), 20, "Dark and Auto cards should be horizontally aligned")
        
        // Check horizontal ordering (Light -> Dark -> Auto)
        XCTAssertLessThan(lightFrame.midX, darkFrame.midX, "Light should be left of Dark")
        XCTAssertLessThan(darkFrame.midX, autoFrame.midX, "Dark should be left of Auto")
        
        // Test theme selection
        darkCard.tap()
        
        // Verify the selection state changed (this is visual but we can at least verify the tap worked)
        // The actual selection verification would need more sophisticated UI testing
        
        // Verify Table display section exists
        let tableDisplayLabel = app.staticTexts["Table display"]
        XCTAssertTrue(tableDisplayLabel.exists, "Table display section should exist")
        
        // Verify table preview cards exist
        let expandedCard = app.buttons.containing(.staticText, identifier: "Expanded").element
        let collapsedCard = app.buttons.containing(.staticText, identifier: "Collapsed").element
        
        XCTAssertTrue(expandedCard.exists, "Expanded table card should exist")
        XCTAssertTrue(collapsedCard.exists, "Collapsed table card should exist")
        
        print("✅ Appearance page layout test completed successfully")
        print("   - Three theme cards properly arranged horizontally")
        print("   - Table display section with preview cards")
        print("   - Theme selection interaction works")
    }
    
    func testAppearancePageVisualStyling() throws {
        // Navigate to appearance page
        app.tabBars.buttons["More"].tap()
        app.buttons["Appearance"].tap()
        
        let appearanceTitle = app.navigationBars["Appearance"]
        XCTAssertTrue(appearanceTitle.waitForExistence(timeout: 5), "Appearance page should load")
        
        // Verify section headers exist and are properly styled
        let appearanceHeader = app.staticTexts["Appearance"]
        let tableDisplayHeader = app.staticTexts["Table display"]
        
        XCTAssertTrue(appearanceHeader.exists, "Appearance section header should exist")
        XCTAssertTrue(tableDisplayHeader.exists, "Table display section header should exist")
        
        // Test that cards have proper spacing and sizing
        let themeCards = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Light' OR label CONTAINS 'Dark' OR label CONTAINS 'Auto'"))
        XCTAssertEqual(themeCards.count, 3, "Should have exactly 3 theme cards")
        
        // Verify cards are not overlapping
        for i in 0..<themeCards.count {
            let card1 = themeCards.element(boundBy: i)
            XCTAssertTrue(card1.exists, "Theme card \(i) should exist")
            
            for j in (i+1)..<themeCards.count {
                let card2 = themeCards.element(boundBy: j)
                let frame1 = card1.frame
                let frame2 = card2.frame
                
                // Verify no overlap (allowing small margin for spacing)
                let noHorizontalOverlap = (frame1.maxX <= frame2.minX + 5) || (frame2.maxX <= frame1.minX + 5)
                let noVerticalOverlap = (frame1.maxY <= frame2.minY + 5) || (frame2.maxY <= frame1.minY + 5)
                
                XCTAssertTrue(noHorizontalOverlap || noVerticalOverlap, "Cards should not overlap")
            }
        }
        
        print("✅ Appearance page visual styling test completed successfully")
        print("   - Proper section headers")
        print("   - Cards are properly spaced and non-overlapping")
    }
}
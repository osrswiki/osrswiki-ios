import XCTest

class TOCSidebarUITest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testTOCSidebarAppearance() {
        // Navigate to search tab
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.exists)
        searchTab.tap()
        
        // Search for "Logs" article
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Logs")
        
        // Tap on first search result
        let firstResult = app.tables.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))
        firstResult.tap()
        
        // Wait for article to load
        sleep(3)
        
        // Tap Contents button in bottom bar
        let contentsButton = app.buttons["Contents"].firstMatch
        XCTAssertTrue(contentsButton.waitForExistence(timeout: 5))
        contentsButton.tap()
        
        // Verify TOC sidebar appears
        let tocSidebar = app.otherElements["contents_drawer"]
        XCTAssertTrue(tocSidebar.waitForExistence(timeout: 3))
        
        // Verify sidebar extends full height (check if it has proper frame)
        let sidebarFrame = tocSidebar.frame
        let screenHeight = app.frame.height
        
        // Sidebar should float as a glass panel, not a full-height opaque slab.
        XCTAssertLessThan(
            sidebarFrame.height,
            screenHeight * 0.9,
            "TOC sidebar should not span the full screen height. Current height: \(sidebarFrame.height), Screen height: \(screenHeight)"
        )
        XCTAssertGreaterThan(
            sidebarFrame.minX,
            8,
            "TOC sidebar should sit inset from the trailing edge, not flush to the screen."
        )
        
        // Verify no shadow artifacts are visible (shadow was removed)
        // This is validated visually but we can check the sidebar renders correctly
        XCTAssertTrue(tocSidebar.isHittable)
        
        // Tap outside to close sidebar
        let backgroundOverlay = app.otherElements.matching(identifier: "BackgroundOverlay").firstMatch
        if backgroundOverlay.exists {
            backgroundOverlay.tap()
        } else {
            // Tap on the article content area to dismiss
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        }
        
        // Verify sidebar closes
        XCTAssertFalse(tocSidebar.waitForExistence(timeout: 1))
    }
    
    func testTOCSidebarNavigation() {
        // Navigate to search tab
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.exists)
        searchTab.tap()
        
        // Search for "Logs" article
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Logs")
        
        // Tap on first search result
        let firstResult = app.tables.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))
        firstResult.tap()
        
        // Wait for article to load
        sleep(3)
        
        // Open TOC sidebar
        let contentsButton = app.buttons["Contents"].firstMatch
        XCTAssertTrue(contentsButton.waitForExistence(timeout: 5))
        contentsButton.tap()
        
        // Check that TOC items are visible
        let tocItems = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Contents' OR label CONTAINS 'Skill info' OR label CONTAINS 'Uses'"))
        XCTAssertTrue(tocItems.count > 0, "TOC should contain navigation items")
        
        // Tap on a TOC item to navigate
        if tocItems.count > 1 {
            tocItems.element(boundBy: 1).tap()
            
            // Verify sidebar closes after selection
            let tocSidebar = app.otherElements["Contents"]
            XCTAssertFalse(tocSidebar.waitForExistence(timeout: 1))
        }
    }
}
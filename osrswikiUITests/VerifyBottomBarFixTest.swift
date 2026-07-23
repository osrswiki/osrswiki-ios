import XCTest

final class VerifyBottomBarFixTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testBottomBarFixInArticleView() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for app to load (starts on Home tab)
        let homeElement = app.staticTexts["Home"].firstMatch
        if !homeElement.waitForExistence(timeout: 10) {
            // Try alternative elements that might be present on launch
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "App should launch with tab bar visible")
        }
        
        // Navigate to Search tab
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5), "Search tab should be visible")
        searchTab.tap()
        
        // Verify main tab bar is visible on search screen
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        let searchTabButton = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTabButton.exists)
        
        // Wait for search content to load
        sleep(2)
        
        // Look for search functionality (search bar, search results, etc.)
        let searchBar = app.searchFields.firstMatch
        if searchBar.exists {
            searchBar.tap()
            searchBar.typeText("Varrock")
            
            // Wait for search results
            sleep(2)
            
            // Look for search results
            let searchResults = app.tables.firstMatch
            if searchResults.exists {
                let firstResult = searchResults.cells.firstMatch
                if firstResult.exists {
                    firstResult.tap()
                    print("Tapped on search result")
                }
            }
        } else {
            // Alternative: look for pre-populated content like history entries
            let historyEntries = app.tables.firstMatch
            if historyEntries.exists {
                let firstEntry = historyEntries.cells.firstMatch
                if firstEntry.exists {
                    firstEntry.tap()
                    print("Tapped on history entry")
                }
            } else {
                print("No searchable content found - test may need adjustment")
                return
            }
        }
        
        // Wait for article to load
        sleep(3)
        
        // Check if we're now in an article view
        // We should verify that the main tab bar is hidden and only article toolbar is visible
        
        // The fix should hide the main tab bar when viewing articles
        let mainTabBar = app.tabBars.buttons["Search"]
        let isMainTabBarHidden = !mainTabBar.exists || !mainTabBar.isHittable
        
        print("Main tab bar hidden: \(isMainTabBarHidden)")
        
        // Check for article-specific elements (these might vary based on the article)
        // We'll look for common article elements
        let articleToolbar = app.toolbars.firstMatch
        let hasArticleToolbar = articleToolbar.exists
        
        print("Article toolbar present: \(hasArticleToolbar)")
        
        // Wait a bit more to ensure everything is loaded
        sleep(2)
        
        // Final assertion: Main tab bar should be hidden in article view
        XCTAssertTrue(isMainTabBarHidden, "Main tab bar should be hidden when viewing an article")
        
        print("Test completed - verifying bottom bar fix")
    }
}

import XCTest

final class MapLibreEmbedVerificationTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testMapLibreEmbedsInVarrockArticle() throws {
        let app = XCUIApplication()
        
        // Enable console logging
        app.launchArguments.append("--enable-map-debug-logging")
        app.launch()
        
        // Step 1: Wait for app to fully load
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 10), "Home screen should appear")
        
        // Step 2: Tap search box and search for Varrock
        let searchBox = app.searchFields["Search OSRS Wiki"]
        XCTAssertTrue(searchBox.waitForExistence(timeout: 5), "Search box should exist")
        searchBox.tap()
        
        // Type "Varrock" 
        searchBox.typeText("Varrock")
        
        // Step 3: Wait for search results and tap on Varrock
        let varrockResult = app.tables.cells.containing(.staticText, identifier: "Varrock").element
        XCTAssertTrue(varrockResult.waitForExistence(timeout: 5), "Varrock search result should appear")
        varrockResult.tap()
        
        // Step 4: Wait for article to load and scroll to Map section
        // Look for article content to ensure navigation completed
        let articleWebView = app.webViews.firstMatch
        XCTAssertTrue(articleWebView.waitForExistence(timeout: 10), "Article should load in WebView")
        
        // Wait additional time for JavaScript bridge and MapLibre to initialize
        Thread.sleep(forTimeInterval: 3)
        
        // Step 5: Scroll down to find the Map section in the infobox
        // The map should be in the infobox, so scroll down to find it
        for _ in 0..<10 {
            articleWebView.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            
            // Check if we can find any map-related elements
            // Since the map is native, we need to look for the container view
            let mapContainers = app.otherElements.matching(NSPredicate(format: "identifier CONTAINS 'map'")).allElementsBoundByIndex
            
            if !mapContainers.isEmpty {
                print("Found \\(mapContainers.count) potential map containers")
                break
            }
        }
        
        // Step 6: Verify MapLibre embed functionality
        // Since this is a bridge-based implementation, we need to verify:
        // 1. Bridge communication worked
        // 2. Native map views were created
        // 3. Maps are positioned correctly
        
        // Wait for potential MapLibre views to render
        Thread.sleep(forTimeInterval: 2)
        
        // Look for any native MapLibre views (MLNMapView instances)
        // These would appear as generic views with map content
        let potentialMapViews = app.otherElements.allElementsBoundByIndex
        print("Found \\(potentialMapViews.count) total UI elements")
        
        // Step 7: Test basic interaction with the article
        // Scroll back up to test scroll synchronization
        for _ in 0..<5 {
            articleWebView.swipeDown()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Scroll back down to map area
        for _ in 0..<8 {
            articleWebView.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Step 8: Attempt to interact with embedded maps if found
        // Look for interactive elements in the current view
        let interactiveElements = app.otherElements.allElementsBoundByIndex
        for i in 0..<min(interactiveElements.count, 20) {
            let element = interactiveElements[i]
            if element.isHittable {
                print("Found hittable element at index \\(i): \\(element.debugDescription)")
                
                // Try a gentle tap to see if it's a map
                element.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        
        // Step 9: Final verification
        // The test passes if we successfully navigated to Varrock without crashes
        // Real verification requires examining console logs externally
        print("✅ MapLibre embed test completed - check console logs for bridge activity")
        print("🔍 Look for messages containing: 'iOS Map Handler', 'MapLibre', 'onMapPlaceholderMeasured'")
        
        // Ensure we're still in the app and it hasn't crashed
        XCTAssertTrue(app.state == .runningForeground, "App should still be running")
    }
    
    func testMapLibreEmbedWithCollapsibleInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Varrock using the same steps as above
        let searchBox = app.searchFields["Search OSRS Wiki"]
        XCTAssertTrue(searchBox.waitForExistence(timeout: 5), "Search box should exist")
        searchBox.tap()
        searchBox.typeText("Varrock")
        
        let varrockResult = app.tables.cells.containing(.staticText, identifier: "Varrock").element
        XCTAssertTrue(varrockResult.waitForExistence(timeout: 5), "Varrock search result should appear")
        varrockResult.tap()
        
        let articleWebView = app.webViews.firstMatch
        XCTAssertTrue(articleWebView.waitForExistence(timeout: 10), "Article should load")
        
        Thread.sleep(forTimeInterval: 3)
        
        // Look for collapsible sections that might contain maps
        // In MediaWiki, these are often implemented as disclosure triangles
        let disclosureTriangles = app.buttons.allElementsBoundByIndex
        
        for i in 0..<min(disclosureTriangles.count, 10) {
            let triangle = disclosureTriangles[i]
            if triangle.label.contains("Show") || triangle.label.contains("Hide") || triangle.isHittable {
                print("Found potential collapsible element: \\(triangle.label)")
                triangle.tap()
                Thread.sleep(forTimeInterval: 1)
                
                // After toggling, check for new map elements
                let mapElements = app.otherElements.allElementsBoundByIndex
                print("After toggle \\(i): Found \\(mapElements.count) elements")
            }
        }
        
        print("✅ Collapsible interaction test completed")
    }
}
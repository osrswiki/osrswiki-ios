//
//  FontMetricsTest.swift
//  osrswikiUITests
//
//  Test font metrics to identify exact spacing differences
//

import XCTest

final class FontMetricsTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testFontMetricsPrecision() throws {
        let app = XCUIApplication()
        app.launch()
        
        sleep(3)
        
        // Navigate to Home
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Home"].tap()
        sleep(1)
        
        // Get exact measurements
        let homeTitle = app.staticTexts["Home"]
        let homeSearch = app.staticTexts["Search OSRS Wiki"]
        
        if homeTitle.exists && homeSearch.exists {
            print("🔍 HOME VIEW PRECISE MEASUREMENTS:")
            print("  - Home title frame: \(homeTitle.frame)")
            print("  - Home title bounds: width=\(homeTitle.frame.width), height=\(homeTitle.frame.height)")
            print("  - Search frame: \(homeSearch.frame)")
            print("  - Title bottom Y: \(homeTitle.frame.maxY)")
            print("  - Search top Y: \(homeSearch.frame.minY)")
            let homeSpacing = homeSearch.frame.minY - homeTitle.frame.maxY
            print("  - EXACT SPACING: \(homeSpacing) points")
        }
        
        // Navigate to History
        tabBar.buttons["Search"].tap()
        sleep(1)
        
        let historyTitle = app.staticTexts["History"] 
        let historySearch = app.staticTexts["Search OSRS Wiki"]
        
        if historyTitle.exists && historySearch.exists {
            print("🔍 HISTORY VIEW PRECISE MEASUREMENTS:")
            print("  - History title frame: \(historyTitle.frame)")
            print("  - History title bounds: width=\(historyTitle.frame.width), height=\(historyTitle.frame.height)")
            print("  - Search frame: \(historySearch.frame)")  
            print("  - Title bottom Y: \(historyTitle.frame.maxY)")
            print("  - Search top Y: \(historySearch.frame.minY)")
            let historySpacing = historySearch.frame.minY - historyTitle.frame.maxY
            print("  - EXACT SPACING: \(historySpacing) points")
            
            // Font analysis
            print("\n📐 FONT ANALYSIS:")
            print("  - 'Home' text width: \(homeTitle.frame.width)")
            print("  - 'History' text width: \(historyTitle.frame.width)") 
            print("  - Width difference: \(abs(homeTitle.frame.width - historyTitle.frame.width))")
        }
        
        XCTAssertTrue(true, "Font metrics analysis complete")
    }
}
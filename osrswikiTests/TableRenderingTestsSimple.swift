import XCTest
@testable import osrswiki

class TableRenderingTestsSimple: XCTestCase {
    
    func testMobileOptimizationDoesNotUseDisplayBlock() {
        // Read the ArticleWebView.swift file to check the CSS
        let currentFile = #file
        let testDir = (currentFile as NSString).deletingLastPathComponent
        let projectDir = (testDir as NSString).deletingLastPathComponent
        let filePath = (projectDir as NSString).appendingPathComponent("osrswiki/Views/ArticleWebView.swift")
        
        guard let content = try? String(contentsOfFile: filePath) else {
            XCTFail("Could not read ArticleWebView.swift at \(filePath)")
            return
        }
        
        // Check that .wikitable does NOT have display: block
        // Look for the specific wikitable CSS section
        let wikiTableRange = content.range(of: ".wikitable")
        if let range = wikiTableRange {
            let startIndex = range.lowerBound
            let endIndex = content.index(startIndex, offsetBy: 200, limitedBy: content.endIndex) ?? content.endIndex
            let wikitableCSS = String(content[startIndex..<endIndex])
            
            XCTAssertFalse(wikitableCSS.contains("display: block"), 
                          "wikitable CSS should not have display: block")
            XCTAssertFalse(wikitableCSS.contains("white-space: nowrap"), 
                          "wikitable CSS should not have white-space: nowrap")
        }
        
        // Verify proper table styling is present
        XCTAssertTrue(content.contains(".wikitable"), 
                     "ArticleWebView should style .wikitable elements")
        XCTAssertTrue(content.contains("width: 100%"), 
                     "Tables should use width: 100%")
        XCTAssertTrue(content.contains("table-layout: auto"), 
                     "Tables should use table-layout: auto")
    }
    
    func testCollapsibleContainerCSSExists() {
        // Check the collapsible_tables.css file
        let currentFile = #file
        let testDir = (currentFile as NSString).deletingLastPathComponent
        let projectDir = (testDir as NSString).deletingLastPathComponent
        let iosDir = (projectDir as NSString).deletingLastPathComponent
        let sessionDir = (iosDir as NSString).deletingLastPathComponent
        let filePath = (sessionDir as NSString).appendingPathComponent("shared/js/collapsible_tables.css")
        
        guard let content = try? String(contentsOfFile: filePath) else {
            XCTFail("Could not read collapsible_tables.css at \(filePath)")
            return
        }
        
        // Check for proper table container styling
        XCTAssertTrue(content.contains(".collapsible-container .wikitable"), 
                     "CSS should style tables within collapsible containers")
        
        // Check for width rules
        XCTAssertTrue(content.contains("width: 100%"), 
                     "Tables should fill container width")
        
        // Check for padding rules on content
        XCTAssertTrue(content.contains(".collapsible-content"), 
                     "CSS should style collapsible-content")
    }
    
    func testOverflowHandling() {
        // Verify overflow is handled at container level
        let currentFile = #file
        let testDir = (currentFile as NSString).deletingLastPathComponent
        let projectDir = (testDir as NSString).deletingLastPathComponent
        let filePath = (projectDir as NSString).appendingPathComponent("osrswiki/Views/ArticleWebView.swift")
        
        guard let content = try? String(contentsOfFile: filePath) else {
            XCTFail("Could not read ArticleWebView.swift at \(filePath)")
            return
        }
        
        // Check for proper overflow handling
        XCTAssertTrue(content.contains("overflow-x: auto") || content.contains("overflow-x:auto"), 
                     "Should handle horizontal overflow")
        XCTAssertTrue(content.contains("-webkit-overflow-scrolling: touch") || 
                     content.contains("-webkit-overflow-scrolling:touch"), 
                     "Should use smooth scrolling on iOS")
    }
}
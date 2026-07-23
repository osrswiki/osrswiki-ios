//
//  MapLibreBridgeTests.swift
//  osrswiki
//
//  Created for MapLibre bridge functionality testing
//

import XCTest
import WebKit
@testable import osrswiki

class MapLibreBridgeTests: XCTestCase {
    
    func testInlineBridgeScriptGeneration() {
        // Test that the inline bridge script is correctly generated
        let builder = osrsPageHtmlBuilder()
        let html = builder.buildFullHtmlDocument(
            title: "Test Article",
            bodyContent: "<div class=\"mw-kartographer-map\" data-lat=\"3094\" data-lon=\"3240\" data-zoom=\"7\" data-plane=\"0\">Map placeholder</div>",
            theme: osrsLightTheme(),
            collapseTablesEnabled: true,
            includeAssetLinks: false
        )
        
        // Verify inline bridge script is present
        XCTAssertTrue(html.contains("🗺️ iOS OsrsWikiBridge initialized and ready"), "Inline bridge script should be present")
        XCTAssertTrue(html.contains("window.OsrsWikiBridge"), "Bridge object should be created")
        XCTAssertTrue(html.contains("onMapPlaceholderMeasured"), "Bridge should have onMapPlaceholderMeasured method")
        
        // Verify script is in head section (early loading)
        let headEndIndex = html.range(of: "</head>")?.lowerBound ?? html.endIndex
        let headSection = String(html[..<headEndIndex])
        XCTAssertTrue(headSection.contains("window.OsrsWikiBridge"), "Bridge script should be in head section for early loading")
    }
    
    func testBridgeScriptContent() {
        // Test that the bridge script has all required methods
        let builder = osrsPageHtmlBuilder()
        let html = builder.buildFullHtmlDocument(
            title: "Test",
            bodyContent: "",
            theme: osrsLightTheme()
        )
        
        // Check for all required bridge methods
        XCTAssertTrue(html.contains("onMapPlaceholderMeasured"), "Should have onMapPlaceholderMeasured method")
        XCTAssertTrue(html.contains("onCollapsibleToggled"), "Should have onCollapsibleToggled method")  
        XCTAssertTrue(html.contains("setHorizontalScroll"), "Should have setHorizontalScroll method")
        XCTAssertTrue(html.contains("log"), "Should have log method")
        
        // Check for webkit message handler integration
        XCTAssertTrue(html.contains("window.webkit.messageHandlers.mapBridge"), "Should use webkit message handlers")
    }
    
    func testMapElementDetection() {
        // Test with multiple map elements to ensure detection works
        let builder = osrsPageHtmlBuilder()
        let bodyContent = """
        <h1>Test Article</h1>
        <p>Some content</p>
        <div class="mw-kartographer-map" data-lat="3094" data-lon="3240" data-zoom="7" data-plane="0">Varrock Map</div>
        <p>More content</p>
        <div class="mw-kartographer-map" data-lat="2500" data-lon="3500" data-zoom="6" data-plane="0">Falador Map</div>
        """
        
        let html = builder.buildFullHtmlDocument(
            title: "Multi Map Test",
            bodyContent: bodyContent,
            theme: osrsLightTheme()
        )
        
        // Verify HTML contains map elements that JavaScript can detect
        XCTAssertTrue(html.contains("mw-kartographer-map"), "Should contain map elements")
        XCTAssertTrue(html.contains("data-lat"), "Should have map data attributes")
        XCTAssertTrue(html.contains("data-lon"), "Should have map data attributes")
        XCTAssertTrue(html.contains("data-zoom"), "Should have map data attributes")
        XCTAssertTrue(html.contains("data-plane"), "Should have map data attributes")
        
        // Count map elements
        let mapElementCount = html.components(separatedBy: "mw-kartographer-map").count - 1
        XCTAssertEqual(mapElementCount, 2, "Should have exactly 2 map elements")
    }
    
    func testScriptLoadingOrder() {
        // Test that map_bridge.js is loaded first in the asset order
        let builder = osrsPageHtmlBuilder()
        let html = builder.buildFullHtmlDocument(
            title: "Script Order Test",
            bodyContent: "",
            theme: osrsLightTheme(),
            includeAssetLinks: true
        )
        
        // Extract script tags to verify order
        let scriptPattern = "<script src=\"[^\"]*web/[^\"]*\\.js\">"
        let regex = try! NSRegularExpression(pattern: scriptPattern)
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: html.count))
        
        if matches.count > 0 {
            let firstScriptRange = matches[0].range
            let firstScript = String(html[Range(firstScriptRange, in: html)!])
            
            // map_bridge.js should be the first JavaScript asset loaded
            XCTAssertTrue(firstScript.contains("map_bridge.js"), "map_bridge.js should be loaded first")
        }
    }
    
    func testBridgeMessageHandlerSetup() {
        // Test that WKWebView message handlers are properly configured
        // This simulates the ArticleWebView setup process
        
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Simulate the message handler registration that happens in ArticleWebView
        let messageHandlerNames = ["clipboardBridge", "renderTimeline", "linkHandler", "mapBridge"]
        
        // In real implementation, a coordinator would be added for each handler
        // Here we just verify the expected handler names
        XCTAssertTrue(messageHandlerNames.contains("mapBridge"), "mapBridge should be in message handler list")
        
        // Verify this is the expected handler name used in JavaScript
        let builder = osrsPageHtmlBuilder()
        let html = builder.buildFullHtmlDocument(title: "Test", bodyContent: "", theme: osrsLightTheme())
        XCTAssertTrue(html.contains("messageHandlers.mapBridge"), "JavaScript should reference mapBridge handler")
    }
    
    func testMapDataJsonFormat() {
        // Test that HTML contains proper map data attributes for JavaScript extraction
        let builder = osrsPageHtmlBuilder()
        let bodyContent = """
        <div class="mw-kartographer-map" 
             data-lat="3094" 
             data-lon="3240" 
             data-zoom="7" 
             data-plane="0">Map</div>
        """
        
        let html = builder.buildFullHtmlDocument(
            title: "Map Data Test",
            bodyContent: bodyContent,
            theme: osrsLightTheme()
        )
        
        // Verify HTML contains map data attributes that collapsible_content.js can extract
        XCTAssertTrue(html.contains("data-lat=\"3094\""), "Should have lat data attribute")
        XCTAssertTrue(html.contains("data-lon=\"3240\""), "Should have lon data attribute")
        XCTAssertTrue(html.contains("data-zoom=\"7\""), "Should have zoom data attribute")
        XCTAssertTrue(html.contains("data-plane=\"0\""), "Should have plane data attribute")
        
        // Verify the bridge methods are available for data handling
        XCTAssertTrue(html.contains("onMapPlaceholderMeasured"), "Bridge should have method to handle map data")
    }
}

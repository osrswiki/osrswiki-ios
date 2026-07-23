//
//  TablePreviewRendererTest.swift
//  osrswikiTests
//
//  Unit test for table preview renderer functionality
//

import XCTest
@testable import osrswiki
import SwiftUI

@MainActor
class TablePreviewRendererTest: XCTestCase {
    
    var renderer: osrsTablePreviewRenderer!
    var lightTheme: osrsLightTheme!
    var darkTheme: osrsDarkTheme!
    
    override func setUp() async throws {
        try await super.setUp()
        renderer = osrsTablePreviewRenderer.shared
        lightTheme = osrsLightTheme()
        darkTheme = osrsDarkTheme()
    }
    
    override func tearDown() async throws {
        renderer.clearCache()
        try await super.tearDown()
    }
    
    func testTablePreviewGenerationForExpanded() async throws {
        // Test generating an expanded table preview
        let expandedPreview = await renderer.generateTablePreview(collapsed: false, theme: lightTheme)
        
        // Verify the image was generated
        XCTAssertNotNil(expandedPreview, "Expanded table preview should be generated")
        XCTAssertGreaterThan(expandedPreview.size.width, 0, "Preview width should be greater than 0")
        XCTAssertGreaterThan(expandedPreview.size.height, 0, "Preview height should be greater than 0")
    }
    
    func testTablePreviewGenerationForCollapsed() async throws {
        // Test generating a collapsed table preview
        let collapsedPreview = await renderer.generateTablePreview(collapsed: true, theme: lightTheme)
        
        // Verify the image was generated
        XCTAssertNotNil(collapsedPreview, "Collapsed table preview should be generated")
        XCTAssertGreaterThan(collapsedPreview.size.width, 0, "Preview width should be greater than 0")
        XCTAssertGreaterThan(collapsedPreview.size.height, 0, "Preview height should be greater than 0")
    }
    
    func testTablePreviewCaching() async throws {
        // Generate a preview
        let firstPreview = await renderer.generateTablePreview(collapsed: false, theme: lightTheme)
        
        // Get the cached version
        let cachedPreview = renderer.getCachedTablePreview(collapsed: false, theme: lightTheme)
        
        // Verify caching works
        XCTAssertNotNil(cachedPreview, "Preview should be cached")
        XCTAssertEqual(firstPreview.size, cachedPreview?.size, "Cached preview should have same size")
    }
    
    func testTablePreviewForDifferentThemes() async throws {
        // Test light theme
        let lightPreview = await renderer.generateTablePreview(collapsed: false, theme: lightTheme)
        XCTAssertNotNil(lightPreview, "Light theme preview should be generated")
        
        // Test dark theme
        let darkPreview = await renderer.generateTablePreview(collapsed: false, theme: darkTheme)
        XCTAssertNotNil(darkPreview, "Dark theme preview should be generated")
        
        // Previews should be different for different themes
        // We can't easily compare image content, but we can verify both were generated
        XCTAssertNotEqual(lightPreview.size.width * lightPreview.size.height, 0)
        XCTAssertNotEqual(darkPreview.size.width * darkPreview.size.height, 0)
    }
    
    func testCacheClearingWorks() async throws {
        // Generate and cache a preview
        _ = await renderer.generateTablePreview(collapsed: false, theme: lightTheme)
        
        // Verify it's cached
        var cachedPreview = renderer.getCachedTablePreview(collapsed: false, theme: lightTheme)
        XCTAssertNotNil(cachedPreview, "Preview should be cached")
        
        // Clear cache
        renderer.clearCache()
        
        // Verify cache is cleared
        cachedPreview = renderer.getCachedTablePreview(collapsed: false, theme: lightTheme)
        XCTAssertNil(cachedPreview, "Preview should not be cached after clearing")
    }
}
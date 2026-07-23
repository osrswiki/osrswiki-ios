//
//  ThemeResponsiveTableTest.swift
//  osrswikiTests
//
//  Test to verify table previews are theme-responsive (light vs dark)
//

import XCTest
@testable import osrswiki

@MainActor
final class ThemeResponsiveTableTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {}
    
    /// Test that table previews generate different images for light vs dark themes
    func testTablePreviewsAreThemeResponsive() async throws {
        print("📊 Testing theme-responsive table previews...")
        
        let renderer = osrsTablePreviewRenderer.shared
        let lightTheme = osrsLightTheme()
        let darkTheme = osrsDarkTheme()
        
        // Generate all 4 combinations
        let collapsedLight = await renderer.generateTablePreview(collapsed: true, theme: lightTheme)
        let collapsedDark = await renderer.generateTablePreview(collapsed: true, theme: darkTheme)
        let expandedLight = await renderer.generateTablePreview(collapsed: false, theme: lightTheme)
        let expandedDark = await renderer.generateTablePreview(collapsed: false, theme: darkTheme)
        
        // Save all 4 previews for visual inspection
        let tempDir = FileManager.default.temporaryDirectory
        try collapsedLight.pngData()?.write(to: tempDir.appendingPathComponent("table-collapsed-light.png"))
        try collapsedDark.pngData()?.write(to: tempDir.appendingPathComponent("table-collapsed-dark.png"))
        try expandedLight.pngData()?.write(to: tempDir.appendingPathComponent("table-expanded-light.png"))
        try expandedDark.pngData()?.write(to: tempDir.appendingPathComponent("table-expanded-dark.png"))
        
        print("📊 Saved all 4 table preview combinations to: \(tempDir.path)")
        
        // Verify images are different between themes
        let collapsedLightData = collapsedLight.pngData()!
        let collapsedDarkData = collapsedDark.pngData()!
        let expandedLightData = expandedLight.pngData()!
        let expandedDarkData = expandedDark.pngData()!
        
        XCTAssertNotEqual(collapsedLightData, collapsedDarkData, "Collapsed previews should differ between light and dark themes")
        XCTAssertNotEqual(expandedLightData, expandedDarkData, "Expanded previews should differ between light and dark themes")
        
        // Verify collapsed vs expanded are different within same theme
        XCTAssertNotEqual(collapsedLightData, expandedLightData, "Light theme should have different collapsed vs expanded previews")
        XCTAssertNotEqual(collapsedDarkData, expandedDarkData, "Dark theme should have different collapsed vs expanded previews")
        
        print("✅ All 4 table preview combinations are unique and theme-responsive!")
    }
}
//
//  SimplePreviewTest.swift
//  osrswikiTests
//
//  Simple test to generate theme preview and save for inspection
//

import XCTest
@testable import osrswiki

@MainActor
final class SimplePreviewTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {}
    
    /// Generate theme preview with real AsyncImages and save for inspection
    func testGenerateThemePreviewWithRealImages() async throws {
        print("🔍 Generating theme preview with real AsyncImages...")
        
        let renderer = osrsThemePreviewRenderer.shared
        
        // Generate light theme preview
        let lightPreview = await renderer.generatePreview(for: .osrsLight, colorScheme: .light)
        let lightData = lightPreview.pngData()!
        let lightURL = getTemporaryURL(filename: "fixed-theme-preview-light")
        try lightData.write(to: lightURL)
        print("🖼️ Saved light theme preview to: \(lightURL.path)")
        
        // Generate dark theme preview
        let darkPreview = await renderer.generatePreview(for: .osrsDark, colorScheme: .dark)
        let darkData = darkPreview.pngData()!
        let darkURL = getTemporaryURL(filename: "fixed-theme-preview-dark")
        try darkData.write(to: darkURL)
        print("🖼️ Saved dark theme preview to: \(darkURL.path)")
        
        // Basic checks
        XCTAssertGreaterThan(lightPreview.size.width, 200, "Preview should have reasonable width")
        XCTAssertGreaterThan(lightPreview.size.height, 150, "Preview should have reasonable height")
        
        print("✅ Theme previews generated successfully")
    }
    
    func getTemporaryURL(filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("\(filename).png")
    }
}
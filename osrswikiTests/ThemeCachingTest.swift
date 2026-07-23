//
//  ThemeCachingTest.swift
//  osrswikiTests
//
//  Simple focused test to verify theme preview caching works
//

import XCTest
@testable import osrswiki

@MainActor
final class ThemeCachingTest: XCTestCase {
    
    private var themeRenderer: osrsThemePreviewRenderer!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        themeRenderer = osrsThemePreviewRenderer.shared
        
        // Clear cache to ensure clean test
        themeRenderer.clearCache()
    }
    
    override func tearDownWithError() throws {}
    
    /// Test that theme previews are properly cached
    func testThemePreviewCaching() async throws {
        print("🧪 Testing theme preview caching mechanism")
        
        // === FIRST CALL: Should be cache miss (slow) ===
        print("📊 First call to osrsLight theme...")
        let startTime1 = CFAbsoluteTimeGetCurrent()
        let image1 = await themeRenderer.generatePreview(for: .osrsLight)
        let endTime1 = CFAbsoluteTimeGetCurrent()
        let duration1 = endTime1 - startTime1
        
        print("⏱️  First call duration: \(String(format: "%.3f", duration1))s")
        XCTAssertNotNil(image1, "Should generate image")
        XCTAssertGreaterThan(duration1, 0.5, "First call should be slow (cache miss)")
        
        // === SECOND CALL: Should be cache hit (instant) ===
        print("📊 Second call to osrsLight theme (should be cached)...")
        let startTime2 = CFAbsoluteTimeGetCurrent()
        let image2 = await themeRenderer.generatePreview(for: .osrsLight)
        let endTime2 = CFAbsoluteTimeGetCurrent()
        let duration2 = endTime2 - startTime2
        
        print("⏱️  Second call duration: \(String(format: "%.3f", duration2))s")
        XCTAssertNotNil(image2, "Should return cached image")
        XCTAssertLessThan(duration2, 0.1, "Second call should be instant (cache hit)")
        
        // === VERIFY IMAGES ARE IDENTICAL ===
        let data1 = image1.pngData()
        let data2 = image2.pngData()
        XCTAssertEqual(data1, data2, "Cached image should be identical to original")
        
        print("✅ Theme preview caching test passed!")
    }
    
    /// Test automatic theme caching (split preview)
    func testAutomaticThemeCaching() async throws {
        print("🧪 Testing automatic theme caching (split preview)")
        
        // Clear cache first
        themeRenderer.clearCache()
        
        // === FIRST CALL: Should be cache miss ===
        print("📊 First call to automatic theme...")
        let startTime1 = CFAbsoluteTimeGetCurrent()
        let image1 = await themeRenderer.generatePreview(for: .automatic)
        let endTime1 = CFAbsoluteTimeGetCurrent()
        let duration1 = endTime1 - startTime1
        
        print("⏱️  First automatic call duration: \(String(format: "%.3f", duration1))s")
        XCTAssertGreaterThan(duration1, 1.0, "First automatic call should be slow (generates light + dark)")
        
        // === SECOND CALL: Should be cache hit ===
        print("📊 Second call to automatic theme (should be cached)...")
        let startTime2 = CFAbsoluteTimeGetCurrent()
        let image2 = await themeRenderer.generatePreview(for: .automatic)
        let endTime2 = CFAbsoluteTimeGetCurrent()
        let duration2 = endTime2 - startTime2
        
        print("⏱️  Second automatic call duration: \(String(format: "%.3f", duration2))s")
        XCTAssertLessThan(duration2, 0.1, "Second automatic call should be instant (cache hit)")
        
        // === NOW CHECK IF LIGHT AND DARK ARE ALSO CACHED ===
        print("📊 Checking if light theme is now cached...")
        let startTime3 = CFAbsoluteTimeGetCurrent()
        let lightImage = await themeRenderer.generatePreview(for: .osrsLight)
        let endTime3 = CFAbsoluteTimeGetCurrent()
        let duration3 = endTime3 - startTime3
        
        print("⏱️  Light theme duration after automatic: \(String(format: "%.3f", duration3))s")
        XCTAssertLessThan(duration3, 0.1, "Light theme should be cached from automatic generation")
        
        print("📊 Checking if dark theme is now cached...")
        let startTime4 = CFAbsoluteTimeGetCurrent()
        let darkImage = await themeRenderer.generatePreview(for: .osrsDark)
        let endTime4 = CFAbsoluteTimeGetCurrent()
        let duration4 = endTime4 - startTime4
        
        print("⏱️  Dark theme duration after automatic: \(String(format: "%.3f", duration4))s")
        XCTAssertLessThan(duration4, 0.1, "Dark theme should be cached from automatic generation")
        
        print("✅ Automatic theme caching test passed!")
    }
}
//
//  SingletonCacheValidationTest.swift
//  osrswikiTests
//
//  Test to verify singleton renderers share cache for instant loading
//

import XCTest
@testable import osrswiki

final class SingletonCacheValidationTest: XCTestCase {
    
    /// Test that background generation and appearance page use same cache
    @MainActor
    func testSharedCacheInstances() async throws {
        print("🧪 Testing singleton cache sharing...")
        
        // Clear everything
        let backgroundManager = osrsBackgroundPreviewManager.shared
        backgroundManager.clearAllPreviews()
        
        // Generate previews via background manager
        print("🔄 Generating previews via background manager...")
        await backgroundManager.preGenerateAllPreviews()
        
        // Verify generation completed
        XCTAssertTrue(backgroundManager.arePreviewsReady, "Background generation should complete")
        
        // Access same instances that appearance page would use
        let themeRenderer = osrsThemePreviewRenderer.shared
        let tableRenderer = osrsTablePreviewRenderer.shared
        
        // Test that cached previews are accessible instantly
        print("⚡ Testing instant cache access...")
        
        let start = CFAbsoluteTimeGetCurrent()
        
        let automaticPreview = themeRenderer.getCachedPreview(for: .automatic)
        let lightPreview = themeRenderer.getCachedPreview(for: .osrsLight)  
        let darkPreview = themeRenderer.getCachedPreview(for: .osrsDark)
        
        let lightTheme = osrsLightTheme()
        let darkTheme = osrsDarkTheme()
        let lightCollapsed = tableRenderer.getCachedTablePreview(collapsed: true, theme: lightTheme)
        let lightExpanded = tableRenderer.getCachedTablePreview(collapsed: false, theme: lightTheme)
        let darkCollapsed = tableRenderer.getCachedTablePreview(collapsed: true, theme: darkTheme)
        let darkExpanded = tableRenderer.getCachedTablePreview(collapsed: false, theme: darkTheme)
        
        let accessTime = CFAbsoluteTimeGetCurrent() - start
        
        // All previews should be available from shared cache
        XCTAssertNotNil(automaticPreview, "✅ Automatic theme should be cached")
        XCTAssertNotNil(lightPreview, "✅ Light theme should be cached")
        XCTAssertNotNil(darkPreview, "✅ Dark theme should be cached")
        XCTAssertNotNil(lightCollapsed, "✅ Light collapsed table should be cached")
        XCTAssertNotNil(lightExpanded, "✅ Light expanded table should be cached")
        XCTAssertNotNil(darkCollapsed, "✅ Dark collapsed table should be cached")
        XCTAssertNotNil(darkExpanded, "✅ Dark expanded table should be cached")
        
        // Access should be instant (< 10ms)
        XCTAssertLessThan(accessTime, 0.01, "✅ Cache access should be instant")
        
        print("🎉 SUCCESS: Singleton cache sharing works!")
        print("📊 Cache access time: \(String(format: "%.1f", accessTime * 1000))ms")
        print("📊 All 7 previews accessible from shared cache")
        
        // Verify image quality
        if let automaticImage = automaticPreview {
            XCTAssertGreaterThan(automaticImage.size.width, 100, "Preview should be substantial")
            print("📏 Automatic preview: \(automaticImage.size)")
        }
        
        if let collapsedImage = lightCollapsed {
            XCTAssertGreaterThan(collapsedImage.size.width, 50, "Table preview should be substantial") 
            print("📏 Table preview: \(collapsedImage.size)")
        }
    }
}
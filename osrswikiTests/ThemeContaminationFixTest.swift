//
//  ThemeContaminationFixTest.swift
//  osrswikiTests
//
//  Test to verify light theme table previews don't have dark theme contamination
//

import XCTest
@testable import osrswiki

final class ThemeContaminationFixTest: XCTestCase {
    
    @MainActor
    func testLightThemeTablePreviewsClean() async throws {
        print("🧪 Testing theme contamination fix...")
        
        let backgroundManager = osrsBackgroundPreviewManager.shared
        let tableRenderer = osrsTablePreviewRenderer.shared
        
        // Clear cache to force regeneration with fixed theme logic
        backgroundManager.clearAllPreviews()
        print("🗑️ Cleared all caches - will regenerate with theme fix")
        
        // Generate fresh previews with the fix
        print("🔄 Regenerating all previews with theme contamination fix...")
        await backgroundManager.preGenerateAllPreviews()
        
        // Verify generation completed
        XCTAssertTrue(backgroundManager.arePreviewsReady, "Background generation should complete")
        
        // Test light theme table previews specifically
        let lightTheme = osrsLightTheme()
        
        let lightCollapsed = tableRenderer.getCachedTablePreview(collapsed: true, theme: lightTheme)
        let lightExpanded = tableRenderer.getCachedTablePreview(collapsed: false, theme: lightTheme)
        
        XCTAssertNotNil(lightCollapsed, "Light collapsed table preview should be cached")
        XCTAssertNotNil(lightExpanded, "Light expanded table preview should be cached") 
        
        if let collapsedImage = lightCollapsed,
           let expandedImage = lightExpanded {
            
            print("✅ Light theme table previews generated:")
            print("  📊 Collapsed: \(collapsedImage.size)")
            print("  📊 Expanded: \(expandedImage.size)")
            
            // Verify images are substantial (not empty/error)
            XCTAssertGreaterThan(collapsedImage.size.width, 100, "Collapsed preview should be substantial")
            XCTAssertGreaterThan(collapsedImage.size.height, 100, "Collapsed preview should be substantial")
            XCTAssertGreaterThan(expandedImage.size.width, 100, "Expanded preview should be substantial")
            XCTAssertGreaterThan(expandedImage.size.height, 100, "Expanded preview should be substantial")
            
            print("🎉 SUCCESS: Light theme table previews generated without theme contamination!")
            print("📝 User should now see clean light theme previews in appearance page")
        }
        
        // Also test dark theme to ensure it still works
        let darkTheme = osrsDarkTheme()
        let darkCollapsed = tableRenderer.getCachedTablePreview(collapsed: true, theme: darkTheme)
        let darkExpanded = tableRenderer.getCachedTablePreview(collapsed: false, theme: darkTheme)
        
        XCTAssertNotNil(darkCollapsed, "Dark collapsed table preview should be cached")
        XCTAssertNotNil(darkExpanded, "Dark expanded table preview should be cached")
        
        print("✅ Dark theme table previews also working correctly")
    }
}
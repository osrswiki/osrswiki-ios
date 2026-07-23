//
//  InstantPreviewLoadingTest.swift
//  osrswikiTests
//
//  Test to verify appearance page loads previews instantly from cache
//  This addresses the user's concern about loading delays
//

import XCTest
@testable import osrswiki

final class InstantPreviewLoadingTest: XCTestCase {
    
    var themeRenderer: osrsThemePreviewRenderer!
    var tableRenderer: osrsTablePreviewRenderer!
    var backgroundManager: osrsBackgroundPreviewManager!
    
    @MainActor 
    override func setUpWithError() throws {
        themeRenderer = osrsThemePreviewRenderer.shared
        tableRenderer = osrsTablePreviewRenderer.shared
        backgroundManager = osrsBackgroundPreviewManager.shared
        backgroundManager.clearAllPreviews()
    }
    
    /// Test that cached previews are accessible instantly without regeneration
    @MainActor
    func testCachedPreviewsAccessible() async throws {
        print("🧪 Testing instant preview access after background generation...")
        
        // 1. Generate all previews in background
        await backgroundManager.preGenerateAllPreviews()
        
        // 2. Verify background generation completed
        XCTAssertTrue(backgroundManager.arePreviewsReady, "Background generation should be complete")
        
        // 3. Test instant theme preview access (should be 0ms)
        let start = CFAbsoluteTimeGetCurrent()
        
        let automaticPreview = themeRenderer.getCachedPreview(for: .automatic)
        let lightPreview = themeRenderer.getCachedPreview(for: .osrsLight)  
        let darkPreview = themeRenderer.getCachedPreview(for: .osrsDark)
        
        let themeAccessTime = CFAbsoluteTimeGetCurrent() - start
        
        // All theme previews should be instantly accessible
        XCTAssertNotNil(automaticPreview, "Automatic theme preview should be cached")
        XCTAssertNotNil(lightPreview, "Light theme preview should be cached")
        XCTAssertNotNil(darkPreview, "Dark theme preview should be cached")
        XCTAssertLessThan(themeAccessTime, 0.01, "Theme preview access should be instant (< 10ms)")
        
        // 4. Test instant table preview access (should be 0ms)  
        let tableStart = CFAbsoluteTimeGetCurrent()
        
        let lightTheme = osrsLightTheme()
        let darkTheme = osrsDarkTheme()
        
        let lightCollapsed = tableRenderer.getCachedTablePreview(collapsed: true, theme: lightTheme)
        let lightExpanded = tableRenderer.getCachedTablePreview(collapsed: false, theme: lightTheme)
        let darkCollapsed = tableRenderer.getCachedTablePreview(collapsed: true, theme: darkTheme)
        let darkExpanded = tableRenderer.getCachedTablePreview(collapsed: false, theme: darkTheme)
        
        let tableAccessTime = CFAbsoluteTimeGetCurrent() - tableStart
        
        // All table previews should be instantly accessible
        XCTAssertNotNil(lightCollapsed, "Light collapsed table preview should be cached")
        XCTAssertNotNil(lightExpanded, "Light expanded table preview should be cached")
        XCTAssertNotNil(darkCollapsed, "Dark collapsed table preview should be cached") 
        XCTAssertNotNil(darkExpanded, "Dark expanded table preview should be cached")
        XCTAssertLessThan(tableAccessTime, 0.01, "Table preview access should be instant (< 10ms)")
        
        print("✅ SUCCESS: All previews accessible instantly!")
        print("📊 Theme preview access time: \(String(format: "%.3f", themeAccessTime * 1000))ms")
        print("📊 Table preview access time: \(String(format: "%.3f", tableAccessTime * 1000))ms")
        
        // 5. Verify preview quality (should be real images, not placeholders)
        if let automaticImage = automaticPreview {
            XCTAssertGreaterThan(automaticImage.size.width, 100, "Preview should be substantial size")
            XCTAssertGreaterThan(automaticImage.size.height, 100, "Preview should be substantial size")
            print("📏 Automatic preview size: \(automaticImage.size)")
        }
        
        if let collapsedImage = lightCollapsed {
            XCTAssertGreaterThan(collapsedImage.size.width, 50, "Table preview should be substantial size")
            XCTAssertGreaterThan(collapsedImage.size.height, 50, "Table preview should be substantial size")
            print("📏 Collapsed table preview size: \(collapsedImage.size)")
        }
    }
    
    /// Test the user scenario: background generation complete, then appearance page access
    @MainActor
    func testUserScenarioInstantLoading() async throws {
        print("🧪 Testing user scenario: wait for 100% then visit appearance page...")
        
        // 1. Simulate background generation (user waits for 100%)
        print("🔄 User waiting for background generation to complete...")
        await backgroundManager.preGenerateAllPreviews()
        XCTAssertTrue(backgroundManager.arePreviewsReady, "User should see 100% complete")
        
        // 2. Simulate user navigating to appearance page
        print("👤 User navigates to appearance page...")
        let pageLoadStart = CFAbsoluteTimeGetCurrent()
        
        // This simulates what AppearanceSettingsView does when it loads
        let themes: [osrsThemeSelection] = [.automatic, .osrsLight, .osrsDark]
        var loadedImages: [UIImage] = []
        
        for theme in themes {
            if let cachedImage = themeRenderer.getCachedPreview(for: theme) {
                loadedImages.append(cachedImage)
                print("⚡ Theme \(theme.rawValue): INSTANT CACHE HIT")
            } else {
                XCTFail("❌ Theme \(theme.rawValue): Cache miss - this should not happen!")
            }
        }
        
        // Table previews
        let lightTheme = osrsLightTheme()
        if let collapsedTable = tableRenderer.getCachedTablePreview(collapsed: true, theme: lightTheme),
           let expandedTable = tableRenderer.getCachedTablePreview(collapsed: false, theme: lightTheme) {
            loadedImages.append(collapsedTable)
            loadedImages.append(expandedTable)
            print("⚡ Table previews: INSTANT CACHE HIT")
        } else {
            XCTFail("❌ Table previews: Cache miss - this should not happen!")
        }
        
        let totalPageLoadTime = CFAbsoluteTimeGetCurrent() - pageLoadStart
        
        // Page should load instantly (all cached)
        XCTAssertLessThan(totalPageLoadTime, 0.1, "Appearance page should load in < 100ms")
        XCTAssertEqual(loadedImages.count, 5, "Should load all 5 previews (3 themes + 2 tables)")
        
        print("🎉 SUCCESS: Appearance page loaded instantly!")
        print("📊 Total page load time: \(String(format: "%.1f", totalPageLoadTime * 1000))ms")
        print("📊 All \(loadedImages.count) previews loaded from cache")
    }
}
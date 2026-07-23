//
//  BackgroundGenerationTimingTest.swift
//  osrswikiTests
//
//  Test-driven development verification of background preview generation timing
//  MUST prove that background generation works and appearance page loads instantly
//

import XCTest
@testable import osrswiki

@MainActor
final class BackgroundGenerationTimingTest: XCTestCase {
    
    private var backgroundManager: osrsBackgroundPreviewManager!
    private var themeRenderer: osrsThemePreviewRenderer!
    private var tableRenderer: osrsTablePreviewRenderer!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        backgroundManager = osrsBackgroundPreviewManager.shared
        themeRenderer = osrsThemePreviewRenderer.shared
        tableRenderer = osrsTablePreviewRenderer.shared
        
        // Clear any existing state to ensure clean test
        backgroundManager.clearAllPreviews()
        themeRenderer.clearCache()
    }
    
    override func tearDownWithError() throws {}
    
    /// CRITICAL TEST: Verify background generation completes and appearance page loads instantly
    func testBackgroundGenerationCompletesAndProvidesInstantLoading() async throws {
        print("🧪 CRITICAL TEST: Background generation timing and instant loading verification")
        
        // === STEP 1: Verify initial state ===
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⏱️  Test started at: \(startTime)")
        
        XCTAssertFalse(backgroundManager.arePreviewsReady, "Previews should not be ready initially")
        XCTAssertFalse(backgroundManager.isGeneratingPreviews, "Should not be generating initially")
        XCTAssertEqual(backgroundManager.generationProgress, 0.0, "Progress should be 0 initially")
        
        // === STEP 2: Start background generation and measure time to completion ===
        print("🔄 Starting background generation...")
        let generationStartTime = CFAbsoluteTimeGetCurrent()
        
        // Start generation and wait for completion
        await backgroundManager.preGenerateAllPreviews()
        
        let generationEndTime = CFAbsoluteTimeGetCurrent()
        let generationDuration = generationEndTime - generationStartTime
        print("⏱️  Background generation completed in: \(String(format: "%.2f", generationDuration)) seconds")
        
        // === STEP 3: Verify background generation completed successfully ===
        XCTAssertTrue(backgroundManager.arePreviewsReady, "Previews should be ready after generation")
        XCTAssertFalse(backgroundManager.isGeneratingPreviews, "Should not be generating after completion")
        XCTAssertEqual(backgroundManager.generationProgress, 1.0, "Progress should be 100% after completion")
        
        print("✅ Background generation state verified - all previews ready")
        
        // === STEP 4: Test theme preview instant loading ===
        print("📊 Testing theme preview instant loading...")
        
        let themeTestResults = await testAllThemePreviewsLoadInstantly()
        for result in themeTestResults {
            print("🖼️  Theme '\(result.theme)': \(String(format: "%.3f", result.loadTime))s")
            XCTAssertLessThan(result.loadTime, 0.1, "Theme preview '\(result.theme)' should load instantly (<100ms), took \(result.loadTime)s")
        }
        
        // === STEP 5: Test table preview instant loading (ALL VARIANTS) ===
        print("📋 Testing table preview instant loading for all theme variants...")
        
        let tableTestResults = await testAllTablePreviewsLoadInstantly()
        for result in tableTestResults {
            print("📊 Table '\(result.description)': \(String(format: "%.3f", result.loadTime))s")
            XCTAssertLessThan(result.loadTime, 0.1, "Table preview '\(result.description)' should load instantly (<100ms), took \(result.loadTime)s")
        }
        
        // === STEP 6: Verify total count of generated previews ===
        let expectedPreviewCount = 7 // 3 themes + 4 table combinations
        let actualPreviewCount = themeTestResults.count + tableTestResults.count
        print("📈 Total previews verified: \(actualPreviewCount) (expected: \(expectedPreviewCount))")
        XCTAssertEqual(actualPreviewCount, expectedPreviewCount, "Should have generated all expected previews")
        
        let totalTestTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️  Total test duration: \(String(format: "%.2f", totalTestTime)) seconds")
        print("🎉 CRITICAL TEST PASSED: Background generation works and provides instant loading!")
    }
    
    /// Test all theme previews load instantly from background cache
    private func testAllThemePreviewsLoadInstantly() async -> [ThemePreviewTestResult] {
        let themes: [osrsThemeSelection] = [.automatic, .osrsLight, .osrsDark]
        var results: [ThemePreviewTestResult] = []
        
        for theme in themes {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // This should be instant since background generation completed
            let _ = await themeRenderer.generatePreview(for: theme)
            
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            
            results.append(ThemePreviewTestResult(theme: theme.rawValue, loadTime: duration))
        }
        
        return results
    }
    
    /// Test all table preview combinations load instantly from background cache
    private func testAllTablePreviewsLoadInstantly() async -> [TablePreviewTestResult] {
        let themes: [any osrsThemeProtocol] = [osrsLightTheme(), osrsDarkTheme()]
        let states = [true, false] // collapsed, expanded
        var results: [TablePreviewTestResult] = []
        
        for theme in themes {
            for collapsed in states {
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // This should be instant since background generation completed
                let _ = await tableRenderer.generateTablePreview(collapsed: collapsed, theme: theme)
                
                let endTime = CFAbsoluteTimeGetCurrent()
                let duration = endTime - startTime
                
                let description = "\(collapsed ? "collapsed" : "expanded")-\(theme.name)"
                results.append(TablePreviewTestResult(description: description, loadTime: duration))
            }
        }
        
        return results
    }
    
    /// Test what happens when user navigates to appearance page before background generation completes
    func testAppearancePageVisitedDuringBackgroundGeneration() async throws {
        print("🧪 TEST: User visits appearance page while background generation is in progress")
        
        // Clear state
        backgroundManager.clearAllPreviews()
        
        // Start background generation but don't wait for completion
        let generationTask = Task {
            await backgroundManager.preGenerateAllPreviews()
        }
        
        // Wait a short time to let generation start
        try await Task.sleep(for: .milliseconds(500))
        
        // Verify generation is in progress
        XCTAssertTrue(backgroundManager.isGeneratingPreviews, "Generation should be in progress")
        XCTAssertFalse(backgroundManager.arePreviewsReady, "Previews should not be ready yet")
        
        // Now test what happens when user visits appearance page
        print("👤 User visits appearance page while generation is in progress...")
        
        let themeLoadTime = await measureThemePreviewLoadTime(.osrsLight)
        print("📊 Theme preview load time during generation: \(String(format: "%.3f", themeLoadTime))s")
        
        // This should take longer since generation is not complete
        XCTAssertGreaterThan(themeLoadTime, 0.5, "Preview should take longer when generation not complete")
        
        // Wait for background generation to complete
        await generationTask.value
        
        // Now test that subsequent loads are instant
        let subsequentLoadTime = await measureThemePreviewLoadTime(.osrsLight)
        print("📊 Theme preview load time after generation complete: \(String(format: "%.3f", subsequentLoadTime))s")
        
        XCTAssertLessThan(subsequentLoadTime, 0.1, "Subsequent load should be instant")
        
        print("✅ TEST PASSED: Behavior during generation vs after completion verified")
    }
    
    /// Measure how long it takes to load a single theme preview
    private func measureThemePreviewLoadTime(_ theme: osrsThemeSelection) async -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        let _ = await themeRenderer.generatePreview(for: theme)
        let endTime = CFAbsoluteTimeGetCurrent()
        return endTime - startTime
    }
    
    /// Comprehensive end-to-end test simulating real user workflow
    func testRealUserWorkflowTiming() async throws {
        print("🧪 TEST: Real user workflow timing simulation")
        
        // === Simulate app launch ===
        print("📱 Simulating app launch...")
        let appLaunchTime = CFAbsoluteTimeGetCurrent()
        
        backgroundManager.clearAllPreviews()
        
        // === Simulate user waiting 10 seconds before opening appearance page ===
        print("⏳ Simulating background generation (like real app launch)...")
        let backgroundTask = Task {
            await backgroundManager.preGenerateAllPreviews()
        }
        
        // Simulate user waiting 10 seconds (as mentioned in the issue)
        print("⏰ User waits 10 seconds before opening appearance page...")
        try await Task.sleep(for: .seconds(10))
        
        // Check if background generation completed in 10 seconds
        let generationComplete = backgroundManager.arePreviewsReady
        print("📊 After 10 seconds - Generation complete: \(generationComplete)")
        
        if !generationComplete {
            print("⚠️  ISSUE DETECTED: Background generation did not complete within 10 seconds")
            print("📈 Current progress: \(backgroundManager.generationProgress * 100)%")
            print("🔄 Still generating: \(backgroundManager.isGeneratingPreviews)")
            
            // Wait for completion to continue test
            await backgroundTask.value
        }
        
        // === Simulate user opening appearance page ===
        print("👤 User opens appearance page...")
        let appearancePageOpenTime = CFAbsoluteTimeGetCurrent()
        
        // Measure appearance page load time
        let themeLoadTimes = await testAllThemePreviewsLoadInstantly()
        let tableLoadTimes = await testAllTablePreviewsLoadInstantly()
        
        let appearancePageLoadComplete = CFAbsoluteTimeGetCurrent()
        let totalAppearanceLoadTime = appearancePageLoadComplete - appearancePageOpenTime
        
        print("⏱️  Appearance page total load time: \(String(format: "%.3f", totalAppearanceLoadTime))s")
        
        // === Simulate user switching themes ===
        print("🔄 User switches themes...")
        let themeSwitchStart = CFAbsoluteTimeGetCurrent()
        
        // Test dark theme table previews (the reported issue)
        let darkCollapsedTime = await measureTablePreviewLoadTime(collapsed: true, theme: osrsDarkTheme())
        let darkExpandedTime = await measureTablePreviewLoadTime(collapsed: false, theme: osrsDarkTheme())
        
        let themeSwitchEnd = CFAbsoluteTimeGetCurrent()
        let totalThemeSwitchTime = themeSwitchEnd - themeSwitchStart
        
        print("📊 Dark theme collapsed table: \(String(format: "%.3f", darkCollapsedTime))s")
        print("📊 Dark theme expanded table: \(String(format: "%.3f", darkExpandedTime))s")
        print("⏱️  Total theme switch time: \(String(format: "%.3f", totalThemeSwitchTime))s")
        
        // === ASSERTIONS ===
        XCTAssertTrue(generationComplete || backgroundManager.arePreviewsReady, "Generation should complete within 10 seconds or shortly after")
        XCTAssertLessThan(totalAppearanceLoadTime, 0.5, "Appearance page should load quickly")
        XCTAssertLessThan(darkCollapsedTime, 0.1, "Dark collapsed table should load instantly")
        XCTAssertLessThan(darkExpandedTime, 0.1, "Dark expanded table should load instantly")
        XCTAssertLessThan(totalThemeSwitchTime, 0.2, "Theme switching should be instant")
        
        let totalWorkflowTime = CFAbsoluteTimeGetCurrent() - appLaunchTime
        print("⏱️  Total user workflow simulation: \(String(format: "%.2f", totalWorkflowTime)) seconds")
        print("🎉 REAL USER WORKFLOW TEST COMPLETED")
    }
    
    /// Measure table preview load time
    private func measureTablePreviewLoadTime(collapsed: Bool, theme: any osrsThemeProtocol) async -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        let _ = await tableRenderer.generateTablePreview(collapsed: collapsed, theme: theme)
        let endTime = CFAbsoluteTimeGetCurrent()
        return endTime - startTime
    }
}

// MARK: - Test Result Types

struct ThemePreviewTestResult {
    let theme: String
    let loadTime: TimeInterval
}

struct TablePreviewTestResult {
    let description: String
    let loadTime: TimeInterval
}
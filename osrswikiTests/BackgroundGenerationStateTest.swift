//
//  BackgroundGenerationStateTest.swift
//  osrswikiTests
//
//  Test to verify background generation state management fix
//  Confirms previewsReady flag is properly set after generation completes
//

import XCTest
@testable import osrswiki

final class BackgroundGenerationStateTest: XCTestCase {
    
    var manager: osrsBackgroundPreviewManager!
    
    @MainActor 
    override func setUpWithError() throws {
        manager = osrsBackgroundPreviewManager.shared
        manager.clearAllPreviews()
    }
    
    /// Test that previewsReady flag is properly set after generation completes
    @MainActor
    func testPreviewsReadyFlagIsSetAfterGeneration() async throws {
        // Initially should be false
        XCTAssertFalse(manager.arePreviewsReady, "previewsReady should start as false")
        XCTAssertFalse(manager.isGeneratingPreviews, "should not be generating initially")
        
        // Start generation
        let generationTask = Task {
            await manager.preGenerateAllPreviews()
        }
        
        // Wait a moment for generation to start
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(manager.isGeneratingPreviews, "should be generating after start")
        XCTAssertFalse(manager.arePreviewsReady, "should not be ready while generating")
        
        // Wait for generation to complete
        await generationTask.value
        
        // CRITICAL TEST: After generation completes, previewsReady should be true
        XCTAssertFalse(manager.isGeneratingPreviews, "should not be generating after completion")
        XCTAssertTrue(manager.arePreviewsReady, "❌ CRITICAL: previewsReady should be true after generation completes")
        XCTAssertEqual(manager.generationProgress, 1.0, "progress should be 100%")
        
        print("✅ SUCCESS: Background generation properly sets previewsReady flag")
    }
    
    /// Test race condition scenario from user's log
    @MainActor
    func testNoRaceConditionInStateUpdate() async throws {
        // This simulates the exact scenario from user's log
        await MainActor.run {
            manager.clearAllPreviews()
        }
        
        // Start generation (like MainTabView.onAppear)
        print("🔄 Simulating app launch - starting background preview generation...")
        
        let generationTask = Task {
            await manager.preGenerateAllPreviews()
        }
        
        // Wait for some progress (simulating user navigating after app launch)
        try await Task.sleep(for: .seconds(2))
        
        // Check intermediate state
        print("🔄 Checking intermediate state...")
        let isGenerating = manager.isGeneratingPreviews
        let progress = manager.generationProgress
        let ready = manager.arePreviewsReady
        
        print("📊 Intermediate state: generating=\(isGenerating), progress=\(progress), ready=\(ready)")
        
        // Complete generation
        await generationTask.value
        
        // Final state check (this is when user visits appearance page)
        let finalGenerating = manager.isGeneratingPreviews
        let finalReady = manager.arePreviewsReady
        
        print("📊 Final state: generating=\(finalGenerating), ready=\(finalReady)")
        print("📱 Simulating appearance page check: background ready: \(finalReady)")
        
        // The fix should ensure this is true
        XCTAssertTrue(finalReady, "❌ Race condition detected: previewsReady should be true after generation")
        XCTAssertFalse(finalGenerating, "Should not be generating after completion")
        
        print("✅ SUCCESS: No race condition - state properly updated")
    }
}
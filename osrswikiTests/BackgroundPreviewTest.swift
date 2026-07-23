//
//  BackgroundPreviewTest.swift
//  osrswikiTests
//
//  Test to verify background preview generation system works correctly
//

import XCTest
@testable import osrswiki

@MainActor
final class BackgroundPreviewTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {}
    
    /// Test that background preview manager can generate all previews without errors
    func testBackgroundPreviewGeneration() async throws {
        print("🚀 Testing background preview generation system...")
        
        let manager = osrsBackgroundPreviewManager.shared
        
        // Clear any existing state
        manager.clearAllPreviews()
        
        // Verify initial state
        XCTAssertFalse(manager.arePreviewsReady, "Previews should not be ready initially")
        XCTAssertFalse(manager.isGeneratingPreviews, "Should not be generating initially")
        XCTAssertEqual(manager.generationProgress, 0.0, "Progress should be 0 initially")
        
        print("🔄 Starting background preview generation...")
        
        // Start background generation
        await manager.preGenerateAllPreviews()
        
        // Verify completion state
        XCTAssertTrue(manager.arePreviewsReady, "Previews should be ready after generation")
        XCTAssertFalse(manager.isGeneratingPreviews, "Should not be generating after completion")
        XCTAssertEqual(manager.generationProgress, 1.0, "Progress should be 100% after completion")
        
        print("✅ Background preview generation completed successfully!")
        
        // Test that subsequent calls don't restart generation
        let previousState = manager.arePreviewsReady
        await manager.preGenerateAllPreviews()
        XCTAssertEqual(manager.arePreviewsReady, previousState, "State should not change on subsequent calls")
        
        print("✅ Background preview generation system test passed!")
    }
    
    /// Test that ensurePreviewsGenerated works correctly
    func testEnsurePreviewsGenerated() async throws {
        print("🔄 Testing ensurePreviewsGenerated method...")
        
        let manager = osrsBackgroundPreviewManager.shared
        
        // Clear any existing state
        manager.clearAllPreviews()
        
        // Call ensurePreviewsGenerated (should start generation)
        manager.ensurePreviewsGenerated()
        
        // Wait a moment for generation to start
        try await Task.sleep(for: .milliseconds(500))
        
        // Should be generating or already complete
        let isGeneratingOrComplete = manager.isGeneratingPreviews || manager.arePreviewsReady
        XCTAssertTrue(isGeneratingOrComplete, "Should either be generating or complete after ensurePreviewsGenerated")
        
        // Wait for completion (max 30 seconds)
        var attempts = 0
        while !manager.arePreviewsReady && attempts < 60 {
            try await Task.sleep(for: .milliseconds(500))
            attempts += 1
        }
        
        XCTAssertTrue(manager.arePreviewsReady, "Previews should be ready after waiting")
        
        print("✅ ensurePreviewsGenerated test passed!")
    }
}
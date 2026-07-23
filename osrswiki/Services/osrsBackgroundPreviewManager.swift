//
//  osrsBackgroundPreviewManager.swift
//  OSRS Wiki
//
//  Background preview generation system - pre-caches all appearance previews
//  Ensures instant loading when users visit the appearance page (no latency)
//

import SwiftUI
import UIKit

/// Background preview generation manager - pre-generates all appearance previews for instant loading
@MainActor
class osrsBackgroundPreviewManager: ObservableObject {
    
    static let shared = osrsBackgroundPreviewManager()
    
    private let themeRenderer = osrsThemePreviewRenderer.shared
    private let tableRenderer = osrsTablePreviewRenderer.shared
    private let imageCache = osrsImageCache.shared
    
    // State tracking
    @Published private(set) var isGeneratingPreviews = false
    @Published private(set) var generationProgress: Double = 0.0
    @Published private(set) var previewsReady = false
    
    private init() {}
    
    /// Pre-generate all appearance previews in the background for instant loading
    func preGenerateAllPreviews() async {
        guard !isGeneratingPreviews else {
            print("🔄 Background preview generation already in progress")
            return
        }
        
        await MainActor.run {
            isGeneratingPreviews = true
            generationProgress = 0.0
            previewsReady = false
        }
        
        print("🚀 Starting background preview generation...")
        
        // Step 1: Pre-load all images for theme previews (0-30%)
        await updateProgress(0.1, "Loading news content...")
        let newsViewModel = NewsViewModel()
        await newsViewModel.loadNews()
        
        if let wikiFeed = newsViewModel.wikiFeed {
            await updateProgress(0.2, "Pre-loading images...")
            await imageCache.preloadImages(from: wikiFeed.recentUpdates)
        }
        
        await updateProgress(0.3, "Images cached")
        
        // Step 2: Generate all theme previews (30-70%)
        await generateAllThemePreviews()
        
        // Step 3: Generate all table previews (70-100%)  
        await generateAllTablePreviews()
        
        print("✅ Background preview generation complete - all previews ready for instant loading!")
    }
    
    /// Generate all theme previews (3 themes x 2 color schemes = 6 total)
    private func generateAllThemePreviews() async {
        let themes: [osrsThemeSelection] = [.automatic, .osrsLight, .osrsDark]
        let totalThemes = themes.count
        
        print("🎨 Generating theme previews...")
        
        for (index, theme) in themes.enumerated() {
            await updateProgress(0.3 + Double(index) / Double(totalThemes) * 0.4, "Generating \(theme.rawValue) preview...")
            
            // Generate preview (this will be cached automatically)
            let _ = await themeRenderer.generatePreview(for: theme)
            print("🎨 Generated theme preview: \(theme.rawValue)")
        }
        
        await updateProgress(0.7, "Theme previews complete")
    }
    
    /// Generate all table previews (2 states x 2 themes = 4 total)
    private func generateAllTablePreviews() async {
        let themes: [any osrsThemeProtocol] = [osrsLightTheme(), osrsDarkTheme()]
        let states = [true, false] // collapsed, expanded
        let totalCombinations = themes.count * states.count
        
        print("📊 Generating table previews...")
        
        var completedCount = 0
        for theme in themes {
            for collapsed in states {
                let description = "\(collapsed ? "collapsed" : "expanded") \(theme.name)"
                await updateProgress(0.7 + Double(completedCount) / Double(totalCombinations) * 0.3, "Generating \(description)...")
                
                // Generate table preview (this will be cached automatically)
                let _ = await tableRenderer.generateTablePreview(collapsed: collapsed, theme: theme)
                print("📊 Generated table preview: \(description)")
                
                completedCount += 1
            }
        }
        
        await updateProgress(1.0, "All previews ready")
        
        // CRITICAL: Set previewsReady flag AFTER all generation is complete
        await MainActor.run {
            previewsReady = true
            isGeneratingPreviews = false
        }
        
        print("✅ Background preview generation complete - previewsReady flag set to true")
    }
    
    /// Update generation progress and status
    private func updateProgress(_ progress: Double, _ status: String) async {
        await MainActor.run {
            generationProgress = progress
        }
        print("🔄 Progress: \(Int(progress * 100))% - \(status)")
    }
    
    /// Check if all previews are ready for instant loading
    var arePreviewsReady: Bool {
        return previewsReady
    }
    
    /// Start background generation if not already done (safe to call multiple times)
    func ensurePreviewsGenerated() {
        guard !previewsReady && !isGeneratingPreviews else { return }
        
        Task {
            await preGenerateAllPreviews()
        }
    }
    
    /// Clear all cached previews and reset state
    func clearAllPreviews() {
        themeRenderer.clearCache()
        imageCache.clearCache()
        
        isGeneratingPreviews = false
        generationProgress = 0.0
        previewsReady = false
        
        print("🗑️ All preview caches cleared")
    }
}
//
//  osrsPreviewContentSource.swift
//  OSRS Wiki
//
//  iOS equivalent to Android's CompositePreviewSource
//  Provides real content for preview generation using smart fallback strategy
//

import SwiftUI
import Combine

/// Protocol for providing preview content (like Android's PreviewSource)
protocol osrsPreviewContentSource {
    func getPreviewContent() async -> osrsPreviewContent?
}

/// Container for preview content (like Android's unified content structure)
struct osrsPreviewContent {
    let wikiFeed: WikiFeed?
    let newsItems: [NewsItem]
    let hasValidContent: Bool
    
    static let empty = osrsPreviewContent(
        wikiFeed: nil,
        newsItems: [],
        hasValidContent: false
    )
}

/// Main content source with fallback strategy (like Android's CompositePreviewSource)
@MainActor
class osrsCompositePreviewSource: osrsPreviewContentSource {
    private let newsRepository = NewsRepository.shared
    private var cachedContent: osrsPreviewContent?
    
    /// Get preview content using smart fallback strategy like Android
    func getPreviewContent() async -> osrsPreviewContent? {
        print("📰 CompositePreviewSource: Getting preview content...")
        
        // 1. Try live repository data (Android's RepositoryFallbackSource)
        if let repositoryContent = await tryRepositoryContent() {
            print("📰 CompositePreviewSource: Using repository content")
            cachedContent = repositoryContent
            return repositoryContent
        }
        
        // 2. Try cached content if available
        if let cached = cachedContent, cached.hasValidContent {
            print("📰 CompositePreviewSource: Using cached content")
            return cached
        }
        
        // 3. Create minimal fallback content (Android's last resort)
        print("📰 CompositePreviewSource: Using fallback content")
        return createFallbackContent()
    }
    
    /// Try to get content from repository (like Android's RepositoryFallbackSource)
    private func tryRepositoryContent() async -> osrsPreviewContent? {
        do {
            // Use NewsRepository directly like the real app
            print("📰 Loading real content from NewsRepository...")
            
            // Create a NewsViewModel to load content properly
            let viewModel = NewsViewModel()
            await viewModel.loadNews()
            
            // Check if we got valid content
            if let wikiFeed = viewModel.wikiFeed, !wikiFeed.recentUpdates.isEmpty {
                print("📰 Successfully loaded \(wikiFeed.recentUpdates.count) updates")
                return osrsPreviewContent(
                    wikiFeed: wikiFeed,
                    newsItems: viewModel.newsItems,
                    hasValidContent: true
                )
            } else {
                print("📰 Repository returned empty content")
                return nil
            }
        } catch {
            print("📰 Repository loading failed: \(error)")
            return nil
        }
    }
    
    /// Create fallback content as last resort (like Android's minimal placeholder)
    private func createFallbackContent() -> osrsPreviewContent {
        // Create placeholder content for preview generation only
        let fallbackUpdates = [
            UpdateItem(
                title: "Sample Update",
                snippet: "Preview placeholder content for background generation",
                imageUrl: "https://via.placeholder.com/280x140/4A90E2/FFFFFF?text=Preview",
                articleUrl: "about:blank"
            )
        ]
        
        let fallbackAnnouncements = [
            AnnouncementItem(
                date: "Recent",
                content: "Preview placeholder announcement"
            )
        ]
        
        let fallbackPopular = [
            PopularPageItem(title: "Sample Page", pageUrl: "about:blank")
        ]
        
        let fallbackFeed = WikiFeed(
            recentUpdates: fallbackUpdates,
            announcements: fallbackAnnouncements,
            onThisDay: OnThisDayItem(
                title: "On this day",
                events: ["Previous updates and milestones"]
            ),
            popularPages: fallbackPopular
        )
        
        return osrsPreviewContent(
            wikiFeed: fallbackFeed,
            newsItems: [],
            hasValidContent: true
        )
    }
    
    /// Pre-load content for background generation (like Android's PreviewGenerationManager)
    func preloadContent() async {
        print("📰 Pre-loading content for background generation...")
        cachedContent = await getPreviewContent()
    }
}

// REMOVED: osrsNewsViewWithPreloadedContent duplicate - using real NewsView from NewsView.swift instead

// REMOVED: PreviewUpdateCardView duplicate - using real UpdateCardView from NewsView.swift instead

// REMOVED: PreviewUpdateCardView duplicate - using real UpdateCardView from NewsView.swift instead
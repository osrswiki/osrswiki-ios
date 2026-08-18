//
//  NewsViewModel.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import Combine
import UIKit // For haptic feedback

@MainActor
class NewsViewModel: ObservableObject {
    @Published var wikiFeed: WikiFeed?
    @Published var newsItems: [NewsItem] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String?
    
    private let newsRepository = NewsRepository.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Expose repository for cache validation in View
    var repository: NewsRepository {
        return newsRepository
    }
    
    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedHomeFeedForUITests") {
            newsRepository.seedHomeFeedForSpecConformanceTests()
        }
#endif
        // Initialize with cached data if available - SYNCHRONOUSLY for instant display
        loadCachedDataSynchronously()
    }
    
    private func loadCachedDataSynchronously() {
        // Use synchronous cache access to eliminate race condition
        if let cachedFeed = newsRepository.getCachedFeedSynchronously() {
            self.wikiFeed = cachedFeed
        }
    }
    
    func loadNews(forceRefresh: Bool = false) async {
        // Check if we have valid cached data and don't need to load
        if !forceRefresh && newsRepository.isCacheValid && wikiFeed != nil {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch the WikiFeed from repository (which handles caching)
            let fetchedFeed = try await newsRepository.fetchWikiFeed(forceRefresh: forceRefresh)
            self.wikiFeed = fetchedFeed
            
            // Still keep newsItems for backwards compatibility
            newsItems = newsRepository.transformFeedToNewsItems(fetchedFeed)
            
            // Clear any previous error message on successful load
            errorMessage = nil
        } catch let networkError as NetworkError {
            errorMessage = networkError.userMessage
            
            // Only clear data if we have no cached data to fall back on
            if !newsRepository.isCacheValid {
                newsItems = []
                wikiFeed = nil
            }
        } catch {
            errorMessage = UserFacingError.message(for: error, fallback: "Home could not be loaded. Please try again.")
            
            // Only clear data if we have no cached data to fall back on
            if !newsRepository.isCacheValid {
                newsItems = []
                wikiFeed = nil
            }
        }
        
        isLoading = false
    }
    
    func refresh() async {
        // Mark refresh attempt immediately - provides UX feedback even if request gets cancelled
        newsRepository.markRefreshAttempt()
        
        // Add haptic feedback to confirm refresh started
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
        
        isRefreshing = true
        
        await loadNews(forceRefresh: true)
        
        // Success haptic feedback (if no error occurred)
        if errorMessage == nil {
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
        } else {
            // Error haptic feedback for failures
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
        }
        
        // Remove artificial delay - let natural timing show refresh duration
        isRefreshing = false
    }
}

// MARK: - Models
struct NewsItem: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let content: String?
    let imageUrl: URL?
    let publishedDate: Date
    let category: NewsCategory
    let url: URL?
    
    enum NewsCategory: String, Codable, CaseIterable {
        case update = "update"
        case announcement = "announcement"
        case popular = "popular"
        case onThisDay = "on_this_day"
        
        var displayName: String {
            switch self {
            case .update:
                return "Game Update"
            case .announcement:
                return "Announcement"
            case .popular:
                return "Popular"
            case .onThisDay:
                return "On This Day"
            }
        }
        
        var iconName: String {
            switch self {
            case .update:
                return "gamecontroller.fill"
            case .announcement:
                return "megaphone.fill"
            case .popular:
                return "flame.fill"
            case .onThisDay:
                return "calendar.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .update:
                return .blue
            case .announcement:
                return .orange
            case .popular:
                return .red
            case .onThisDay:
                return .purple
            }
        }
    }
}

struct NewsCardView: View {
    let newsItem: NewsItem
    let onReadMore: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category and date
            HStack {
                Label(newsItem.category.displayName, 
                      systemImage: newsItem.category.iconName)
                    .font(.caption)
                    .foregroundStyle(.osrsAccent)
                
                Spacer()
                
                Text(newsItem.publishedDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.osrsTextSecondary)
            }
            
            // Image if available
            if let imageUrl = newsItem.imageUrl {
                AsyncImage(url: imageUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.osrsSurfaceVariant)
                        .overlay(
                            ProgressView()
                                .tint(Color.osrsAccentColor)
                        )
                }
                .frame(height: 180)
                .clipped()
                .cornerRadius(8)
            }
            
            // Title and summary
            VStack(alignment: .leading, spacing: 8) {
                Text(newsItem.title)
                    .font(.osrsTitle)
                    .foregroundStyle(.osrsOnSurface)
                    .lineLimit(3)
                
                Text(newsItem.summary)
                    .font(.osrsBody)
                    .foregroundStyle(.osrsTextSecondary)
                    .lineLimit(4)
            }
            
            // Read more button
            HStack {
                Spacer()
                
                Button("Read More") {
                    onReadMore()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.osrsAccent)
            }
        }
        .padding()
        .background(.osrsSurface)
        .cornerRadius(12)
    }
}

// MARK: - Wiki Feed Data Models (matching Android structure)

struct WikiFeed: Sendable {
    let recentUpdates: [UpdateItem]
    let announcements: [AnnouncementItem]
    let onThisDay: OnThisDayItem?
    let popularPages: [PopularPageItem]
}

struct UpdateItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let snippet: String
    let imageUrl: String
    let articleUrl: String
}

struct AnnouncementItem: Identifiable, Sendable {
    let id = UUID()
    let date: String
    let content: String
}

struct OnThisDayItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let events: [String]
}

struct PopularPageItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let pageUrl: String
}

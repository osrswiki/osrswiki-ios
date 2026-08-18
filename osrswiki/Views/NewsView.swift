//
//  NewsView.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import UIKit

enum osrsHomeFeedArticleLinkExtractor {
    struct Link: Identifiable, Hashable {
        let url: URL
        let label: String

        var id: String { "\(url.absoluteString)|\(label)" }
    }

    nonisolated static func links(in html: String) -> [Link] {
        let pattern = #"<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let baseURL = URL(string: "https://oldschool.runescape.wiki/")!
        var seen: Set<String> = []
        var result: [Link] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            where match.numberOfRanges > 2 {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else { continue }
            let rawHref = String(html[hrefRange]).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: rawHref, relativeTo: baseURL)?.absoluteURL else { continue }
            let label = osrsStringUtils.plainText(fromHTML: String(html[labelRange]))
            let key = "\(url.absoluteString)|\(label)"
            guard seen.insert(key).inserted else { continue }
            result.append(Link(url: url, label: label.isEmpty ? "Open article" : label))
        }
        return result
    }

    nonisolated static func internalArticleURLs(in html: String) -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []
        for link in links(in: html) {
            guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: link.url),
                  seen.insert(articleURL).inserted else {
                continue
            }
            result.append(articleURL)
        }
        return result
    }
}

/// Avoids attributed hyperlinks inside feed rows. On iOS 26 those links can form a
/// cyclic accessibility layout graph when a horizontal card is snapshotted. The
/// visible prose stays plain, while every authored link remains a native button.
private struct osrsHomeFeedLinkedText: View {
    let html: String
    let prefix: String
    let onLinkTap: (URL) -> Void

    init(_ html: String, prefix: String = "", onLinkTap: @escaping (URL) -> Void) {
        self.html = html
        self.prefix = prefix
        self.onLinkTap = onLinkTap
    }

    private var links: [osrsHomeFeedArticleLinkExtractor.Link] {
        osrsHomeFeedArticleLinkExtractor.links(in: html)
    }

    private var text: String {
        prefix + osrsStringUtils.plainText(fromHTML: html)
    }

    var body: some View {
        if links.isEmpty {
            Text(text)
        } else if links.count == 1, let link = links.first {
            Button(action: { onLinkTap(link.url) }) {
                Text(text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(link.label)")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                ForEach(links) { link in
                    Button(action: { onLinkTap(link.url) }) {
                        Label(link.label, systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.osrsLink)
                }
            }
        }
    }
}

struct NewsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @StateObject private var viewModel = NewsViewModel()
    @State private var randomPageUrl: URL?
    @State private var randomPrewarmOwner = UUID()

    private var homeGlassAccessory: some View {
        osrsTabSearchWithTrailingControl(
            search: osrsSearchLauncher(
                placeholder: "Search OSRS Wiki",
                accessibilityIdentifier: "home_search",
                voiceAccessibilityIdentifier: "home_voice_search",
                speechState: appState.speechManager.currentState,
                onSearchTap: { appState.navigateToActiveSearch(startsVoiceRecognition: false) },
                onVoiceTap: {
                    appState.navigateToActiveSearch(startsVoiceRecognition: true)
                }
            )
        ) {
            osrsGlassIconButton(
                systemImage: "shuffle",
                accessibilityLabel: "Random page",
                accessibilityIdentifier: "home_random_page",
                action: handleRandomPageClick
            )
        }
        .onAppear {
            if randomPageUrl == nil {
                preloadNextRandomPage()
            }
        }
    }
    
    var body: some View {
        // DIAGNOSTIC: Log NavigationStack state for NewsView (WORKING REFERENCE)
        let _ = print("🔍 NEWSVIEW: NavigationStack rendering with newsNavigationStack.count = \(appState.newsNavigationStack.count)")
        let _ = appState.newsNavigationStack.isEmpty ? print("🔍 NEWSVIEW: newsNavigationStack is EMPTY") : print("🔍 NEWSVIEW: newsNavigationStack contents: \(appState.newsNavigationStack)")
        
        return NavigationStack(path: $appState.newsNavigationStack) {
            VStack(spacing: 0) {
                    osrsAccessibilityMarker(identifier: "home_screen", label: "Home screen")

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Refresh indicator (shown above content during refresh)
                            if viewModel.isRefreshing {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Refreshing...")
                                        .font(.osrsCaption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.osrsPrimaryColor.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                            }

                            // Show content if available (prioritize cached content over loading states)
                            if let wikiFeed = viewModel.wikiFeed {
                                WikiFeedContentView(wikiFeed: wikiFeed, appState: appState, viewModel: viewModel)
                            } else if let errorMessage = viewModel.errorMessage {
                                ErrorStateView(errorMessage: errorMessage, viewModel: viewModel, appState: appState)
                            } else if viewModel.isLoading {
                                ProgressView("Loading news...")
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .tint(.osrsPrimaryColor)
                                    .frame(maxWidth: .infinity, minHeight: 200)
                            } else {
                                EmptyStateView(
                                    iconName: "newspaper",
                                    title: "No News Available",
                                    subtitle: "Check back later for OSRS updates"
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                    .refreshable {
                        // Use Task wrapping to prevent SwiftUI cancellation when user releases gesture early
                        // This follows community best practices for robust pull-to-refresh implementation
                        await Task {
                            await viewModel.refresh()
                        }.value
                    }
                    .accessibilityIdentifier("home_feed_scroll")
                    .scrollPosition($appState.newsFeedScrollPosition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("")
            .navigationBarHidden(true)
            .background(.osrsBackground)
            .osrsTabGlassAccessoryBar {
                homeGlassAccessory
            }
            .ignoresSafeArea(.keyboard) // Prevent layout adjustment during keyboard appearance in child views
            .onReceive(appState.$newsNavigationStack) { stack in
                print("🔍 NEWSVIEW: NavigationStack path changed - new count: \(stack.count)")
                if !stack.isEmpty {
                    print("🔍 NEWSVIEW: Latest navigation destination: \(stack.last!)")
                }
            }
            .navigationDestination(for: NewsNavigationDestination.self) { destination in
                switch destination {
                case .search:
                    ImmediateStyledSearchView(
                        appState: appState,
                        themeManager: themeManager,
                        theme: osrsTheme
                    )
                    .onAppear {
                        print("🎯 NEWSVIEW: navigationDestination TRIGGERED! Processing: \(destination)")
                        print("🎯 NEWSVIEW: Creating ImmediateStyledSearchView")
                        print("✅ NEWSVIEW: ImmediateStyledSearchView.onAppear - Search view successfully created!")
                    }
                case .article(let articleDestination):
                    ArticleView(
                        pageTitle: articleDestination.title, 
                        pageUrl: articleDestination.url,
                        navigationIdentity: articleDestination.navigationIdentity,
                        snippet: articleDestination.snippet,
                        thumbnailUrl: articleDestination.thumbnailUrl
                    )
                    .id(articleDestination.navigationIdentity)
                    .environmentObject(appState)
                    .environment(\.osrsTheme, osrsTheme)
                    .onAppear {
                        print("🎯 NEWSVIEW: navigationDestination TRIGGERED! Processing: \(destination)")
                        print("🎯 NEWSVIEW: Creating ArticleView with:")
                        print("  - title: \(articleDestination.title ?? "nil")")
                        print("  - url: \(articleDestination.url)")
                        print("  - snippet: \(articleDestination.snippet ?? "nil")")
                        print("  - thumbnailUrl: \(articleDestination.thumbnailUrl?.absoluteString ?? "nil")")
                        print("✅ NEWSVIEW: ArticleView.onAppear - ArticleView successfully created and appeared!")
                    }
                    .onDisappear {
                        print("❌ NEWSVIEW: ArticleView.onDisappear - ArticleView disappeared")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            // Only load if we don't have any cached data available
            // The synchronous cache loading in init() should have populated wikiFeed if cache exists
            // This prevents unnecessary loading when returning to home tab with valid cache
            if viewModel.wikiFeed == nil {
                print("📱 NewsView.task: No cached content available, loading fresh data")
                await viewModel.loadNews()
            } else {
                print("📱 NewsView.task: Cached content available, skipping load")
            }
        }
    }

    private func handleRandomPageClick() {
        if let url = randomPageUrl {
            appState.navigateToArticle(url: url)
            preloadNextRandomPage()
        } else {
            preloadNextRandomPage()
        }
    }

    private func preloadNextRandomPage() {
        let retiringOwner = randomPrewarmOwner
        randomPrewarmOwner = UUID()
        let nextOwner = randomPrewarmOwner
        Task {
            await osrsArticleDocumentCoordinator.shared.cancelPrewarm(owner: retiringOwner)
            let result = await osrsRandomPageRepository.shared.getRandomPage()
            await MainActor.run {
                switch result {
                case .success(let pageTitle):
                    let pageUrlString = "https://oldschool.runescape.wiki/w/\(pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pageTitle)"
                    randomPageUrl = URL(string: pageUrlString)
                case .failure:
                    randomPageUrl = nil
                }
            }
            guard let url = await MainActor.run(body: { randomPageUrl }) else { return }
            let renderOptions = await MainActor.run {
                osrsArticleRenderOptions(
                    usesDarkTheme: themeManager.currentTheme is osrsDarkTheme,
                    collapseTablesEnabled: themeManager.collapseTables,
                    articleTextScale: Double(themeManager.articleTextScale)
                )
            }
            _ = await osrsArticleDocumentCoordinator.shared.startPrewarm(
                owner: nextOwner,
                request: osrsArticleDocumentRequest(pageURL: url, pageTitle: nil),
                renderOptions: renderOptions,
                conditions: osrsArticlePrewarmConditions.current(isOfflineContentAvailable: false)
            )
        }
    }
}

struct EmptyStateView: View {
    let iconName: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(.osrsPlaceholderColor)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.osrsHeadline)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text(subtitle)
                    .font(.osrsBody)
                    .foregroundStyle(.osrsSecondaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Content Section Views

struct WikiFeedContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let wikiFeed: WikiFeed
    let appState: AppState
    let viewModel: NewsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            osrsAccessibilityMarker(identifier: "home_feed_content", label: "Home feed content")

            // Recent Updates section (horizontal scrolling)
            if !wikiFeed.recentUpdates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Header with last updated timestamp
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Updates")
                            .font(.osrsSectionHeaderSmallCaps)
                            .dynamicTypeSize(.xSmall ... .xLarge)
                            .foregroundStyle(.osrsOnSurface)
                            .kerning(0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("home_updates_section")
                        
                        Text("Last updated: \(viewModel.repository.lastUpdatedString)")
                            .font(.caption)
                            .dynamicTypeSize(.xSmall ... .accessibility2)
                            .foregroundStyle(.osrsPrimaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(wikiFeed.recentUpdates) { update in
                                UpdateCardView(updateItem: update) {
                                    if !update.articleUrl.isEmpty,
                                       let url = URL(string: update.articleUrl) {
                                        appState.navigateToArticle(
                                            title: update.title,
                                            url: url,
                                            snippet: update.snippet,
                                            thumbnailUrl: URL(string: update.imageUrl)
                                        )
                                    }
                                }
                                .zIndex(1)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .accessibilityIdentifier("home_updates_carousel")
                }
                .padding(.vertical, 8)
            }
            
            // Announcements section (show only first like Android)
            if let firstAnnouncement = wikiFeed.announcements.first {
                AnnouncementCardView(announcementItem: firstAnnouncement) { url in
                    if let articleUrl = URL(string: url) {
                        appState.navigateToArticle(url: articleUrl)
                    }
                }
            }
            
            // On This Day section
            if let onThisDay = wikiFeed.onThisDay {
                OnThisDayCardView(onThisDayItem: onThisDay) { url in
                    if let articleUrl = URL(string: url) {
                        appState.navigateToArticle(url: articleUrl)
                    }
                }
            }
            
            // Popular Pages section
            if !wikiFeed.popularPages.isEmpty {
                PopularPagesCardView(popularPages: wikiFeed.popularPages) { url in
                    if let articleUrl = URL(string: url) {
                        appState.navigateToArticle(url: articleUrl)
                    }
                }
            }
        }
    }
}

struct ErrorStateView: View {
    let errorMessage: String
    let viewModel: NewsViewModel
    let appState: AppState
    
    var body: some View {
        if viewModel.wikiFeed == nil {
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("Unable to Load News")
                    .font(.osrsHeadline)
                    .foregroundStyle(.osrsOnBackground)
                
                Text(errorMessage)
                    .font(.osrsBody)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Try Again") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.osrsPrimaryColor)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            // If we have cached content, show it with error banner
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Using cached content - refresh failed")
                        .font(.osrsCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .font(.osrsCaption)
                    .foregroundColor(.osrsPrimaryColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                
                // Show cached content
                WikiFeedContentView(wikiFeed: viewModel.wikiFeed!, appState: appState, viewModel: viewModel)
            }
        }
    }
}

struct UpdateCardView: View {
    let updateItem: UpdateItem
    let onTap: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.osrsPreviewMode) private var isPreviewMode
    @ObservedObject private var imageCache = osrsImageCache.shared
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image section - use cached images in preview mode, AsyncImage otherwise
                Group {
                    if isPreviewMode, let cachedImage = imageCache.getCachedImage(for: updateItem.imageUrl) {
                        // Preview mode: use pre-loaded cached image for reliable rendering
                        Image(uiImage: cachedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        AsyncImage(url: URL(string: updateItem.imageUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.7, green: 0.6, blue: 0.4), Color(red: 0.5, green: 0.4, blue: 0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 24, weight: .medium))
                                                .foregroundStyle(.white)
                                            Text("OSRS")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                    )
                            case .empty:
                                Rectangle()
                                    .fill(.osrsSurfaceVariant)
                                    .overlay(
                                        ProgressView()
                                            .tint(Color.osrsAccentColor)
                                    )
                            @unknown default:
                                Rectangle()
                                    .fill(.osrsSurfaceVariant)
                            }
                        }
                    }
                }
                .frame(width: cardWidth, height: imageHeight)
                .clipped()
                
                // Content section
                VStack(alignment: .leading, spacing: contentSpacing) {
                    Text(osrsStringUtils.extractMainTitle(updateItem.title))
                        .font(titleFont)
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    
                    Text(osrsStringUtils.plainText(fromHTML: updateItem.snippet))
                        .font(snippetFont)
                        .foregroundStyle(.osrsOnSurface)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(height: contentHeight, alignment: .top)
                .clipped()
            }
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .background(.osrsSurfaceVariant)
        .cornerRadius(8)
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("home_update_card")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .osrsPrewarmArticleWhenVisible(
            pageURL: URL(string: updateItem.articleUrl),
            pageTitle: updateItem.title
        )
    }

    private var cardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? min(UIScreen.main.bounds.width - 32, 398) : osrsRecentUpdateCardMetrics.standardWidth
    }

    private var cardHeight: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : osrsRecentUpdateCardMetrics.standardHeight
    }

    private var imageHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? osrsRecentUpdateCardMetrics.accessibilityImageHeight : osrsRecentUpdateCardMetrics.standardImageHeight
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 8 : osrsRecentUpdateCardMetrics.standardContentSpacing
    }

    private var contentHeight: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : osrsRecentUpdateCardMetrics.standardContentHeight
    }

    private var titleFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .headline.weight(.bold) : .osrsListTitleBold
    }

    private var snippetFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .body : .osrsBodyMedium
    }

    private var accessibilityLabel: String {
        let title = osrsStringUtils.extractMainTitle(updateItem.title)
        let snippet = osrsStringUtils.plainText(fromHTML: updateItem.snippet)
        return "\(title), \(snippet)"
    }
}

private enum osrsRecentUpdateCardMetrics {
    static let standardWidth: CGFloat = 280
    static let standardHeight: CGFloat = 228
    static let standardImageHeight: CGFloat = 140
    static let standardContentHeight: CGFloat = standardHeight - standardImageHeight
    static let accessibilityImageHeight: CGFloat = 120
    static let standardContentSpacing: CGFloat = 4
}

struct AnnouncementCardView: View {
    let announcementItem: AnnouncementItem
    let onLinkTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Announcements")
                .font(.osrsSectionHeaderSmallCaps)
                .foregroundStyle(.osrsOnSurface)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("home_announcements_section")
            
            // Card content
            VStack(alignment: .leading, spacing: 16) {
                osrsHomeFeedLinkedText(
                    announcementItem.content,
                    prefix: "\(announcementItem.date): "
                ) { url in
                    onLinkTap(url.absoluteString)
                }
                .font(.osrsBody)
                .foregroundStyle(.osrsOnSurface)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.osrsSurfaceVariant)
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .osrsPrewarmArticlesWhenVisible(pageURLs: prewarmArticleURLs)
    }

    private var prewarmArticleURLs: [URL] {
        osrsHomeFeedArticleLinkExtractor.internalArticleURLs(in: announcementItem.content)
    }
}

struct OnThisDayCardView: View {
    let onThisDayItem: OnThisDayItem
    let onLinkTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(osrsStringUtils.extractMainTitle(onThisDayItem.title))
                .font(.osrsSectionHeaderSmallCaps)
                .foregroundStyle(.osrsOnSurface)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("home_on_this_day_section")
            
            // Card content
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(onThisDayItem.events.enumerated()), id: \.offset) { index, event in
                    OnThisDayEventView(event: event) { url in
                        onLinkTap(url.absoluteString)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.osrsSurfaceVariant)
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

struct PopularPagesCardView: View {
    let popularPages: [PopularPageItem]
    let onLinkTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Popular pages")
                .font(.osrsSectionHeaderSmallCaps)
                .foregroundStyle(.osrsOnSurface)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("home_popular_pages_section")
            
            // Card content
            VStack(alignment: .leading, spacing: 8) {
                ForEach(popularPages) { page in
                    Button(action: { onLinkTap(page.pageUrl) }) {
                        Text(osrsStringUtils.extractMainTitle(page.title))
                            .osrsLinkText(fontSize: 16) // Apply heavier font weight to popular page links
                            .foregroundStyle(.osrsLink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .osrsPrewarmArticleWhenVisible(
                        pageURL: URL(string: page.pageUrl),
                        pageTitle: page.title
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.osrsSurfaceVariant)
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - On This Day Event View

/// Specialized view for "On This Day" events that applies monospace to years
struct OnThisDayEventView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let event: String
    let onLinkTap: (URL) -> Void
    
    var body: some View {
        osrsHomeFeedLinkedText(event, prefix: "• ") { url in
            onLinkTap(url)
        }
        .font(.osrsBody)
        .foregroundStyle(.osrsOnSurface)
        .lineLimit(1)
        .truncationMode(.tail)
        .osrsPrewarmArticlesWhenVisible(pageURLs: prewarmArticleURLs)
    }

    private var prewarmArticleURLs: [URL] {
        osrsHomeFeedArticleLinkExtractor.internalArticleURLs(in: event)
    }
}

/// Specialized HTMLTextView that applies monospace font to year patterns
struct MonospaceYearHTMLTextView: View {
    let htmlString: String
    let onLinkTap: ((URL) -> Void)?
    
    init(_ htmlString: String, onLinkTap: ((URL) -> Void)? = nil) {
        self.htmlString = htmlString
        self.onLinkTap = onLinkTap
    }
    
    var body: some View {
        if let attributedString = parseHTMLWithMonospaceYears(htmlString) {
            Text(AttributedString(attributedString))
                .environment(\.openURL, OpenURLAction { url in
                    if let onLinkTap = onLinkTap {
                        onLinkTap(url)
                        return .handled
                    }
                    return .systemAction
                })
        } else {
            Text(htmlString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        }
    }
    
    private func parseHTMLWithMonospaceYears(_ htmlString: String) -> NSAttributedString? {
        // For non-HTML text, create attributed string directly
        if !htmlString.contains("<") {
            let attributedString = NSMutableAttributedString(string: htmlString)
            let range = NSRange(location: 0, length: attributedString.length)
            
            // Apply base styling with theme-aware colors
            let systemFont = UIFont.systemFont(ofSize: 16)
            attributedString.addAttribute(.font, value: systemFont, range: range)
            // Use theme-aware text color instead of system label
            let textColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(red: 244/255, green: 234/255, blue: 234/255, alpha: 1.0) // osrs_text_light_alt
                } else {
                    return UIColor(red: 58/255, green: 46/255, blue: 28/255, alpha: 1.0) // osrs_text_dark
                }
            }
            attributedString.addAttribute(.foregroundColor, value: textColor, range: range)
            
            // Apply monospace to year and dash pattern
            let text = attributedString.string
            do {
                let yearDashPattern = try NSRegularExpression(pattern: "^(• \\d{4} – )")
                let matches = yearDashPattern.matches(in: text, range: NSRange(location: 0, length: text.count))
                
                for match in matches {
                    let monoFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
                    attributedString.addAttribute(.font, value: monoFont, range: match.range)
                }
            } catch {
                print("Error applying monospace pattern: \(error)")
            }
            
            return attributedString
        }
        
        // For HTML content, parse normally
        guard let data = htmlString.data(using: .utf8) else { return nil }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        do {
            let attributedString = try NSMutableAttributedString(data: data, options: options, documentAttributes: nil)
            
            // Override HTML fonts and colors with theme-aware styling
            let range = NSRange(location: 0, length: attributedString.length)
            let systemFont = UIFont.systemFont(ofSize: 16)
            
            // Remove existing attributes and apply base styling with theme-aware colors
            attributedString.removeAttribute(.font, range: range)
            attributedString.removeAttribute(.foregroundColor, range: range)
            attributedString.addAttribute(.font, value: systemFont, range: range)
            // Use theme-aware text color instead of system label
            let textColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(red: 244/255, green: 234/255, blue: 234/255, alpha: 1.0) // osrs_text_light_alt
                } else {
                    return UIColor(red: 58/255, green: 46/255, blue: 28/255, alpha: 1.0) // osrs_text_dark
                }
            }
            attributedString.addAttribute(.foregroundColor, value: textColor, range: range)
            
            // Fix link colors
            attributedString.enumerateAttribute(.link, in: range) { value, linkRange, _ in
                if value != nil {
                    // Use a theme-aware link color
                    let linkColor = UIColor { traitCollection in
                        if traitCollection.userInterfaceStyle == .dark {
                            return UIColor(red: 183/255, green: 157/255, blue: 126/255, alpha: 1.0) // osrs link color dark
                        } else {
                            return UIColor(red: 147/255, green: 96/255, blue: 57/255, alpha: 1.0) // osrs link color light
                        }
                    }
                    attributedString.addAttribute(.foregroundColor, value: linkColor, range: linkRange)
                    
                    // Apply medium font weight to make links heavier (iOS-Android consistency)
                    let mediumFont = UIFont.systemFont(ofSize: 16, weight: .medium)
                    attributedString.addAttribute(.font, value: mediumFont, range: linkRange)
                }
            }
            
            // Apply monospace to year pattern
            let text = attributedString.string
            do {
                let yearDashPattern = try NSRegularExpression(pattern: "^(• \\d{4} – )")
                let matches = yearDashPattern.matches(in: text, range: NSRange(location: 0, length: text.count))
                
                for match in matches {
                    let monoFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
                    attributedString.addAttribute(.font, value: monoFont, range: match.range)
                }
            } catch {
                print("Error applying monospace pattern: \(error)")
            }
            
            return attributedString
        } catch {
            print("Error parsing HTML: \(error)")
            return nil
        }
    }
}

// MARK: - HTML Content Helper

struct HTMLTextView: View {
    let htmlString: String
    let onLinkTap: ((URL) -> Void)?
    
    init(_ htmlString: String, onLinkTap: ((URL) -> Void)? = nil) {
        self.htmlString = htmlString
        self.onLinkTap = onLinkTap
    }
    
    var body: some View {
        if let attributedString = parseHTML(htmlString) {
            Text(AttributedString(attributedString))
                .environment(\.openURL, OpenURLAction { url in
                    if let onLinkTap = onLinkTap {
                        onLinkTap(url)
                        return .handled
                    }
                    return .systemAction
                })
        } else {
            Text(htmlString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        }
    }
    
    private func parseHTML(_ htmlString: String) -> NSAttributedString? {
        guard let data = htmlString.data(using: .utf8) else { return nil }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        do {
            let attributedString = try NSMutableAttributedString(data: data, options: options, documentAttributes: nil)
            
            // Override HTML colors with theme-aware styling and let SwiftUI apply Dynamic Type fonts.
            let range = NSRange(location: 0, length: attributedString.length)
            
            // Remove any existing font and color attributes
            attributedString.removeAttribute(.font, range: range)
            attributedString.removeAttribute(.foregroundColor, range: range)
            
            // Use theme-aware text color instead of system label
            let textColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(red: 244/255, green: 234/255, blue: 234/255, alpha: 1.0) // osrs_text_light_alt
                } else {
                    return UIColor(red: 58/255, green: 46/255, blue: 28/255, alpha: 1.0) // osrs_text_dark
                }
            }
            attributedString.addAttribute(.foregroundColor, value: textColor, range: range)
            
            // Fix link colors to use theme colors
            attributedString.enumerateAttribute(.link, in: range) { value, linkRange, _ in
                if value != nil {
                    // Use theme-aware link color matching OSRS theme
                    let linkColor = UIColor { traitCollection in
                        if traitCollection.userInterfaceStyle == .dark {
                            return UIColor(red: 183/255, green: 157/255, blue: 126/255, alpha: 1.0) // osrs link color dark
                        } else {
                            return UIColor(red: 147/255, green: 96/255, blue: 57/255, alpha: 1.0) // osrs link color light
                        }
                    }
                    attributedString.addAttribute(.foregroundColor, value: linkColor, range: linkRange)
                }
            }
            
            return attributedString
        } catch {
            print("Error parsing HTML: \(error)")
            return nil
        }
    }
}

// MARK: - Preview-Optimized NewsView

/// Static NewsView that takes WikiFeed data directly (no ObservableObject) to avoid UIHostingController update issues
struct StaticNewsView: View {
    let wikiFeed: WikiFeed
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        NavigationStack(path: $appState.newsNavigationStack) {
            VStack(spacing: 0) {
                    osrsSearchLauncher(
                        placeholder: "Search OSRS Wiki",
                        accessibilityIdentifier: "home_search",
                        voiceAccessibilityIdentifier: "home_voice_search",
                        speechState: appState.speechManager.currentState,
                        onSearchTap: { appState.navigateToActiveSearch(startsVoiceRecognition: false) },
                        onVoiceTap: {
                            appState.navigateToActiveSearch(startsVoiceRecognition: true)
                        }
                    )
                    .osrsTabSearchLauncherLayout()

                    ScrollView {
                        LazyVStack(spacing: 12) {
                        
                        // Feed content matching Android structure - using STATIC data (no @Published dependencies)
                        let _ = print("🔍 StaticNewsView rendering with \(wikiFeed.recentUpdates.count) updates, \(wikiFeed.announcements.count) announcements")
                        
                        // Recent Updates section (horizontal scrolling)
                        if !wikiFeed.recentUpdates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Updates")
                                    .font(.osrsSectionHeaderSmallCaps)
                                    .foregroundStyle(.osrsOnSurface)
                                    .textCase(.uppercase)
                                    .kerning(0.5)
                                    .padding(.horizontal, 16)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(wikiFeed.recentUpdates) { update in
                                            UpdateCardView(updateItem: update) {
                                                // Navigate to article
                                                if !update.articleUrl.isEmpty {
                                                    appState.navigateToArticle(
                                                        title: update.title,
                                                        url: URL(string: update.articleUrl)!,
                                                        snippet: update.snippet,
                                                        thumbnailUrl: URL(string: update.imageUrl)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // Announcements section (show only first like Android)
                        if let firstAnnouncement = wikiFeed.announcements.first {
                            AnnouncementCardView(announcementItem: firstAnnouncement) { url in
                                if let articleUrl = URL(string: url) {
                                    appState.navigateToArticle(url: articleUrl)
                                }
                            }
                        }
                        
                        // On This Day section
                        if let onThisDay = wikiFeed.onThisDay {
                            OnThisDayCardView(onThisDayItem: onThisDay) { url in
                                if let articleUrl = URL(string: url) {
                                    appState.navigateToArticle(url: articleUrl)
                                }
                            }
                        }
                        
                        // Popular Pages section
                        if !wikiFeed.popularPages.isEmpty {
                            PopularPagesCardView(popularPages: wikiFeed.popularPages) { url in
                                if let articleUrl = URL(string: url) {
                                    appState.navigateToArticle(url: articleUrl)
                                }
                            }
                        }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                    .accessibilityIdentifier("home_feed_scroll")
                    .scrollPosition($appState.newsFeedScrollPosition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.osrsBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("")
        .navigationBarHidden(true)
    }
}

/// NewsView variant that accepts a pre-loaded ViewModel to avoid timing issues in preview rendering
struct NewsViewWithPreloadedData: View {
    @ObservedObject var viewModel: NewsViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        NavigationStack(path: $appState.newsNavigationStack) {
            VStack(spacing: 0) {
                    osrsSearchLauncher(
                        placeholder: "Search OSRS Wiki",
                        accessibilityIdentifier: "home_search",
                        voiceAccessibilityIdentifier: "home_voice_search",
                        speechState: appState.speechManager.currentState,
                        onSearchTap: { appState.navigateToActiveSearch(startsVoiceRecognition: false) },
                        onVoiceTap: {
                            appState.navigateToActiveSearch(startsVoiceRecognition: true)
                        }
                    )
                    .osrsTabSearchLauncherLayout()

                    ScrollView {
                        LazyVStack(spacing: 12) {
                        
                        // Feed content matching Android structure - use pre-loaded data  
                        // DEBUG: Print state before rendering
                        let _ = print("🔍 NewsViewWithPreloadedData rendering: wikiFeed=\(viewModel.wikiFeed != nil ? "✅" : "❌"), updates=\(viewModel.wikiFeed?.recentUpdates.count ?? 0)")
                        if let wikiFeed = viewModel.wikiFeed {
                            // Recent Updates section (horizontal scrolling)
                            if !wikiFeed.recentUpdates.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Updates")
                                        .font(.osrsSectionHeaderSmallCaps)
                                        .foregroundStyle(.osrsOnSurface)
                                        .textCase(.uppercase)
                                        .kerning(0.5)
                                        .padding(.horizontal, 16)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(alignment: .top, spacing: 12) {
                                            ForEach(wikiFeed.recentUpdates) { update in
                                                UpdateCardView(updateItem: update) {
                                                    // Navigate to article
                                                    if !update.articleUrl.isEmpty {
                                                        if let url = URL(string: update.articleUrl) {
                                                            appState.navigateToArticle(
                                                                title: update.title,
                                                                url: url,
                                                                snippet: update.snippet,
                                                                thumbnailUrl: URL(string: update.imageUrl)
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            
                            // Announcements section (show only first like Android)
                            if let firstAnnouncement = wikiFeed.announcements.first {
                                AnnouncementCardView(announcementItem: firstAnnouncement) { url in
                                    if let articleUrl = URL(string: url) {
                                        appState.navigateToArticle(url: articleUrl)
                                    }
                                }
                            }
                            
                            // On This Day section
                            if let onThisDay = wikiFeed.onThisDay {
                                OnThisDayCardView(onThisDayItem: onThisDay) { url in
                                    if let articleUrl = URL(string: url) {
                                        appState.navigateToArticle(url: articleUrl)
                                    }
                                }
                            }
                            
                            // Popular Pages section
                            if !wikiFeed.popularPages.isEmpty {
                                PopularPagesCardView(popularPages: wikiFeed.popularPages) { url in
                                    if let articleUrl = URL(string: url) {
                                        appState.navigateToArticle(url: articleUrl)
                                    }
                                }
                            }
                        } else {
                            EmptyStateView(
                                iconName: "newspaper",
                                title: "No News Available",
                                subtitle: "Check back later for OSRS updates"
                            )
                        }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                    .accessibilityIdentifier("home_feed_scroll")
                    .scrollPosition($appState.newsFeedScrollPosition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.osrsBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("")
        .navigationBarHidden(true)
    }
}

// MARK: - Cached Content View

struct CachedContentView: View {
    let wikiFeed: WikiFeed
    let appState: AppState
    
    var body: some View {
        LazyVStack(spacing: 12) {
            // Recent Updates section (horizontal scrolling)
            if !wikiFeed.recentUpdates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Updates")
                        .font(.osrsSectionHeaderSmallCaps)
                        .foregroundStyle(.osrsOnSurface)
                        .kerning(0.5)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(wikiFeed.recentUpdates) { update in
                                UpdateCardView(updateItem: update) {
                                    // Navigate to article
                                    if !update.articleUrl.isEmpty {
                                        if let url = URL(string: update.articleUrl) {
                                            appState.navigateToArticle(
                                                title: update.title,
                                                url: url,
                                                snippet: update.snippet,
                                                thumbnailUrl: URL(string: update.imageUrl)
                                            )
                                        }
                                    }
                                }
                                .zIndex(1) // Ensure cards are above other content
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Announcements section (show only first like Android)
            if let firstAnnouncement = wikiFeed.announcements.first {
                AnnouncementCardView(announcementItem: firstAnnouncement) { url in
                    if let articleUrl = URL(string: url) {
                        appState.navigateToArticle(url: articleUrl)
                    }
                }
            }
            
            // On This Day section
            if let onThisDay = wikiFeed.onThisDay {
                OnThisDayCardView(onThisDayItem: onThisDay) { url in
                    if let articleUrl = URL(string: url) {
                        appState.navigateToArticle(url: articleUrl)
                    }
                }
            }
            
            // Popular Pages section
            if !wikiFeed.popularPages.isEmpty {
                PopularPagesCardView(popularPages: wikiFeed.popularPages) { url in
                    if let articleUrl = URL(string: url) {
                        appState.navigateToArticle(url: articleUrl)
                    }
                }
            }
        }
    }
}

#Preview {
    NewsView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

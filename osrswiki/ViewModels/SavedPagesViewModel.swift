//
//  SavedPagesViewModel.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import Combine

struct SavedPagesSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

#if DEBUG
struct SavedPagesShareRequestRecord {
    let identifier: String
    let label: String
}
#endif

@MainActor
class SavedPagesViewModel: ObservableObject {
    @Published var savedPages: [SavedPage] = []
    @Published var isLoading: Bool = false
    @Published var sortOrder: SortOrder = .date
    @Published var sharePayload: SavedPagesSharePayload?
#if DEBUG
    @Published var shareRequestRecordForUITests: SavedPagesShareRequestRecord?
#endif
    
    private let savedPagesRepository: SavedPagesRepository
    private let metadataEnricher = osrsHistoryEnricher()

    init(savedPagesRepository: SavedPagesRepository = SavedPagesRepository()) {
        self.savedPagesRepository = savedPagesRepository
    }
    
    enum SortOrder {
        case date
        case title
    }
    
    func loadSavedPages() async {
        isLoading = true
        savedPages = Self.visibleSavedPages(from: savedPagesRepository.getSavedPages())
        applySorting()
        isLoading = false
        Task { await enrichMissingMetadata() }
    }

    /// Incomplete first-time saves stay in the repository so ArticleView can retry them in
    /// place, but they are not Reading List entries until there is a readable prior snapshot.
    /// A failed/outdated refresh of an existing snapshot remains visible and truthfully reports
    /// that it needs attention instead of disappearing with the user's previously saved page.
    static func visibleSavedPages(from pages: [SavedPage]) -> [SavedPage] {
        pages.filter(\.isVisibleInSavedLibrary)
    }

    private func enrichMissingMetadata() async {
        let cachedFeed = NewsRepository.shared.getCachedFeedSynchronously()
        for page in savedPages where page.thumbnailUrl == nil || page.description == nil {
            let cachedMetadata = osrsHistoryUpdateMetadataResolver.cachedMetadata(
                forTitle: page.displayTitle,
                in: cachedFeed
            )
            let metadata = await metadataEnricher.enrichHistoryEntry(
                pageTitle: page.displayTitle,
                pageUrl: page.url
            )
            let thumbnailUrl = metadata.thumbnailUrl ?? cachedMetadata?.thumbnailUrl
            let description = metadata.snippet ?? cachedMetadata?.description
            guard thumbnailUrl != nil || description != nil,
                  let enriched = savedPagesRepository.updateSavedPageMetadata(
                    id: page.id,
                    description: description,
                    thumbnailUrl: thumbnailUrl
                  ),
                  let index = savedPages.firstIndex(where: { $0.id == page.id }) else { continue }
            savedPages[index] = enriched
        }
    }
    
    func refresh() async {
        await loadSavedPages()
    }
    
    func sortBy(_ order: SortOrder) {
        sortOrder = order
        applySorting()
    }
    
    func removeSavedPage(_ savedPage: SavedPage) {
        let removedPage = savedPagesRepository.removeSavedPage(savedPage.id)
        savedPages.removeAll { $0.id == savedPage.id }
        if #available(iOS 17.0, *), let removedPage {
            Task {
                await ProxyInterceptorService.shared.removeCachedResponses(pageId: removedPage.offlineCachePageId)
            }
        }
    }
    
    func moveSavedPages(from: IndexSet, to: Int) {
        savedPages.move(fromOffsets: from, toOffset: to)
        savedPagesRepository.updateOrder(pageIDs: savedPages.map(\.id))
    }
    
    func navigateToPage(_ savedPage: SavedPage, appState: AppState) {
        // Check if we can use the modern iOS 17+ proxy-based approach
        if #available(iOS 17.0, *) {
            print("🚀 SavedPagesViewModel: Using modern proxy-based navigation for: \(savedPage.title)")
            navigateToPageWithProxySupport(savedPage, appState: appState)
        } else {
            print("⚠️ SavedPagesViewModel: Using legacy web archive approach for iOS <17")
            navigateToPageLegacy(savedPage, appState: appState)
        }
    }
    
    /// Modern iOS 17+ proxy-based navigation (replaces web archive approach)
    @available(iOS 17.0, *)
    private func navigateToPageWithProxySupport(_ savedPage: SavedPage, appState: AppState) {
        let cleanTitle = savedPage.displayTitle // HTML entity decoding included
        let title = osrsStringUtils.extractMainTitle(cleanTitle)
        
        print("🔍 SavedPagesViewModel: Modern proxy navigation for '\(title)'")
        print("📍 SavedPagesViewModel: Using original HTTPS URL: \(savedPage.url.absoluteString)")
        
        // Use original HTTPS URL - proxy system will handle caching automatically
        appState.navigateToArticle(
            title: title,
            url: savedPage.url, // Always use original HTTPS URL, never custom schemes
            snippet: savedPage.description,
            thumbnailUrl: savedPage.thumbnailUrl,
            savedPageId: savedPage.offlineCachePageId
        )
        
        // Note: Proxy configuration now happens in SavedPagesView.onAppear with intelligent mode detection
        print("🔗 SavedPagesViewModel: Proxy configuration will be handled by ArticleView.onAppear")
    }
    
    /// Legacy web archive navigation (fallback for iOS <17)
    private func navigateToPageLegacy(_ savedPage: SavedPage, appState: AppState) {
        // Use AppState navigation for in-app article viewing  
        // CRITICAL FIX: Use decoded display title for proper API requests
        let cleanTitle = savedPage.displayTitle // This now includes HTML entity decoding
        let title = osrsStringUtils.extractMainTitle(cleanTitle)
        
        // UNIFIED OFFLINE/ONLINE NAVIGATION: Use viewingURL which automatically chooses offline custom scheme or original URL
        let rawNavigationUrl = savedPage.viewingURL
        let offlineStatusLog = savedPage.canAttemptOfflineCacheRead ? " (CACHE CANDIDATE via \(rawNavigationUrl.scheme ?? "unknown")://)" : " (ONLINE)"
        
        // URL NORMALIZATION: For online URLs, ensure they're in the correct format
        let navigationUrl: URL
        if savedPage.canAttemptOfflineCacheRead {
            // Offline URLs use custom scheme - don't normalize
            navigationUrl = rawNavigationUrl
        } else {
            // Online URLs need normalization to ensure proper format
            navigationUrl = normalizeWikiURL(rawNavigationUrl)
        }
        
        // DIAGNOSTIC LOGGING: Enhanced debugging for saved page navigation
        print("🔍 SavedPagesViewModel: Legacy navigation to saved page '\(title)'\(offlineStatusLog)")
        print("📍 SavedPagesViewModel: Using URL: \(navigationUrl.absoluteString)")
        print("🛠️ DIAGNOSTIC: SavedPage details:")
        print("  - Raw Title: \(savedPage.title)")
        print("  - Clean Title (with HTML decoding): \(cleanTitle)")
        print("  - Extracted Title: \(title)")
        print("  - Original URL: \(savedPage.url.absoluteString)")
        print("  - Raw Viewing URL: \(rawNavigationUrl.absoluteString)")
        print("  - Normalized URL: \(navigationUrl.absoluteString)")  
        print("  - URL Host: \(navigationUrl.host ?? "nil")")
        print("  - URL Path: \(navigationUrl.path)")
        print("  - URL Scheme: \(navigationUrl.scheme ?? "nil")")
        print("  - Offline Status: \(savedPage.offlineStatus.rawValue)")
        print("  - Is Available Offline: \(savedPage.isAvailableOffline)")
        print("  - Page ID: \(savedPage.id)")
        print("  - Saved Date: \(savedPage.savedDate)")
        
        appState.navigateToArticle(
            title: title,
            url: navigationUrl,
            snippet: savedPage.description,
            thumbnailUrl: savedPage.thumbnailUrl
        )
    }
    
    func sharePage(_ savedPage: SavedPage) {
        let title = osrsStringUtils.extractMainTitle(savedPage.displayTitle)
        let shareText = Self.sharePageText(title: title, url: savedPage.url)

#if DEBUG
        if osrsTestEnvironment.stubsShareSheetsForUITests {
            shareRequestRecordForUITests = SavedPagesShareRequestRecord(
                identifier: "saved_share_request_recorded",
                label: "saved_share_request_recorded \(shareText)"
            )
            return
        }
#endif

        sharePayload = SavedPagesSharePayload(items: [shareText])
    }
    
    func exportReadingList() {
        let exportText = Self.exportReadingListText(from: savedPages)

#if DEBUG
        if osrsTestEnvironment.stubsShareSheetsForUITests {
            shareRequestRecordForUITests = SavedPagesShareRequestRecord(
                identifier: "saved_export_request_recorded",
                label: "saved_export_request_recorded \(exportText)"
            )
            return
        }
#endif

        do {
            let fileURL = try Self.writeExportReadingListText(exportText)
            sharePayload = SavedPagesSharePayload(items: [fileURL])
        } catch {
            print("❌ SavedPagesViewModel: Failed to create reading list export: \(error)")
            sharePayload = SavedPagesSharePayload(items: [exportText])
        }
    }

    static func exportReadingListText(from pages: [SavedPage]) -> String {
        let pages = visibleSavedPages(from: pages)
        var lines: [String] = [
            "OSRS Wiki Reading List",
            "Exported \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))",
            ""
        ]

        if pages.isEmpty {
            lines.append("No saved pages.")
            return lines.joined(separator: "\n")
        }

        for (index, page) in pages.enumerated() {
            lines.append("\(index + 1). \(osrsStringUtils.extractMainTitle(page.displayTitle))")
            lines.append("   URL: \(page.url.absoluteString)")
            if let description = page.description, !description.isEmpty {
                lines.append("   Description: \(description)")
            }
            lines.append("   Saved: \(DateFormatter.localizedString(from: page.savedDate, dateStyle: .medium, timeStyle: .short))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func sharePageText(title: String, url: URL) -> String {
        "\(title)\n\(url.absoluteString)"
    }

    private static func writeExportReadingListText(_ text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent("osrswiki-reading-list.txt")
        try text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    func clearAllSavedPages() {
        let removedPages = savedPagesRepository.clearSavedPages()
        let cachePageIDs = Set(removedPages.map(\.offlineCachePageId))
        if #available(iOS 17.0, *) {
            Task {
                for pageID in cachePageIDs {
                    await ProxyInterceptorService.shared.removeCachedResponses(pageId: pageID)
                }
            }
        }
        savedPages.removeAll()
        print("🗑️ SavedPagesViewModel: Cleared all saved pages")
    }
    
    
    // MARK: - URL Normalization
    
    /// Normalize a URL to ensure it's in the correct format for ArticleView loading
    private func normalizeWikiURL(_ originalUrl: URL) -> URL {
        let urlString = originalUrl.absoluteString
        
        print("🔧 NORMALIZE: Starting normalization for URL: \(urlString)")
        
        // CRITICAL FIX: Handle URL encoding issues like %26 → &
        var decodedUrlString = urlString
        
        // First, check if the URL contains percent-encoded characters
        if urlString.contains("%") {
            print("🔧 NORMALIZE: URL contains percent encoding, decoding...")
            if let decodedString = urlString.removingPercentEncoding {
                decodedUrlString = decodedString
                print("🔧 NORMALIZE: Decoded URL: \(decodedUrlString)")
            } else {
                print("⚠️ NORMALIZE: Failed to decode URL, using original")
            }
        }
        
        // Create URL from decoded string
        guard let decodedUrl = URL(string: decodedUrlString) else {
            print("⚠️ NORMALIZE: Could not create URL from decoded string, using original")
            return originalUrl
        }
        
        // Check if URL is already in correct format (using decoded URL)
        if decodedUrlString.contains("oldschool.runescape.wiki/w/") {
            print("🔧 NORMALIZE: URL already in correct format after decoding: \(decodedUrlString)")
            return decodedUrl
        }
        
        // Check if URL is an API URL that needs conversion
        if decodedUrlString.contains("oldschool.runescape.wiki/api.php") {
            print("🔧 NORMALIZE: Converting API URL to article URL")
            // Try to extract page title from API URL
            if let pageComponent = URLComponents(url: decodedUrl, resolvingAgainstBaseURL: false),
               let queryItems = pageComponent.queryItems,
               let pageItem = queryItems.first(where: { $0.name == "page" }),
               let pageTitle = pageItem.value {
                let normalizedTitle = pageTitle.replacingOccurrences(of: " ", with: "_")
                let normalizedUrl = URL(string: "https://oldschool.runescape.wiki/w/\(normalizedTitle)")!
                print("🔧 NORMALIZE: Converted API URL to: \(normalizedUrl.absoluteString)")
                return normalizedUrl
            }
        }
        
        // Check for other oldschool.runescape.wiki URLs that need path correction
        if decodedUrlString.contains("oldschool.runescape.wiki") && !decodedUrlString.contains("/w/") {
            print("🔧 NORMALIZE: Fixing wiki URL path structure")
            // Extract the path and try to construct proper /w/ URL
            let pathComponents = decodedUrl.pathComponents
            if pathComponents.count > 1 {
                let articlePath = pathComponents.last ?? ""
                let normalizedUrl = URL(string: "https://oldschool.runescape.wiki/w/\(articlePath)")!
                print("🔧 NORMALIZE: Fixed URL structure to: \(normalizedUrl.absoluteString)")
                return normalizedUrl
            }
        }
        
        print("⚠️ NORMALIZE: Could not normalize URL: \(decodedUrlString)")
        return decodedUrl // Return decoded URL even if we couldn't normalize further
    }
    
    // MARK: - Diagnostic Functions
    
    /// Debug function to inspect all saved page URLs and their formats
    func inspectSavedPagesUrls() {
        print("🔍 DIAGNOSTIC: Inspecting all saved pages URLs")
        print("📊 Total saved pages: \(savedPages.count)")
        
        if savedPages.isEmpty {
            print("📝 No saved pages found in repository")
            return
        }
        
        for (index, savedPage) in savedPages.enumerated() {
            print("📄 Saved Page [\(index + 1)/\(savedPages.count)]:")
            print("  - Title: \(savedPage.title)")
            print("  - Display Title: \(savedPage.displayTitle)")
            print("  - URL: \(savedPage.url.absoluteString)")
            print("  - URL Host: \(savedPage.url.host ?? "nil")")
            print("  - URL Path: \(savedPage.url.path)")
            print("  - URL Scheme: \(savedPage.url.scheme ?? "nil")")
            print("  - Viewing URL: \(savedPage.viewingURL.absoluteString)")
            print("  - Offline Status: \(savedPage.offlineStatus.rawValue)")
            print("  - Is Available Offline: \(savedPage.isAvailableOffline)")
            print("  - Saved Date: \(savedPage.savedDate)")
            print("  - Page ID: \(savedPage.id)")
            
            // URL format analysis
            let urlString = savedPage.url.absoluteString
            let isWikiFormat = urlString.contains("oldschool.runescape.wiki/w/")
            let containsWikiDomain = savedPage.url.host?.contains("oldschool.runescape.wiki") ?? false
            print("  - Analysis:")
            print("    • Is wiki format (/w/): \(isWikiFormat)")
            print("    • Contains wiki domain: \(containsWikiDomain)")
            print("    • Has query params: \(savedPage.url.query != nil)")
            print("    • Has fragment: \(savedPage.url.fragment != nil)")
            
            print("  ---")
        }
        
        print("📊 URL Format Summary:")
        let wikiFormatCount = savedPages.filter { $0.url.absoluteString.contains("oldschool.runescape.wiki/w/") }.count
        let wikiDomainCount = savedPages.filter { $0.url.host?.contains("oldschool.runescape.wiki") ?? false }.count
        let withQueryCount = savedPages.filter { $0.url.query != nil }.count
        let withFragmentCount = savedPages.filter { $0.url.fragment != nil }.count
        
        print("  - Wiki format (/w/): \(wikiFormatCount)/\(savedPages.count)")
        print("  - Wiki domain: \(wikiDomainCount)/\(savedPages.count)")
        print("  - With query params: \(withQueryCount)/\(savedPages.count)")
        print("  - With fragments: \(withFragmentCount)/\(savedPages.count)")
    }
    
    func filteredSavedPages(searchText: String) -> [SavedPage] {
        if searchText.isEmpty {
            return savedPages
        }
        
        return savedPages.filter { page in
            page.title.localizedCaseInsensitiveContains(searchText) ||
            (page.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private func applySorting() {
        switch sortOrder {
        case .date:
            savedPages.sort { $0.savedDate > $1.savedDate }
        case .title:
            savedPages.sort { $0.title < $1.title }
        }
    }
}

// MARK: - Models
struct SavedPage: Identifiable, Codable {
    let id: String
    let title: String
    let description: String?
    let url: URL
    let thumbnailUrl: URL?
    let savedDate: Date
    let isOfflineAvailable: Bool
    
    // MARK: - Offline Metadata (Added for unified offline architecture)
    let offlineDownloadDate: Date?
    let offlineStatus: OfflineStatus
    let offlineFileSize: Int64?
    let offlineLocalPath: String? // Path relative to offline_pages directory
    /// Only an exact main-document + exhaustive artwork settlement may write the current marker.
    /// A missing value identifies an older app record that must be refreshed before it is trusted.
    let durableSettlementVersion: Int?
    /// A persisted compare-and-swap token for one explicit refresh attempt. It prevents a stale
    /// completion from publishing over a newer retry or resurrecting a deleted record.
    let pendingSettlementGeneration: String?
    /// MediaWiki revid for the persisted snapshot. Cheap remote probes compare this
    /// integer instead of re-downloading the article.
    let revisionId: Int?

    static let currentDurableSettlementVersion = 1

    init(
        id: String,
        title: String,
        description: String?,
        url: URL,
        thumbnailUrl: URL?,
        savedDate: Date,
        isOfflineAvailable: Bool,
        offlineDownloadDate: Date?,
        offlineStatus: OfflineStatus,
        offlineFileSize: Int64?,
        offlineLocalPath: String?,
        durableSettlementVersion: Int? = nil,
        pendingSettlementGeneration: String? = nil,
        revisionId: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.savedDate = savedDate
        self.isOfflineAvailable = isOfflineAvailable
        self.offlineDownloadDate = offlineDownloadDate
        self.offlineStatus = offlineStatus
        self.offlineFileSize = offlineFileSize
        self.offlineLocalPath = offlineLocalPath
        self.durableSettlementVersion = durableSettlementVersion
        self.pendingSettlementGeneration = pendingSettlementGeneration
        self.revisionId = revisionId
    }

    var hasCurrentDurableSettlement: Bool {
        durableSettlementVersion == Self.currentDurableSettlementVersion
    }

    /// A legacy namespace can remain useful as a best-effort cache source while its metadata is
    /// truthfully retryable. The proxy still verifies the exact main response before serving it.
    var canAttemptOfflineCacheRead: Bool {
        offlineLocalPath != nil && offlineStatus != .notDownloaded
    }

    /// The Saved list is a library of readable snapshots, not a progress/error queue for the
    /// first save attempt. Retry records with an older readable namespace remain discoverable.
    var isVisibleInSavedLibrary: Bool {
        isAvailableOffline || canAttemptOfflineCacheRead
    }

    var savedLibraryStatusLabel: String {
        if isAvailableOffline {
            return "SAVED"
        }
        return offlineStatus == .downloading ? "UPDATING" : "RETRY"
    }

    /// Repository identity and cache namespace are intentionally distinct. Exact refreshes are
    /// assembled under a generation-specific namespace and this pointer is changed only after
    /// the entire snapshot is durable.
    var offlineCachePageId: String {
        offlineLocalPath ?? id
    }

    func requiringDurableSettlementRefresh() -> SavedPage {
        SavedPage(
            id: id,
            title: title,
            description: description,
            url: url,
            thumbnailUrl: thumbnailUrl,
            savedDate: savedDate,
            isOfflineAvailable: false,
            offlineDownloadDate: offlineDownloadDate,
            offlineStatus: .outdated,
            offlineFileSize: offlineFileSize,
            offlineLocalPath: offlineLocalPath,
            durableSettlementVersion: nil,
            pendingSettlementGeneration: nil,
            revisionId: revisionId
        )
    }

    func markingCurrentDurableSettlementAvailable(
        at downloadDate: Date,
        offlineLocalPath: String? = nil,
        offlineFileSize: Int64? = nil,
        revisionId: Int? = nil
    ) -> SavedPage {
        SavedPage(
            id: id,
            title: title,
            description: description,
            url: url,
            thumbnailUrl: thumbnailUrl,
            savedDate: savedDate,
            isOfflineAvailable: true,
            offlineDownloadDate: downloadDate,
            offlineStatus: .available,
            offlineFileSize: offlineFileSize,
            offlineLocalPath: offlineLocalPath ?? id,
            durableSettlementVersion: Self.currentDurableSettlementVersion,
            pendingSettlementGeneration: nil,
            revisionId: revisionId ?? self.revisionId
        )
    }
    
    var displayTitle: String {
        return title.replacingOccurrences(of: "_", with: " ").decodingHTMLEntities()
    }

    func replacingMetadata(description: String?, thumbnailUrl: URL?) -> SavedPage {
        SavedPage(
            id: id,
            title: title,
            description: description,
            url: url,
            thumbnailUrl: thumbnailUrl,
            savedDate: savedDate,
            isOfflineAvailable: isOfflineAvailable,
            offlineDownloadDate: offlineDownloadDate,
            offlineStatus: offlineStatus,
            offlineFileSize: offlineFileSize,
            offlineLocalPath: offlineLocalPath,
            durableSettlementVersion: durableSettlementVersion,
            pendingSettlementGeneration: pendingSettlementGeneration,
            revisionId: revisionId
        )
    }
    
    // MARK: - Offline Status Enum
    enum OfflineStatus: String, Codable, CaseIterable {
        case notDownloaded = "not_downloaded"     // Not available offline
        case downloading = "downloading"          // Currently downloading for offline use
        case available = "available"             // Fully downloaded and available offline
        case failed = "failed"                   // Download failed, needs retry
        case outdated = "outdated"               // Local version may be outdated
        
        var isDownloadedSuccessfully: Bool {
            return self == .available
        }
        
        var needsDownload: Bool {
            return self == .notDownloaded || self == .failed || self == .outdated
        }
    }
    
    // MARK: - Computed Properties for Offline Functionality
    
    /// True if the page is fully available for offline viewing
    var isAvailableOffline: Bool {
        return offlineStatus.isDownloadedSuccessfully &&
            offlineLocalPath != nil &&
            hasCurrentDurableSettlement
    }
    
    /// Generate the appropriate URL for this page (iOS Web Archive approach)
    /// Returns custom scheme URL for offline content, original HTTPS URL for online content
    var viewingURL: URL {
        if canAttemptOfflineCacheRead {
            // Page is available offline - return custom scheme URL for web archive loading
            print("📦 SavedPage: Returning custom scheme URL for web archive loading")
            return URL(string: "app-assets://saved-pages/\(id)")!
        } else {
            // Page not cached offline - return original HTTPS URL for online loading
            print("🌐 SavedPage: Returning HTTPS URL for online page")
            return url
        }
    }
    
    /// Human-readable offline status description
    var offlineStatusDescription: String {
        switch offlineStatus {
        case .notDownloaded:
            return "Not downloaded"
        case .downloading:
            return "Downloading..."
        case .available:
            if let downloadDate = offlineDownloadDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "Downloaded \(formatter.string(from: downloadDate))"
            } else {
                return "Available offline"
            }
        case .failed:
            return "Download failed"
        case .outdated:
            return "Update available"
        }
    }
    
    /// File size in human-readable format
    var offlineFileSizeFormatted: String? {
        guard let fileSize = offlineFileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

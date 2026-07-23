//
//  OfflineContentService.swift
//  OSRS Wiki
//
//  iOS-native offline content service using WKWebView createWebArchiveData
//  Implements Apple's recommended approach for offline web content
//

import Foundation
import WebKit

@MainActor
class OfflineContentService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = OfflineContentService()
    private init() {}
    
    // MARK: - Storage Structure (iOS Web Archive Format)
    
    /// Base directory for offline content: Documents/offline_pages/
    private var offlineBaseDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let offlineDir = documentsPath.appendingPathComponent("offline_pages")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
        
        return offlineDir
    }
    
    /// Web archive file for a saved page: Documents/offline_pages/{pageId}.webarchive
    func webArchiveFile(for pageId: String) -> URL {
        return offlineBaseDirectory.appendingPathComponent("\(pageId).webarchive")
    }
    
    /// Metadata file for a saved page: Documents/offline_pages/{pageId}.json
    private func metadataFile(for pageId: String) -> URL {
        return offlineBaseDirectory.appendingPathComponent("\(pageId).json")
    }
    
    // MARK: - Web Archive Operations
    
    /// Create web archive from WKWebView using iOS-native createWebArchiveData
    func createWebArchive(from webView: WKWebView, pageId: String, title: String, originalURL: URL) async throws {
        print("📦 OfflineContentService: Creating web archive for page: \(pageId)")
        
        return try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { result in
                switch result {
                case .success(let archiveData):
                    Task { @MainActor in
                        do {
                            // Save the web archive data
                            let archiveURL = self.webArchiveFile(for: pageId)
                            try archiveData.write(to: archiveURL)
                            print("✅ OfflineContentService: Saved web archive (\(archiveData.count) bytes) to: \(archiveURL.lastPathComponent)")
                            
                            // Save metadata
                            let metadata = WebArchiveMetadata(
                                pageId: pageId,
                                title: title,
                                originalURL: originalURL.absoluteString,
                                archiveDate: Date(),
                                archiveSize: archiveData.count
                            )
                            try self.saveMetadata(metadata, for: pageId)
                            
                            continuation.resume()
                        } catch {
                            print("❌ OfflineContentService: Failed to save web archive: \(error)")
                            continuation.resume(throwing: error)
                        }
                    }
                    
                case .failure(let error):
                    print("❌ OfflineContentService: createWebArchiveData failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Content Status & Access
    
    /// Check if a page has been archived and is available offline
    func isPageAvailableOffline(pageId: String) -> Bool {
        let archiveFile = webArchiveFile(for: pageId)
        let isAvailable = FileManager.default.fileExists(atPath: archiveFile.path)
        
        if isAvailable {
            print("✅ OfflineContentService: Page \(pageId) is available offline")
        } else {
            print("❌ OfflineContentService: Page \(pageId) is NOT available offline")
        }
        
        return isAvailable
    }
    
    /// Get file URL for loading web archive in WKWebView
    func webArchiveFileURL(for pageId: String) -> URL {
        return webArchiveFile(for: pageId)
    }
    
    /// Get metadata for an archived page
    func getMetadata(for pageId: String) -> WebArchiveMetadata? {
        do {
            let metadataURL = metadataFile(for: pageId)
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder().decode(WebArchiveMetadata.self, from: data)
        } catch {
            print("❌ OfflineContentService: Failed to load metadata for \(pageId): \(error)")
            return nil
        }
    }
    
    // MARK: - Storage Management
    
    /// Delete offline content for a page
    func deleteOfflineContent(pageId: String) throws {
        let archiveFile = webArchiveFile(for: pageId)
        let metadataFile = metadataFile(for: pageId)
        
        if FileManager.default.fileExists(atPath: archiveFile.path) {
            try FileManager.default.removeItem(at: archiveFile)
            print("✅ OfflineContentService: Deleted web archive for \(pageId)")
        }
        
        if FileManager.default.fileExists(atPath: metadataFile.path) {
            try FileManager.default.removeItem(at: metadataFile)
            print("✅ OfflineContentService: Deleted metadata for \(pageId)")
        }
    }
    
    /// Get total storage size used by offline content
    func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: offlineBaseDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            for fileURL in contents {
                if let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        } catch {
            print("❌ OfflineContentService: Error calculating storage size: \(error)")
        }
        
        return totalSize
    }
    
    /// Clear all offline content
    func clearAllOfflineContent() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: offlineBaseDirectory, includingPropertiesForKeys: nil)
        
        for fileURL in contents {
            try FileManager.default.removeItem(at: fileURL)
        }
        
        print("✅ OfflineContentService: Cleared all offline content")
    }
    
    // MARK: - Private Helpers
    
    private func saveMetadata(_ metadata: WebArchiveMetadata, for pageId: String) throws {
        let metadataURL = metadataFile(for: pageId)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL)
        print("✅ OfflineContentService: Saved metadata for \(pageId)")
    }
    
    // MARK: - Legacy Compatibility (for migration)
    
    /// Legacy method for compatibility with existing SavedPage creation
    @available(*, deprecated, message: "Use createWebArchive(from:pageId:title:originalURL:) instead")
    func downloadPageForOfflineViewing(pageUrl: URL, pageId: String, pageTitle: String) async throws {
        print("❌ OfflineContentService: Legacy downloadPageForOfflineViewing cannot create durable offline content")
        throw OfflineContentError.webArchiveRequiresActiveWebView
    }
    
    /// Legacy HTTP response methods (kept for compatibility with existing code)
    func saveHttpResponse(pageId: String, url: String, filename: String, data: Data, metadata: [String: Any]) throws {
        // No-op for compatibility - web archives handle all resources automatically
        print("⚠️ OfflineContentService: Legacy saveHttpResponse called - web archives handle resources automatically")
    }
    
    func getCachedHttpResponse(pageId: String, url: String, filename: String) throws -> (data: Data, response: HTTPURLResponse)? {
        // No-op for compatibility - web archives serve resources automatically
        print("⚠️ OfflineContentService: Legacy getCachedHttpResponse called - web archives serve resources automatically")
        return nil
    }
}

enum OfflineContentError: LocalizedError {
    case webArchiveRequiresActiveWebView

    var errorDescription: String? {
        switch self {
        case .webArchiveRequiresActiveWebView:
            return "Offline archive creation requires an active article WebView."
        }
    }
}

// MARK: - WebArchiveMetadata Model

struct WebArchiveMetadata: Codable {
    let pageId: String
    let title: String
    let originalURL: String
    let archiveDate: Date
    let archiveSize: Int
    
    var formattedArchiveDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: archiveDate)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(archiveSize))
    }
}

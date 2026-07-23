//
//  SavedPagesRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import Foundation

// MARK: - Legacy SavedPage structure for migration compatibility
private struct LegacySavedPage: Codable {
    let id: String
    let title: String
    let description: String?
    let url: URL
    let thumbnailUrl: URL?
    let savedDate: Date
    let isOfflineAvailable: Bool
}

class SavedPagesRepository {
    private static let storageLock = NSLock()
    private let userDefaults: UserDefaults
    private let savedPagesKey = "saved_pages"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func getSavedPages() -> [SavedPage] {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        return getSavedPagesUnlocked()
    }

    private func getSavedPagesUnlocked() -> [SavedPage] {
        guard let data = userDefaults.data(forKey: savedPagesKey) else {
            return []
        }
        
        // Try to decode with new structure first
        if let savedPages = try? JSONDecoder().decode([SavedPage].self, from: data) {
            return savedPages
        }
        
        // If that fails, try legacy structure and migrate
        if let legacySavedPages = try? JSONDecoder().decode([LegacySavedPage].self, from: data) {
            let migratedPages = legacySavedPages.map { legacy in
                SavedPage(
                    id: legacy.id,
                    title: legacy.title,
                    description: legacy.description,
                    url: legacy.url,
                    thumbnailUrl: legacy.thumbnailUrl,
                    savedDate: legacy.savedDate,
                    isOfflineAvailable: legacy.isOfflineAvailable,
                    offlineDownloadDate: nil,
                    offlineStatus: .notDownloaded,
                    offlineFileSize: nil,
                    offlineLocalPath: nil
                )
            }
            
            // Save migrated data in new format
            saveSavedPagesUnlocked(migratedPages)
            print("📱 SavedPagesRepository: Migrated \(migratedPages.count) saved pages to new offline structure")
            return migratedPages
        }
        
        return []
    }
    
    func addSavedPage(_ page: SavedPage) {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }

        var savedPages = getSavedPagesUnlocked()
        
        // Remove existing entry for same page
        savedPages.removeAll { $0.url == page.url }
        
        // Add new entry at beginning
        savedPages.insert(page, at: 0)
        
        saveSavedPagesUnlocked(savedPages)
    }
    
    func removeSavedPage(_ id: String) {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }

        var savedPages = getSavedPagesUnlocked()
        savedPages.removeAll { $0.id == id }
        saveSavedPagesUnlocked(savedPages)
    }
    
    func updateOrder(_ pages: [SavedPage]) {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        saveSavedPagesUnlocked(pages)
    }
    
    func updateSavedPage(_ updatedPage: SavedPage) {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }

        var savedPages = getSavedPagesUnlocked()
        
        // Find and replace the existing page
        if let index = savedPages.firstIndex(where: { $0.id == updatedPage.id }) {
            savedPages[index] = updatedPage
            saveSavedPagesUnlocked(savedPages)
            print("📝 SavedPagesRepository: Updated saved page '\(updatedPage.title)'")
        } else {
            print("⚠️ SavedPagesRepository: Could not find page with ID '\(updatedPage.id)' to update")
        }
    }
    
    func clearSavedPages() {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        saveSavedPagesUnlocked([])
    }
    
    private func saveSavedPages(_ pages: [SavedPage]) {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        saveSavedPagesUnlocked(pages)
    }

    private func saveSavedPagesUnlocked(_ pages: [SavedPage]) {
        if let data = try? JSONEncoder().encode(pages) {
            userDefaults.set(data, forKey: savedPagesKey)
        }
    }
}

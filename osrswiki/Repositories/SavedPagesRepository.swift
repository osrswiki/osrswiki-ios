//
//  SavedPagesRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import Foundation

extension Notification.Name {
    static let osrsSavedPagesRepositoryDidChange = Notification.Name(
        "osrsSavedPagesRepositoryDidChange"
    )
}

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
        let result = getSavedPagesUnlocked()
        Self.storageLock.unlock()
        if result.didMigrate {
            notifySavedPagesChanged()
        }
        return result.pages
    }

    private func getSavedPagesUnlocked() -> (pages: [SavedPage], didMigrate: Bool) {
        guard let data = userDefaults.data(forKey: savedPagesKey) else {
            return ([], false)
        }
        
        // Try to decode with new structure first
        if let savedPages = try? JSONDecoder().decode([SavedPage].self, from: data) {
            var didMigrate = false
            let migratedPages = savedPages.map { page in
                guard page.offlineStatus == .available,
                      !page.hasCurrentDurableSettlement else {
                    return page
                }
                didMigrate = true
                return page.requiringDurableSettlementRefresh()
            }
            if didMigrate {
                saveSavedPagesUnlocked(migratedPages)
                print("📱 SavedPagesRepository: Marked unversioned offline saves for exact refresh")
            }
            return (migratedPages, didMigrate)
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
                    // Pre-offline-schema rows were Reading List membership, not proof of the
                    // current exhaustive snapshot contract. Keep them visible and retryable,
                    // while letting ArticleView's persisted-main probe decide whether this old
                    // identity has any best-effort cache bytes to serve.
                    isOfflineAvailable: false,
                    offlineDownloadDate: nil,
                    offlineStatus: .outdated,
                    offlineFileSize: nil,
                    offlineLocalPath: legacy.id,
                    durableSettlementVersion: nil
                )
            }
            
            // Save migrated data in new format
            saveSavedPagesUnlocked(migratedPages)
            print("📱 SavedPagesRepository: Migrated \(migratedPages.count) saved pages to new offline structure")
            return (migratedPages, true)
        }
        
        return ([], false)
    }
    
    func addSavedPage(_ page: SavedPage) {
        Self.storageLock.lock()
        defer {
            Self.storageLock.unlock()
            notifySavedPagesChanged()
        }

        var savedPages = getSavedPagesUnlocked().pages
        
        // Remove existing entry for same page
        savedPages.removeAll { $0.url == page.url }
        
        // Add new entry at beginning
        savedPages.insert(page, at: 0)
        
        saveSavedPagesUnlocked(savedPages)
    }
    
    /// Remove and return the latest record under one lock so cleanup uses the cache namespace
    /// that actually won any concurrent settlement publication.
    @discardableResult
    func removeSavedPage(_ id: String) -> SavedPage? {
        Self.storageLock.lock()
        var didChange = false
        defer {
            Self.storageLock.unlock()
            if didChange { notifySavedPagesChanged() }
        }

        var savedPages = getSavedPagesUnlocked().pages
        guard let index = savedPages.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = savedPages.remove(at: index)
        saveSavedPagesUnlocked(savedPages)
        didChange = true
        return removed
    }
    
    /// Reorder by identity while reading the latest records under the same lock. A stale view
    /// snapshot must never write old offline status, marker, or cache pointers back to storage.
    func updateOrder(pageIDs: [String]) {
        Self.storageLock.lock()
        var didChange = false
        defer {
            Self.storageLock.unlock()
            if didChange { notifySavedPagesChanged() }
        }
        let latest = getSavedPagesUnlocked().pages
        let latestByID = Dictionary(uniqueKeysWithValues: latest.map { ($0.id, $0) })
        var emitted = Set<String>()
        var reordered = pageIDs.compactMap { id -> SavedPage? in
            guard emitted.insert(id).inserted else { return nil }
            return latestByID[id]
        }
        reordered.append(contentsOf: latest.filter { emitted.insert($0.id).inserted })
        guard reordered.map(\.id) != latest.map(\.id) else { return }
        saveSavedPagesUnlocked(reordered)
        didChange = true
    }

    /// Patch only descriptive fields against the latest record. This is safe to call after a
    /// network await even when an offline settlement completed in the meantime.
    @discardableResult
    func updateSavedPageMetadata(
        id: String,
        description: String?,
        thumbnailUrl: URL?
    ) -> SavedPage? {
        Self.storageLock.lock()
        var didChange = false
        defer {
            Self.storageLock.unlock()
            if didChange { notifySavedPagesChanged() }
        }

        var savedPages = getSavedPagesUnlocked().pages
        guard let index = savedPages.firstIndex(where: { $0.id == id }) else { return nil }
        let latest = savedPages[index]
        let updated = latest.replacingMetadata(
            description: latest.description ?? description,
            thumbnailUrl: latest.thumbnailUrl ?? thumbnailUrl
        )
        guard updated.description != latest.description ||
                updated.thumbnailUrl != latest.thumbnailUrl else {
            return latest
        }
        savedPages[index] = updated
        saveSavedPagesUnlocked(savedPages)
        didChange = true
        return updated
    }
    
    /// Returns false when the record was deleted while an asynchronous save/refresh was in
    /// flight. Callers must not resurrect that record or publish its staged cache namespace.
    @discardableResult
    func updateSavedPage(_ updatedPage: SavedPage) -> Bool {
        Self.storageLock.lock()
        var didChange = false
        defer {
            Self.storageLock.unlock()
            if didChange { notifySavedPagesChanged() }
        }

        var savedPages = getSavedPagesUnlocked().pages
        
        // Find and replace the existing page
        if let index = savedPages.firstIndex(where: { $0.id == updatedPage.id }) {
            savedPages[index] = updatedPage
            saveSavedPagesUnlocked(savedPages)
            didChange = true
            print("📝 SavedPagesRepository: Updated saved page '\(updatedPage.title)'")
            return true
        } else {
            print("⚠️ SavedPagesRepository: Could not find page with ID '\(updatedPage.id)' to update")
            return false
        }
    }

    /// Atomically publishes or fails one explicit offline settlement. The record must still be
    /// the exact in-flight generation and point at the cache snapshot from which the retry began.
    @discardableResult
    func compareAndSwapOfflineSettlement(
        _ updatedPage: SavedPage,
        expectedGeneration: String,
        expectedPriorCachePageId: String?
    ) -> Bool {
        Self.storageLock.lock()
        var didChange = false
        defer {
            Self.storageLock.unlock()
            if didChange { notifySavedPagesChanged() }
        }

        var savedPages = getSavedPagesUnlocked().pages
        guard let index = savedPages.firstIndex(where: { $0.id == updatedPage.id }) else {
            return false
        }
        let current = savedPages[index]
        guard current.offlineStatus == .downloading,
              current.pendingSettlementGeneration == expectedGeneration,
              current.offlineLocalPath == expectedPriorCachePageId else {
            print("🔒 SavedPagesRepository: Rejected stale offline settlement for '\(updatedPage.title)'")
            return false
        }

        savedPages[index] = updatedPage
        saveSavedPagesUnlocked(savedPages)
        didChange = true
        return true
    }
    
    /// Clear and return the latest records atomically; callers must clean these returned cache
    /// namespaces rather than cache pointers captured by an older view snapshot.
    @discardableResult
    func clearSavedPages() -> [SavedPage] {
        Self.storageLock.lock()
        var didChange = false
        defer {
            Self.storageLock.unlock()
            if didChange { notifySavedPagesChanged() }
        }
        let removed = getSavedPagesUnlocked().pages
        saveSavedPagesUnlocked([])
        didChange = !removed.isEmpty
        return removed
    }
    
    private func saveSavedPages(_ pages: [SavedPage]) {
        Self.storageLock.lock()
        defer {
            Self.storageLock.unlock()
            notifySavedPagesChanged()
        }
        saveSavedPagesUnlocked(pages)
    }

    private func saveSavedPagesUnlocked(_ pages: [SavedPage]) {
        if let data = try? JSONEncoder().encode(pages) {
            userDefaults.set(data, forKey: savedPagesKey)
        }
    }

    private func notifySavedPagesChanged() {
        NotificationCenter.default.post(name: .osrsSavedPagesRepositoryDidChange, object: nil)
    }
}

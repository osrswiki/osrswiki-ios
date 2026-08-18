//
//  HistoryRepository.swift
//  OSRS Wiki
//
//  Created on iOS webviewer implementation session
//

import Foundation

class HistoryRepository {
    private static let queue = DispatchQueue(label: "HistoryRepository.Serial")
    private let userDefaults: UserDefaults
    private let historyKey = "search_history"
    private let maxHistoryItems = 100
    private let historyEnricher = osrsHistoryEnricher()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func getHistory() -> [HistoryItem] {
        Self.queue.sync {
            loadHistory()
        }
    }

    func addToHistory(_ item: HistoryItem) {
        Self.queue.sync {
            var history = loadHistory()
            let normalizedItem = item.normalizedForStorage()

            // Remove existing item with same URL to avoid duplicates
            history.removeAll { $0.pageUrl == normalizedItem.pageUrl }

            // Add new item at the beginning
            history.insert(normalizedItem, at: 0)

            // Keep only the most recent items
            if history.count > maxHistoryItems {
                history = Array(history.prefix(maxHistoryItems))
            }

            saveHistory(history)
        }
    }

    private func loadHistory() -> [HistoryItem] {
        guard let data = userDefaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return []
        }
        return history
            .map { $0.normalizedForStorage() }
            .sorted { $0.visitedDate > $1.visitedDate }
    }
    
    /// Adds an enriched history entry with thumbnail and snippet data
    /// Matches Android's PageHistoryManager.logPageVisit() functionality
    func addEnrichedHistoryEntry(pageTitle: String, pageUrl: URL, visitedDate: Date = Date()) async {
        let historyItem = await makeEnrichedHistoryEntry(
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            visitedDate: visitedDate
        )
        addToHistory(historyItem)
    }

    func makeEnrichedHistoryEntry(pageTitle: String, pageUrl: URL, visitedDate: Date = Date()) async -> HistoryItem {
        // First enrich the entry with metadata
        let (thumbnailUrl, snippet) = await historyEnricher.enrichHistoryEntry(
            pageTitle: pageTitle,
            pageUrl: pageUrl
        )
        
        // Create the enriched history item
        let historyItem = HistoryItem(
            id: UUID().uuidString,
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            visitedDate: visitedDate,
            thumbnailUrl: thumbnailUrl,
            description: snippet,
            metadataUpdatedAt: thumbnailUrl != nil && snippet != nil ? Date() : nil
        )

        return historyItem
    }
    
    func removeFromHistory(_ itemId: String) {
        Self.queue.sync {
            var history = loadHistory()
            history.removeAll { $0.id == itemId }
            saveHistory(history)
        }
    }
    
    func clearHistory() {
        Self.queue.sync {
            userDefaults.removeObject(forKey: historyKey)
        }
    }

    func updateMetadata(
        for pageURL: URL,
        thumbnailUrl: URL?,
        description: String?,
        updatedAt: Date = Date()
    ) {
        Self.queue.sync {
            var history = loadHistory()
            guard let index = history.firstIndex(where: { $0.pageUrl == pageURL }) else { return }
            let existingItem = history[index]
            let resolvedThumbnail = thumbnailUrl ?? existingItem.thumbnailUrl
            let resolvedDescription = description ?? existingItem.description
            let refreshProducedMetadata = thumbnailUrl != nil || description != nil
            let refreshCompletedMetadata = refreshProducedMetadata && resolvedThumbnail != nil && resolvedDescription != nil
            history[index] = history[index].replacingMetadata(
                thumbnailUrl: resolvedThumbnail,
                description: resolvedDescription,
                // A failed or partial response must remain eligible for retry.
                // Preserve an older timestamp rather than falsely marking it fresh.
                updatedAt: refreshCompletedMetadata ? updatedAt : existingItem.metadataUpdatedAt
            )
            saveHistory(history)
        }
    }
    
    private func saveHistory(_ history: [HistoryItem]) {
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
}

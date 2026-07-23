//
//  HistoryRepository.swift
//  OSRS Wiki
//
//  Created on iOS webviewer implementation session
//

import Foundation

class HistoryRepository {
    private let userDefaults: UserDefaults
    private let historyKey = "search_history"
    private let maxHistoryItems = 100
    private let historyEnricher = osrsHistoryEnricher()
    private let queue = DispatchQueue(label: "HistoryRepository.Serial")

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func getHistory() -> [HistoryItem] {
        queue.sync {
            loadHistory()
        }
    }

    func addToHistory(_ item: HistoryItem) {
        queue.sync {
            var history = loadHistory()

            // Remove existing item with same URL to avoid duplicates
            history.removeAll { $0.pageUrl == item.pageUrl }

            // Add new item at the beginning
            history.insert(item, at: 0)

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
        return history.sorted { $0.visitedDate > $1.visitedDate }
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
            description: snippet
        )

        return historyItem
    }
    
    func removeFromHistory(_ itemId: String) {
        queue.sync {
            var history = loadHistory()
            history.removeAll { $0.id == itemId }
            saveHistory(history)
        }
    }
    
    func clearHistory() {
        queue.sync {
            userDefaults.removeObject(forKey: historyKey)
        }
    }
    
    private func saveHistory(_ history: [HistoryItem]) {
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
}

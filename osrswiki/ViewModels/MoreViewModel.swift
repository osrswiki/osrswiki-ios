//
//  MoreViewModel.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import StoreKit

@MainActor
class MoreViewModel: ObservableObject {
    
    func clearCache() {
        // Implementation for clearing cache
        let alert = UIAlertController(
            title: "Clear Cache",
            message: "Are you sure you want to clear the cache? This will free up storage space but may slow down loading times temporarily.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            // Perform cache clearing
            CacheManager.shared.clearCache()
        })
        
        presentAlert(alert)
    }
    
    func shareApp() {
        guard let url = URL(string: "https://apps.apple.com/app/osrs-wiki/id123456789") else { return }
        
        let activityController = UIActivityViewController(
            activityItems: [
                "Check out the OSRS Wiki app!",
                url
            ],
            applicationActivities: nil
        )
        
        presentViewController(activityController)
    }
    
    func rateApp() {
        // App is not yet live on App Store - disable rating until public launch
        // TODO: Enable this when app is published to App Store
        let isAppOnAppStore = false
        
        if !isAppOnAppStore {
            print("[MoreViewModel] Rate App disabled - app not yet on App Store")
            return
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            AppStore.requestReview(in: windowScene)
        }
    }
    
    func openPrivacyPolicy() {
        guard let url = URL(string: "https://oldschool.runescape.wiki/privacy") else { return }
        UIApplication.shared.open(url)
    }
    
    func openTermsOfService() {
        guard let url = URL(string: "https://oldschool.runescape.wiki/terms") else { return }
        UIApplication.shared.open(url)
    }
    
    private func presentAlert(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func presentViewController(_ viewController: UIViewController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(viewController, animated: true)
        }
    }
}

// MARK: - Cache Manager
class CacheManager {
    static let shared = CacheManager()
    
    private init() {}
    
    func clearCache() {
        // Clear URLCache
        URLCache.shared.removeAllCachedResponses()
        
        // Clear UserDefaults cache (if any)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cached_news")
        defaults.removeObject(forKey: "cached_search_results")
        
        // Clear temporary files
        let tempDirectory = NSTemporaryDirectory()
        let fileManager = FileManager.default
        do {
            let tempFiles = try fileManager.contentsOfDirectory(atPath: tempDirectory)
            for file in tempFiles {
                let filePath = tempDirectory + file
                try fileManager.removeItem(atPath: filePath)
            }
        } catch {
            print("Error clearing temp files: \(error)")
        }
        
        // Post notification that cache was cleared
        NotificationCenter.default.post(name: .cacheCleared, object: nil)
    }
    
    func getCacheSize() -> String {
        let cacheSize = URLCache.shared.currentDiskUsage
        return ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file)
    }
}

extension Notification.Name {
    static let cacheCleared = Notification.Name("cacheCleared")
}

//
//  ComprehensiveOfflineWorkflowTest.swift
//  osrswikiTests
//
//  Comprehensive test for complete save→cache→offline load workflow
//  Tests the entire offline functionality to catch issues before users encounter them
//

import XCTest
import WebKit
@testable import osrswiki

@MainActor
class ComprehensiveOfflineWorkflowTest: XCTestCase {
    
    var articleViewModel: ArticleViewModel!
    var webView: WKWebView!
    var testPageId: String!
    var discoveredResourceCount: Int = 0
    var successfullyCachedCount: Int = 0
    var failedCachingCount: Int = 0
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize web view configuration
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        print("🧪 ComprehensiveOfflineWorkflowTest: Test setup complete")
    }
    
    override func tearDown() async throws {
        if #available(iOS 17.0, *) {
            ProxyInterceptorService.shared.disableOfflineSaveMode()
            NetworkManager.shared.configureProxyRouting(enabled: false)
        }
        articleViewModel = nil
        webView = nil
        testPageId = nil
        try await super.tearDown()
    }
    
    func testCompleteVarrockOfflineWorkflow() async throws {
        print("🧪 COMPREHENSIVE OFFLINE WORKFLOW TEST")
        print("═══════════════════════════════════════════════")
        
        // Step 1: Initialize ArticleViewModel and load page
        print("📱 Step 1: Initialize ArticleViewModel for Varrock")
        let varrockURL = URL(string: "https://oldschool.runescape.wiki/w/Varrock")!
        articleViewModel = ArticleViewModel(pageUrl: varrockURL)
        articleViewModel.webView = webView
        
        // Load the page first (similar to real app workflow)
        print("📥 Loading page content...")
        await articleViewModel.loadArticle()
        
        // Wait for loading to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        print("✅ Page loading completed")
        
        // Step 2: Perform save action and track resource caching
        print("\n📦 Step 2: Save page with resource caching tracking")
        await performSaveWithResourceTracking()
        
        // Step 3: Verify cache contents after save
        print("\n🔍 Step 3: Verify cache contents")
        await verifyCacheContents()
        
        // Step 4: Test offline loading workflow  
        print("\n📵 Step 4: Test offline loading")
        await testOfflineLoading()
        
        // Step 5: Summary and analysis
        print("\n📊 Step 5: Workflow Analysis Summary")
        printWorkflowSummary()
        
        print("═══════════════════════════════════════════════")
        print("🧪 COMPREHENSIVE WORKFLOW TEST COMPLETE")
    }
    
    // MARK: - Step 2: Save with Resource Tracking
    
    private func performSaveWithResourceTracking() async {
        print("💾 Starting save process with comprehensive resource tracking...")
        
        // Reset tracking counters
        discoveredResourceCount = 0
        successfullyCachedCount = 0
        failedCachingCount = 0
        
        // Perform the save action
        await articleViewModel.performSaveAction()
        
        // Extract the page ID from the saved page for tracking
        let repository = SavedPagesRepository()
        let savedPages = repository.getSavedPages()
        if let savedPage = savedPages.first(where: { $0.url == articleViewModel.pageUrl }) {
            testPageId = savedPage.id
            print("🆔 Test page ID: \(testPageId!)")
            print("📊 Save state: \(articleViewModel.saveState)")
            print("📈 Save progress: \(articleViewModel.saveProgress)")
            print("🔖 Is bookmarked: \(articleViewModel.isBookmarked)")
        } else {
            print("❌ Could not find saved page in repository")
        }
    }
    
    // MARK: - Step 3: Cache Verification
    
    private func verifyCacheContents() async {
        guard let pageId = testPageId else {
            print("❌ No page ID available for cache verification")
            return
        }
        
        print("🔍 Performing comprehensive cache audit for page: \(pageId)")
        
        // Use ProxyInterceptorService to audit cache
        let hasCache = ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: pageId)
        print("📦 ProxyInterceptorService cache check: \(hasCache)")
        
        // Use LocalHTTPServer to audit cache contents
        ProxyInterceptorService.shared.auditCacheForPage(pageId: pageId)
        
        // Get detailed cache statistics
        await getCacheStatistics(pageId: pageId)
    }
    
    private func getCacheStatistics(pageId: String) async {
        print("📊 Detailed cache analysis:")
        
        // Check if we can find cache directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheDir = documentsPath.appendingPathComponent("offline_http_cache")
        
        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            let pageFiles = cacheFiles.filter { $0.lastPathComponent.contains(pageId) }
            
            print("📁 Cache directory: \(cacheDir.path)")
            print("📄 Total cache files: \(cacheFiles.count)")
            print("🎯 Page-specific files: \(pageFiles.count)")
            
            for (index, file) in pageFiles.prefix(5).enumerated() {
                let fileSize = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
                print("   [\(index + 1)] \(file.lastPathComponent) (\(fileSize) bytes)")
            }
            
            if pageFiles.count > 5 {
                print("   ... and \(pageFiles.count - 5) more files")
            }
            
        } catch {
            print("❌ Error reading cache directory: \(error)")
        }
    }
    
    // MARK: - Step 4: Offline Loading Test
    
    private func testOfflineLoading() async {
        guard let pageId = testPageId else {
            print("❌ No page ID available for offline loading test")
            return
        }
        
        print("📵 Testing offline loading workflow...")
        
        // Enable offline mode for testing
        print("🔄 Enabling cache-only mode...")
        _ = await ProxyInterceptorService.shared.enableCacheOnlyMode(pageId: pageId)
        
        // Test main HTML content loading
        await testMainContentLoading(pageId: pageId)
        
        // Test resource loading (images, CSS, JS)
        await testResourceLoading(pageId: pageId)
        
        // Disable offline mode after testing (remove from cache-only mode)
        if #available(iOS 17.0, *) {
            ProxyInterceptorService.shared.disableOfflineSaveMode()
            NetworkManager.shared.configureProxyRouting(enabled: false)
        }
        print("🔄 Offline mode test completed")
    }
    
    private func testMainContentLoading(pageId: String) async {
        print("📄 Testing main HTML content loading...")
        
        // Try to load main content through the proxy system
        let mainContentURL = URL(string: "https://oldschool.runescape.wiki/api.php?action=parse&format=json&prop=text|displaytitle|revid&disablelimitreport=1&wrapoutputclass=mw-parser-output&page=Varrock")!
        
        do {
            let response = try await NetworkManager.shared.performRequest(
                url: mainContentURL,
                responseType: osrsParseResponse.self
            )
            print("✅ Main content loaded successfully (\(response.parse.text.count) characters)")
        } catch {
            print("❌ Main content loading failed: \(error)")
        }
    }
    
    private func testResourceLoading(pageId: String) async {
        print("🖼️ Testing resource loading (sample images)...")
        
        // Test loading some sample image resources that should be cached
        let sampleImageURLs = [
            "https://oldschool.runescape.wiki/images/thumb/Varrock.png/300px-Varrock.png?620c5",
            "https://oldschool.runescape.wiki/images/Misthalin_Area_Badge.png?d6e6d",
            "https://oldschool.runescape.wiki/images/thumb/Varrock_East_bank.png/600px-Varrock_East_bank.png?732e4", // This was failing in user logs
            "https://oldschool.runescape.wiki/images/thumb/Varrock_standard_banner.png/60px-Varrock_standard_banner.png?ac30d"
        ]
        
        var successCount = 0
        var failureCount = 0
        
        for (index, urlString) in sampleImageURLs.enumerated() {
            guard let url = URL(string: urlString) else { continue }
            
            print("   [\(index + 1)] Testing: \(url.lastPathComponent)")
            
            do {
                let (data, _) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)
                print("   ✅ Success: \(data.count) bytes")
                successCount += 1
            } catch {
                print("   ❌ Failed: \(error)")
                failureCount += 1
            }
        }
        
        print("📊 Resource loading test results:")
        print("   ✅ Successful: \(successCount)/\(sampleImageURLs.count)")
        print("   ❌ Failed: \(failureCount)/\(sampleImageURLs.count)")
        
        if failureCount > 0 {
            print("⚠️ ISSUE DETECTED: Some resources failed to load offline")
        }
    }
    
    // MARK: - Step 5: Summary Analysis
    
    private func printWorkflowSummary() {
        print("📋 COMPREHENSIVE WORKFLOW ANALYSIS:")
        print("──────────────────────────────────")
        
        if let pageId = testPageId {
            print("🆔 Test Page ID: \(pageId)")
            print("📊 Save State: \(articleViewModel.saveState)")
            print("📈 Save Progress: \(articleViewModel.saveProgress)")
            print("🔖 Is Bookmarked: \(articleViewModel.isBookmarked)")
            
            // Check final cache status
            let hasCompleteCache = ProxyInterceptorService.shared.hasCompleteOfflineCache(pageId: pageId)
            print("📦 Complete Cache Available: \(hasCompleteCache)")
            
            if hasCompleteCache {
                print("🎉 SUCCESS: Complete offline workflow functioning correctly")
            } else {
                print("⚠️ ISSUE: Incomplete cache - some resources may not load offline")
            }
        } else {
            print("❌ FAILURE: Could not complete workflow analysis - missing page ID")
        }
        
        print("──────────────────────────────────")
        print("💡 RECOMMENDATIONS:")
        
        if discoveredResourceCount > 0 && successfullyCachedCount < discoveredResourceCount {
            print("   • Investigate failed resource caching during save process")
            print("   • Check individual NetworkManager.performDataRequest failures")
            print("   • Verify save process completion logic waits for all resources")
        }
        
        print("   • Run this test after making save process changes")
        print("   • Compare results with user-reported offline behavior")
        print("   • Monitor cache size growth during save process")
    }
}

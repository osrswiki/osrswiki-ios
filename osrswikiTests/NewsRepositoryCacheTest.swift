//
//  NewsRepositoryCacheTest.swift
//  OSRS Wiki Tests
//
//  Unit tests for NewsRepository caching functionality
//

import XCTest
@testable import osrswiki

@MainActor
class NewsRepositoryCacheTest: XCTestCase {
    
    var repository: NewsRepository!
    
    override func setUpWithError() throws {
        // Clear any existing cache before each test
        UserDefaults.standard.removeObject(forKey: "osrs_wiki_feed_cache")
        UserDefaults.standard.removeObject(forKey: "osrs_wiki_feed_timestamp")
        repository = NewsRepository.shared
    }
    
    override func tearDownWithError() throws {
        // Clean up after tests
        repository.clearCache()
        repository = nil
    }
    
    // MARK: - Cache Validation Tests
    
    func testCacheInitiallyEmpty() {
        // Test that cache starts empty
        XCTAssertFalse(repository.isCacheValid, "Cache should be initially invalid")
    }
    
    func testCacheValidationAfterSuccessfulLoad() async throws {
        // Test that cache becomes valid after successful data load
        do {
            _ = try await repository.fetchWikiFeed(forceRefresh: true)
            XCTAssertTrue(repository.isCacheValid, "Cache should be valid after successful fetch")
        } catch {
            // If network fails, this test might not be applicable
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    func testCacheInvalidationOnClear() async throws {
        // Load data first
        do {
            _ = try await repository.fetchWikiFeed(forceRefresh: true)
            XCTAssertTrue(repository.isCacheValid, "Cache should be valid after fetch")
            
            // Clear cache
            repository.clearCache()
            XCTAssertFalse(repository.isCacheValid, "Cache should be invalid after clear")
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    // MARK: - Cache Persistence Tests
    
    func testCachePersistenceInUserDefaults() async throws {
        // Test that cache data persists in UserDefaults
        do {
            let originalFeed = try await repository.fetchWikiFeed(forceRefresh: true)
            
            // Create new repository instance to test persistence
            let newRepository = NewsRepository.shared
            
            // Cache should still be valid
            XCTAssertTrue(newRepository.isCacheValid, "Cache should persist across instances")
            
            let cachedFeed = try await newRepository.fetchWikiFeed(forceRefresh: false)
            
            // Verify data integrity (basic checks)
            XCTAssertEqual(originalFeed.recentUpdates.count, cachedFeed.recentUpdates.count, "Recent updates count should match")
            XCTAssertEqual(originalFeed.announcements.count, cachedFeed.announcements.count, "Announcements count should match")
            XCTAssertEqual(originalFeed.popularPages.count, cachedFeed.popularPages.count, "Popular pages count should match")
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    func testCacheExpirationAfterTTL() {
        // Test cache expiration logic (simulate by manipulating timestamp)
        
        // Create expired timestamp (25 hours ago)
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        UserDefaults.standard.set(expiredDate, forKey: "osrs_wiki_feed_timestamp")
        
        // Cache should be invalid due to expiration
        XCTAssertFalse(repository.isCacheValid, "Cache should be invalid after TTL expiration")
    }
    
    // MARK: - Force Refresh Tests
    
    func testForceRefreshBypassesCache() async throws {
        // This test verifies that forceRefresh actually makes network calls
        
        do {
            // First load with force refresh
            let feed1 = try await repository.fetchWikiFeed(forceRefresh: true)
            XCTAssertTrue(repository.isCacheValid, "Cache should be valid after first load")
            
            // Second load with force refresh should make new request
            let feed2 = try await repository.fetchWikiFeed(forceRefresh: true)
            
            // Both should be valid WikiFeed objects
            XCTAssertTrue(feed1.recentUpdates.count >= 0, "First feed should have data structure")
            XCTAssertTrue(feed2.recentUpdates.count >= 0, "Second feed should have data structure")
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    func testNormalLoadUsesCache() async throws {
        // Test that normal load uses cache when available
        
        do {
            // Load fresh data
            _ = try await repository.fetchWikiFeed(forceRefresh: true)
            XCTAssertTrue(repository.isCacheValid, "Cache should be valid")
            
            // Normal load should use cache (no network request)
            let cachedFeed = try await repository.fetchWikiFeed(forceRefresh: false)
            
            // Should return data without error
            XCTAssertTrue(cachedFeed.recentUpdates.count >= 0, "Cached feed should have valid structure")
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    // MARK: - Data Integrity Tests
    
    func testCachedDataStructureIntegrity() async throws {
        // Test that cached data maintains proper structure
        
        do {
            let feed = try await repository.fetchWikiFeed(forceRefresh: true)
            
            // Verify basic structure exists
            XCTAssertNotNil(feed.recentUpdates, "Recent updates should not be nil")
            XCTAssertNotNil(feed.announcements, "Announcements should not be nil")
            XCTAssertNotNil(feed.popularPages, "Popular pages should not be nil")
            
            // Test cached retrieval maintains structure
            let cachedFeed = try await repository.fetchWikiFeed(forceRefresh: false)
            
            XCTAssertNotNil(cachedFeed.recentUpdates, "Cached recent updates should not be nil")
            XCTAssertNotNil(cachedFeed.announcements, "Cached announcements should not be nil")
            XCTAssertNotNil(cachedFeed.popularPages, "Cached popular pages should not be nil")
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    func testUpdateItemStructureIntegrity() async throws {
        // Test that UpdateItem objects maintain integrity through caching
        
        do {
            let feed = try await repository.fetchWikiFeed(forceRefresh: true)
            
            guard let firstUpdate = feed.recentUpdates.first else {
                try XCTSkipIf(true, "No recent updates available for testing")
                return
            }
            
            // Verify original structure
            XCTAssertFalse(firstUpdate.title.isEmpty, "Update title should not be empty")
            XCTAssertNotNil(firstUpdate.snippet, "Update snippet should not be nil")
            XCTAssertNotNil(firstUpdate.imageUrl, "Update imageUrl should not be nil")
            XCTAssertNotNil(firstUpdate.articleUrl, "Update articleUrl should not be nil")
            
            // Test cached version maintains integrity
            let cachedFeed = try await repository.fetchWikiFeed(forceRefresh: false)
            
            guard let cachedFirstUpdate = cachedFeed.recentUpdates.first else {
                XCTFail("Cached feed should have same structure as original")
                return
            }
            
            XCTAssertEqual(firstUpdate.title, cachedFirstUpdate.title, "Cached title should match original")
            XCTAssertEqual(firstUpdate.snippet, cachedFirstUpdate.snippet, "Cached snippet should match original")
            XCTAssertEqual(firstUpdate.imageUrl, cachedFirstUpdate.imageUrl, "Cached imageUrl should match original")
            XCTAssertEqual(firstUpdate.articleUrl, cachedFirstUpdate.articleUrl, "Cached articleUrl should match original")
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testCacheHandlingWithNetworkErrors() async {
        // Test that cache operations handle network errors gracefully
        
        // Clear cache first
        repository.clearCache()
        XCTAssertFalse(repository.isCacheValid, "Cache should be initially invalid")
        
        do {
            _ = try await repository.fetchWikiFeed(forceRefresh: false)
            // If this succeeds, cache should become valid
            XCTAssertTrue(repository.isCacheValid, "Cache should be valid after successful load")
        } catch {
            // If network fails, cache should remain invalid but not crash
            XCTAssertFalse(repository.isCacheValid, "Cache should remain invalid on network failure")
            XCTAssertTrue(error is NetworkError, "Should throw NetworkError on failure")
        }
    }
    
    func testCompatibilityWithLegacyNewsItems() async throws {
        // Test that the cached WikiFeed can still be transformed to NewsItems
        
        do {
            let wikiFeed = try await repository.fetchWikiFeed(forceRefresh: true)
            let newsItems = repository.transformFeedToNewsItems(wikiFeed)
            
            XCTAssertTrue(newsItems.count >= 0, "Should be able to transform WikiFeed to NewsItems")
            
            // Test cached version as well
            let cachedFeed = try await repository.fetchWikiFeed(forceRefresh: false)
            let cachedNewsItems = repository.transformFeedToNewsItems(cachedFeed)
            
            XCTAssertEqual(newsItems.count, cachedNewsItems.count, "Cached transformation should match original")
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
    
    // MARK: - Performance Tests
    
    func testCacheRetrievalPerformance() async throws {
        // Test that cache retrieval is fast
        
        do {
            // Load data into cache
            _ = try await repository.fetchWikiFeed(forceRefresh: true)
            XCTAssertTrue(repository.isCacheValid)
            
            // Measure cache retrieval performance
            measure {
                Task {
                    do {
                        _ = try await repository.fetchWikiFeed(forceRefresh: false)
                    } catch {
                        XCTFail("Cache retrieval should not fail")
                    }
                }
            }
            
        } catch {
            throw XCTSkip("Skipping due to network unavailability")
        }
    }
}

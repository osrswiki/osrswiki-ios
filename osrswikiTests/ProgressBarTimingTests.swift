//
//  ProgressBarTimingTests.swift
//  osrswikiTests
//
//  Automated test to measure and fix progress bar vs page visibility timing
//

import XCTest
import Combine
@testable import osrswiki

@MainActor 
final class ProgressBarTimingTests: XCTestCase {
    
    var articleViewModel: ArticleViewModel!
    var timingMeasurements: [String: TimeInterval] = [:]
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        let testURL = URL(string: "https://oldschool.runescape.wiki/w/Abyssal_whip")!
        articleViewModel = ArticleViewModel(pageUrl: testURL, pageTitle: "Abyssal whip", pageId: nil)
        timingMeasurements = [:]
    }
    
    override func tearDownWithError() throws {
        articleViewModel = nil
    }
    
    /// Automated test to measure timing between progress completion and page visibility
    func testProgressBarToPageVisibilityTiming() async throws {
        let testExpectation = expectation(description: "Page loading timing test")
        var progressCompletionTime: Date?
        var pageVisibleTime: Date?
        
        // Set up timing measurement observers
        let progressObserver = articleViewModel.$loadingProgress.sink { progress in
            if progress >= 1.0 && progressCompletionTime == nil {
                progressCompletionTime = Date()
                print("📊 TIMING: Progress bar completed at \(Date())")
            }
        }
        
        let loadingObserver = articleViewModel.$isLoading.sink { isLoading in
            if !isLoading && pageVisibleTime == nil && progressCompletionTime != nil {
                pageVisibleTime = Date()
                print("📊 TIMING: Page became visible at \(Date())")
                
                // Calculate delay
                if let start = progressCompletionTime, let end = pageVisibleTime {
                    let delay = end.timeIntervalSince(start)
                    print("📊 TIMING RESULT: Delay = \(String(format: "%.3f", delay))s")
                    
                    // Store measurement for iteration
                    self.timingMeasurements["progressToPageDelay"] = delay
                    
                    // FAIL if delay is too long (Android target: <100ms)
                    XCTAssertLessThan(delay, 0.1, "Progress to page visibility delay (\(String(format: "%.3f", delay))s) exceeds 100ms target")
                    
                    testExpectation.fulfill()
                }
            }
        }
        
        // Trigger page load with theme
        articleViewModel.loadArticle(theme: osrsLightTheme())
        
        // Wait for completion (timeout after 10 seconds)
        await fulfillment(of: [testExpectation], timeout: 10.0)
        
        // Clean up observers
        progressObserver.cancel()
        loadingObserver.cancel()
        
        // Output results for automated analysis
        if let delay = timingMeasurements["progressToPageDelay"] {
            print("📊 AUTOMATED TEST RESULT: Progress-to-page delay = \(String(format: "%.3f", delay))s")
            
            // Provide automated optimization suggestions
            if delay > 0.5 {
                print("🔧 OPTIMIZATION: Severe delay detected. Check WebView rendering pipeline.")
            } else if delay > 0.1 {
                print("🔧 OPTIMIZATION: Moderate delay. Consider optimizing progress completion logic.")
            } else {
                print("✅ OPTIMIZATION: Timing is within acceptable range.")
            }
        }
    }
    
}
//
//  TimelineAnalysisTest.swift
//  osrswikiTests
//
//  Comprehensive timeline analysis test to understand complete loading phases
//

import XCTest
import SwiftUI
@testable import osrswiki

final class TimelineAnalysisTest: XCTestCase {
    
    func testCompleteLoadingTimeline() async throws {
        print("\n📊 🔍 TIMELINE ANALYSIS: Starting comprehensive timeline tracking test")
        
        await MainActor.run {
            let viewModel = ArticleViewModel(
                pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Abyssal_whip")!,
                pageTitle: "Abyssal whip"
            )
            
            let expectation = XCTestExpectation(description: "Complete timeline tracking")
            var timelineEvents: [(String, Date)] = []
            
            // Track all state changes with timestamps
            let progressCancellable = viewModel.$loadingProgress.sink { progress in
                let timestamp = Date()
                let event = "Progress: \(String(format: "%.1f", progress * 100))%"
                timelineEvents.append((event, timestamp))
                print("📊 TIMELINE EVENT: \(event) at \(DateFormatter.timeFormatter.string(from: timestamp))")
            }
            
            let loadingCancellable = viewModel.$isLoading.sink { isLoading in
                let timestamp = Date()
                let event = isLoading ? "Loading Started" : "Loading Finished"
                timelineEvents.append((event, timestamp))
                print("📊 TIMELINE EVENT: \(event) at \(DateFormatter.timeFormatter.string(from: timestamp))")
                
                if !isLoading {
                    expectation.fulfill()
                }
            }
            
            print("📊 🚀 STARTING ARTICLE LOAD: Beginning timeline analysis...")
            viewModel.loadArticle(theme: osrsLightTheme())
            
            Task {
                await fulfillment(of: [expectation], timeout: 60.0)
                
                progressCancellable.cancel()
                loadingCancellable.cancel()
                
                print("\n📊 📋 COMPLETE TIMELINE ANALYSIS:")
                print("📊 Total events tracked: \(timelineEvents.count)")
                
                for (index, event) in timelineEvents.enumerated() {
                    let timeString = DateFormatter.timeFormatter.string(from: event.1)
                    print("📊 [\(String(format: "%02d", index + 1))] [\(timeString)] \(event.0)")
                }
                
                if timelineEvents.count >= 2 {
                    let startTime = timelineEvents.first!.1
                    let endTime = timelineEvents.last!.1
                    let totalTime = endTime.timeIntervalSince(startTime)
                    print("📊 🏁 TOTAL LOADING TIME: \(String(format: "%.3f", totalTime))s")
                }
                
                print("📊 ✅ TIMELINE ANALYSIS COMPLETE")
            }
        }
    }
}
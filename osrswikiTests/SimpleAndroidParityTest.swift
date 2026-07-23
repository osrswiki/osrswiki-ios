//
//  SimpleAndroidParityTest.swift
//  osrswikiTests
//
//  Simple test to verify Android parity timing behavior
//

import XCTest
import SwiftUI
@testable import osrswiki

final class SimpleAndroidParityTest: XCTestCase {
    
    func testAndroidParityBehavior() async throws {
        print("\n🚀 SIMPLE ANDROID PARITY TEST: Verifying progress caps at 95%")
        
        await MainActor.run {
            let viewModel = ArticleViewModel(
                pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Abyssal_whip")!,
                pageTitle: "Abyssal whip"
            )
            
            let expectation = XCTestExpectation(description: "Progress tracking")
            var progressValues: [Double] = []
            var finalProgress: Double = 0.0
            
            let progressCancellable = viewModel.$loadingProgress.sink { progress in
                progressValues.append(progress)
                print("📊 Progress: \(String(format: "%.1f", progress * 100))%")
            }
            
            let loadingCancellable = viewModel.$isLoading.sink { isLoading in
                if !isLoading {
                    finalProgress = viewModel.loadingProgress
                    print("📊 Final progress when loading complete: \(String(format: "%.1f", finalProgress * 100))%")
                    expectation.fulfill()
                }
            }
            
            viewModel.loadArticle(theme: osrsLightTheme())
            
            Task {
                await fulfillment(of: [expectation], timeout: 30.0)
                
                progressCancellable.cancel()
                loadingCancellable.cancel()
                
                // Analyze progress behavior
                let maxProgressWhileLoading = progressValues.dropLast().max() ?? 0.0
                print("📊 ANDROID PARITY ANALYSIS:")
                print("   - Max progress while loading: \(String(format: "%.1f", maxProgressWhileLoading * 100))%")
                print("   - Final progress: \(String(format: "%.1f", finalProgress * 100))%")
                
                // ANDROID PARITY: Should not exceed 95% until JavaScript completes
                if maxProgressWhileLoading <= 0.95 {
                    print("✅ ANDROID PARITY VERIFIED: Progress caps at 95% as expected")
                } else {
                    print("❌ ANDROID PARITY ISSUE: Progress exceeded 95% before completion")
                }
                
                XCTAssertLessThanOrEqual(maxProgressWhileLoading, 0.95, 
                                       "Progress should cap at 95% until JavaScript completion (Android parity)")
                
                XCTAssertEqual(finalProgress, 1.0, accuracy: 0.01, 
                              "Final progress should reach 100%")
            }
        }
    }
}
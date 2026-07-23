//
//  AppLaunchPreloadingTest.swift
//  OSRS Wiki Tests  
//
//  Test to check if preloading starts automatically on app launch
//

import XCTest
import MapLibre
import SwiftUI
@testable import osrswiki

class AppLaunchPreloadingTest: XCTestCase {
    
    func testAppLaunchPreloadingBehavior() {
        print("\n🚨 === APP LAUNCH PRELOADING TEST ===")
        print("🎯 Checking if preloading starts automatically without manual calls")
        
        let testExpectation = expectation(description: "App launch preloading test")
        
        Task { @MainActor in
            print("📱 App launched - checking initial state...")
            
            let preloader = osrsBackgroundMapPreloader.shared
            
            print("📊 Immediately after app launch:")
            print("   isPreloadingMap: \(preloader.isPreloadingMap)")
            print("   mapPreloaded: \(preloader.mapPreloaded)")
            print("   progress: \(Int(preloader.preloadingProgress * 100))%")
            print("   isMapReady: \(preloader.isMapReady)")
            
            if preloader.isPreloadingMap {
                print("✅ Preloading IS running automatically")
                
                // Wait for it to complete
                print("⏳ Waiting for preloading to complete...")
                var attempts = 0
                while preloader.isPreloadingMap && attempts < 100 {
                    try? await Task.sleep(for: .milliseconds(100))
                    attempts += 1
                    if attempts % 10 == 0 {
                        print("   Progress: \(Int(preloader.preloadingProgress * 100))%")
                    }
                }
                
                print("📊 After preloading completion:")
                print("   isMapReady: \(preloader.isMapReady)")
                print("   Final result: \(preloader.isMapReady ? "✅ SUCCESS" : "❌ FAILED")")
                
            } else if preloader.isMapReady {
                print("✅ Preloading already completed before test")
                
            } else {
                print("❌ Preloading is NOT running automatically")
                print("🔍 This means MainTabView.onAppear may not be called")
                
                // Test what happens when user navigates to map tab
                print("\n🚨 SIMULATING USER TAP ON MAP TAB:")
                
                // This simulates what OSRSMapLibreView.makeUIView does
                let containerView = UIView()
                containerView.backgroundColor = .black
                
                print("🔍 Checking if shared map is ready: \(preloader.isMapReady)")
                
                if preloader.isMapReady {
                    print("✅ Using shared map instance - instant display!")
                    preloader.attachToMainMapContainer(containerView)
                    print("✅ Map attached successfully")
                } else {
                    print("⚠️ Shared map not ready - will show loading state")
                    print("❌ USER SEES: Black/loading screen")
                }
            }
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 15.0)
    }
}
//
//  PreloadingStatusTest.swift
//  OSRS Wiki Tests  
//
//  Simple test to check if preloading is actually running
//

import XCTest
import MapLibre
import SwiftUI
@testable import osrswiki

class PreloadingStatusTest: XCTestCase {
    
    func testPreloadingActuallyRuns() {
        print("\n🔍 === PRELOADING STATUS CHECK ===")
        print("🎯 Checking if preloading actually starts and runs")
        
        let testExpectation = expectation(description: "Preloading status check")
        
        Task { @MainActor in
            let preloader = osrsBackgroundMapPreloader.shared
            
            print("📊 Initial state:")
            print("   isPreloadingMap: \(preloader.isPreloadingMap)")
            print("   mapPreloaded: \(preloader.mapPreloaded)")
            print("   allLayersReady: \(preloader.allLayersReady)")
            print("   isMapReady: \(preloader.isMapReady)")
            print("   progress: \(Int(preloader.preloadingProgress * 100))%")
            print("   sharedMapView exists: \(preloader.sharedMapView != nil)")
            
            // Wait 5 seconds and check again
            print("\n⏳ Waiting 5 seconds to see if anything changes...")
            try? await Task.sleep(for: .seconds(5))
            
            print("\n📊 After 5 seconds:")
            print("   isPreloadingMap: \(preloader.isPreloadingMap)")
            print("   mapPreloaded: \(preloader.mapPreloaded)")
            print("   allLayersReady: \(preloader.allLayersReady)")
            print("   isMapReady: \(preloader.isMapReady)")
            print("   progress: \(Int(preloader.preloadingProgress * 100))%")
            print("   sharedMapView exists: \(preloader.sharedMapView != nil)")
            
            // Check if MainTabView actually starts preloading
            print("\n🔍 Testing if MainTabView.onAppear starts preloading...")
            
            // Simulate MainTabView.onAppear behavior
            print("🚀 PRIORITY 1: Starting MapLibre background preloading...")
            await osrsBackgroundMapPreloader.shared.preloadMapInBackground()
            print("✅ Preloading call completed")
            
            print("\n📊 After manual preloading call:")
            print("   isPreloadingMap: \(preloader.isPreloadingMap)")
            print("   mapPreloaded: \(preloader.mapPreloaded)")
            print("   allLayersReady: \(preloader.allLayersReady)")
            print("   isMapReady: \(preloader.isMapReady)")
            print("   progress: \(Int(preloader.preloadingProgress * 100))%")
            print("   sharedMapView exists: \(preloader.sharedMapView != nil)")
            
            if preloader.isMapReady {
                print("✅ RESULT: Preloading DOES work when called")
            } else {
                print("❌ RESULT: Preloading FAILS even when called directly")
            }
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 15.0)
    }
}
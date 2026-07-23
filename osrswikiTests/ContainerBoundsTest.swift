//
//  ContainerBoundsTest.swift
//  OSRS Wiki Tests  
//
//  Test to check container bounds during map attachment
//

import XCTest
import MapLibre
import SwiftUI
@testable import osrswiki

class ContainerBoundsTest: XCTestCase {
    
    func testContainerBoundsIssue() {
        print("\n🔍 === CONTAINER BOUNDS TEST ===")
        print("🎯 Checking if container bounds cause invisible map")
        
        let testExpectation = expectation(description: "Container bounds test")
        
        Task { @MainActor in
            // Wait for preloading to complete
            let preloader = osrsBackgroundMapPreloader.shared
            
            if !preloader.isMapReady {
                print("⏳ Waiting for preloading to complete...")
                while !preloader.isMapReady {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            
            print("✅ Preloading completed, testing container bounds scenarios")
            
            // Test 1: Zero bounds container (mimics SwiftUI timing issue)
            print("\n🔍 TEST 1: Zero bounds container")
            let zeroBoundsContainer = UIView(frame: .zero)
            print("   Container bounds: \(zeroBoundsContainer.bounds)")
            
            preloader.attachToMainMapContainer(zeroBoundsContainer)
            
            if let mapView = zeroBoundsContainer.subviews.first {
                print("   Map frame after attachment: \(mapView.frame)")
                print("   Map bounds: \(mapView.bounds)")
                print("   Map hidden: \(mapView.isHidden)")
                print("   Map alpha: \(mapView.alpha)")
                
                if mapView.frame.width == 0 || mapView.frame.height == 0 {
                    print("   ❌ CRITICAL: Map has zero size - will be invisible!")
                } else {
                    print("   ✅ Map has valid size")
                }
            }
            
            // Test 2: Valid bounds container  
            print("\n🔍 TEST 2: Valid bounds container")
            let validBoundsContainer = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            print("   Container bounds: \(validBoundsContainer.bounds)")
            
            // Need to create fresh map since previous one was attached
            await preloader.preloadMapInBackground()
            preloader.attachToMainMapContainer(validBoundsContainer)
            
            if let mapView = validBoundsContainer.subviews.first {
                print("   Map frame after attachment: \(mapView.frame)")
                print("   Map bounds: \(mapView.bounds)")
                
                if mapView.frame.width > 0 && mapView.frame.height > 0 {
                    print("   ✅ Map has valid size - should be visible")
                } else {
                    print("   ❌ Map still has zero size")
                }
            }
            
            // Test 3: Check what happens in real SwiftUI container
            print("\n🔍 TEST 3: SwiftUI container simulation")
            let swiftuiContainer = UIView()
            print("   Initial container bounds: \(swiftuiContainer.bounds)")
            
            // This mimics what happens in makeUIView
            await preloader.preloadMapInBackground()
            preloader.attachToMainMapContainer(swiftuiContainer)
            
            if let mapView = swiftuiContainer.subviews.first {
                print("   Map frame in SwiftUI container: \(mapView.frame)")
                
                // Simulate layout update that happens later
                swiftuiContainer.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
                mapView.frame = swiftuiContainer.bounds
                print("   Map frame after layout update: \(mapView.frame)")
            }
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 20.0)
    }
}
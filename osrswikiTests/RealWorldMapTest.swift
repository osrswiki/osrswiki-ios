//
//  RealWorldMapTest.swift
//  OSRS Wiki Tests  
//
//  Tests that exactly mirror the real app behavior - no artificial waiting
//

import XCTest
import MapLibre
import SwiftUI
@testable import osrswiki

class RealWorldMapTest: XCTestCase {
    
    func testMainAppMapBehavior() {
        print("\n🚨 === REAL WORLD MAP TEST (NO ARTIFICIAL WAITING) ===")
        print("🎯 This test mimics exactly what happens when user taps Map tab")
        print("📱 Same timing, same conditions, same code path as real app\n")
        
        let testExpectation = expectation(description: "Real world test")
        
        Task { @MainActor in
            // Simulate user opening Map tab - NO waiting, NO special conditions
            // This is exactly what happens when user taps the tab
            
            let containerView = UIView()
            containerView.backgroundColor = .black
            
            print("📱 User tapped Map tab...")
            print("🔍 Checking if shared map is ready: \(osrsBackgroundMapPreloader.shared.isMapReady)")
            print("📊 Preloading progress: \(Int(osrsBackgroundMapPreloader.shared.preloadingProgress * 100))%")
            
            // EXACT SAME CODE as OSRSMapLibreView.makeUIView
            if osrsBackgroundMapPreloader.shared.isMapReady {
                print("✅ Using shared map instance - instant display!")
                osrsBackgroundMapPreloader.shared.attachToMainMapContainer(containerView)
                
                // Check what actually happened
                let subviewCount = containerView.subviews.count
                let hasMapView = containerView.subviews.first is MLNMapView
                
                print("📊 Container subviews: \(subviewCount)")
                print("📊 Has MLNMapView: \(hasMapView)")
                
                if let mapView = containerView.subviews.first as? MLNMapView {
                    print("📊 MapView bounds: \(mapView.bounds)")
                    print("📊 MapView hidden: \(mapView.isHidden)")
                    print("📊 MapView alpha: \(mapView.alpha)")
                    
                    if let style = mapView.style {
                        let totalLayers = style.layers.count
                        let rasterLayers = style.layers.compactMap { $0 as? MLNRasterStyleLayer }
                        let visibleRasters = rasterLayers.filter { layer in
                            if let opacityExpr = layer.rasterOpacity,
                               let opacity = opacityExpr.constantValue as? NSNumber {
                                return opacity.doubleValue > 0.0
                            }
                            return false
                        }
                        
                        print("📊 Total layers: \(totalLayers)")
                        print("📊 Raster layers: \(rasterLayers.count)")
                        print("📊 Visible rasters: \(visibleRasters.count)")
                        
                        if visibleRasters.count > 0 {
                            print("✅ REAL WORLD RESULT: Map should be visible")
                        } else {
                            print("❌ REAL WORLD RESULT: Map will be BLACK - no visible layers!")
                        }
                    } else {
                        print("❌ REAL WORLD RESULT: Map will be BLACK - no style!")
                    }
                } else {
                    print("❌ REAL WORLD RESULT: Map will be BLACK - no MapView attached!")
                }
                
            } else {
                print("⚠️ Shared map not ready - will show loading state")
                print("❌ REAL WORLD RESULT: User sees loading/black screen")
                
                // This is what actually happens - loading label, then waiting
                let loadingLabel = UILabel()
                loadingLabel.text = "Preparing map..."
                loadingLabel.textColor = .white
                loadingLabel.textAlignment = .center
                containerView.addSubview(loadingLabel)
                
                print("📊 Container shows loading label, no map yet")
            }
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0)
    }
}
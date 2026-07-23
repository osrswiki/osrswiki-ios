//
//  MainMapTabRenderingTest.swift
//  OSRS Wiki Tests  
//
//  Test to verify main Map tab actually renders after preloading
//

import XCTest
import MapLibre
import SwiftUI
@testable import osrswiki

class MainMapTabRenderingTest: XCTestCase {
    
    func testMainMapTabActualRendering() {
        print("\n🔥 === MAIN MAP TAB RENDERING TEST ===")
        print("🎯 Testing if preloaded shared map actually renders in main Map tab")
        
        let testExpectation = expectation(description: "Main map tab rendering test")
        
        Task { @MainActor in
            // Step 1: Wait for preloading to complete
            let preloader = osrsBackgroundMapPreloader.shared
            
            print("🔥 TEST: Checking preloader state...")
            print("🔥   - isMapReady: \(preloader.isMapReady)")
            print("🔥   - Status: \(preloader.statusSummary)")
            
            if !preloader.isMapReady {
                print("⏳ TEST: Waiting for preloading to complete...")
                var attempts = 0
                while !preloader.isMapReady && attempts < 200 {
                    try? await Task.sleep(for: .milliseconds(100))
                    attempts += 1
                    if attempts % 10 == 0 {
                        print("⏳   Progress: \(Int(preloader.preloadingProgress * 100))%")
                    }
                }
            }
            
            if !preloader.isMapReady {
                print("❌ TEST FAILED: Preloading never completed")
                testExpectation.fulfill()
                return
            }
            
            print("✅ TEST: Preloading complete, testing main map tab...")
            
            // Step 2: Create main map container (simulates Map tab)
            let mainMapContainer = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            mainMapContainer.backgroundColor = .systemBackground
            
            print("🔥 TEST: Created main map container: \(mainMapContainer.frame)")
            
            // Step 3: Attach shared map (this is what OSRSMapLibreView.makeUIView does)
            preloader.attachToMainMapContainer(mainMapContainer)
            
            print("🔥 TEST: Attachment called, waiting for post-attachment diagnostic...")
            
            // Step 4: Wait for post-attachment diagnostic and verify
            try? await Task.sleep(for: .milliseconds(1500)) // Wait for 1s diagnostic + buffer
            
            // Step 5: Manual verification of attachment state
            print("\n🔥 TEST VERIFICATION:")
            
            let hasSubviews = !mainMapContainer.subviews.isEmpty
            print("🔥   - Container has subviews: \(hasSubviews)")
            
            if let mapView = mainMapContainer.subviews.first {
                print("🔥   - MapView type: \(type(of: mapView))")
                print("🔥   - MapView frame: \(mapView.frame)")
                print("🔥   - MapView bounds: \(mapView.bounds)")
                print("🔥   - MapView hidden: \(mapView.isHidden)")
                print("🔥   - MapView alpha: \(mapView.alpha)")
                
                if let mlnMapView = mapView as? MLNMapView {
                    print("🔥   - MLNMapView center: \(mlnMapView.centerCoordinate)")
                    print("🔥   - MLNMapView zoom: \(mlnMapView.zoomLevel)")
                    
                    if let style = mlnMapView.style {
                        print("🔥   - Style layers: \(style.layers.count)")
                        print("🔥   - Style sources: \(style.sources.count)")
                        
                        // Check if any raster layers exist
                        let rasterLayers = style.layers.compactMap { $0 as? MLNRasterStyleLayer }
                        print("🔥   - Raster layers: \(rasterLayers.count)")
                        
                        for layer in rasterLayers {
                            if let opacity = layer.rasterOpacity?.constantValue as? Double {
                                print("🔥   - \(layer.identifier): opacity=\(opacity), visible=\(layer.isVisible)")
                            }
                        }
                        
                        // Test critical conditions
                        let hasValidFrame = mapView.frame.width > 0 && mapView.frame.height > 0
                        let isVisible = !mapView.isHidden && mapView.alpha > 0
                        let hasLayers = style.layers.count > 2 // background + annotations + floors
                        let hasVisibleLayers = rasterLayers.contains { layer in
                            if let opacity = layer.rasterOpacity?.constantValue as? Double {
                                return layer.isVisible && opacity > 0
                            }
                            return false
                        }
                        
                        print("\n🔥 TEST RESULTS:")
                        print("🔥   ✅ Has valid frame: \(hasValidFrame)")
                        print("🔥   ✅ Is visible: \(isVisible)")
                        print("🔥   ✅ Has layers: \(hasLayers)")
                        print("🔥   ✅ Has visible layers: \(hasVisibleLayers)")
                        
                        if hasValidFrame && isVisible && hasLayers && hasVisibleLayers {
                            print("🎉 TEST SUCCESS: Main map tab should be rendering correctly!")
                            print("🔍 If user still sees black screen, issue is likely:")
                            print("   1. GPU/Metal rendering context problem")
                            print("   2. SwiftUI integration timing issue")
                            print("   3. Off-screen to on-screen transition problem")
                        } else {
                            print("❌ TEST FAILURE: One or more critical conditions failed")
                            print("🔍 This explains why user sees black screen")
                        }
                        
                    } else {
                        print("❌ TEST FAILURE: MLNMapView has no style")
                    }
                } else {
                    print("❌ TEST FAILURE: Subview is not MLNMapView")
                }
            } else {
                print("❌ TEST FAILURE: No subviews in main container")
            }
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0)
    }
    
    func testSharedMapPreloadingState() {
        print("\n🔥 === SHARED MAP PRELOADING STATE TEST ===")
        print("🎯 Verifying shared map internal state")
        
        let testExpectation = expectation(description: "Shared map state test")
        
        Task { @MainActor in
            let preloader = osrsBackgroundMapPreloader.shared
            
            // Wait for preloading if not ready
            if !preloader.isMapReady {
                var attempts = 0
                while !preloader.isMapReady && attempts < 200 {
                    try? await Task.sleep(for: .milliseconds(100))
                    attempts += 1
                }
            }
            
            print("🔥 SHARED MAP STATE:")
            print("🔥   - isMapReady: \(preloader.isMapReady)")
            print("🔥   - Status: \(preloader.statusSummary)")
            
            if let sharedMapView = preloader.sharedMapView {
                print("🔥   - SharedMapView exists: YES")
                print("🔥   - Frame: \(sharedMapView.frame)")
                print("🔥   - Bounds: \(sharedMapView.bounds)")
                print("🔥   - Center: \(sharedMapView.centerCoordinate)")
                print("🔥   - Zoom: \(sharedMapView.zoomLevel)")
                print("🔥   - Hidden: \(sharedMapView.isHidden)")
                print("🔥   - Alpha: \(sharedMapView.alpha)")
                
                if let style = sharedMapView.style {
                    print("🔥   - Style layers: \(style.layers.count)")
                    print("🔥   - Style sources: \(style.sources.count)")
                    
                    for layer in style.layers {
                        print("🔥   - Layer: \(layer.identifier)")
                    }
                } else {
                    print("🔥   - Style: NIL")
                }
            } else {
                print("🔥   - SharedMapView: NIL")
            }
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0)
    }
}
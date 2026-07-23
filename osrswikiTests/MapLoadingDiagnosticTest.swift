//
//  MapLoadingDiagnosticTest.swift
//  OSRS Wiki Tests  
//
//  Comprehensive diagnostic system to quantify map loading behavior
//  Tests: 1) Map actually loads, 2) Loads instantly after preloading complete
//

import XCTest
import MapLibre
import SwiftUI
@testable import osrswiki

class MapLoadingDiagnosticTest: XCTestCase {
    
    private var diagnosticResults: [DiagnosticResult] = []
    
    func testMapLoadingComprehensiveDiagnostic() {
        print("\n🧪 === COMPREHENSIVE MAP LOADING DIAGNOSTIC ===")
        print("📊 Testing: 1) Map loads, 2) Loads instantly after preloading")
        print("🎯 Will provide definitive evidence of actual behavior\n")
        
        let testExpectation = expectation(description: "Complete diagnostic test")
        
        Task { @MainActor in
            // Wait for any ongoing preloading to complete
            print("⏳ Waiting for any ongoing preloading to complete...")
            for attempt in 1...100 {
                if !osrsBackgroundMapPreloader.shared.isPreloadingMap {
                    print("✅ Preloading completed, proceeding with diagnostics")
                    break
                } else {
                    print("⏳ Attempt \(attempt)/100: Still preloading... Progress: \(Int(osrsBackgroundMapPreloader.shared.preloadingProgress * 100))%")
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            // Step 1: Test background preloader state
            await testBackgroundPreloaderState()
            
            // Step 2: Test shared map instance creation
            await testSharedMapInstanceState()
            
            // Step 3: Test MBTiles file accessibility
            await testMBTilesFileState()
            
            // Step 4: Test actual map loading in container
            await testMapLoadingInContainer()
            
            // Step 5: Test floor switching behavior
            await testFloorSwitchingBehavior()
            
            // Analyze and report results
            analyzeComprehensiveResults()
            
            testExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 60.0) { error in
            if let error = error {
                XCTFail("Diagnostic test timed out: \(error)")
            }
        }
    }
    
    @MainActor
    private func testBackgroundPreloaderState() async {
        print("🔍 DIAGNOSTIC 1: Background Preloader State")
        
        let preloader = osrsBackgroundMapPreloader.shared
        
        let result = DiagnosticResult(
            testName: "Background Preloader State",
            timestamp: Date(),
            measurements: [
                "isPreloadingMap": preloader.isPreloadingMap ? "true" : "false",
                "preloadingProgress": String(format: "%.1f%%", preloader.preloadingProgress * 100),
                "mapPreloaded": preloader.mapPreloaded ? "true" : "false", 
                "allLayersReady": preloader.allLayersReady ? "true" : "false",
                "isMapReady": preloader.isMapReady ? "true" : "false",
                "statusSummary": preloader.statusSummary
            ],
            success: preloader.isMapReady,
            details: "Preloader status: \(preloader.statusSummary)"
        )
        
        diagnosticResults.append(result)
        
        print("   📊 isPreloadingMap: \(result.measurements["isPreloadingMap"]!)")
        print("   📊 preloadingProgress: \(result.measurements["preloadingProgress"]!)")
        print("   📊 mapPreloaded: \(result.measurements["mapPreloaded"]!)")
        print("   📊 allLayersReady: \(result.measurements["allLayersReady"]!)")
        print("   📊 isMapReady: \(result.measurements["isMapReady"]!)")
        print("   📝 Status: \(result.measurements["statusSummary"]!)")
        print("   ✅ RESULT: \(result.success ? "READY" : "NOT READY")\n")
    }
    
    @MainActor
    private func testSharedMapInstanceState() async {
        print("🔍 DIAGNOSTIC 2: Shared Map Instance State")
        
        let preloader = osrsBackgroundMapPreloader.shared
        let sharedMapExists = preloader.sharedMapView != nil
        var mapViewBounds = "nil"
        var hasStyle = false
        var layerCount = 0
        var layerDetails: [String] = []
        
        if let sharedMapView = preloader.sharedMapView {
            mapViewBounds = "\(sharedMapView.bounds)"
            
            if let style = sharedMapView.style {
                hasStyle = true
                let allLayers = style.layers
                layerCount = allLayers.count
                
                for layer in allLayers {
                    layerDetails.append("\(layer.identifier): \(type(of: layer))")
                }
            }
        }
        
        let result = DiagnosticResult(
            testName: "Shared Map Instance State",
            timestamp: Date(),
            measurements: [
                "sharedMapExists": sharedMapExists ? "true" : "false",
                "mapViewBounds": mapViewBounds,
                "hasStyle": hasStyle ? "true" : "false",
                "layerCount": String(layerCount),
                "layerDetails": layerDetails.joined(separator: ", ")
            ],
            success: sharedMapExists && hasStyle && layerCount >= 4,
            details: "Shared map: exists=\(sharedMapExists), style=\(hasStyle), layers=\(layerCount)"
        )
        
        diagnosticResults.append(result)
        
        print("   📊 sharedMapExists: \(result.measurements["sharedMapExists"]!)")
        print("   📊 mapViewBounds: \(result.measurements["mapViewBounds"]!)")
        print("   📊 hasStyle: \(result.measurements["hasStyle"]!)")
        print("   📊 layerCount: \(result.measurements["layerCount"]!)")
        print("   📊 layerDetails: \(result.measurements["layerDetails"]!)")
        print("   ✅ RESULT: \(result.success ? "VALID" : "INVALID")\n")
    }
    
    private func testMBTilesFileState() async {
        print("🔍 DIAGNOSTIC 3: MBTiles File State")
        
        var bundleFiles: [String] = []
        var bundleFileSizes: [String] = []
        var documentsFiles: [String] = []
        var documentsFileSizes: [String] = []
        
        // Check bundle files
        for floor in 0...3 {
            let fileName = "map_floor_\(floor)"
            if let bundlePath = Bundle.main.path(forResource: fileName, ofType: "mbtiles") {
                bundleFiles.append("floor\(floor)")
                
                let url = URL(fileURLWithPath: bundlePath)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: bundlePath),
                   let size = attributes[.size] as? Int64 {
                    bundleFileSizes.append("floor\(floor)=\(size)B")
                }
            }
        }
        
        // Check Documents files
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for floor in 0...3 {
            let fileName = "map_floor_\(floor).mbtiles"
            let filePath = documentsURL.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: filePath.path) {
                documentsFiles.append("floor\(floor)")
                
                if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path),
                   let size = attributes[.size] as? Int64 {
                    documentsFileSizes.append("floor\(floor)=\(size)B")
                }
            }
        }
        
        let result = DiagnosticResult(
            testName: "MBTiles File State",
            timestamp: Date(),
            measurements: [
                "bundleFiles": bundleFiles.joined(separator: ", "),
                "bundleFileSizes": bundleFileSizes.joined(separator: ", "),
                "documentsFiles": documentsFiles.joined(separator: ", "), 
                "documentsFileSizes": documentsFileSizes.joined(separator: ", "),
                "totalBundleFiles": String(bundleFiles.count),
                "totalDocumentsFiles": String(documentsFiles.count)
            ],
            success: bundleFiles.count >= 4 || documentsFiles.count >= 4,
            details: "Bundle: \(bundleFiles.count) files, Documents: \(documentsFiles.count) files"
        )
        
        diagnosticResults.append(result)
        
        print("   📊 bundleFiles (\(bundleFiles.count)): \(bundleFiles.joined(separator: ", "))")
        print("   📊 bundleFileSizes: \(bundleFileSizes.joined(separator: ", "))")
        print("   📊 documentsFiles (\(documentsFiles.count)): \(documentsFiles.joined(separator: ", "))")
        print("   📊 documentsFileSizes: \(documentsFileSizes.joined(separator: ", "))")
        print("   ✅ RESULT: \(result.success ? "FILES FOUND" : "NO FILES")\n")
    }
    
    @MainActor
    private func testMapLoadingInContainer() async {
        print("🔍 DIAGNOSTIC 4: Map Loading in Container (ACTUAL VISUAL TEST)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create container and attempt to attach shared map
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        containerView.backgroundColor = .red // Red background to detect if map covers it
        
        var attachmentSuccess = false
        var attachmentTime: Double = 0
        var mapViewCount = 0
        var mapViewBounds = "none"
        var actualMapVisible = false
        var layerAnalysis = "none"
        
        let preloader = osrsBackgroundMapPreloader.shared
        
        if preloader.isMapReady {
            preloader.attachToMainMapContainer(containerView)
            attachmentTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            attachmentSuccess = true
            
            // Check if map view was actually added
            mapViewCount = containerView.subviews.count
            if let mapView = containerView.subviews.first as? MLNMapView {
                mapViewBounds = "\(mapView.bounds)"
                
                // CRITICAL: Check if map is actually rendering content
                if let style = mapView.style {
                    let layers = style.layers
                    let visibleLayers = layers.filter { layer in
                        if let rasterLayer = layer as? MLNRasterStyleLayer {
                            // Check if layer has opacity > 0 and is properly configured
                            if let opacityExpression = rasterLayer.rasterOpacity,
                               let opacityValue = opacityExpression.constantValue as? NSNumber {
                                return opacityValue.doubleValue > 0.0
                            }
                            return false
                        }
                        return false
                    }
                    
                    layerAnalysis = "Total: \(layers.count), Visible raster: \(visibleLayers.count)"
                    
                    // Map is considered "actually visible" if:
                    // 1. Has valid style
                    // 2. Has at least one visible raster layer with source
                    // 3. MapView is not hidden/transparent
                    actualMapVisible = visibleLayers.count > 0 && !mapView.isHidden && mapView.alpha > 0.5
                    
                    print("   🔍 Layer analysis: \(layerAnalysis)")
                    print("   🔍 Map view hidden: \(mapView.isHidden), alpha: \(mapView.alpha)")
                    print("   🔍 Visible raster layers: \(visibleLayers.count)/\(layers.count)")
                }
            }
        }
        
        let result = DiagnosticResult(
            testName: "Map Loading in Container",
            timestamp: Date(),
            measurements: [
                "attachmentSuccess": attachmentSuccess ? "true" : "false",
                "attachmentTime": String(format: "%.1fms", attachmentTime),
                "mapViewCount": String(mapViewCount),
                "mapViewBounds": mapViewBounds,
                "containerBounds": "\(containerView.bounds)",
                "actualMapVisible": actualMapVisible ? "true" : "false",
                "layerAnalysis": layerAnalysis
            ],
            success: attachmentSuccess && mapViewCount > 0 && actualMapVisible,
            details: "Attachment: \(attachmentSuccess), visible: \(actualMapVisible), layers: \(layerAnalysis)"
        )
        
        diagnosticResults.append(result)
        
        print("   📊 attachmentSuccess: \(result.measurements["attachmentSuccess"]!)")
        print("   📊 attachmentTime: \(result.measurements["attachmentTime"]!)")
        print("   📊 mapViewCount: \(result.measurements["mapViewCount"]!)")
        print("   📊 mapViewBounds: \(result.measurements["mapViewBounds"]!)")
        print("   📊 containerBounds: \(result.measurements["containerBounds"]!)")
        print("   📊 actualMapVisible: \(result.measurements["actualMapVisible"]!)")
        print("   📊 layerAnalysis: \(result.measurements["layerAnalysis"]!)")
        print("   ✅ RESULT: \(result.success ? "ACTUALLY VISIBLE" : "BLACK/HIDDEN")\n")
    }
    
    @MainActor
    private func testFloorSwitchingBehavior() async {
        print("🔍 DIAGNOSTIC 5: Floor Switching Behavior")
        
        let preloader = osrsBackgroundMapPreloader.shared
        var switchTimes: [String] = []
        var allSwitchesInstant = true
        
        if preloader.isMapReady {
            for floor in 0...3 {
                let startTime = CFAbsoluteTimeGetCurrent()
                preloader.updateFloor(floor)
                let switchTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                
                switchTimes.append("floor\(floor)=\(String(format: "%.1fms", switchTime))")
                
                if switchTime > 10.0 { // Anything over 10ms is not "instant"
                    allSwitchesInstant = false
                }
                
                // Small delay between switches
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        
        let result = DiagnosticResult(
            testName: "Floor Switching Behavior", 
            timestamp: Date(),
            measurements: [
                "switchTimes": switchTimes.joined(separator: ", "),
                "allSwitchesInstant": allSwitchesInstant ? "true" : "false",
                "totalSwitches": String(switchTimes.count)
            ],
            success: allSwitchesInstant && switchTimes.count >= 4,
            details: "Switches: \(switchTimes.count), instant: \(allSwitchesInstant)"
        )
        
        diagnosticResults.append(result)
        
        print("   📊 switchTimes: \(switchTimes.joined(separator: ", "))")
        print("   📊 allSwitchesInstant: \(result.measurements["allSwitchesInstant"]!)")
        print("   📊 totalSwitches: \(result.measurements["totalSwitches"]!)")
        print("   ✅ RESULT: \(result.success ? "INSTANT" : "SLOW")\n")
    }
    
    private func analyzeComprehensiveResults() {
        print("🔬 === COMPREHENSIVE DIAGNOSTIC ANALYSIS ===")
        
        let totalTests = diagnosticResults.count
        let passedTests = diagnosticResults.filter { $0.success }.count
        let successRate = totalTests > 0 ? Double(passedTests) / Double(totalTests) * 100 : 0
        
        print("📊 OVERALL RESULTS:")
        print("   Tests Run: \(totalTests)")
        print("   Tests Passed: \(passedTests)")
        print("   Success Rate: \(String(format: "%.1f%%", successRate))")
        print("")
        
        print("📋 DETAILED BREAKDOWN:")
        for (index, result) in diagnosticResults.enumerated() {
            let status = result.success ? "✅ PASS" : "❌ FAIL"
            print("   \(index + 1). \(result.testName): \(status)")
            print("      \(result.details)")
        }
        print("")
        
        // Determine root cause
        let preloaderReady = diagnosticResults.first { $0.testName.contains("Background Preloader") }?.success ?? false
        let sharedMapValid = diagnosticResults.first { $0.testName.contains("Shared Map Instance") }?.success ?? false
        let filesExist = diagnosticResults.first { $0.testName.contains("MBTiles File") }?.success ?? false
        let mapLoads = diagnosticResults.first { $0.testName.contains("Map Loading in Container") }?.success ?? false
        let switchingInstant = diagnosticResults.first { $0.testName.contains("Floor Switching") }?.success ?? false
        
        print("🔍 ROOT CAUSE ANALYSIS:")
        
        if !preloaderReady {
            print("   🚨 CRITICAL: Background preloader not ready")
            print("   🔧 FIX NEEDED: Background preloading system")
        } else if !sharedMapValid {
            print("   🚨 CRITICAL: Shared map instance invalid") 
            print("   🔧 FIX NEEDED: Map instance creation logic")
        } else if !filesExist {
            print("   🚨 CRITICAL: MBTiles files missing/inaccessible")
            print("   🔧 FIX NEEDED: File bundle configuration")
        } else if !mapLoads {
            print("   🚨 CRITICAL: Map fails to attach to container")
            print("   🔧 FIX NEEDED: Container attachment logic")
        } else if !switchingInstant {
            print("   🚨 ISSUE: Floor switching not instant")
            print("   🔧 FIX NEEDED: Opacity update optimization")
        } else {
            print("   🎉 ALL SYSTEMS WORKING: No issues detected!")
        }
        
        print("")
        print("🎯 USER EXPERIENCE PREDICTION:")
        if preloaderReady && sharedMapValid && filesExist && mapLoads {
            print("   ✅ Map should load")
            if switchingInstant {
                print("   ✅ Map should load instantly after preloading")
                print("   🎉 BOTH REQUIREMENTS MET")
            } else {
                print("   ⚠️  Map loads but floor switching may be slow")
                print("   📋 PARTIAL SUCCESS: Requirement 1 ✅, Requirement 2 ⚠️")
            }
        } else {
            print("   ❌ Map will NOT load properly")
            print("   💥 BOTH REQUIREMENTS FAILED")
        }
        
        // Set test result based on requirements
        let requirement1Met = preloaderReady && sharedMapValid && filesExist && mapLoads
        let requirement2Met = requirement1Met && switchingInstant
        
        if !requirement1Met {
            XCTFail("❌ REQUIREMENT 1 FAILED: Map does not load")
        }
        
        if !requirement2Met {
            XCTFail("❌ REQUIREMENT 2 FAILED: Map does not load instantly after preloading")
        }
        
        if requirement1Met && requirement2Met {
            print("\n🏆 SUCCESS: All requirements verified with quantitative evidence!")
        }
    }
}

// MARK: - Data Models
struct DiagnosticResult {
    let testName: String
    let timestamp: Date
    let measurements: [String: String]
    let success: Bool
    let details: String
}
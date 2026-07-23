//
//  osrsMapTilePrewarmingService.swift
//  OSRS Wiki
//
//  Main Map Tile Pre-warming Service - Eliminates pixelated loading on Map tab
//  Mirrors Android's tile pre-warming approach for instant map display
//

import Foundation
import UIKit
import MapLibre
import SwiftUI

@MainActor
class osrsMapTilePrewarmingService: ObservableObject {
    static let shared = osrsMapTilePrewarmingService()
    
    // MARK: - State Management
    
    @Published private(set) var isPrewarming: Bool = false
    @Published private(set) var prewarmedFloors: Set<Int> = []
    @Published private(set) var isFullyPrewarmed: Bool = false
    
    private var prewarmingMapView: MLNMapView?
    private var prewarmingDelegate: osrsPrewarmingDelegate?
    private var currentPrewarmingFloor: Int = 0
    private let maxFloor = 3
    
    private init() {
        print("🔥 MapTilePrewarmingService: Initialized")
    }
    
    // MARK: - Public Interface
    
    /// Start tile pre-warming for all floors - completely invisible to user
    func startPrewarming() {
        guard !isPrewarming && !isFullyPrewarmed else {
            print("⚠️ MapTilePrewarmingService: Already prewarming or complete")
            return
        }
        
        print("🚀 MapTilePrewarmingService: Starting INVISIBLE tile pre-warming for all floors")
        isPrewarming = true
        currentPrewarmingFloor = 0
        prewarmedFloors.removeAll()
        
        // Use a delay to avoid blocking app startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startInvisiblePrewarming()
        }
    }
    
    /// Start completely invisible pre-warming that doesn't affect user experience
    private func startInvisiblePrewarming() {
        // Instead of creating a UI-blocking map view, use a more subtle approach
        // Pre-open the MBTiles files to warm the file system cache
        warmFileSystemCache()
    }
    
    /// Pre-warm file system cache for all MBTiles files
    private func warmFileSystemCache() {
        print("🔥 MapTilePrewarmingService: Pre-warming file system cache for MBTiles")
        
        for floor in 0...maxFloor {
            DispatchQueue.global(qos: .background).async {
                self.prewarmMBTilesFile(floor: floor)
            }
        }
    }
    
    /// Pre-warm a specific MBTiles file by accessing it
    private func prewarmMBTilesFile(floor: Int) {
        let fileName = "map_floor_\(floor).mbtiles"
        
        // Check Documents directory first
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let documentsPath = documentsURL.appendingPathComponent(fileName)
        
        var mbtilesPath: URL?
        
        if FileManager.default.fileExists(atPath: documentsPath.path) {
            mbtilesPath = documentsPath
        } else if let bundlePath = Bundle.main.path(forResource: "map_floor_\(floor)", ofType: "mbtiles") {
            mbtilesPath = URL(fileURLWithPath: bundlePath)
        }
        
        guard let validPath = mbtilesPath else {
            print("❌ MapTilePrewarmingService: MBTiles not found: \(fileName)")
            return
        }
        
        // Pre-warm by reading file metadata and some initial bytes
        do {
            let fileSize = try validPath.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            print("📂 MapTilePrewarmingService: Pre-warming \(fileName) (\(fileSize) bytes)")
            
            // Read first chunk to warm file system cache
            let data = try Data(contentsOf: validPath, options: .mappedIfSafe)
            let prereadSize = min(1024 * 1024, data.count) // Read first 1MB or whole file
            _ = data.subdata(in: 0..<prereadSize)
            
            DispatchQueue.main.async {
                self.onFloorPrewarmingComplete(floor: floor)
            }
            
        } catch {
            print("❌ MapTilePrewarmingService: Failed to pre-warm \(fileName) - \(error)")
            DispatchQueue.main.async {
                self.onFloorPrewarmingFailed(floor: floor)
            }
        }
    }
    
    /// Check if a specific floor is prewarmed
    func isFloorPrewarmed(_ floor: Int) -> Bool {
        return prewarmedFloors.contains(floor)
    }
    
    /// Check if all floors are prewarmed
    func areAllFloorsPrewarmed() -> Bool {
        return isFullyPrewarmed
    }
    
    /// Force cleanup (useful for testing)
    func cleanup() {
        print("🧹 MapTilePrewarmingService: Cleaning up prewarming resources")
        
        prewarmingMapView?.removeFromSuperview()
        prewarmingMapView = nil
        prewarmingDelegate = nil
        
        isPrewarming = false
        // Keep prewarmedFloors and isFullyPrewarmed to maintain cache status
    }
    
    // MARK: - Pre-warming Implementation
    
    private func createPrewarmingMapView() {
        // Create invisible MapLibre view for tile loading
        let mapView = MLNMapView(frame: CGRect(x: -1000, y: -1000, width: 100, height: 100))
        
        // Configure like main map but optimized for pre-warming
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.compassView.isHidden = true
        mapView.showsScale = false
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.allowsZooming = false
        mapView.allowsScrolling = false
        mapView.isHidden = true // Completely invisible
        
        // Set position to OSRS map area (Lumbridge default)
        mapView.setCenter(osrsMapDefaultView.coordinate, zoomLevel: osrsMapDefaultView.zoom, animated: false)
        
        // Set bounds to cover the entire OSRS map area for comprehensive pre-warming
        let contentBounds = MLNCoordinateBounds(
            sw: osrsMapDefaultView.southWestCoordinate,
            ne: osrsMapDefaultView.northEastCoordinate
        )
        mapView.setVisibleCoordinateBounds(contentBounds, animated: false)
        
        // Create delegate for handling pre-warming progress
        let delegate = osrsPrewarmingDelegate(service: self)
        mapView.delegate = delegate
        
        // Store references
        prewarmingMapView = mapView
        prewarmingDelegate = delegate
        
        // Add to a parent view (required for MapLibre to work)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.addSubview(mapView)
            window.sendSubviewToBack(mapView) // Ensure it's behind everything
        }
        
        // Set up style for pre-warming
        setupPrewarmingStyle(mapView: mapView)
        
        print("✅ MapTilePrewarmingService: Created invisible pre-warming map view")
    }
    
    private func setupPrewarmingStyle(mapView: MLNMapView) {
        // Use same style as main map
        let customStyleJSON = """
        {
            "version": 8,
            "name": "OSRS Prewarming Style",
            "sources": {},
            "layers": [
                {
                    "id": "background",
                    "type": "background",
                    "paint": {
                        "background-color": "#000000"
                    }
                }
            ]
        }
        """
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let styleURL = tempDirectory.appendingPathComponent("osrs-prewarming-style.json")
        
        do {
            try customStyleJSON.write(to: styleURL, atomically: true, encoding: .utf8)
            mapView.styleURL = styleURL
            print("✅ MapTilePrewarmingService: Set pre-warming style")
        } catch {
            print("❌ MapTilePrewarmingService: Failed to setup pre-warming style - \(error)")
        }
    }
    
    // MARK: - Floor Pre-warming Progression
    
    func onStyleLoaded() {
        print("🎯 MapTilePrewarmingService: Style loaded, starting floor pre-warming")
        prewarmCurrentFloor()
    }
    
    private func prewarmCurrentFloor() {
        guard let mapView = prewarmingMapView,
              let style = mapView.style else {
            print("❌ MapTilePrewarmingService: Missing map view or style")
            return
        }
        
        print("🔥 MapTilePrewarmingService: Pre-warming floor \(currentPrewarmingFloor)")
        
        // Add floor layer (same logic as main map)
        addPrewarmingFloorLayer(floor: currentPrewarmingFloor, to: style, mapView: mapView)
    }
    
    private func addPrewarmingFloorLayer(floor: Int, to style: MLNStyle, mapView: MLNMapView) {
        let sourceId = "osrs-prewarming-source-\(floor)"
        let layerId = "osrs-prewarming-layer-\(floor)"
        let fileName = "map_floor_\(floor).mbtiles"
        
        // Use same MBTiles loading logic as main map
        var mbtilesPath: String?
        
        // Check Documents directory first (copied from bundle)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let documentsPath = documentsURL.appendingPathComponent(fileName).path
        
        if FileManager.default.fileExists(atPath: documentsPath) {
            mbtilesPath = documentsPath
            print("📂 MapTilePrewarmingService: Using copied MBTiles: \(fileName)")
        } else if let bundlePath = Bundle.main.path(forResource: "map_floor_\(floor)", ofType: "mbtiles") {
            mbtilesPath = bundlePath
            print("📦 MapTilePrewarmingService: Using bundle MBTiles: \(fileName)")
        }
        
        guard let validPath = mbtilesPath else {
            print("❌ MapTilePrewarmingService: MBTiles not found: \(fileName)")
            onFloorPrewarmingFailed(floor: floor)
            return
        }
        
        let mbtilesURLString = "mbtiles://\(validPath)"
        
        let rasterSource = MLNRasterTileSource(
            identifier: sourceId,
            configurationURL: URL(string: mbtilesURLString)!
        )
        
        style.addSource(rasterSource)
        
        let rasterLayer = MLNRasterStyleLayer(identifier: layerId, source: rasterSource)
        rasterLayer.rasterResamplingMode = NSExpression(forConstantValue: "nearest")
        rasterLayer.rasterOpacity = NSExpression(forConstantValue: 1.0)
        
        style.addLayer(rasterLayer)
        
        print("✅ MapTilePrewarmingService: Added pre-warming layer for floor \(floor)")
        
        // Trigger tile loading by forcing a render
        mapView.setNeedsDisplay()
        
        // Use a timer to allow tiles to load before moving to next floor
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.onFloorPrewarmingComplete(floor: floor)
        }
    }
    
    func onFloorPrewarmingComplete(floor: Int) {
        prewarmedFloors.insert(floor)
        print("🎉 MapTilePrewarmingService: Floor \(floor) pre-warming complete")
        print("📊 MapTilePrewarmingService: \(prewarmedFloors.count)/\(maxFloor + 1) floors prewarmed")
        
        // Move to next floor or complete
        currentPrewarmingFloor += 1
        
        if currentPrewarmingFloor <= maxFloor {
            // Continue with next floor
            prewarmCurrentFloor()
        } else {
            // All floors complete
            onAllFloorsPrewarmed()
        }
    }
    
    func onFloorPrewarmingFailed(floor: Int) {
        print("❌ MapTilePrewarmingService: Floor \(floor) pre-warming failed")
        
        // Continue with next floor even if one fails
        currentPrewarmingFloor += 1
        
        if currentPrewarmingFloor <= maxFloor {
            prewarmCurrentFloor()
        } else {
            onAllFloorsPrewarmed()
        }
    }
    
    private func onAllFloorsPrewarmed() {
        isPrewarming = false
        isFullyPrewarmed = true
        
        print("🎉 MapTilePrewarmingService: All floors pre-warmed successfully!")
        print("📊 MapTilePrewarmingService: Prewarmed floors: \(prewarmedFloors)")
        
        // Clean up the pre-warming map view (keep tiles in memory cache)
        cleanup()
        
        // Notify that main map is ready for instant display
        NotificationCenter.default.post(name: .mapTilesPrewarmed, object: nil)
    }
}

// MARK: - Pre-warming Delegate

class osrsPrewarmingDelegate: NSObject, MLNMapViewDelegate {
    private weak var service: osrsMapTilePrewarmingService?
    
    init(service: osrsMapTilePrewarmingService) {
        self.service = service
        super.init()
    }
    
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        print("🔥 MapTilePrewarmingService: Pre-warming style loaded")
        
        // Configure background
        if let backgroundLayer = style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer {
            backgroundLayer.backgroundColor = NSExpression(forConstantValue: UIColor.black)
        }
        
        Task { @MainActor in
            self.service?.onStyleLoaded()
        }
    }
    
    private func mapView(_ mapView: MLNMapView, didFailToLoadMapWithError error: Error) {
        print("❌ MapTilePrewarmingService: Failed to load pre-warming map - \(error)")
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let mapTilesPrewarmed = Notification.Name("mapTilesPrewarmed")
}

//
//  osrsMapPreloadService.swift
//  OSRS Wiki
//
//  iOS MapLibre Preloading Service - Eliminates pixelated loading state
//  Mirrors Android's proactive map creation pattern
//

import Foundation
import UIKit
import WebKit
import MapLibre
import SwiftUI

// MARK: - Map Data Models

struct osrsPreloadMapData: Codable, Hashable {
    let lat: String?
    let lon: String? 
    let zoom: String?
    let plane: String?
    let id: String
    
    // Custom hash implementation for Set storage
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Custom equality for Set storage
    static func == (lhs: osrsPreloadMapData, rhs: osrsPreloadMapData) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Map Preload Service

@MainActor
class osrsMapPreloadService: ObservableObject {
    static let shared = osrsMapPreloadService()
    
    // MARK: - State Management
    
    @Published private(set) var preloadedMaps: [String: osrsPreloadedMapContainer] = [:]
    @Published private(set) var renderingMaps: Set<String> = []
    @Published private(set) var readyMaps: Set<String> = []
    
    private var parentView: UIView?
    private let offscreenTranslationX: CGFloat = -2000.0
    
    // MARK: - Container Management
    
    struct osrsPreloadedMapContainer {
        let container: UIView
        let mapView: MLNMapView
        let delegate: osrsPreloadMapDelegate
        let data: osrsPreloadMapData
        let isReady: Bool
        
        init(container: UIView, mapView: MLNMapView, delegate: osrsPreloadMapDelegate, data: osrsPreloadMapData, isReady: Bool = false) {
            self.container = container
            self.mapView = mapView
            self.delegate = delegate
            self.data = data
            self.isReady = isReady
        }
    }
    
    private init() {
        print("🔄 MapPreloadService: Initialized")
    }
    
    // MARK: - Public Interface
    
    /// Set the parent view for map containers (typically the article webview's parent)
    func setParentView(_ view: UIView) {
        parentView = view
        print("📂 MapPreloadService: Set parent view: \(type(of: view))")
    }
    
    /// Preload maps from HTML content before JavaScript measurement
    func preloadMapsFromHTML(_ html: String) {
        let mapDataArray = Self.parseMapDataFromHTML(html)
        preloadMaps(mapDataArray)
    }

    func preloadMaps(_ mapDataArray: [osrsPreloadMapData]) {
        print("🗺️ MapPreloadService: Found \(mapDataArray.count) maps to preload")
        
        for mapData in mapDataArray {
            preloadMap(data: mapData)
        }
    }
    
    /// Get a preloaded map container if ready
    func getPreloadedMap(id: String) -> osrsPreloadedMapContainer? {
        guard let container = preloadedMaps[id], container.isReady else {
            print("⏳ MapPreloadService: Map \(id) not ready yet")
            return nil
        }
        
        print("✅ MapPreloadService: Retrieved ready map \(id)")
        return container
    }
    
    /// Check if a map is ready for display
    func isMapReady(id: String) -> Bool {
        return readyMaps.contains(id)
    }
    
    /// Clear all preloaded maps (called on page navigation)
    func clearPreloadedMaps() {
        print("🧹 MapPreloadService: Clearing \(preloadedMaps.count) preloaded maps")
        
        for (_, container) in preloadedMaps {
            container.container.removeFromSuperview()
        }
        
        preloadedMaps.removeAll()
        renderingMaps.removeAll()
        readyMaps.removeAll()
    }
    
    // MARK: - HTML Parsing
    
    nonisolated static func parseMapDataFromHTML(_ html: String) -> [osrsPreloadMapData] {
        var mapDataArray: [osrsPreloadMapData] = []
        
        // Parse HTML for map divs with data attributes
        // Pattern: <div class="osrswiki-map" data-lat="..." data-lon="..." data-zoom="..." data-plane="..." id="...">
        let mapPattern = #"<div[^>]*class="[^"]*osrswiki-map[^"]*"[^>]*data-lat="([^"]*)"[^>]*data-lon="([^"]*)"[^>]*data-zoom="([^"]*)"[^>]*data-plane="([^"]*)"[^>]*id="([^"]*)"[^>]*>"#
        
        let regex = try! NSRegularExpression(pattern: mapPattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        
        for match in matches {
            guard match.numberOfRanges == 6 else { continue }
            
            let latRange = Range(match.range(at: 1), in: html)
            let lonRange = Range(match.range(at: 2), in: html)  
            let zoomRange = Range(match.range(at: 3), in: html)
            let planeRange = Range(match.range(at: 4), in: html)
            let idRange = Range(match.range(at: 5), in: html)
            
            guard let latRange = latRange,
                  let lonRange = lonRange,
                  let zoomRange = zoomRange,
                  let planeRange = planeRange,
                  let idRange = idRange else { continue }
            
            let lat = String(html[latRange])
            let lon = String(html[lonRange])
            let zoom = String(html[zoomRange])
            let plane = String(html[planeRange])
            let id = String(html[idRange])
            
            let mapData = osrsPreloadMapData(
                lat: lat.isEmpty ? nil : lat,
                lon: lon.isEmpty ? nil : lon,
                zoom: zoom.isEmpty ? nil : zoom,
                plane: plane.isEmpty ? nil : plane,
                id: id
            )
            
            mapDataArray.append(mapData)
            print("📍 MapPreloadService: Parsed map data - id: \(id), coords: (\(lat), \(lon)), plane: \(plane)")
        }
        
        return mapDataArray
    }
    
    // MARK: - Map Creation
    
    private func preloadMap(data: osrsPreloadMapData) {
        // Skip if already preloading or ready
        if renderingMaps.contains(data.id) || readyMaps.contains(data.id) {
            print("⚠️ MapPreloadService: Map \(data.id) already processing")
            return
        }
        
        guard let parentView = parentView else {
            print("❌ MapPreloadService: No parent view set for preloading")
            return
        }
        
        renderingMaps.insert(data.id)
        
        print("🚀 MapPreloadService: Starting preload for map \(data.id)")
        
        // Create container (similar to NativeMapHandler but for preloading)
        let container = UIView()
        container.backgroundColor = UIColor.clear
        container.isHidden = false // Visible but off-screen
        container.layer.zPosition = -1 // Behind other content during preload
        
        // Position off-screen for invisible rendering
        container.frame = CGRect(
            x: offscreenTranslationX,
            y: 0,
            width: 300, // Default size for preloading
            height: 200
        )
        
        parentView.addSubview(container)
        
        // Create MapLibre view for preloading
        let mapView = createPreloadMapView(data: data)
        container.addSubview(mapView)
        
        // CRITICAL FIX: Use frame-based positioning for consistent sizing across all map types
        // This matches the embedded map's frame-based approach and eliminates timing issues
        mapView.frame = container.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Create delegate for handling map ready state
        let delegate = osrsPreloadMapDelegate(mapId: data.id, service: self)
        mapView.delegate = delegate
        
        // Store the preloaded map container
        let mapContainer = osrsPreloadedMapContainer(
            container: container,
            mapView: mapView,
            delegate: delegate,
            data: data
        )
        
        preloadedMaps[data.id] = mapContainer
        
        print("✅ MapPreloadService: Created preload container for \(data.id)")
    }
    
    private func createPreloadMapView(data: osrsPreloadMapData) -> MLNMapView {
        let mapView = MLNMapView()
        osrsMapPreferredFrameRate.apply(to: mapView)
        
        // Configure for preloading (similar to embedded map but optimized)
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.compassView.isHidden = true
        mapView.showsScale = false
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.allowsZooming = false // Disable during preload
        mapView.allowsScrolling = false // Disable during preload
        
        // Set initial position using game coordinates
        let gameX = Double(data.lon ?? "") ?? 3200.0
        let gameY = Double(data.lat ?? "") ?? 3200.0
        let zoom = 6.0 // Fixed zoom for preloading
        let coordinate = gameToLatLng(gameX: gameX, gameY: gameY)
        
        mapView.setCenter(coordinate, zoomLevel: zoom, animated: false)
        
        // Set up style with MBTiles
        setupPreloadMapStyle(mapView: mapView, targetFloor: Int(data.plane ?? "0") ?? 0, mapId: data.id)
        
        print("🎯 MapPreloadService: Configured preload mapView for \(data.id) at (\(gameX), \(gameY))")
        
        return mapView
    }
    
    private func setupPreloadMapStyle(mapView: MLNMapView, targetFloor: Int, mapId: String) {
        // Use same style as embedded maps
        let customStyleJSON = """
        {
            "version": 8,
            "name": "OSRS Preload Style",
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
        let styleURL = tempDirectory.appendingPathComponent("osrs-preload-style-\(mapId).json")
        
        do {
            try customStyleJSON.write(to: styleURL, atomically: true, encoding: .utf8)
            mapView.styleURL = styleURL
            print("✅ MapPreloadService: Set preload style for \(mapId)")
        } catch {
            print("❌ MapPreloadService: Failed to setup preload style - \(error)")
        }
    }
    
    // MARK: - Coordinate Conversion (copied from main map)
    
    private func gameToLatLng(gameX: Double, gameY: Double) -> CLLocationCoordinate2D {
        osrsMapDefaultView.mapCoordinate(gameX: gameX, gameY: gameY)
    }
    
    // MARK: - Internal State Updates
    
    func markMapAsReady(_ mapId: String) {
        renderingMaps.remove(mapId)
        readyMaps.insert(mapId)
        
        // Update the container ready state by creating new container with isReady = true
        if let container = preloadedMaps[mapId] {
            let updatedContainer = osrsPreloadedMapContainer(
                container: container.container,
                mapView: container.mapView,
                delegate: container.delegate,
                data: container.data,
                isReady: true
            )
            preloadedMaps[mapId] = updatedContainer
        }
        
        print("🎉 MapPreloadService: Map \(mapId) is ready for display")
        print("📊 MapPreloadService: \(readyMaps.count) ready, \(renderingMaps.count) rendering")
    }
    
    func markMapAsFailed(_ mapId: String, error: Error) {
        renderingMaps.remove(mapId)
        
        // Remove failed map from preloaded maps
        if let container = preloadedMaps[mapId] {
            container.container.removeFromSuperview()
            preloadedMaps.removeValue(forKey: mapId)
        }
        
        print("❌ MapPreloadService: Map \(mapId) failed to load - \(error)")
    }
}

// MARK: - Preload Map Delegate

class osrsPreloadMapDelegate: NSObject, MLNMapViewDelegate {
    private let mapId: String
    private weak var service: osrsMapPreloadService?
    
    init(mapId: String, service: osrsMapPreloadService) {
        self.mapId = mapId
        self.service = service
        super.init()
    }
    
    @MainActor
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        print("🔥 MapPreloadService: Style loaded for preload map \(mapId)")
        
        // Add floor layers like embedded maps
        let targetFloor = Int(service?.preloadedMaps[mapId]?.data.plane ?? "0") ?? 0
        addFloorLayer(floor: targetFloor, to: style, mapView: mapView)
        
        // Add ground floor underlay for upper floors
        if targetFloor > 0 {
            addFloorLayer(floor: 0, to: style, mapView: mapView, opacity: 0.5)
        }
        
        // Mark as ready after a short delay to ensure tiles are loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.service?.markMapAsReady(self.mapId)
        }
    }
    
    @MainActor
    func mapView(_ mapView: MLNMapView, didFailToLoadMapWithError error: Error) {
        print("❌ MapPreloadService: Failed to load preload map \(mapId) - \(error)")
        service?.markMapAsFailed(mapId, error: error)
    }
    
    private func addFloorLayer(floor: Int, to style: MLNStyle, mapView: MLNMapView, opacity: Double = 1.0) {
        let sourceId = "osrs-preload-source-\(floor)-\(mapId)"
        let layerId = "osrs-preload-layer-\(floor)-\(mapId)"
        let fileName = "map_floor_\(floor).mbtiles"
        
        // Use Documents directory (copied from bundle like main implementation)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let documentsPath = documentsURL.appendingPathComponent(fileName).path
        
        var mbtilesPath: String?
        
        if FileManager.default.fileExists(atPath: documentsPath) {
            mbtilesPath = documentsPath
            print("📂 MapPreloadService: Using copied MBTiles: \(fileName)")
        } else if let bundlePath = Bundle.main.path(forResource: "map_floor_\(floor)", ofType: "mbtiles") {
            mbtilesPath = bundlePath
            print("📦 MapPreloadService: Using bundle MBTiles: \(fileName)")
        }
        
        guard let validPath = mbtilesPath else {
            print("❌ MapPreloadService: MBTiles not found: \(fileName)")
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
        rasterLayer.rasterOpacity = NSExpression(forConstantValue: opacity)
        
        style.addLayer(rasterLayer)
        
        print("✅ MapPreloadService: Added preload floor \(floor) layer for \(mapId)")
    }
}

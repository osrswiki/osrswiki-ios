//
//  osrsNativeMapHandler.swift
//  OSRS Wiki
//
//  iOS equivalent of Android's NativeMapHandler for in-article MapLibre embeds
//

import SwiftUI
import UIKit
import WebKit
import MapLibre
import CoreLocation

// MARK: - Data Models (matching Android JSON structure)

struct osrsMapRect: Codable {
    let y: Double
    let x: Double  
    let width: Double
    let height: Double
}

struct osrsMapData: Codable {
    let lat: String?
    let lon: String?
    let zoom: String?
    let plane: String?
}

struct osrsEmbeddedMapLayoutState {
    static let offscreenTranslationX: CGFloat = -2000.0

    private(set) var visibleFrame: CGRect
    private(set) var isVisible: Bool

    mutating func updateVisibleFrame(_ frame: CGRect) -> CGRect {
        visibleFrame = frame
        return currentFrame
    }

    mutating func applyVisibility(isVisible: Bool) -> CGRect {
        self.isVisible = isVisible
        return currentFrame
    }

    var currentFrame: CGRect {
        var frame = visibleFrame
        if !isVisible {
            frame.origin.x += Self.offscreenTranslationX
        }
        return frame
    }
}

// MARK: - Native Map Handler

class osrsNativeMapHandler: NSObject {
    weak var articleWebView: WKWebView?
    private var mapContainers: [String: UIView] = [:]
    private var mapLayoutStates: [String: osrsEmbeddedMapLayoutState] = [:]
    private var mapContentYById: [String: CGFloat] = [:]
    
    // CRITICAL FIX: Store delegates and MapViews to prevent deallocation (Android pattern)
    private var mapDelegates: [String: osrsEmbeddedMapDelegate] = [:]
    private var mapViews: [String: MLNMapView] = [:]
    
    private let offscreenTranslationX = osrsEmbeddedMapLayoutState.offscreenTranslationX
    
    @Published var isHorizontalScrollInProgress = false
    
    // Storage for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // Track observer state to prevent double removal crashes
    private var hasScrollObserver = false
    private var isCleanedUp = false
    
    init(webView: WKWebView) {
        self.articleWebView = webView
        super.init()
        setupScrollListener()
        setupGestureIntegration()
        
        // CRITICAL FIX: Copy MBTiles to Documents like Android copies to filesDir
        copyMBTilesToDocuments()
    }
    
    // MARK: - MBTiles Management (Android Pattern)
    
    private func copyMBTilesToDocuments() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        for floor in 0...3 {
            let fileName = "map_floor_\(floor).mbtiles"
            let destinationURL = documentsURL.appendingPathComponent(fileName)
            
            // Check if we need to update existing files (compare file sizes)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                guard let bundlePath = Bundle.main.path(forResource: "map_floor_\(floor)", ofType: "mbtiles") else {
                    print("❌ MBTiles not found in bundle: \(fileName)")
                    continue
                }
                
                do {
                    let bundleAttributes = try FileManager.default.attributesOfItem(atPath: bundlePath)
                    let documentsAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                    
                    let bundleSize = bundleAttributes[.size] as? Int64 ?? 0
                    let documentsSize = documentsAttributes[.size] as? Int64 ?? 0
                    
                    if bundleSize == documentsSize {
                        print("📂 MBTiles up to date: \(fileName) (\(bundleSize) bytes)")
                        continue
                    } else {
                        print("🔄 MBTiles size changed: \(fileName) (bundle: \(bundleSize), docs: \(documentsSize)) - updating...")
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                } catch {
                    print("⚠️ Could not compare file sizes for \(fileName), will re-copy: \(error)")
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }
            
            // Copy from bundle to Documents
            guard let bundlePath = Bundle.main.path(forResource: "map_floor_\(floor)", ofType: "mbtiles") else {
                print("❌ MBTiles not found in bundle: \(fileName)")
                continue
            }
            
            do {
                try FileManager.default.copyItem(atPath: bundlePath, toPath: destinationURL.path)
                print("✅ Copied MBTiles to Documents: \(fileName)")
            } catch {
                print("❌ Failed to copy MBTiles \(fileName): \(error)")
            }
        }
    }
    
    // MARK: - JavaScript Bridge Methods (equivalent to @JavascriptInterface)
    
    func onMapPlaceholderMeasured(id: String, rectJson: String, mapDataJson: String) {
        print("🔥 CRITICAL DEBUG: onMapPlaceholderMeasured called for \(id)")
        print("🔥 Rect JSON: \(rectJson)")
        print("🔥 Map Data JSON: \(mapDataJson)")
        
        guard let webView = articleWebView else { 
            print("❌ CRITICAL: No articleWebView found")
            return 
        }
        
        do {
            guard let rectData = rectJson.data(using: .utf8),
                  let mapDataData = mapDataJson.data(using: .utf8) else {
                print("❌ CRITICAL ERROR: Failed to convert JSON strings to UTF8 data")
                return
            }
            
            let rect = try JSONDecoder().decode(osrsMapRect.self, from: rectData)
            let mapData = try JSONDecoder().decode(osrsMapData.self, from: mapDataData)
            
            print("🔥 Parsed rect: x=\(rect.x), y=\(rect.y), w=\(rect.width), h=\(rect.height)")
            print("🔥 Parsed mapData: lat=\(mapData.lat ?? "nil"), lon=\(mapData.lon ?? "nil"), zoom=\(mapData.zoom ?? "nil"), plane=\(mapData.plane ?? "nil")")
            
            DispatchQueue.main.async { [weak self] in
                print("🔥 CRITICAL: About to call preloadMap")
                self?.preloadMap(id: id, rect: rect, mapData: mapData, webView: webView)
                print("🔥 CRITICAL: preloadMap call completed")
            }
        } catch {
            print("❌ CRITICAL ERROR: Failed to parse JSON - \(error)")
        }
    }
    
    func onCollapsibleToggled(mapId: String, isOpening: Bool) {
        print("🔥 TOGGLE: onCollapsibleToggled - \(mapId), opening: \(isOpening)")
        
        guard let webView = articleWebView,
              let container = mapContainers[mapId] else { 
            print("❌ TOGGLE ERROR: WebView or container not found for \(mapId)")
            return 
        }
        
        print("🔥 TOGGLE: Container found for \(mapId)")
        print("🔥 TOGGLE: Container current frame: \(container.frame)")
        print("🔥 TOGGLE: Container superview: \(container.superview != nil ? "EXISTS" : "NIL")")
        print("🔥 TOGGLE: Container isHidden: \(container.isHidden)")
        print("🔥 TOGGLE: Container alpha: \(container.alpha)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var layoutState = self.mapLayoutStates[mapId] ?? osrsEmbeddedMapLayoutState(
                visibleFrame: container.frame.offsetBy(dx: -self.offscreenTranslationX, dy: 0),
                isVisible: container.frame.origin.x >= 0
            )
            container.frame = layoutState.applyVisibility(isVisible: isOpening)
            self.mapLayoutStates[mapId] = layoutState

            if isOpening {
                print("🔥 TOGGLE: OPENING map \(mapId)")
                print("🔥 TOGGLE: New container frame: \(container.frame)")
                
                // Hide WebView placeholder
                let script = "var el = document.getElementById('\(mapId)'); if (el) { el.style.opacity = 0; }"
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print("❌ TOGGLE: JavaScript error hiding placeholder: \(error)")
                    } else {
                        print("✅ TOGGLE: WebView placeholder hidden for \(mapId)")
                    }
                }
                
                // Check if map view inside container is visible
                if let mapView = container.subviews.first {
                    print("🔥 TOGGLE: MapView inside container:")
                    print("🔥   - Frame: \(mapView.frame)")
                    print("🔥   - Bounds: \(mapView.bounds)")
                    print("🔥   - Hidden: \(mapView.isHidden)")
                    print("🔥   - Alpha: \(mapView.alpha)")
                    
                    // Force redraw
                    mapView.setNeedsDisplay()
                }
                
                print("✅ TOGGLE: Showing native map for \(mapId)")
            } else {
                print("🔥 TOGGLE: CLOSING map \(mapId)")
                print("🔥 TOGGLE: New container frame: \(container.frame)")
                
                // Show WebView placeholder
                let script = "var el = document.getElementById('\(mapId)'); if (el) { el.style.opacity = 1; }"
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print("❌ TOGGLE: JavaScript error showing placeholder: \(error)")
                    } else {
                        print("✅ TOGGLE: WebView placeholder shown for \(mapId)")
                    }
                }
                
                print("✅ TOGGLE: Hiding native map for \(mapId)")
            }
        }
    }
    
    func setHorizontalScroll(inProgress: Bool) {
        print("🗺️ iOS Map Handler: setHorizontalScroll - \(inProgress)")
        self.isHorizontalScrollInProgress = inProgress
    }
    
    func log(message: String) {
        print("🗺️ JS: \(message)")
    }

#if DEBUG
    var activeMapContainerIdentifiersForTesting: [String] {
        mapContainers.keys.sorted()
    }

    func mapContainerFrameForTesting(id: String) -> CGRect? {
        mapContainers[id]?.frame
    }
#endif
    
    // MARK: - Private Implementation
    
    private func preloadMap(id: String, rect: osrsMapRect, mapData: osrsMapData, webView: WKWebView) {
        print("🔥 CRITICAL: preloadMap started for \(id)")
        
        if updateExistingMapContainer(id: id, rect: rect, webView: webView) {
            print("🔥 CRITICAL: Container \(id) already exists - updated layout")
            return
        }
        
        // PRELOADING INTEGRATION: Check if map is already preloaded
        Task { @MainActor in
            if let preloadedContainer = osrsMapPreloadService.shared.getPreloadedMap(id: id) {
                print("🚀 CRITICAL: Using preloaded map for \(id) - zero loading time!")
                
                // Use the preloaded map container
                self.usePreloadedMap(id: id, rect: rect, preloadedContainer: preloadedContainer, webView: webView)
                return
            }
            
            print("⏳ FALLBACK: Map \(id) not preloaded, creating on-demand (will show loading)")
            self.createMapOnDemand(id: id, rect: rect, mapData: mapData, webView: webView)
        }
    }
    
    // MARK: - Preloaded Map Usage
    
    private func usePreloadedMap(id: String, rect: osrsMapRect, preloadedContainer: osrsMapPreloadService.osrsPreloadedMapContainer, webView: WKWebView) {
        guard webView.superview != nil else {
            print("❌ CRITICAL ERROR: No parent view for preloaded map")
            return
        }
        
        // Move the preloaded container to the correct position and size
        let container = preloadedContainer.container
        configureAccessibility(for: container, id: id)
        
        let visibleFrame = calculateVisibleFrame(rect: rect, webView: webView)
        let layoutState = osrsEmbeddedMapLayoutState(visibleFrame: visibleFrame, isVisible: false)
        container.frame = layoutState.currentFrame
        
        // Store in our containers map for toggle handling
        mapContainers[id] = container
        mapLayoutStates[id] = layoutState
        mapContentYById[id] = CGFloat(rect.y)
        
        print("🎉 CRITICAL SUCCESS: Preloaded map \(id) positioned and ready for instant display")
    }
    
    // MARK: - On-Demand Map Creation (Fallback)
    
    private func createMapOnDemand(id: String, rect: osrsMapRect, mapData: osrsMapData, webView: WKWebView) {
        // Original implementation as fallback when preloading didn't work
        
        // CRITICAL FIX: Use parent view like Android uses binding.root (parent ConstraintLayout)
        // Android: binding.root.addView(container)
        guard let parentView = webView.superview else {
            print("❌ CRITICAL ERROR: No parent view for WebView")
            print("🔥 WebView hierarchy: \(webView)")
            return
        }
        
        print("🔥 CRITICAL: Found parent view: \(type(of: parentView))")
        
        // Create container view (equivalent to Android's FragmentContainerView)
        let container = UIView()
        container.backgroundColor = UIColor.clear
        container.isHidden = false // Visible but positioned off-screen
        container.layer.zPosition = 0 // Default layer - let view hierarchy handle z-ordering
        configureAccessibility(for: container, id: id)
        
        // Position will be set in frame calculation below (no transforms needed)
        
        // CRITICAL FIX: Add to parent view like Android adds to binding.root
        parentView.addSubview(container)
        mapContainers[id] = container
        
        let visibleFrame = calculateVisibleFrame(rect: rect, webView: webView)
        let layoutState = osrsEmbeddedMapLayoutState(visibleFrame: visibleFrame, isVisible: false)
        
        print("🎯 iOS Map Handler: Positioning container - width:\(visibleFrame.width), height:\(visibleFrame.height), top:\(visibleFrame.origin.y), left:\(visibleFrame.origin.x), scale:\(webView.scrollView.zoomScale)")
        print("🔍 iOS Map Handler: WebView frame: \(webView.frame), rect: x:\(rect.x) y:\(rect.y)")
        
        // Set frame directly (matching Android's direct positioning approach)
        container.frame = layoutState.currentFrame
        mapLayoutStates[id] = layoutState
        mapContentYById[id] = CGFloat(rect.y)
        
        // Create embedded MapLibre view with proper retention
        let mapView = createEmbeddedMapView(mapData: mapData, mapId: id)
        mapView.accessibilityIdentifier = "native_map_view_\(id)"
        mapView.accessibilityLabel = "Embedded OSRS map"
        container.addSubview(mapView)
        
        // CRITICAL FIX: Use frame-based positioning instead of Auto Layout for embedded maps
        // This matches the container's frame-based approach and eliminates timing issues
        mapView.frame = container.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        print("🔥 CRITICAL SUCCESS: Created embedded map container \(id)")
        print("🔥 Container frame: \(container.frame)")
        print("🔥 Container superview: \(container.superview != nil ? "YES" : "NO")")
        print("🔥 MapView frame: \(mapView.frame)")
        print("🔥 Total containers: \(mapContainers.count)")
    }

    private func updateExistingMapContainer(id: String, rect: osrsMapRect, webView: WKWebView) -> Bool {
        guard let container = mapContainers[id] else { return false }
        configureAccessibility(for: container, id: id)

        let visibleFrame = calculateVisibleFrame(rect: rect, webView: webView)
        var layoutState = mapLayoutStates[id] ?? osrsEmbeddedMapLayoutState(
            visibleFrame: visibleFrame,
            isVisible: false
        )
        container.frame = layoutState.updateVisibleFrame(visibleFrame)
        mapLayoutStates[id] = layoutState
        mapContentYById[id] = CGFloat(rect.y)

        if let mapView = container.subviews.first {
            mapView.frame = CGRect(origin: .zero, size: visibleFrame.size)
            mapView.setNeedsDisplay()
        }

        return true
    }

    private func configureAccessibility(for container: UIView, id: String) {
        container.isAccessibilityElement = true
        container.accessibilityIdentifier = "native_map_container_\(id)"
        container.accessibilityLabel = "Embedded OSRS map container"
    }

    private func calculateVisibleFrame(rect: osrsMapRect, webView: WKWebView) -> CGRect {
        let correction: CGFloat = 1.0
        let width = CGFloat(rect.width) + correction
        let height = CGFloat(rect.height)
        let webViewContentOffset = webView.scrollView.contentOffset
        let safeAreaTop = webView.safeAreaInsets.top
        let baseTopMargin = webView.frame.origin.y + CGFloat(rect.y) - webViewContentOffset.y
        let minAllowedTop = safeAreaTop + 60
        let topMargin = max(baseTopMargin, minAllowedTop)
        let leftMargin = webView.frame.origin.x + CGFloat(rect.x) - webViewContentOffset.x

        print("🔧 ZINDEX DEBUG: safeAreaTop=\(safeAreaTop), baseTopMargin=\(baseTopMargin), minAllowed=\(minAllowedTop), finalTopMargin=\(topMargin)")

        return CGRect(x: leftMargin, y: topMargin, width: width, height: height)
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert OSRS in-game coordinates to geographical coordinates for MapLibre
    /// This matches the Android implementation exactly
    private func gameToLatLng(gameX: Double, gameY: Double) -> CLLocationCoordinate2D {
        osrsMapDefaultView.mapCoordinate(gameX: gameX, gameY: gameY)
    }
    
    private func createEmbeddedMapView(mapData: osrsMapData, mapId: String) -> MLNMapView {
        let mapView = MLNMapView()
        
        // Configure like main map but optimized for embedding
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.compassView.isHidden = true
        mapView.showsScale = false
        mapView.allowsRotating = false // Disable rotation for embeds
        mapView.allowsTilting = false
        mapView.allowsZooming = true
        mapView.allowsScrolling = true
        
        // Parse OSRS in-game coordinates
        let gameX = Double(mapData.lon ?? "") ?? 3200.0 // Note: OSRS wiki uses lon for X coordinate
        let gameY = Double(mapData.lat ?? "") ?? 3200.0 // Note: OSRS wiki uses lat for Y coordinate  
        let zoom = 6.0 // CRITICAL FIX: Use hardcoded zoom like Android (not JSON zoom value)
        let plane = Int(mapData.plane ?? "0") ?? 0
        
        print("🎯 iOS Map Handler: Converting OSRS coordinates gameX:\(gameX), gameY:\(gameY), zoom:\(zoom), plane:\(plane)")
        
        // Convert OSRS coordinates to geographical coordinates (matching Android implementation)
        let geographicalCoords = gameToLatLng(gameX: gameX, gameY: gameY)
        
        print("🌍 iOS Map Handler: Converted to geographical lat:\(geographicalCoords.latitude), lon:\(geographicalCoords.longitude)")
        
        // Set initial position using converted coordinates
        mapView.setCenter(geographicalCoords, zoomLevel: zoom, animated: false)
        
        // CRITICAL FIX: Store MapView to prevent deallocation (Android pattern)
        mapViews[mapId] = mapView
        
        // Set up map style and tiles (reuse logic from main map)
        setupEmbeddedMapStyle(mapView: mapView, targetFloor: plane, mapId: mapId)
        
        return mapView
    }
    
    private func setupEmbeddedMapStyle(mapView: MLNMapView, targetFloor: Int, mapId: String) {
        // CRITICAL FIX: Use the same style JSON as the main map to ensure tiles load
        // This matches Android's approach of using the same map configuration
        let customStyleJSON = """
        {
            "version": 8,
            "name": "OSRS Embedded Map Style",
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
        let styleURL = tempDirectory.appendingPathComponent("osrs-embedded-style-\(mapId).json")
        
        do {
            try customStyleJSON.write(to: styleURL, atomically: true, encoding: .utf8)
            mapView.styleURL = styleURL
            
            // CRITICAL FIX: Store delegate to prevent deallocation (Android pattern)
            let delegate = osrsEmbeddedMapDelegate(targetFloor: targetFloor, mapId: mapId)
            mapDelegates[mapId] = delegate  // Retain delegate
            mapView.delegate = delegate
            
            print("✅ iOS Map Handler: Set up embedded map style for floor \(targetFloor), mapId: \(mapId)")
            
        } catch {
            print("❌ iOS Map Handler: Failed to setup embedded map style - \(error)")
        }
    }
    
    private func setupScrollListener() {
        guard let webView = articleWebView, !hasScrollObserver else { return }
        
        // Observe WebView scroll changes to keep map containers in sync
        webView.scrollView.addObserver(self, forKeyPath: "contentOffset", options: .new, context: nil)
        hasScrollObserver = true
        print("✅ osrsNativeMapHandler: KVO observer added for contentOffset")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, 
                              change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentOffset" {
            guard let webView = articleWebView else { return }
            let scrollY = webView.scrollView.contentOffset.y
            
            // CRITICAL FIX: Use frame-based scroll handling with proper clipping behavior
            // Match Android's translationY = -scrollY behavior using frames
            let safeAreaTop = webView.safeAreaInsets.top
            let minAllowedTop = safeAreaTop + 60 // Same buffer as positioning logic
            
            for (mapId, container) in mapContainers {
                guard var layoutState = mapLayoutStates[mapId],
                      let contentY = mapContentYById[mapId] else { continue }
                let originalHeight = layoutState.visibleFrame.height
                let originalWidth = layoutState.visibleFrame.width
                
                // Calculate where the container should be positioned
                let calculatedY = webView.frame.origin.y + contentY - scrollY
                var updatedVisibleFrame = layoutState.visibleFrame
                updatedVisibleFrame.origin.y = calculatedY

                if calculatedY < minAllowedTop {
                    // Widget would overlap navigation bar
                    let webViewContentTop = webView.frame.origin.y + webView.safeAreaInsets.top
                    
                    // Check if the entire widget is above the content area
                    if calculatedY + originalHeight <= webViewContentTop {
                        // Completely hidden - entire widget is above visible area
                        container.isHidden = true
                        print("🔧 ZINDEX SCROLL: Hiding widget - entire widget above content area")
                    } else {
                        // Partially visible - position container at safe boundary and mask content
                        container.isHidden = false
                        
                        // Position container at the actual WebView content boundary
                        // The real boundary is where the WebView content starts, not minAllowedTop
                        let webViewContentTop = webView.frame.origin.y + webView.safeAreaInsets.top
                        updatedVisibleFrame.origin.y = webViewContentTop
                        container.frame = layoutState.updateVisibleFrame(updatedVisibleFrame)
                        mapLayoutStates[mapId] = layoutState
                        
                        // Recalculate overlap based on actual WebView content boundary
                        let actualOverlap = webViewContentTop - calculatedY
                        
                        // Create a mask that shows the bottom portion of the original content
                        let maskLayer = CALayer()
                        maskLayer.backgroundColor = UIColor.black.cgColor
                        // Show only the portion that would be visible (bottom part of original content)
                        maskLayer.frame = CGRect(
                            x: 0,
                            y: 0,  // Mask starts at top of repositioned container
                            width: originalWidth,
                            height: originalHeight - actualOverlap  // Height of visible portion
                        )
                        
                        // Shift the MapLibre content up so we see the correct portion
                        if let mapView = container.subviews.first {
                            mapView.frame = CGRect(
                                x: 0,
                                y: -actualOverlap,  // Shift content up to show bottom portion
                                width: originalWidth,
                                height: originalHeight
                            )
                        }
                        
                        // Apply the mask to clip GPU-rendered MapLibre content
                        container.layer.mask = maskLayer
                        
                        print("🔧 ZINDEX SCROLL: PRECISE clipping - calculatedY: \(calculatedY), webViewContentTop: \(webViewContentTop), actualOverlap: \(actualOverlap), maskHeight: \(originalHeight - actualOverlap)")
                    }
                } else {
                    // Fully in safe area - normal positioning and remove mask
                    container.isHidden = false
                    
                    // Update position normally
                    container.frame = layoutState.updateVisibleFrame(updatedVisibleFrame)
                    mapLayoutStates[mapId] = layoutState
                    
                    // Remove any clipping mask and reset MapLibre content positioning
                    container.layer.mask = nil
                    
                    // Reset MapLibre content to normal position
                    if let mapView = container.subviews.first {
                        mapView.frame = CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight)
                    }
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Prevent multiple cleanup calls that cause crashes
        guard !isCleanedUp else {
            print("⚠️ osrsNativeMapHandler: cleanup() already called, skipping")
            return
        }
        
        print("🗺️ iOS Map Handler: Cleaning up \(mapContainers.count) map containers")
        isCleanedUp = true
        
        // Remove all containers
        for container in mapContainers.values {
            container.removeFromSuperview()
        }
        mapContainers.removeAll()
        mapLayoutStates.removeAll()
        mapContentYById.removeAll()
        
        // CRITICAL FIX: Clean up retained delegates and MapViews (Android pattern)
        mapDelegates.removeAll()
        mapViews.removeAll()
        
        // Remove scroll observer safely to prevent crashes
        if hasScrollObserver, let webView = articleWebView {
            do {
                webView.scrollView.removeObserver(self, forKeyPath: "contentOffset")
                hasScrollObserver = false
                print("✅ osrsNativeMapHandler: KVO observer removed for contentOffset")
            } catch {
                print("⚠️ osrsNativeMapHandler: KVO observer already removed or never added")
                hasScrollObserver = false
            }
        }
        
        isHorizontalScrollInProgress = false
    }
    
    deinit {
        print("🗺️ osrsNativeMapHandler: deinit called")
        if !isCleanedUp {
            cleanup()
        }
        print("🗺️ osrsNativeMapHandler: deinit completed")
    }
}

// MARK: - Embedded Map Delegate

class osrsEmbeddedMapDelegate: NSObject, MLNMapViewDelegate {
    private let targetFloor: Int
    private let mapId: String
    
    init(targetFloor: Int, mapId: String) {
        self.targetFloor = targetFloor
        self.mapId = mapId
        super.init()
    }
    
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        print("🔥 CRITICAL SUCCESS: Style loaded for floor \(targetFloor), mapId: \(mapId)")
        print("🔥 MapView bounds: \(mapView.bounds)")
        print("🔥 MapView frame: \(mapView.frame)")
        print("🔥 MapView isHidden: \(mapView.isHidden)")
        print("🔥 MapView alpha: \(mapView.alpha)")
        print("🔥 MapView superview: \(mapView.superview != nil ? "EXISTS" : "NIL")")
        print("🔥 MapView center: \(mapView.centerCoordinate)")
        print("🔥 MapView zoom: \(mapView.zoomLevel)")
        print("🔥 Style layers count: \(style.layers.count)")
        print("🔥 Style sources count: \(style.sources.count)")
        
        // Log detailed style information
        for layer in style.layers {
            print("🔥 Style layer: \(layer.identifier) (type: \(type(of: layer)))")
        }
        
        for source in style.sources {
            print("🔥 Style source: \(source.identifier) (type: \(type(of: source)))")
        }
        
        // Add background
        if let backgroundLayer = style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer {
            backgroundLayer.backgroundColor = NSExpression(forConstantValue: UIColor.black)
            print("🔥 Background layer configured with black color")
        } else {
            print("🔥 WARNING: Background layer not found or wrong type")
        }
        
        // Add floor layers using same logic as main map
        print("🔥 About to add floor layer for floor \(targetFloor)")
        addFloorLayer(floor: targetFloor, to: style, mapView: mapView)
        
        // If viewing upper floor, add ground floor as underlay
        if targetFloor > 0 {
            print("🔥 Adding ground floor underlay")
            addFloorLayer(floor: 0, to: style, mapView: mapView, opacity: 0.5)
        }
        
        // Final state logging
        print("🔥 FINAL STATE for \(mapId):")
        print("🔥   - Total layers: \(style.layers.count)")
        print("🔥   - Total sources: \(style.sources.count)")
        print("🔥   - MapView visible: \(!mapView.isHidden && mapView.alpha > 0)")
        print("🔥   - Container visible: \(mapView.superview?.isHidden == false)")
        
        print("🔥 CRITICAL: Style setup complete for \(mapId)")
    }
    
    private func addFloorLayer(floor: Int, to style: MLNStyle, mapView: MLNMapView, opacity: Double = 1.0) {
        let sourceId = "osrs-embedded-source-\(floor)"
        let layerId = "osrs-embedded-layer-\(floor)"
        let fileName = "map_floor_\(floor).mbtiles"
        
        print("🔥 FLOOR LAYER CREATION START: floor \(floor), mapId: \(mapId)")
        
        // CRITICAL FIX: Use Documents directory like Android uses filesDir
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let documentsPath = documentsURL.appendingPathComponent(fileName).path
        
        var mbtilesPath: String?
        var mbtilesFileSize: UInt64 = 0
        
        // Check Documents directory first (copied from bundle like Android)
        if FileManager.default.fileExists(atPath: documentsPath) {
            mbtilesPath = documentsPath
            
            // Get file size for validation
            if let attributes = try? FileManager.default.attributesOfItem(atPath: documentsPath) {
                mbtilesFileSize = attributes[.size] as? UInt64 ?? 0
            }
            
            print("📂 Embedded Map: Using copied MBTiles from Documents: \(fileName)")
            print("📂 File size: \(mbtilesFileSize) bytes")
        } else if let bundlePath = Bundle.main.path(forResource: "map_floor_\(floor)", ofType: "mbtiles") {
            mbtilesPath = bundlePath
            
            // Get file size for validation
            if let attributes = try? FileManager.default.attributesOfItem(atPath: bundlePath) {
                mbtilesFileSize = attributes[.size] as? UInt64 ?? 0
            }
            
            print("📦 Embedded Map: Fallback to bundle MBTiles: \(fileName)")
            print("📦 File size: \(mbtilesFileSize) bytes")
        }
        
        guard let validPath = mbtilesPath else {
            print("❌ CRITICAL ERROR: MBTiles file not found: \(fileName)")
            print("❌ Checked Documents directory (\(documentsPath)) and bundle")
            print("❌ This will cause black/empty tiles")
            return
        }
        
        // Validate file is not empty
        if mbtilesFileSize == 0 {
            print("❌ CRITICAL ERROR: MBTiles file is empty: \(validPath)")
            print("❌ This will cause black/empty tiles")
            return
        }
        
        let mbtilesURLString = "mbtiles://\(validPath)"
        print("🗺️ MBTILES URL: \(mbtilesURLString)")
        
        // Validate URL
        guard let mbtilesURL = URL(string: mbtilesURLString) else {
            print("❌ CRITICAL ERROR: Invalid MBTiles URL: \(mbtilesURLString)")
            return
        }
        
        print("🔥 Creating raster source with identifier: \(sourceId)")
        let rasterSource = MLNRasterTileSource(
            identifier: sourceId,
            configurationURL: mbtilesURL
        )
        
        // Log source properties
        print("🔥 Raster source created:")
        print("🔥   - Identifier: \(rasterSource.identifier)")
        print("🔥   - Configuration URL: \(rasterSource.configurationURL?.absoluteString ?? "NIL")")
        
        // Check if source already exists
        if style.source(withIdentifier: sourceId) != nil {
            print("⚠️ WARNING: Source \(sourceId) already exists, removing first")
            style.removeSource(style.source(withIdentifier: sourceId)!)
        }
        
        style.addSource(rasterSource)
        print("🔥 Source added to style")
        
        // Verify source was added
        if let addedSource = style.source(withIdentifier: sourceId) {
            print("✅ Source verification: \(addedSource.identifier) added successfully")
        } else {
            print("❌ CRITICAL ERROR: Source was not added to style")
            return
        }
        
        print("🔥 Creating raster layer with identifier: \(layerId)")
        let rasterLayer = MLNRasterStyleLayer(identifier: layerId, source: rasterSource)
        rasterLayer.rasterResamplingMode = NSExpression(forConstantValue: "nearest")
        rasterLayer.rasterOpacity = NSExpression(forConstantValue: opacity)
        
        // Log layer properties
        print("🔥 Raster layer created:")
        print("🔥   - Identifier: \(rasterLayer.identifier)")
        print("🔥   - Source identifier: \(rasterLayer.sourceIdentifier ?? "NIL")")
        print("🔥   - Opacity: \(opacity)")
        print("🔥   - Resampling: nearest")
        print("🔥   - Visible: \(rasterLayer.isVisible)")
        
        // Check if layer already exists
        if style.layer(withIdentifier: layerId) != nil {
            print("⚠️ WARNING: Layer \(layerId) already exists, removing first")
            style.removeLayer(style.layer(withIdentifier: layerId)!)
        }
        
        style.addLayer(rasterLayer)
        print("🔥 Layer added to style")
        
        // Verify layer was added
        if let addedLayer = style.layer(withIdentifier: layerId) {
            print("✅ Layer verification: \(addedLayer.identifier) added successfully")
            if let rasterLayerCheck = addedLayer as? MLNRasterStyleLayer {
                print("✅ Layer type verification: MLNRasterStyleLayer confirmed")
                print("✅ Layer opacity: \(rasterLayerCheck.rasterOpacity?.constantValue ?? "NIL")")
                print("✅ Layer visible: \(rasterLayerCheck.isVisible)")
            }
        } else {
            print("❌ CRITICAL ERROR: Layer was not added to style")
            return
        }
        
        // Force a render update
        DispatchQueue.main.async {
            mapView.setNeedsDisplay()
        }
        
        print("🔥 FLOOR LAYER CREATION SUCCESS: floor \(floor)")
        print("🔥   - Source: \(sourceId) (\(mbtilesFileSize) bytes)")
        print("🔥   - Layer: \(layerId) (opacity: \(opacity))")
        print("🔥   - Path: \(validPath)")
        print("🔥   - Style total layers: \(style.layers.count)")
        print("🔥   - Style total sources: \(style.sources.count)")
    }
}

// MARK: - Gesture Integration Extension

extension osrsNativeMapHandler {
    
    /// Set up gesture integration matching Android's NativeMapHandler
    func setupGestureIntegration() {
        // Monitor horizontal scroll state and update global gesture state
        $isHorizontalScrollInProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isScrolling in
                osrsGestureState.shared.isHorizontalScrollInProgress = isScrolling
                print("[NativeMapHandler] MapLibre horizontal scroll: \(isScrolling)")
                
                // Update scroll state based on map interactions
                self?.updateMapScrollState()
            }
            .store(in: &cancellables)
    }
    
    /// Update map scroll state based on MapView interactions
    private func updateMapScrollState() {
        // Monitor all embedded map views for scroll state
        for (mapId, mapView) in mapViews {
            // Check if any map view is actively being interacted with
            if mapView.isUserLocationVisible || !mapView.bounds.isEmpty {
                print("[NativeMapHandler] Monitoring map \(mapId) for scroll interactions")
            }
        }
    }
    
}

// Import needed for Combine
import Combine

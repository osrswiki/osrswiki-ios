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
    let mapId: Int?
    let initiallyVisible: Bool?
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

/// One canonical projection from the map placeholder's document rectangle into the native
/// overlay coordinate space. Scrolling and late JavaScript remeasurement both use this exact
/// calculation so they cannot fight over the frame, mask, or hidden state.
struct osrsEmbeddedMapViewportLayout: Equatable {
    let containerFrame: CGRect
    let mapContentFrame: CGRect
    let maskFrame: CGRect?
    let intersectsViewport: Bool

    static func resolve(
        documentFrame: CGRect,
        webViewFrame: CGRect,
        safeAreaTop: CGFloat,
        contentOffset: CGPoint
    ) -> osrsEmbeddedMapViewportLayout {
        let rawFrame = CGRect(
            x: webViewFrame.minX + documentFrame.minX,
            y: webViewFrame.minY + documentFrame.minY - contentOffset.y,
            width: documentFrame.width,
            height: documentFrame.height
        )
        let viewportTop = webViewFrame.minY + safeAreaTop
        let viewportBottom = webViewFrame.maxY
        let visibleTop = max(rawFrame.minY, viewportTop)
        let visibleBottom = min(rawFrame.maxY, viewportBottom)
        guard visibleBottom > visibleTop else {
            return osrsEmbeddedMapViewportLayout(
                containerFrame: rawFrame,
                mapContentFrame: CGRect(origin: .zero, size: rawFrame.size),
                maskFrame: nil,
                intersectsViewport: false
            )
        }

        let topOcclusion = max(0, visibleTop - rawFrame.minY)
        let visibleHeight = visibleBottom - visibleTop
        let containerFrame = CGRect(
            x: rawFrame.minX,
            y: visibleTop,
            width: rawFrame.width,
            height: visibleHeight
        )
        let mapContentFrame = CGRect(
            x: 0,
            y: -topOcclusion,
            width: rawFrame.width,
            height: rawFrame.height
        )
        let isFullyVisible = topOcclusion <= 0.5 && visibleHeight >= rawFrame.height - 0.5
        return osrsEmbeddedMapViewportLayout(
            containerFrame: containerFrame,
            mapContentFrame: mapContentFrame,
            maskFrame: isFullyVisible
                ? nil
                : CGRect(x: 0, y: 0, width: rawFrame.width, height: visibleHeight),
            intersectsViewport: true
        )
    }
}

enum osrsEmbeddedMapGestureHitPolicy {
    static func owns(point: CGPoint, visibleFrames: [CGRect]) -> Bool {
        visibleFrames.contains { !$0.isEmpty && $0.contains(point) }
    }
}

// MARK: - Native Map Handler

class osrsNativeMapHandler: NSObject {
    weak var articleWebView: WKWebView?
    private var mapContainers: [String: UIView] = [:]
    private var mapLayoutStates: [String: osrsEmbeddedMapLayoutState] = [:]
    private var mapDocumentFrames: [String: CGRect] = [:]

    // CRITICAL FIX: Store delegates and MapViews to prevent deallocation (Android pattern)
    private var mapDelegates: [String: osrsEmbeddedMapDelegate] = [:]
    private var mapViews: [String: MLNMapView] = [:]
    private var requestedVisibleMapIds: Set<String> = []
    private var desiredMapVisibility: [String: Bool] = [:]
    private var renderedMapIds: Set<String> = []
    private var activeEmbeddedMapGestureIds: Set<String> = []
    
    @Published var isHorizontalScrollInProgress = false
    
    // Storage for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // Track observer state to prevent double removal crashes
    private var hasScrollObserver = false
    private var isCleanedUp = false
    private let realmManifest: osrsRealmMapManifest?
    private let realmAssetRoot: URL?
    
    init(webView: WKWebView) {
        self.articleWebView = webView
        self.realmManifest = try? osrsRealmMapManifest.load()
        self.realmAssetRoot = Bundle.main.resourceURL?
            .appendingPathComponent("UndergroundRealms", isDirectory: true)
        super.init()
        setupScrollListener()
        setupGestureIntegration()
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
    
    func onMapViewportVisibilityChanged(mapId: String, isVisible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyDesiredVisibility(mapId: mapId, isVisible: isVisible)
        }
    }

    func onCollapsibleToggled(mapId: String, isOpening: Bool) {
        print("🔥 TOGGLE: onCollapsibleToggled - \(mapId), opening: \(isOpening)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.desiredMapVisibility[mapId] = isOpening
            if isOpening {
                self.requestedVisibleMapIds.insert(mapId)
            } else {
                self.requestedVisibleMapIds.remove(mapId)
            }
            // Stable map IDs are assigned before a collapsed table is measured. Recording the
            // desired state here closes the first-open/rapid-close race even if no overlay exists.
            guard let webView = self.articleWebView,
                  let container = self.mapContainers[mapId] else {
                return
            }
            let showNative = isOpening && self.renderedMapIds.contains(mapId)
            self.applyMapLayout(id: mapId, webView: webView)

            if isOpening {
                print("🔥 TOGGLE: OPENING map \(mapId)")
                print("🔥 TOGGLE: New container frame: \(container.frame)")
                
                // Keep the static Wiki fallback until MapLibre reports a complete frame.
                let opacity = showNative ? 0 : 1
                let script = "var el = document.getElementById('\(mapId)'); if (el) { el.style.opacity = \(opacity); }"
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
        if inProgress {
            osrsGestureState.shared.claimJavaScriptGesture(id: "legacy-local-scroll")
        } else {
            osrsGestureState.shared.endJavaScriptGesture(id: "legacy-local-scroll")
        }
    }

    func setHorizontalScrollGesture(
        phase: String,
        gestureId: String,
        ownerId: String,
        isLocalOwner: Bool
    ) {
        print("[NativeMapHandler] gesture phase=\(phase) id=\(gestureId) owner=\(ownerId) local=\(isLocalOwner)")
        switch phase {
        case "begin":
            osrsGestureState.shared.classifyJavaScriptGesture(
                id: gestureId,
                isLocalOwner: isLocalOwner
            )
            if isLocalOwner {
                isHorizontalScrollInProgress = true
            }
        case "change":
            if isLocalOwner {
                isHorizontalScrollInProgress = true
                osrsGestureState.shared.claimJavaScriptGesture(id: gestureId)
            }
        case "end":
            if isLocalOwner {
                isHorizontalScrollInProgress = false
            }
            osrsGestureState.shared.endJavaScriptGesture(id: gestureId)
        case "cancel":
            if isLocalOwner {
                isHorizontalScrollInProgress = false
            }
            osrsGestureState.shared.cancelJavaScriptGesture(id: gestureId)
        default:
            break
        }
    }
    
    func log(message: String) {
        print("🗺️ JS: \(message)")
    }

    /// Native article maps are overlay siblings of WKWebView. DOM `elementFromPoint` can only
    /// see the placeholder underneath that overlay, so article-swipe arbitration must also hit
    /// test the actual visible UIKit containers in their shared parent coordinate space.
    func ownsArticleGesture(at pointInWebView: CGPoint, in webView: WKWebView) -> Bool {
        guard let parent = webView.superview else { return false }
        let pointInParent = webView.convert(pointInWebView, to: parent)
        let visibleFrames = mapContainers.values.compactMap { container -> CGRect? in
            guard !container.isHidden,
                  container.alpha > 0.01,
                  container.window != nil else { return nil }
            return container.frame
        }
        return osrsEmbeddedMapGestureHitPolicy.owns(
            point: pointInParent,
            visibleFrames: visibleFrames
        )
    }

#if DEBUG
    var activeMapContainerIdentifiersForTesting: [String] {
        mapContainers.keys.sorted()
    }

    func mapContainerFrameForTesting(id: String) -> CGRect? {
        mapContainers[id]?.frame
    }

    func mapContainerIsHiddenForTesting(id: String) -> Bool? {
        mapContainers[id]?.isHidden
    }

    func mapContentFrameForTesting(id: String) -> CGRect? {
        mapContainers[id]?.subviews.first?.frame
    }

    func mapMaskFrameForTesting(id: String) -> CGRect? {
        mapContainers[id]?.layer.mask?.frame
    }

    func markMapRenderedForTesting(id: String) {
        guard let mapView = mapViews[id] else { return }
        revealRenderedMap(id: id, mapView: mapView)
    }
#endif
    
    // MARK: - Private Implementation
    
    private func applyDesiredVisibility(mapId: String, isVisible: Bool) {
        desiredMapVisibility[mapId] = isVisible
        if isVisible {
            requestedVisibleMapIds.insert(mapId)
        } else {
            requestedVisibleMapIds.remove(mapId)
        }
        guard let webView = articleWebView, mapContainers[mapId] != nil else { return }
        applyMapLayout(id: mapId, webView: webView)
        let showNative = isVisible && renderedMapIds.contains(mapId)
        let opacity = showNative ? 0 : 1
        webView.evaluateJavaScript(
            "var el = document.getElementById('\(mapId)'); if (el) { el.style.opacity = \(opacity); }"
        )
    }

    private func preloadMap(id: String, rect: osrsMapRect, mapData: osrsMapData, webView: WKWebView) {
        print("🔥 CRITICAL: preloadMap started for \(id)")
        
        if updateExistingMapContainer(id: id, rect: rect, webView: webView) {
            print("🔥 CRITICAL: Container \(id) already exists - updated layout")
            return
        }
        
        // Article maps use the same reviewed canonical assets as the Map tab. The former
        // process-wide preloader owns the retired map_floor_*.mbtiles stack and must never be
        // used here: those files are not part of the canonical product anymore.
        createMapOnDemand(id: id, rect: rect, mapData: mapData, webView: webView)
    }
    
    // MARK: - Preloaded Map Usage
    
    private func usePreloadedMap(id: String, rect: osrsMapRect, mapData: osrsMapData, preloadedContainer: osrsMapPreloadService.osrsPreloadedMapContainer, webView: WKWebView) {
        guard webView.superview != nil else {
            print("❌ CRITICAL ERROR: No parent view for preloaded map")
            return
        }
        
        // Move the preloaded container to the correct position and size
        let container = preloadedContainer.container
        configureAccessibility(for: container, id: id)
        
        let documentFrame = mapDocumentFrame(from: rect)
        mapDocumentFrames[id] = documentFrame
        if desiredMapVisibility[id] ?? (mapData.initiallyVisible == true) {
            requestedVisibleMapIds.insert(id)
        } else {
            requestedVisibleMapIds.remove(id)
        }
        let layoutState = osrsEmbeddedMapLayoutState(visibleFrame: documentFrame, isVisible: false)
        
        // Store in our containers map for toggle handling
        mapContainers[id] = container
        mapLayoutStates[id] = layoutState
        applyMapLayout(id: id, webView: webView)
        
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
        // The native map is an overlay sibling of WKWebView.  Giving it an explicit
        // z-position prevents SwiftUI's platform-view host from reordering it behind
        // WebKit during a layout pass (which would leave the now-transparent wiki map
        // looking like a static/blank rectangle).
        container.layer.zPosition = 1
        configureAccessibility(for: container, id: id)
        
        // Position will be set in frame calculation below (no transforms needed)
        
        // CRITICAL FIX: Add to parent view like Android adds to binding.root
        parentView.addSubview(container)
        mapContainers[id] = container
        
        let documentFrame = mapDocumentFrame(from: rect)
        mapDocumentFrames[id] = documentFrame
        if desiredMapVisibility[id] ?? (mapData.initiallyVisible == true) {
            requestedVisibleMapIds.insert(id)
        } else {
            requestedVisibleMapIds.remove(id)
        }
        let layoutState = osrsEmbeddedMapLayoutState(visibleFrame: documentFrame, isVisible: false)
        
        print("🎯 iOS Map Handler: Positioning container - width:\(documentFrame.width), height:\(documentFrame.height), top:\(documentFrame.origin.y), left:\(documentFrame.origin.x), scale:\(webView.scrollView.zoomScale)")
        print("🔍 iOS Map Handler: WebView frame: \(webView.frame), rect: x:\(rect.x) y:\(rect.y)")
        
        // Set frame directly (matching Android's direct positioning approach)
        mapLayoutStates[id] = layoutState
        applyMapLayout(id: id, webView: webView)
        
        // Create embedded MapLibre view with proper retention
        let mapView = createEmbeddedMapView(
            mapData: mapData,
            mapId: id,
            viewportSize: documentFrame.size
        )
        mapView.accessibilityIdentifier = "native_map_view_\(id)"
        mapView.accessibilityLabel = "Embedded OSRS map"
        container.addSubview(mapView)
        
        // CRITICAL FIX: Use frame-based positioning instead of Auto Layout for embedded maps
        // This matches the container's frame-based approach and eliminates timing issues
        mapView.frame = container.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        applyMapLayout(id: id, webView: webView)
        
        print("🔥 CRITICAL SUCCESS: Created embedded map container \(id)")
        print("🔥 Container frame: \(container.frame)")
        print("🔥 Container superview: \(container.superview != nil ? "YES" : "NO")")
        print("🔥 MapView frame: \(mapView.frame)")
        print("🔥 Total containers: \(mapContainers.count)")
    }

    private func updateExistingMapContainer(id: String, rect: osrsMapRect, webView: WKWebView) -> Bool {
        guard let container = mapContainers[id] else { return false }
        configureAccessibility(for: container, id: id)

        mapDocumentFrames[id] = mapDocumentFrame(from: rect)
        let layoutState = mapLayoutStates[id] ?? osrsEmbeddedMapLayoutState(
            visibleFrame: mapDocumentFrame(from: rect),
            isVisible: false
        )
        mapLayoutStates[id] = layoutState
        applyMapLayout(id: id, webView: webView)

        return true
    }

    private func configureAccessibility(for container: UIView, id: String) {
        container.isAccessibilityElement = true
        container.accessibilityIdentifier = "native_map_container_\(id)"
        container.accessibilityLabel = "Embedded OSRS map container"
        container.accessibilityTraits = [.allowsDirectInteraction]
    }

    private func publishNativeMapCount(
        on webView: WKWebView,
        renderedFrame: CGRect? = nil,
        notifyAccessibility: Bool = true
    ) {
        let existing = (webView.accessibilityValue as? String) ?? ""
        let retainedTokens = existing
            .split(separator: ";")
            .map(String.init)
            .filter {
                !$0.hasPrefix("native_article_maps=") &&
                    !$0.hasPrefix("native_map_frame=")
            }
        var nativeTokens = ["native_article_maps=\(renderedMapIds.count)"]
        if let frame = renderedFrame {
            nativeTokens.append(
                "native_map_frame=\(frame.minX),\(frame.minY),\(frame.width),\(frame.height)"
            )
        }
        // Put the native-map diagnostics first: WebKit may truncate long DOM-derived
        // accessibility values, but the rendered-frame contract must remain observable.
        webView.accessibilityValue = (nativeTokens + retainedTokens)
            .joined(separator: ";")
        if notifyAccessibility {
            UIAccessibility.post(notification: .layoutChanged, argument: webView)
        }
    }

    private func mapDocumentFrame(from rect: osrsMapRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.x),
            y: CGFloat(rect.y),
            width: CGFloat(rect.width) + 1,
            height: CGFloat(rect.height)
        )
    }

    @discardableResult
    private func applyMapLayout(id: String, webView: WKWebView) -> Bool {
        guard let container = mapContainers[id],
              let documentFrame = mapDocumentFrames[id] else { return false }
        let layout = osrsEmbeddedMapViewportLayout.resolve(
            documentFrame: documentFrame,
            webViewFrame: webView.frame,
            safeAreaTop: webView.safeAreaInsets.top,
            contentOffset: webView.scrollView.contentOffset
        )
        let lifecycleVisible = requestedVisibleMapIds.contains(id) && renderedMapIds.contains(id)
        var state = mapLayoutStates[id] ?? osrsEmbeddedMapLayoutState(
            visibleFrame: layout.containerFrame,
            isVisible: lifecycleVisible
        )
        _ = state.updateVisibleFrame(layout.containerFrame)
        container.frame = state.applyVisibility(isVisible: lifecycleVisible)
        mapLayoutStates[id] = state
        container.isHidden = !lifecycleVisible || !layout.intersectsViewport

        if let maskFrame = layout.maskFrame {
            let mask = container.layer.mask ?? CALayer()
            mask.backgroundColor = UIColor.black.cgColor
            mask.frame = maskFrame
            container.layer.mask = mask
        } else {
            container.layer.mask = nil
        }
        if let mapView = container.subviews.first {
            mapView.frame = layout.mapContentFrame
            mapView.setNeedsDisplay()
        }
        return lifecycleVisible && layout.intersectsViewport
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert OSRS in-game coordinates to geographical coordinates for MapLibre
    /// This matches the Android implementation exactly
    private func gameToLatLng(gameX: Double, gameY: Double) -> CLLocationCoordinate2D {
        osrsMapDefaultView.mapCoordinate(gameX: gameX, gameY: gameY)
    }
    
    private func createEmbeddedMapView(
        mapData: osrsMapData,
        mapId: String,
        viewportSize: CGSize
    ) -> MLNMapView {
        let mapView = MLNMapView()
        osrsMapPreferredFrameRate.apply(to: mapView)
        
        // Configure like main map but optimized for embedding
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.compassView.isHidden = true
        mapView.showsScale = false
        mapView.allowsRotating = false // Disable rotation for embeds
        mapView.allowsTilting = false
        mapView.allowsZooming = true
        mapView.allowsScrolling = true
        mapView.gestureRecognizers?
            .filter { $0 is UIPanGestureRecognizer || $0 is UIPinchGestureRecognizer }
            .forEach { $0.addTarget(self, action: #selector(handleEmbeddedMapGesture(_:))) }
        
        // Parse OSRS in-game coordinates
        let gameX = Double(mapData.lon ?? "") ?? 3200.0 // Note: OSRS wiki uses lon for X coordinate
        let gameY = Double(mapData.lat ?? "") ?? 3200.0 // Note: OSRS wiki uses lat for Y coordinate
        let plane = Int(mapData.plane ?? "0") ?? 0
        let resolved = realmManifest.flatMap { manifest in
            osrsArticleMapRealmResolver.resolve(
                manifest: manifest,
                mapId: mapData.mapId,
                plane: plane,
                gameX: Int(gameX),
                gameY: Int(gameY)
            )
        }
        let selectedRealm = resolved?.realm ?? realmManifest?.surface
        let selectedPlane = resolved?.plane ?? plane
        let targetAsset = selectedRealm?.asset(plane: selectedPlane) ?? selectedRealm?.asset(plane: 0)
        let envelope = selectedRealm.flatMap {
            osrsRealmCameraEnvelope.visibleComposition(realm: $0, selectedPlane: targetAsset?.plane ?? 0)
        }
        let geographicalCoords = resolved?.destination?.coordinate ?? gameToLatLng(gameX: gameX, gameY: gameY)
        let baseMinimum = targetAsset.map { max(0, Double($0.minZoom) - 2) } ?? 0
        let minimumZoom = envelope?.finiteRealmMinimumZoom(
            baseMinimumZoom: baseMinimum,
            viewportWidth: Double(max(viewportSize.width, 1)),
            viewportHeight: Double(max(viewportSize.height, 1))
        ) ?? baseMinimum
        mapView.minimumZoomLevel = minimumZoom
        mapView.maximumZoomLevel = targetAsset.map { min(22, Double($0.maxZoom) + 8) } ?? 22
        if let bounds = envelope?.screenBoundsAllowingCenterEdgeOverflow() {
            mapView.maximumScreenBounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west),
                ne: CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.east)
            )
        }
        let zoom = max(targetAsset.map(osrsRealmDefaultCamera.zoom(asset:)) ?? 6.0, minimumZoom)
        
        print("🎯 iOS Map Handler: Converting OSRS coordinates gameX:\(gameX), gameY:\(gameY), zoom:\(zoom), plane:\(plane)")
        
        print("🌍 iOS Map Handler: Converted to geographical lat:\(geographicalCoords.latitude), lon:\(geographicalCoords.longitude)")
        
        // Set initial position using converted coordinates
        mapView.setCenter(geographicalCoords, zoomLevel: zoom, animated: false)
        
        // CRITICAL FIX: Store MapView to prevent deallocation (Android pattern)
        mapViews[mapId] = mapView
        
        // Set up map style and tiles (reuse logic from main map)
        setupEmbeddedMapStyle(
            mapView: mapView,
            targetFloor: targetAsset?.plane ?? 0,
            mapId: mapId,
            surfaceRealm: selectedRealm
        )
        
        return mapView
    }

    /// Article navigation owns broad horizontal swipes, while an embedded map must own
    /// every pan and pinch that begins inside it. Keep the blocker set through the gesture's
    /// completion turn so the enclosing SwiftUI recognizer cannot mistake the same touch for
    /// article navigation after MapLibre reports `.ended`.
    @objc private func handleEmbeddedMapGesture(_ gesture: UIGestureRecognizer) {
        let gestureId = "native-map-\(ObjectIdentifier(gesture).hashValue)"
        switch gesture.state {
        case .began, .changed:
            activeEmbeddedMapGestureIds.insert(gestureId)
            isHorizontalScrollInProgress = !activeEmbeddedMapGestureIds.isEmpty
            osrsGestureState.shared.claimNativeGesture(id: gestureId)
        case .ended, .cancelled, .failed:
            activeEmbeddedMapGestureIds.remove(gestureId)
            isHorizontalScrollInProgress = !activeEmbeddedMapGestureIds.isEmpty
            osrsGestureState.shared.endNativeGesture(id: gestureId)
        default:
            break
        }
    }
    
    private func setupEmbeddedMapStyle(
        mapView: MLNMapView,
        targetFloor: Int,
        mapId: String,
        surfaceRealm: osrsRealmMapRecord?
    ) {
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
            let assets = surfaceRealm.map { realm in
                targetFloor > 0
                    ? [realm.asset(plane: 0), realm.asset(plane: targetFloor)].compactMap { $0 }
                    : [realm.asset(plane: targetFloor)].compactMap { $0 }
            } ?? []
            let delegate = osrsEmbeddedMapDelegate(
                targetFloor: targetFloor,
                mapId: mapId,
                assets: assets,
                assetRoot: realmAssetRoot,
                onFirstFrame: { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    self.revealRenderedMap(id: mapId, mapView: mapView)
                }
            )
            mapDelegates[mapId] = delegate  // Retain delegate
            mapView.delegate = delegate
            
            print("✅ iOS Map Handler: Set up embedded map style for floor \(targetFloor), mapId: \(mapId)")
            
        } catch {
            print("❌ iOS Map Handler: Failed to setup embedded map style - \(error)")
        }
    }

    private func revealRenderedMap(id: String, mapView: MLNMapView) {
        guard !renderedMapIds.contains(id), let webView = articleWebView else { return }
        renderedMapIds.insert(id)
        guard requestedVisibleMapIds.contains(id),
              let container = mapContainers[id] else { return }
        applyMapLayout(id: id, webView: webView)
        publishNativeMapCount(on: webView, renderedFrame: container.frame)
        webView.evaluateJavaScript("var el=document.getElementById('\(id)'); if(el){el.style.opacity=0;}")
        mapView.setNeedsDisplay()
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
            for mapId in mapContainers.keys {
                applyMapLayout(id: mapId, webView: webView)
            }
#if DEBUG
            // Keep the UI-test diagnostic in the same coordinate space as the live
            // overlay after article scrolling. Avoid posting a layout-change
            // announcement on every scroll frame; the value is diagnostic only.
            if let renderedId = renderedMapIds.sorted().first,
               let renderedContainer = mapContainers[renderedId] {
                publishNativeMapCount(
                    on: webView,
                    renderedFrame: renderedContainer.frame,
                    notifyAccessibility: false
                )
            }
#endif
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
        requestedVisibleMapIds.removeAll()
        desiredMapVisibility.removeAll()
        renderedMapIds.removeAll()
        if let webView = articleWebView {
            publishNativeMapCount(on: webView)
        }
        mapLayoutStates.removeAll()
        mapDocumentFrames.removeAll()
        activeEmbeddedMapGestureIds.removeAll()
        
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
        osrsGestureState.shared.resetState()
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
    private let assets: [osrsRealmMapAsset]
    private let assetRoot: URL?
    private var onFirstFrame: (() -> Void)?
    private var assetsReady = false

    init(
        targetFloor: Int,
        mapId: String,
        assets: [osrsRealmMapAsset],
        assetRoot: URL?,
        onFirstFrame: (() -> Void)?
    ) {
        self.targetFloor = targetFloor
        self.mapId = mapId
        self.assets = assets
        self.assetRoot = assetRoot
        self.onFirstFrame = onFirstFrame
        super.init()
    }

    func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
        guard assetsReady, fullyRendered, let callback = onFirstFrame else { return }
        onFirstFrame = nil
        callback()
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
        for asset in assets.sorted(by: { $0.plane < $1.plane }) {
            addFloorLayer(
                asset: asset,
                to: style,
                mapView: mapView,
                opacity: asset.plane == targetFloor ? 1 : 0.5
            )
        }
        // A frame of the empty background style is not a successful article-map
        // handoff. Only a subsequent fully rendered frame after the canonical
        // raster sources and layers exist may replace the Wiki fallback image.
        assetsReady = !assets.isEmpty
        
        // Final state logging
        print("🔥 FINAL STATE for \(mapId):")
        print("🔥   - Total layers: \(style.layers.count)")
        print("🔥   - Total sources: \(style.sources.count)")
        print("🔥   - MapView visible: \(!mapView.isHidden && mapView.alpha > 0)")
        print("🔥   - Container visible: \(mapView.superview?.isHidden == false)")
        
        print("🔥 CRITICAL: Style setup complete for \(mapId)")
    }
    
    private func addFloorLayer(
        asset: osrsRealmMapAsset,
        to style: MLNStyle,
        mapView: MLNMapView,
        opacity: Double = 1.0
    ) {
        let floor = asset.plane
        let sourceId = "osrs-embedded-source-\(floor)"
        let layerId = "osrs-embedded-layer-\(floor)"
        let fileName = asset.mbtilesPath
        
        print("🔥 FLOOR LAYER CREATION START: floor \(floor), mapId: \(mapId)")
        
        let canonicalURL = assetRoot?.appendingPathComponent(asset.mbtilesPath)
        let mbtilesPath = canonicalURL?.path
        var mbtilesFileSize: UInt64 = 0
        if let mbtilesPath,
           FileManager.default.fileExists(atPath: mbtilesPath),
           let attributes = try? FileManager.default.attributesOfItem(atPath: mbtilesPath) {
            mbtilesFileSize = attributes[.size] as? UInt64 ?? 0
        }
        
        guard let validPath = mbtilesPath else {
            print("❌ CRITICAL ERROR: MBTiles file not found: \(fileName)")
            print("❌ Canonical realm asset root: \(assetRoot?.path ?? "missing")")
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

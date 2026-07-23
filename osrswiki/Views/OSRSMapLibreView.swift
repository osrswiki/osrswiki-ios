//
//  osrsMapLibreView.swift
//  OSRS Wiki
//
//  MapLibre Native implementation with MBTiles support for OSRS game maps
//

import SwiftUI
import MapLibre
import Foundation
import CoreLocation

private extension Notification.Name {
    static let osrsMainMapFloorDidChange = Notification.Name("osrsMainMapFloorDidChange")
}

struct osrsMapLibreView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @State private var currentFloor: Int = 0
    @State private var isMapReady: Bool = false

    private let maxFloor = 3

    var body: some View {
        ZStack {
            // MapLibre Native view
            osrsMapLibreMapView(
                currentFloor: $currentFloor,
                isMapReady: $isMapReady
            )
            .ignoresSafeArea(.all, edges: .top)

            if !isMapReady {
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Preparing map...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(16)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preparing map")
            }

            // Floor controls overlay aligned with compass
            VStack {
                HStack(alignment: .top) {
                    osrsFloorControlsView(
                        currentFloor: $currentFloor,
                        maxFloor: maxFloor
                    )
                    .padding(.leading, 8) // Match compass right margin (8pt from screen edge)
                    .padding(.top, 8) // Match compass top margin

                    Spacer()
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .background(.osrsBackground)
    }

    // Coordinate conversion function ported from Android
    static func gameToLatLng(gx: Double, gy: Double) -> CLLocationCoordinate2D {
        osrsMapDefaultView.mapCoordinate(gameX: gx, gameY: gy)
    }
}

struct osrsFloorControlsView: View {
    @Binding var currentFloor: Int
    let maxFloor: Int
    @Environment(\.osrsTheme) var osrsTheme

    // Fixed compass dimensions for alignment
    private let compassWidth: CGFloat = 40
    private let compassHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 4) {
            // Up arrow button
            Button(action: {
                if currentFloor < maxFloor {
                    let newFloor = currentFloor + 1
                    currentFloor = newFloor
                    NotificationCenter.default.post(
                        name: .osrsMainMapFloorDidChange,
                        object: nil,
                        userInfo: ["floor": newFloor]
                    )
                }
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: compassWidth, height: compassHeight)
                    .foregroundColor(Color(osrsTheme.mapControlTextColor))
                    .background(Color.clear)
            }
            .disabled(currentFloor >= maxFloor)
            .opacity(currentFloor >= maxFloor ? 0.4 : 1.0)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("map_floor_up")
            .accessibilityLabel("Increase map floor")
            .accessibilityAddTraits(.isButton)

            // Floor number display
            Text("\(currentFloor)")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(osrsTheme.mapControlTextColor))
                .frame(width: compassWidth, height: 28)
                .padding(.vertical, 4)

            // Down arrow button
            Button(action: {
                if currentFloor > 0 {
                    let newFloor = currentFloor - 1
                    currentFloor = newFloor
                    NotificationCenter.default.post(
                        name: .osrsMainMapFloorDidChange,
                        object: nil,
                        userInfo: ["floor": newFloor]
                    )
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: compassWidth, height: compassHeight)
                    .foregroundColor(Color(osrsTheme.mapControlTextColor))
                    .background(Color.clear)
            }
            .disabled(currentFloor <= 0)
            .opacity(currentFloor <= 0 ? 0.4 : 1.0)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("map_floor_down")
            .accessibilityLabel("Decrease map floor")
            .accessibilityAddTraits(.isButton)
        }
        .padding(4)
        .frame(width: compassWidth + 8) // Match compass width (40px + 8px padding)
        .background(Color(osrsTheme.mapControlBackgroundColor))
        .clipShape(Capsule()) // Perfect semicircles at top and bottom
        .shadow(radius: 4)
    }
}


struct osrsMapLibreMapView: UIViewRepresentable {
    @Binding var currentFloor: Int
    @Binding var isMapReady: Bool

    func makeUIView(context: Context) -> UIView {
        // Create container view
        let containerView = UIView()
        containerView.backgroundColor = .black

        let mapView = MLNMapView(frame: .zero)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: containerView.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.setupVisibleMap(mapView)

        return containerView
    }

    func updateUIView(_ containerView: UIView, context: Context) {
        context.coordinator.parent = self
        // CRITICAL FIX: Defer floor updates to avoid "Modifying state during view update" warnings
        // Problem: updateUIView is called during SwiftUI's update cycle, calling updateFloor
        // directly here can trigger state changes during view updates, causing the warning
        // Solution: Defer the update using DispatchQueue.main.async to break the update cycle
        DispatchQueue.main.async {
            context.coordinator.updateFloor(currentFloor)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: osrsMapLibreMapView
        weak var mapView: MLNMapView?
        var isMapReady: Bool = false
        private var currentFloorState: Int = -1 // Track current floor state to avoid redundant updates
        private var pendingFloorState: Int?
        private var floorObserver: NSObjectProtocol?

        init(_ parent: osrsMapLibreMapView) {
            self.parent = parent
            super.init()
            floorObserver = NotificationCenter.default.addObserver(
                forName: .osrsMainMapFloorDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let floor = notification.userInfo?["floor"] as? Int else { return }
                Task { @MainActor in
                    self?.updateFloor(floor)
                }
            }
        }

        deinit {
            if let floorObserver {
                NotificationCenter.default.removeObserver(floorObserver)
            }
        }

        /// Set up the visible MapLibre instance for the main Map tab.
        @MainActor
        func setupVisibleMap(_ mapView: MLNMapView) {
            self.mapView = mapView
            mapView.delegate = self
            mapView.logoView.isHidden = true
            mapView.attributionButton.isHidden = true
            mapView.compassView.isHidden = false
            mapView.showsScale = false
            mapView.allowsRotating = true
            mapView.allowsTilting = false
            mapView.prefetchesTiles = true
            mapView.isAccessibilityElement = true
            mapView.accessibilityIdentifier = "map_view"
            mapView.accessibilityLabel = "OSRS map"

            let center = osrsMapDefaultView.coordinate
            mapView.setCenter(center, zoomLevel: osrsMapDefaultView.zoom, animated: false)
            updateMapAccessibilityValue(ready: false)

            let contentBounds = MLNCoordinateBounds(
                sw: osrsMapDefaultView.southWestCoordinate,
                ne: osrsMapDefaultView.northEastCoordinate
            )
            mapView.setVisibleCoordinateBounds(
                contentBounds,
                edgePadding: .zero,
                animated: false,
                completionHandler: nil
            )

            if mapView.zoomLevel < 1.0 {
                mapView.setCenter(center, zoomLevel: osrsMapDefaultView.zoom, animated: false)
                updateMapAccessibilityValue(ready: false)
            }

            setupCustomMapStyle(mapView)
        }

        @MainActor
        private func updateMapAccessibilityValue(ready: Bool? = nil) {
            guard let mapView else { return }
            let center = mapView.centerCoordinate
            let isReady = ready ?? isMapReady
            let cameraSnapshot = String(
                format: "centerLat=%.14f;centerLon=%.10f;zoom=%.13f;floor=%d;ready=%@",
                locale: Locale(identifier: "en_US_POSIX"),
                center.latitude,
                center.longitude,
                mapView.zoomLevel,
                currentFloorState,
                isReady ? "true" : "false"
            )
            mapView.accessibilityValue = cameraSnapshot

#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-exposeMapCameraForUITests") {
                mapView.accessibilityLabel = "OSRS map;\(cameraSnapshot)"
            }
#endif
        }

        @MainActor
        private func setupCustomMapStyle(_ mapView: MLNMapView) {
            let customStyleJSON = """
            {
                "version": 8,
                "name": "OSRS Main Map Style",
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

            let styleURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("osrs-main-map-style.json")

            do {
                try customStyleJSON.write(to: styleURL, atomically: true, encoding: .utf8)
                mapView.styleURL = styleURL
            } catch {
                print("❌ Main map: Failed to write custom style: \(error)")
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            Task { @MainActor in
                self.handleStyleLoaded(style)
            }
        }

        @MainActor
        private func handleStyleLoaded(_ style: MLNStyle) {
            isMapReady = true
            parent.isMapReady = true
            currentFloorState = -1
            let floorToShow = pendingFloorState ?? parent.currentFloor
            pendingFloorState = nil
            updateFloor(floorToShow)
            updateMapAccessibilityValue(ready: true)
            mapView?.setNeedsDisplay()
            print("✅ Main Map tab style loaded with OSRS floor layers")
        }

        @MainActor
        private func sourceId(for floor: Int) -> String {
            "osrs-main-source-\(floor)"
        }

        @MainActor
        private func layerId(for floor: Int) -> String {
            "osrs-main-layer-\(floor)"
        }

        @MainActor
        private func addFloorSourceIfNeeded(floor: Int, to style: MLNStyle) -> MLNRasterTileSource? {
            let sourceId = sourceId(for: floor)
            if let existingSource = style.source(withIdentifier: sourceId) as? MLNRasterTileSource {
                return existingSource
            }

            let fileName = "map_floor_\(floor)"

            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let documentsPath = documentsURL.appendingPathComponent("\(fileName).mbtiles").path

            let mbtilesPath: String?
            if FileManager.default.fileExists(atPath: documentsPath) {
                mbtilesPath = documentsPath
            } else {
                mbtilesPath = Bundle.main.path(forResource: fileName, ofType: "mbtiles")
            }

            guard let validPath = mbtilesPath else {
                print("❌ Main map: MBTiles missing for floor \(floor)")
                return nil
            }

            guard FileManager.default.fileExists(atPath: validPath) else {
                print("❌ Main map: MBTiles path missing for floor \(floor): \(validPath)")
                return nil
            }

            let rasterSource = MLNRasterTileSource(
                identifier: sourceId,
                configurationURL: URL(string: "mbtiles://\(validPath)")!
            )
            style.addSource(rasterSource)
            return rasterSource
        }

        @MainActor
        private func rebuildFloorLayers(selectedFloor: Int, in style: MLNStyle) {
            for floor in 0...3 {
                if let existingLayer = style.layer(withIdentifier: layerId(for: floor)) {
                    style.removeLayer(existingLayer)
                }
            }

            let visibleFloors: [(floor: Int, opacity: Double)]
            if selectedFloor > 0 {
                visibleFloors = [(0, 0.5), (selectedFloor, 1.0)]
            } else {
                visibleFloors = [(0, 1.0)]
            }

            for visibleFloor in visibleFloors {
                guard let rasterSource = addFloorSourceIfNeeded(floor: visibleFloor.floor, to: style) else {
                    continue
                }

                let rasterLayer = MLNRasterStyleLayer(identifier: layerId(for: visibleFloor.floor), source: rasterSource)
                rasterLayer.rasterResamplingMode = NSExpression(forConstantValue: "nearest")
                rasterLayer.rasterOpacity = NSExpression(forConstantValue: visibleFloor.opacity)
                rasterLayer.isVisible = true
                rasterLayer.minimumZoomLevel = 0
                rasterLayer.maximumZoomLevel = 12
                style.addLayer(rasterLayer)
            }
        }

        /// Update floor in shared map
        @MainActor
        func updateFloor(_ floor: Int) {
            guard isMapReady, let style = mapView?.style else {
                pendingFloorState = floor
                print("⚠️ Map not ready yet for floor update")
                return
            }

            // CRITICAL FIX: Avoid redundant floor updates that can trigger state modification warnings
            // Only update if the floor has actually changed from our tracked state
            guard floor != currentFloorState else {
                print("🔄 Floor \(floor) already active, skipping redundant update")
                return
            }

            print("🔄 Updating main map to floor \(floor) (was \(currentFloorState))")
            currentFloorState = floor

            rebuildFloorLayers(selectedFloor: floor, in: style)
            updateMapAccessibilityValue()
            mapView?.setNeedsDisplay()
        }
    }
}

#Preview {
    osrsMapLibreView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

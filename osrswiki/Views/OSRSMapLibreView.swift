import SwiftUI
import MapLibre
import CoreLocation

struct osrsMapLibreView: View {
    @StateObject private var store = osrsRealmMapStore()
    @StateObject private var mapController = osrsRealmMapController()
    @State private var isMapReady = false
    @State private var hasPresentedInitialMap = false
    @State private var bearing = 0.0
    @State private var selectorPresented = false
    @Environment(\.osrsTheme) private var osrsTheme

    var body: some View {
        ZStack(alignment: .top) {
            osrsRealmMapLibreView(
                store: store,
                isMapReady: $isMapReady,
                bearing: $bearing,
                mapController: mapController
            )
            .ignoresSafeArea()

            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .padding(24)
                    .accessibilityIdentifier("realm_map_error")
            } else if osrsShouldShowInitialMapLoader(
                hasPresentedInitialMap: hasPresentedInitialMap,
                errorMessage: store.errorMessage
            ) {
                ProgressView("Preparing map…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("realm_map_loading")
            }

            VStack(spacing: 10) {
                if !selectorPresented {
                    osrsRealmSelectorButton(store: store, expanded: false) {
                        selectorPresented = true
                    }
                    .osrsMapGlassChrome(in: Capsule())
                }

                HStack {
                    Spacer(minLength: 0)
                    if abs(osrsNormalizedBearing(bearing)) > 1 {
                        osrsRealmCompass(bearing: bearing) {
                            mapController.resetNorth()
                        }
                        .zIndex(10)
                        .transition(.opacity)
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)
                    if let realm = store.activeRealm, realm.planes.count > 1 {
                        osrsRealmFloorControl(store: store, realm: realm)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)

            if selectorPresented {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { selectorPresented = false }

                        osrsRealmSelectorPanel(store: store) {
                            selectorPresented = false
                        }
                        .frame(height: min(440, geometry.size.height * 0.52))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: isMapReady) { _, ready in
            if ready { hasPresentedInitialMap = true }
        }
        .navigationBarHidden(true)
        .background(.black)
        .animation(.easeOut(duration: 0.2), value: bearing)
    }

    static func gameToLatLng(gx: Double, gy: Double) -> CLLocationCoordinate2D {
        osrsMapDefaultView.mapCoordinate(gameX: gx, gameY: gy)
    }
}

func osrsShouldShowInitialMapLoader(
    hasPresentedInitialMap: Bool,
    errorMessage: String?
) -> Bool {
    !hasPresentedInitialMap && errorMessage == nil
}

private struct osrsRealmFloorControl: View {
    @ObservedObject var store: osrsRealmMapStore
    let realm: osrsRealmMapRecord
    @Environment(\.osrsTheme) private var osrsTheme

    var body: some View {
        VStack(spacing: 0) {
            button(systemName: "chevron.up", label: "Increase map floor") {
                guard let index = realm.planes.firstIndex(of: store.activePlane),
                      index + 1 < realm.planes.count else { return }
                store.select(plane: realm.planes[index + 1])
            }
            Text("\(store.activePlane)")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 48, height: 32)
            button(systemName: "chevron.down", label: "Decrease map floor") {
                guard let index = realm.planes.firstIndex(of: store.activePlane), index > 0 else { return }
                store.select(plane: realm.planes[index - 1])
            }
        }
        .foregroundStyle(Color(osrsTheme.mapControlTextColor))
        .frame(width: 48)
        .osrsMapGlassChrome(in: Capsule())
        .accessibilityIdentifier("realm_floor_control")
    }

    private func button(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .accessibilityLabel(label)
    }
}

private struct osrsRealmCompass: View {
    @Environment(\.osrsTheme) private var osrsTheme
    let bearing: Double
    let reset: () -> Void

    var body: some View {
        Button(action: reset) {
            ZStack {
                VStack(spacing: 1) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.red)
                    Text("N")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(osrsTheme.mapControlTextColor))
                }
                .rotationEffect(.degrees(-osrsNormalizedBearing(bearing)))
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(TapGesture().onEnded { reset() })
        .osrsMapGlassChrome(in: Circle())
        .accessibilityIdentifier("realm_map_compass")
        .accessibilityLabel("Reset map bearing to north")
    }
}

private struct osrsRealmSelectorButton: View {
    @ObservedObject var store: osrsRealmMapStore
    let expanded: Bool
    let action: () -> Void
    @Environment(\.osrsTheme) private var osrsTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .regular))
                Text(store.activeRealm?.canonicalName ?? "Choose realm")
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(Color(osrsTheme.mapControlTextColor))
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("realm_selector")
        .accessibilityLabel("Map realm, \(store.activeRealm?.canonicalName ?? "unavailable")")
    }
}

private struct osrsMapCapsuleGlassChromeModifier: ViewModifier {
    @Environment(\.osrsTheme) private var osrsTheme

    func body(content: Content) -> some View {
        content.osrsMapReadableGlass(in: Capsule(), theme: osrsTheme)
    }
}

private struct osrsMapPillGlassChromeModifier: ViewModifier {
    @Environment(\.osrsTheme) private var osrsTheme
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        content.osrsMapReadableGlass(in: shape, theme: osrsTheme)
    }
}

private struct osrsMapGlassChromeModifier<ChromeShape: Shape>: ViewModifier {
    @Environment(\.osrsTheme) private var osrsTheme
    let shape: ChromeShape

    func body(content: Content) -> some View {
        content.osrsMapReadableGlass(in: shape, theme: osrsTheme)
    }
}

private extension View {
    @ViewBuilder
    func osrsMapReadableGlass<ChromeShape: Shape>(
        in shape: ChromeShape,
        theme: any osrsThemeProtocol
    ) -> some View {
        let fallback = Color(theme.mapControlBackgroundColor)
        if theme is osrsLightTheme {
            self
                .background(fallback, in: shape)
                .clipShape(shape)
        } else {
            self.osrsFloatingGlass(in: shape, fallback: fallback.opacity(0.92))
        }
    }
}

private extension View {
    func osrsMapGlassChrome(in shape: Capsule) -> some View {
        modifier(osrsMapCapsuleGlassChromeModifier())
    }

    func osrsMapGlassChrome(in shape: RoundedRectangle) -> some View {
        modifier(osrsMapPillGlassChromeModifier(shape: shape))
    }

    func osrsMapGlassChrome<ChromeShape: Shape>(in shape: ChromeShape) -> some View {
        modifier(osrsMapGlassChromeModifier(shape: shape))
    }
}

private struct osrsRealmSelectorPanel: View {
    @ObservedObject var store: osrsRealmMapStore
    let close: () -> Void
    @Environment(\.osrsTheme) private var osrsTheme
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            osrsRealmSelectorButton(store: store, expanded: true, action: close)

            searchField
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider().overlay(osrsTheme.outline.opacity(0.35))

            Group {
                if store.filteredRealms.isEmpty {
                    Text("No realms found")
                        .font(.body)
                        .foregroundStyle(osrsTheme.secondaryTextColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("realm_selector_empty")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.filteredRealms) { realm in
                                realmRow(realm)
                                if realm.id != store.filteredRealms.last?.id {
                                    Divider()
                                        .overlay(osrsTheme.outline.opacity(0.22))
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }

        }
        .foregroundStyle(osrsTheme.primaryTextColor)
        .osrsMapGlassChrome(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .alert(
            "Voice Search Error",
            isPresented: Binding(
                get: { appState.speechManager.errorMessage != nil },
                set: { if !$0 { appState.speechManager.clearError() } }
            )
        ) {
            Button("OK") { appState.speechManager.clearError() }
        } message: {
            Text(appState.speechManager.errorMessage ?? "")
        }
        .onDisappear {
            appState.speechManager.cleanup()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(osrsTheme.secondaryTextColor)
            TextField("Search realms", text: $store.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(osrsTheme.primaryTextColor)
                .accessibilityIdentifier("realm_selector_search")
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(osrsTheme.secondaryTextColor)
                }
                .accessibilityLabel("Clear realm search")
            }
            osrsVoiceSearchButton(
                action: startVoiceRealmSearch,
                state: appState.speechManager.currentState,
                accessibilityIdentifier: "realm_selector_voice_search"
            )
        }
        .padding(.horizontal, 14)
        .frame(minHeight: osrsSearchControlGeometry.compactHeight)
        .osrsMapGlassChrome(in: osrsSearchControlGeometry.pillShape(height: osrsSearchControlGeometry.compactHeight))
    }

    private func startVoiceRealmSearch() {
        appState.speechManager.clearError()
        appState.speechManager.configure(
            onResult: { result in
                store.query = result
            },
            onPartialResult: { partialResult in
                store.query = partialResult
            },
            onError: { _ in }
        )
        appState.speechManager.startVoiceRecognition()
    }

    private func realmRow(_ realm: osrsRealmMapRecord) -> some View {
        Button {
            store.select(realm: realm)
            close()
        } label: {
            HStack(spacing: 12) {
                Text(realm.canonicalName)
                    .font(.body.weight(realm.id == store.activeRealmID ? .semibold : .regular))
                    .foregroundStyle(osrsTheme.primaryTextColor)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(
                realm.id == store.activeRealmID
                    ? osrsTheme.primary.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("realm_row_\(realm.id)")
        .accessibilityValue(realm.id == store.activeRealmID ? "Selected" : "")
    }
}

private func osrsNormalizedBearing(_ bearing: Double) -> Double {
    let normalized = bearing.truncatingRemainder(dividingBy: 360)
    let positive = normalized < 0 ? normalized + 360 : normalized
    return positive > 180 ? positive - 360 : positive
}

private struct osrsRealmMapLibreView: UIViewRepresentable {
    @ObservedObject var store: osrsRealmMapStore
    @Binding var isMapReady: Bool
    @Binding var bearing: Double
    @ObservedObject var mapController: osrsRealmMapController

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        container.isAccessibilityElement = false
        let mapView = MLNMapView(frame: .zero)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: container.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.configure(mapView)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applySelectionIfNeeded()
        context.coordinator.updateMinimumZoomIfNeeded()
        context.coordinator.updateAccessibility()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: osrsRealmMapLibreView
        weak var mapView: MLNMapView?
        private var styleReady = false
        private var appliedSelection: String?
        private var appliedRealmID: String?
        private var cameraAppliedSelection: String?
        private var cameraApplyGeneration = 0
        private var clampInProgress = false
        private var defaultMaximumScreenBounds: MLNCoordinateBounds?
        private var pendingFloorCamera: osrsLiveRealmCamera?
        private weak var mapPanGestureRecognizer: UIPanGestureRecognizer?
        private weak var mapPinchGestureRecognizer: UIPinchGestureRecognizer?
        private var cameraGestureTouchActive = false
        private var cameraZoomGestureTouchActive = false
        private var cameraGestureIncludedPinch = false
        private var cameraPanLastTranslationY = CGFloat.zero
        private var cameraVerticalOverscrollRawPoints = 0.0
        private var cameraVerticalOverscrollPoints = 0.0
        private var cameraVerticalSpring: osrsDampedSpringAxisState?
        private var edgePeakVisualVerticalOvershootPoints = 0.0
        private var cameraEdgePhysicsPhase = "idle"
        private var cameraEdgeDisplayLink: CADisplayLink?
        private var cameraEdgeLastTimestamp: CFTimeInterval = 0
        private var cameraEdgeStartedAt: CFTimeInterval?
        private var cameraEdgeFrameCount = 0
        private var cameraEdgeFrameIntervalTotal = 0.0
        private var cameraEdgeObservedMinimumFPS = Double.infinity
        private var cameraEdgeObservedMaximumFPS = 0.0
        private var cameraVelocityXPointsPerSecond = 0.0
        private var cameraVelocityYPointsPerSecond = 0.0
        private var cameraZoomVelocityLevelsPerSecond = 0.0
        private var cameraPinchReleaseVelocityLevelsPerSecond = 0.0
        private var cameraPinchFocalPoint: CGPoint?
        private var cameraPinchFocalCoordinate: CLLocationCoordinate2D?
        private var zoomMomentumStartZoom: Double?
        private var zoomMomentumPeakContinuation = 0.0
        private var lastZoomMomentumDurationSeconds: Double?
        private var lastZoomMomentumFrameCount = 0
        private var springLatitude: osrsDampedSpringAxisState?
        private var springLongitude: osrsDampedSpringAxisState?
        private var springTarget: CLLocationCoordinate2D?
        private var edgePeakLatitudeOvershoot = 0.0
        private var edgePeakLongitudeOvershoot = 0.0
        private var edgeLivePeakLatitudeOvershoot = 0.0
        private var edgeLivePeakLongitudeOvershoot = 0.0
        private var lastEdgeBounceDurationSeconds: Double?
        private var lastEdgeBounceFrameCount = 0
        private var edgePhysicsWriteInProgress = false
        private var compassResetUntil: CFTimeInterval = 0

        init(parent: osrsRealmMapLibreView) {
            self.parent = parent
            super.init()
        }

        @MainActor
        func configure(_ mapView: MLNMapView) {
            self.mapView = mapView
            parent.mapController.mapView = mapView
            parent.mapController.cancelMapMotion = { [weak self] in
                self?.cancelCameraEdgePhysics(reason: "compass-reset")
            }
            parent.mapController.applyNorthCamera = { [weak self] in
                self?.applyNorthCamera()
            }
            defaultMaximumScreenBounds = mapView.maximumScreenBounds
            mapView.delegate = self
            mapView.logoView.isHidden = true
            mapView.attributionButton.isHidden = true
            mapView.compassView.isHidden = true
            mapView.showsScale = false
            mapView.allowsRotating = true
            mapView.allowsTilting = false
            mapView.prefetchesTiles = true
            osrsMapPreferredFrameRate.apply(to: mapView)
            // Disable MapLibre's unconstrained coast. We retain native direct dragging and own
            // release inertia plus the finite-edge spring, matching Android's interaction model.
            mapView.decelerationRate = MLNMapViewDecelerationRate.immediate.rawValue
            mapView.isAccessibilityElement = true
            mapView.accessibilityIdentifier = "map_view"
            mapView.accessibilityLabel = "OSRS realm map"
            let styleJSON = """
            {"version":8,"name":"OSRS Realm Map","sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"#000000"}}]}
            """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("osrs-realm-style.json")
            try? styleJSON.write(to: url, atomically: true, encoding: .utf8)
            mapView.styleURL = url
            if let pan = mapView.gestureRecognizers?
                .compactMap({ $0 as? UIPanGestureRecognizer })
                .first {
                mapPanGestureRecognizer = pan
                pan.addTarget(self, action: #selector(handleMapPanGesture(_:)))
            }
            if let pinch = mapView.gestureRecognizers?
                .compactMap({ $0 as? UIPinchGestureRecognizer })
                .first {
                mapPinchGestureRecognizer = pinch
                pinch.addTarget(self, action: #selector(handleMapPinchGesture(_:)))
            }
        }

        @MainActor
        func teardown() {
            cancelCameraEdgePhysics(reason: "teardown")
            mapPanGestureRecognizer?.removeTarget(
                self,
                action: #selector(handleMapPanGesture(_:))
            )
            mapPinchGestureRecognizer?.removeTarget(
                self,
                action: #selector(handleMapPinchGesture(_:))
            )
            mapPanGestureRecognizer = nil
            mapPinchGestureRecognizer = nil
            parent.mapController.cancelMapMotion = nil
            parent.mapController.applyNorthCamera = nil
            parent.mapController.mapView = nil
            mapView?.delegate = nil
            mapView = nil
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            Task { @MainActor in
                self.styleReady = true
                self.appliedSelection = nil
                self.appliedRealmID = nil
                self.applySelectionIfNeeded()
            }
        }

        nonisolated func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            Task { @MainActor in
                if self.holdCompassReset(on: mapView) { return }
                self.parent.bearing = mapView.direction
                if self.cameraGestureTouchActive && !self.edgePhysicsWriteInProgress {
                    self.applyElasticCameraEnvelopeDuringGesture()
                }
                self.updateAccessibility()
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            Task { @MainActor in
                guard !self.cameraGestureTouchActive,
                      self.cameraEdgePhysicsPhase == "idle" else {
                    self.updateAccessibility()
                    return
                }
                if self.handleCameraChanged() {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        _ = self.handleCameraChanged()
                        self.persistCamera()
                    }
                } else {
                    self.persistCamera()
                }
            }
        }

        @MainActor
        func applySelectionIfNeeded() {
            guard styleReady,
                  let mapView,
                  let style = mapView.style,
                  let realm = parent.store.activeRealm else { return }
            let selection = "\(realm.id):\(parent.store.activePlane)"
            guard selection != appliedSelection else {
                scheduleCameraIfNeeded(realm: realm, selection: selection)
                return
            }
            cancelCameraEdgePhysics(reason: "selection-change")
            if appliedRealmID == realm.id,
               cameraAppliedSelection != nil {
                pendingFloorCamera = osrsLiveRealmCamera(
                    coordinate: mapView.centerCoordinate,
                    zoom: mapView.zoomLevel,
                    direction: mapView.direction
                )
            } else {
                pendingFloorCamera = nil
            }
            appliedSelection = selection
            appliedRealmID = realm.id
            cameraAppliedSelection = nil
            parent.isMapReady = false

            for layer in style.layers where layer.identifier.hasPrefix("osrs-realm-layer-") {
                style.removeLayer(layer)
            }
            for source in style.sources where source.identifier.hasPrefix("osrs-realm-source-") {
                style.removeSource(source)
            }

            let visible: [(osrsRealmMapAsset, Double)]
            if parent.store.activePlane > 0,
               let base = realm.asset(plane: 0),
               let selected = realm.asset(plane: parent.store.activePlane) {
                visible = [(base, 0.5), (selected, 1)]
            } else if let selected = realm.asset(plane: parent.store.activePlane) {
                visible = [(selected, 1)]
            } else {
                return
            }

            for (asset, opacity) in visible {
                guard let url = parent.store.assetURL(for: asset),
                      FileManager.default.fileExists(atPath: url.path) else { continue }
                let sourceID = "osrs-realm-source-\(asset.plane)"
                let layerID = "osrs-realm-layer-\(asset.plane)"
                let source = MLNRasterTileSource(
                    identifier: sourceID,
                    configurationURL: URL(string: "mbtiles://\(url.path)")!
                )
                style.addSource(source)
                let layer = MLNRasterStyleLayer(identifier: layerID, source: source)
                layer.rasterResamplingMode = NSExpression(forConstantValue: "nearest")
                layer.rasterOpacity = NSExpression(forConstantValue: opacity)
                layer.maximumZoomLevel = 22
                style.addLayer(layer)
            }

            scheduleCameraIfNeeded(realm: realm, selection: selection)
        }

        /// MapLibre can finish loading its style before SwiftUI has laid out the
        /// representable. Camera writes made while the native view is still 0x0
        /// are silently replaced by MapLibre's world overview. Wait for real
        /// bounds and make the geometry-derived camera the final initialization
        /// write for the active realm/floor.
        @MainActor
        private func scheduleCameraIfNeeded(
            realm: osrsRealmMapRecord,
            selection: String,
            attempt: Int = 0
        ) {
            guard cameraAppliedSelection != selection else { return }
            cameraApplyGeneration += 1
            let generation = cameraApplyGeneration
            let delay = attempt == 0 ? 0.0 : 0.02
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.cameraApplyGeneration == generation,
                      self.appliedSelection == selection,
                      self.parent.store.activeRealm?.id == realm.id else { return }
                guard let mapView = self.mapView,
                      mapView.bounds.width > 0,
                      mapView.bounds.height > 0 else {
                    guard attempt < 50 else { return }
                    self.scheduleCameraIfNeeded(
                        realm: realm,
                        selection: selection,
                        attempt: attempt + 1
                    )
                    return
                }
                mapView.layoutIfNeeded()
                self.applyCamera(realm: realm, preservedFloorCamera: self.pendingFloorCamera)
                self.pendingFloorCamera = nil
                self.cameraAppliedSelection = selection
                // MapLibre applies maximumScreenBounds and the following camera write
                // on separate native update turns. Publish readiness only after those
                // updates settle so UI clients cannot observe the intermediate nearest
                // edge inherited from the previous realm.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self,
                          self.cameraAppliedSelection == selection,
                          self.appliedSelection == selection else { return }
                    self.handleCameraChanged()
                    self.updateAccessibility()
                    self.parent.isMapReady = true
                }
            }
        }

        @MainActor
        private func applyCamera(
            realm: osrsRealmMapRecord,
            preservedFloorCamera: osrsLiveRealmCamera?
        ) {
            cancelCameraEdgePhysics(reason: "app-camera")
            guard let mapView,
                  let asset = realm.asset(plane: parent.store.activePlane),
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ) else { return }
            mapView.minimumZoomLevel = effectiveMinimumZoom(
                asset: asset,
                envelope: envelope
            )
            mapView.maximumZoomLevel = min(22, Double(asset.maxZoom) + 8)
            installOverflowScreenBounds(envelope: envelope)

            if let preservedFloorCamera {
                let coordinate = envelope.clamped(
                    envelope.resolvingMapLibreRepresentation(preservedFloorCamera.coordinate)
                )
                mapView.setCenter(
                    coordinate,
                    zoomLevel: min(
                        max(preservedFloorCamera.zoom, mapView.minimumZoomLevel),
                        mapView.maximumZoomLevel
                    ),
                    direction: preservedFloorCamera.direction,
                    animated: false
                )
                return
            }
            if let saved = parent.store.camera(for: realm) {
                let coordinate = envelope.clamped(CLLocationCoordinate2D(
                    latitude: saved.latitude,
                    longitude: saved.longitude
                ))
                mapView.setCenter(coordinate, zoomLevel: saved.zoom, direction: saved.direction, animated: false)
                return
            }

            let defaultZoom = min(
                max(osrsRealmDefaultCamera.zoom(asset: asset), mapView.minimumZoomLevel),
                mapView.maximumZoomLevel
            )
            if realm.isSurface,
               let projection = parent.store.manifest?.rasterProjection,
               let destination = osrsRealmEndpointMapper.map(
                gameX: 3222,
                gameY: 3218,
                plane: 0,
                realm: realm,
                projection: projection
               ) {
                mapView.setCenter(destination.coordinate, zoomLevel: defaultZoom, animated: false)
            } else {
                mapView.setCenter(
                    CLLocationCoordinate2D(
                        latitude: (envelope.south + envelope.north) / 2,
                        longitude: (envelope.west + envelope.east) / 2
                    ),
                    zoomLevel: defaultZoom,
                    animated: false
                )
            }
        }

        @MainActor
        func updateMinimumZoomIfNeeded() {
            guard let mapView,
                  let realm = parent.store.activeRealm,
                  let asset = realm.asset(plane: parent.store.activePlane),
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ) else { return }
            mapView.minimumZoomLevel = effectiveMinimumZoom(
                asset: asset,
                envelope: envelope
            )
            installOverflowScreenBounds(envelope: envelope)
        }

        @MainActor
        private func installOverflowScreenBounds(envelope: osrsRealmCameraEnvelope) {
            guard let mapView else { return }
            guard let screenBounds = envelope.screenBoundsAllowingCenterEdgeOverflow() else {
                if let defaultMaximumScreenBounds {
                    mapView.maximumScreenBounds = defaultMaximumScreenBounds
                }
                return
            }
            mapView.maximumScreenBounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: screenBounds.south,
                    longitude: screenBounds.west
                ),
                ne: CLLocationCoordinate2D(
                    latitude: screenBounds.north,
                    longitude: screenBounds.east
                )
            )
        }

        @MainActor
        private func effectiveMinimumZoom(
            asset: osrsRealmMapAsset,
            envelope: osrsRealmCameraEnvelope
        ) -> Double {
            let baseMinimum = max(0, Double(asset.minZoom) - 2)
            let viewportWidth = Double(mapView?.bounds.width ?? 0)
            let viewportHeight = Double(mapView?.bounds.height ?? 0)
            let resolvedWidth = viewportWidth > 0 ? viewportWidth : Double(UIScreen.main.bounds.width)
            let resolvedHeight = viewportHeight > 0 ? viewportHeight : Double(UIScreen.main.bounds.height)
            return envelope.finiteRealmMinimumZoom(
                baseMinimumZoom: baseMinimum,
                viewportWidth: resolvedWidth,
                viewportHeight: resolvedHeight
            ) ?? baseMinimum
        }

        @objc @MainActor
        private func handleMapPanGesture(_ pan: UIPanGestureRecognizer) {
            guard let mapView else { return }
            switch pan.state {
            case .began:
                cancelCameraEdgePhysics(reason: "gesture-began")
                cameraGestureTouchActive = true
                if !cameraZoomGestureTouchActive {
                    cameraGestureIncludedPinch = false
                }
                cameraEdgePhysicsPhase = "gesture"
                cameraPanLastTranslationY = pan.translation(in: mapView).y
                cameraVerticalOverscrollRawPoints = 0
                applyVerticalOverscrollTransform(0, mapView: mapView)
            case .changed:
                cameraGestureTouchActive = true
                let translationY = pan.translation(in: mapView).y
                let deltaY = Double(translationY - cameraPanLastTranslationY)
                cameraPanLastTranslationY = translationY
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    self.applyVerticalElasticOverscrollDuringGesture(
                        deltaYPoints: deltaY,
                        mapView: mapView
                    )
                }
            case .ended:
                let velocity = pan.velocity(in: mapView)
                cameraGestureTouchActive = false
                if !cameraZoomGestureTouchActive && !cameraGestureIncludedPinch {
                    beginCameraEdgeRelease(
                        velocityXPointsPerSecond: Double(velocity.x),
                        velocityYPointsPerSecond: Double(velocity.y),
                        allowInertia: true
                    )
                }
            case .cancelled, .failed:
                cameraGestureTouchActive = false
                if !cameraZoomGestureTouchActive && !cameraGestureIncludedPinch {
                    beginCameraEdgeRelease(
                        velocityXPointsPerSecond: 0,
                        velocityYPointsPerSecond: 0,
                        allowInertia: false
                    )
                }
            default:
                break
            }
        }

        @objc @MainActor
        private func handleMapPinchGesture(_ pinch: UIPinchGestureRecognizer) {
            guard let mapView else { return }
            switch pinch.state {
            case .began:
                cancelCameraEdgePhysics(reason: "pinch-began")
                cameraZoomGestureTouchActive = true
                cameraGestureIncludedPinch = true
                cameraPinchReleaseVelocityLevelsPerSecond = 0
                cameraEdgePhysicsPhase = "zoom-gesture"
            case .changed:
                cameraZoomGestureTouchActive = true
                cameraPinchFocalPoint = pinch.location(in: mapView)
                cameraPinchFocalCoordinate = mapView.convert(
                    pinch.location(in: mapView),
                    toCoordinateFrom: mapView
                )
                cameraPinchReleaseVelocityLevelsPerSecond = osrsPinchZoomVelocityLevelsPerSecond(
                    scale: max(Double(pinch.scale), 0.000_001),
                    scaleVelocityPerSecond: Double(pinch.velocity)
                )
            case .ended:
                cameraPinchFocalPoint = pinch.location(in: mapView)
                cameraPinchFocalCoordinate = mapView.convert(
                    pinch.location(in: mapView),
                    toCoordinateFrom: mapView
                )
                let velocity = osrsPinchZoomVelocityLevelsPerSecond(
                    scale: max(Double(pinch.scale), 0.000_001),
                    scaleVelocityPerSecond: Double(pinch.velocity)
                )
                cameraPinchReleaseVelocityLevelsPerSecond = velocity
                cameraZoomGestureTouchActive = false
                cameraGestureTouchActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.beginCameraZoomRelease(velocityLevelsPerSecond: velocity)
                    self?.cameraGestureIncludedPinch = false
                }
            case .cancelled, .failed:
                cameraZoomGestureTouchActive = false
                cameraGestureTouchActive = false
                cameraGestureIncludedPinch = false
                beginCameraZoomRelease(velocityLevelsPerSecond: 0)
            default:
                break
            }
        }

        @MainActor
        private func verticalOverscrollLimitPoints(mapView: MLNMapView) -> Double {
            min(max(Double(mapView.bounds.height) * 0.12, 24), 120)
        }

        @MainActor
        private func applyVerticalElasticOverscrollDuringGesture(
            deltaYPoints: Double,
            mapView: MLNMapView
        ) {
            guard let realm = parent.store.activeRealm,
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ),
                  let current = currentResolvedCamera(envelope: envelope) else { return }
            let latitudeTolerance = max((envelope.north - envelope.south) * 0.000_01, 0.000_001)
            let atNorth = current.coordinate.latitude >= envelope.north - latitudeTolerance
            let atSouth = current.coordinate.latitude <= envelope.south + latitudeTolerance
            let outward = (atNorth && deltaYPoints > 0) || (atSouth && deltaYPoints < 0)
            let returning = cameraVerticalOverscrollRawPoints != 0 &&
                ((cameraVerticalOverscrollRawPoints > 0 && deltaYPoints < 0) ||
                    (cameraVerticalOverscrollRawPoints < 0 && deltaYPoints > 0))
            guard outward || returning else {
                if !atNorth && !atSouth && cameraVerticalOverscrollPoints != 0 {
                    cameraVerticalOverscrollRawPoints = 0
                    applyVerticalOverscrollTransform(0, mapView: mapView)
                }
                return
            }
            cameraVerticalOverscrollRawPoints += deltaYPoints
            if atNorth {
                cameraVerticalOverscrollRawPoints = max(cameraVerticalOverscrollRawPoints, 0)
            } else if atSouth {
                cameraVerticalOverscrollRawPoints = min(cameraVerticalOverscrollRawPoints, 0)
            }
            let resisted = osrsResistedScreenOverscroll(
                distance: cameraVerticalOverscrollRawPoints,
                limit: verticalOverscrollLimitPoints(mapView: mapView)
            )
            applyVerticalOverscrollTransform(resisted, mapView: mapView)
            cameraEdgePhysicsPhase = abs(resisted) > 0.1 ? "gesture-vertical-elastic" : "gesture"
            updateAccessibility()
        }

        @MainActor
        private func applyVerticalOverscrollTransform(_ points: Double, mapView: MLNMapView) {
            cameraVerticalOverscrollPoints = points
            edgePeakVisualVerticalOvershootPoints = max(
                edgePeakVisualVerticalOvershootPoints,
                abs(points)
            )
            mapView.transform = CGAffineTransform(translationX: 0, y: CGFloat(points))
        }

        @MainActor
        private func currentResolvedCamera(
            envelope: osrsRealmCameraEnvelope
        ) -> osrsLiveRealmCamera? {
            guard let mapView else { return nil }
            return osrsLiveRealmCamera(
                coordinate: envelope.resolvingMapLibreRepresentation(mapView.centerCoordinate),
                zoom: mapView.zoomLevel,
                direction: mapView.direction
            )
        }

        @MainActor
        private func applyElasticCameraEnvelopeDuringGesture() {
            guard let mapView,
                  let realm = parent.store.activeRealm,
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ),
                  let current = currentResolvedCamera(envelope: envelope) else { return }
            let elastic = CLLocationCoordinate2D(
                latitude: osrsElasticAxisPosition(
                    requested: current.coordinate.latitude,
                    minimum: envelope.south,
                    maximum: envelope.north
                ),
                longitude: osrsElasticAxisPosition(
                    requested: current.coordinate.longitude,
                    minimum: envelope.west,
                    maximum: envelope.east
                )
            )
            recordCameraEdgeOvershoot(elastic, envelope: envelope)
            cameraEdgePhysicsPhase = envelope.contains(current.coordinate)
                ? "gesture"
                : "gesture-elastic"
            guard abs(elastic.latitude - current.coordinate.latitude) > 0.000_000_1 ||
                    abs(elastic.longitude - current.coordinate.longitude) > 0.000_000_1 else {
                return
            }
            setCameraFromEdgePhysics(elastic, mapView: mapView)
        }

        @MainActor
        private func beginCameraEdgeRelease(
            velocityXPointsPerSecond: Double,
            velocityYPointsPerSecond: Double,
            allowInertia: Bool
        ) {
            guard let mapView,
                  let realm = parent.store.activeRealm,
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ),
                  let current = currentResolvedCamera(envelope: envelope) else {
                cancelCameraEdgePhysics(reason: "release-no-envelope")
                return
            }
            cameraEdgeStartedAt = CACurrentMediaTime()
            cameraEdgeFrameCount = 0
            cameraEdgeFrameIntervalTotal = 0
            cameraEdgeObservedMinimumFPS = .infinity
            cameraEdgeObservedMaximumFPS = 0
            edgePeakLatitudeOvershoot = 0
            edgePeakLongitudeOvershoot = 0
            edgeLivePeakLatitudeOvershoot = 0
            edgeLivePeakLongitudeOvershoot = 0
            recordCameraEdgeOvershoot(current.coordinate, envelope: envelope)
            let strict = envelope.clamped(current.coordinate)
            let atNorth = current.coordinate.latitude >= envelope.north - 0.000_001
            let atSouth = current.coordinate.latitude <= envelope.south + 0.000_001
            let outwardVerticalRelease =
                (atNorth && velocityYPointsPerSecond > 0) ||
                (atSouth && velocityYPointsPerSecond < 0)
            if abs(cameraVerticalOverscrollPoints) > 0.1 || outwardVerticalRelease {
                setCameraFromEdgePhysics(strict, mapView: mapView)
                startVerticalVisualSpring(
                    initialVelocityPointsPerSecond: velocityYPointsPerSecond,
                    mapView: mapView
                )
                return
            }
            if !envelope.contains(current.coordinate) {
                let velocity = cameraCoordinateVelocity(
                    current: current.coordinate,
                    velocityXPointsPerSecond: velocityXPointsPerSecond,
                    velocityYPointsPerSecond: velocityYPointsPerSecond,
                    mapView: mapView,
                    envelope: envelope
                )
                startCameraEdgeSpring(
                    current: current.coordinate,
                    target: strict,
                    latitudeVelocity: velocity.latitude,
                    longitudeVelocity: velocity.longitude
                )
                return
            }
            let speed = hypot(velocityXPointsPerSecond, velocityYPointsPerSecond)
            if allowInertia && speed >= 80 {
                cameraVelocityXPointsPerSecond = velocityXPointsPerSecond
                cameraVelocityYPointsPerSecond = velocityYPointsPerSecond
                cameraEdgePhysicsPhase = "inertia"
                startCameraEdgeDisplayLink()
            } else {
                finishCameraEdgePhysics(at: strict, reason: "release-settled")
            }
        }

        @MainActor
        private func startVerticalVisualSpring(
            initialVelocityPointsPerSecond: Double,
            mapView: MLNMapView
        ) {
            let limit = verticalOverscrollLimitPoints(mapView: mapView)
            cameraVerticalSpring = osrsBoundedScreenSpringAxisState(
                osrsDampedSpringAxisState(
                    position: cameraVerticalOverscrollPoints,
                    velocity: min(max(initialVelocityPointsPerSecond, -2_400), 2_400)
                ),
                limit: limit
            )
            cameraEdgePhysicsPhase = "vertical-spring"
            startCameraEdgeDisplayLink()
        }

        @MainActor
        private func beginCameraZoomRelease(velocityLevelsPerSecond: Double) {
            guard let mapView else {
                cancelCameraEdgePhysics(reason: "zoom-release-no-map")
                return
            }
            cameraEdgeStartedAt = CACurrentMediaTime()
            cameraEdgeFrameCount = 0
            cameraEdgeFrameIntervalTotal = 0
            cameraEdgeObservedMinimumFPS = .infinity
            cameraEdgeObservedMaximumFPS = 0
            let boundedVelocity = min(
                max(velocityLevelsPerSecond, -osrsZoomMomentumMaximumVelocity),
                osrsZoomMomentumMaximumVelocity
            )
            guard abs(boundedVelocity) >= osrsZoomMomentumMinimumReleaseVelocity else {
                cancelCameraEdgePhysics(reason: "zoom-release-settled", retainLastResult: true)
                persistCamera()
                updateAccessibility()
                return
            }
            cameraZoomVelocityLevelsPerSecond = boundedVelocity
            zoomMomentumStartZoom = mapView.zoomLevel
            zoomMomentumPeakContinuation = 0
            cameraEdgePhysicsPhase = "zoom-inertia"
            startCameraEdgeDisplayLink()
        }

        @MainActor
        private func cameraCoordinateVelocity(
            current: CLLocationCoordinate2D,
            velocityXPointsPerSecond: Double,
            velocityYPointsPerSecond: Double,
            mapView: MLNMapView,
            envelope: osrsRealmCameraEnvelope
        ) -> (latitude: Double, longitude: Double) {
            let probeSeconds = 1.0 / 120.0
            let projected = mapView.convert(
                CGPoint(
                    x: mapView.bounds.midX - CGFloat(velocityXPointsPerSecond * probeSeconds),
                    y: mapView.bounds.midY - CGFloat(velocityYPointsPerSecond * probeSeconds)
                ),
                toCoordinateFrom: mapView
            )
            let resolved = envelope.resolvingMapLibreRepresentation(projected)
            return (
                (resolved.latitude - current.latitude) / probeSeconds,
                (resolved.longitude - current.longitude) / probeSeconds
            )
        }

        @MainActor
        private func startCameraEdgeSpring(
            current: CLLocationCoordinate2D,
            target: CLLocationCoordinate2D,
            latitudeVelocity: Double,
            longitudeVelocity: Double
        ) {
            springLatitude = osrsDampedSpringAxisState(
                position: current.latitude,
                velocity: latitudeVelocity
            )
            springLongitude = osrsDampedSpringAxisState(
                position: current.longitude,
                velocity: longitudeVelocity
            )
            springTarget = target
            cameraEdgePhysicsPhase = "spring"
            startCameraEdgeDisplayLink()
        }

        @MainActor
        private func startCameraEdgeDisplayLink() {
            if cameraEdgeDisplayLink == nil {
                let link = CADisplayLink(
                    target: self,
                    selector: #selector(stepCameraEdgePhysics(_:))
                )
                if #available(iOS 15.0, *) {
                    link.preferredFrameRateRange = osrsMapPreferredFrameRate.viewRange
                }
                link.add(to: .main, forMode: .common)
                cameraEdgeDisplayLink = link
            }
            cameraEdgeLastTimestamp = 0
        }

        @objc @MainActor
        private func stepCameraEdgePhysics(_ displayLink: CADisplayLink) {
            guard !cameraGestureTouchActive,
                  !cameraZoomGestureTouchActive,
                  cameraEdgePhysicsPhase != "idle" else { return }
            let previous = cameraEdgeLastTimestamp
            cameraEdgeLastTimestamp = displayLink.targetTimestamp
            guard previous > 0 else { return }
            let elapsed = min(
                max(displayLink.targetTimestamp - previous, 1.0 / 240.0),
                1.0 / 30.0
            )
            cameraEdgeFrameCount += 1
            let displayInterval = displayLink.targetTimestamp - displayLink.timestamp
            if displayInterval > 0 {
                let framesPerSecond = 1 / displayInterval
                cameraEdgeFrameIntervalTotal += displayInterval
                cameraEdgeObservedMinimumFPS = min(cameraEdgeObservedMinimumFPS, framesPerSecond)
                cameraEdgeObservedMaximumFPS = max(cameraEdgeObservedMaximumFPS, framesPerSecond)
            }
            switch cameraEdgePhysicsPhase {
            case "inertia":
                stepCameraEdgeInertia(elapsedSeconds: elapsed)
            case "spring":
                stepCameraEdgeSpring(elapsedSeconds: elapsed)
            case "vertical-spring":
                stepVerticalVisualSpring(elapsedSeconds: elapsed)
            case "zoom-inertia":
                stepCameraZoomInertia(elapsedSeconds: elapsed)
            default:
                break
            }
        }

        @MainActor
        private func stepCameraEdgeInertia(elapsedSeconds: Double) {
            guard let mapView,
                  let realm = parent.store.activeRealm,
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ),
                  let current = currentResolvedCamera(envelope: envelope) else {
                cancelCameraEdgePhysics(reason: "inertia-no-camera")
                return
            }
            let projected = mapView.convert(
                CGPoint(
                    x: mapView.bounds.midX -
                        CGFloat(cameraVelocityXPointsPerSecond * elapsedSeconds),
                    y: mapView.bounds.midY -
                        CGFloat(cameraVelocityYPointsPerSecond * elapsedSeconds)
                ),
                toCoordinateFrom: mapView
            )
            let requested = envelope.resolvingMapLibreRepresentation(projected)
            let strict = envelope.clamped(requested)
            if !envelope.contains(requested) {
                let elastic = CLLocationCoordinate2D(
                    latitude: osrsElasticAxisPosition(
                        requested: requested.latitude,
                        minimum: envelope.south,
                        maximum: envelope.north
                    ),
                    longitude: osrsElasticAxisPosition(
                        requested: requested.longitude,
                        minimum: envelope.west,
                        maximum: envelope.east
                    )
                )
                setCameraFromEdgePhysics(elastic, mapView: mapView)
                recordCameraEdgeOvershoot(elastic, envelope: envelope)
                startCameraEdgeSpring(
                    current: elastic,
                    target: strict,
                    latitudeVelocity:
                        (elastic.latitude - current.coordinate.latitude) / elapsedSeconds,
                    longitudeVelocity:
                        (elastic.longitude - current.coordinate.longitude) / elapsedSeconds
                )
                return
            }
            setCameraFromEdgePhysics(requested, mapView: mapView)
            let decay = exp(-5.2 * elapsedSeconds)
            cameraVelocityXPointsPerSecond *= decay
            cameraVelocityYPointsPerSecond *= decay
            if hypot(cameraVelocityXPointsPerSecond, cameraVelocityYPointsPerSecond) < 12 {
                finishCameraEdgePhysics(at: strict, reason: "inertia-settled")
            }
        }

        @MainActor
        private func stepCameraEdgeSpring(elapsedSeconds: Double) {
            guard let mapView,
                  let realm = parent.store.activeRealm,
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ),
                  let target = springTarget,
                  let latitudeState = springLatitude,
                  let longitudeState = springLongitude else {
                cancelCameraEdgePhysics(reason: "spring-incomplete")
                return
            }
            let latitude = osrsBoundedElasticSpringAxisState(
                state: osrsStepDampedSpring(
                    state: latitudeState,
                    target: target.latitude,
                    elapsedSeconds: elapsedSeconds
                ),
                minimum: envelope.south,
                maximum: envelope.north
            )
            let longitude = osrsBoundedElasticSpringAxisState(
                state: osrsStepDampedSpring(
                    state: longitudeState,
                    target: target.longitude,
                    elapsedSeconds: elapsedSeconds
                ),
                minimum: envelope.west,
                maximum: envelope.east
            )
            springLatitude = latitude
            springLongitude = longitude
            let coordinate = CLLocationCoordinate2D(
                latitude: latitude.position,
                longitude: longitude.position
            )
            setCameraFromEdgePhysics(coordinate, mapView: mapView)
            recordCameraEdgeOvershoot(coordinate, envelope: envelope)
            if osrsDampedSpringIsSettled(
                state: latitude,
                target: target.latitude,
                axisSpan: envelope.north - envelope.south
            ) && osrsDampedSpringIsSettled(
                state: longitude,
                target: target.longitude,
                axisSpan: envelope.east - envelope.west
            ) {
                finishCameraEdgePhysics(at: target, reason: "spring-settled")
            }
        }

        @MainActor
        private func stepVerticalVisualSpring(elapsedSeconds: Double) {
            guard let mapView, let state = cameraVerticalSpring else {
                cancelCameraEdgePhysics(reason: "vertical-spring-incomplete")
                return
            }
            let next = osrsBoundedScreenSpringAxisState(
                osrsStepDampedSpring(
                    state: state,
                    target: 0,
                    elapsedSeconds: elapsedSeconds
                ),
                limit: verticalOverscrollLimitPoints(mapView: mapView)
            )
            cameraVerticalSpring = next
            applyVerticalOverscrollTransform(next.position, mapView: mapView)
            updateAccessibility()
            if osrsDampedSpringIsSettled(
                state: next,
                target: 0,
                axisSpan: max(Double(mapView.bounds.height), 1)
            ) {
                guard let realm = parent.store.activeRealm,
                      let envelope = osrsRealmCameraEnvelope.visibleComposition(
                        realm: realm,
                        selectedPlane: parent.store.activePlane
                      ),
                      let current = currentResolvedCamera(envelope: envelope) else {
                    cancelCameraEdgePhysics(reason: "vertical-spring-finish-no-camera")
                    return
                }
                finishCameraEdgePhysics(
                    at: envelope.clamped(current.coordinate),
                    reason: "vertical-spring-settled"
                )
            }
        }

        @MainActor
        private func stepCameraZoomInertia(elapsedSeconds: Double) {
            guard let mapView else {
                cancelCameraEdgePhysics(reason: "zoom-inertia-no-map")
                return
            }
            let minimum = mapView.minimumZoomLevel
            let maximum = mapView.maximumZoomLevel
            let current = mapView.zoomLevel
            let requested = current + cameraZoomVelocityLevelsPerSecond * elapsedSeconds
            let next = min(max(requested, minimum), maximum)
            edgePhysicsWriteInProgress = true
            mapView.setCenter(
                mapView.centerCoordinate,
                zoomLevel: next,
                direction: mapView.direction,
                animated: false
            )
            if let focalPoint = cameraPinchFocalPoint,
               let focalCoordinate = cameraPinchFocalCoordinate {
                let renderedPoint = mapView.convert(focalCoordinate, toPointTo: mapView)
                let adjustedCenterPoint = CGPoint(
                    x: mapView.bounds.midX + renderedPoint.x - focalPoint.x,
                    y: mapView.bounds.midY + renderedPoint.y - focalPoint.y
                )
                let adjustedCoordinate = mapView.convert(
                    adjustedCenterPoint,
                    toCoordinateFrom: mapView
                )
                let finalCoordinate: CLLocationCoordinate2D
                if let realm = parent.store.activeRealm,
                   let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                   ) {
                    finalCoordinate = envelope.clamped(
                        envelope.resolvingMapLibreRepresentation(adjustedCoordinate)
                    )
                } else {
                    finalCoordinate = adjustedCoordinate
                }
                mapView.setCenter(
                    finalCoordinate,
                    zoomLevel: next,
                    direction: mapView.direction,
                    animated: false
                )
            }
            edgePhysicsWriteInProgress = false
            if let start = zoomMomentumStartZoom {
                zoomMomentumPeakContinuation = max(
                    zoomMomentumPeakContinuation,
                    abs(mapView.zoomLevel - start)
                )
            }
            cameraZoomVelocityLevelsPerSecond = osrsDecayZoomMomentumVelocity(
                cameraZoomVelocityLevelsPerSecond,
                elapsedSeconds: elapsedSeconds
            )
            updateAccessibility()
            let reachedLimit = abs(next - requested) > 0.000_001
            if reachedLimit || abs(cameraZoomVelocityLevelsPerSecond) < osrsZoomMomentumStopVelocity {
                lastZoomMomentumFrameCount = cameraEdgeFrameCount
                lastZoomMomentumDurationSeconds = cameraEdgeStartedAt.map {
                    CACurrentMediaTime() - $0
                }
                cameraPinchFocalPoint = nil
                cameraPinchFocalCoordinate = nil
                cancelCameraEdgePhysics(reason: "zoom-inertia-settled", retainLastResult: true)
                persistCamera()
                updateAccessibility()
            }
        }

        @MainActor
        private func setCameraFromEdgePhysics(
            _ coordinate: CLLocationCoordinate2D,
            mapView: MLNMapView
        ) {
            edgePhysicsWriteInProgress = true
            mapView.setCenter(
                coordinate,
                zoomLevel: mapView.zoomLevel,
                direction: mapView.direction,
                animated: false
            )
            edgePhysicsWriteInProgress = false
            if let realm = parent.store.activeRealm,
               let envelope = osrsRealmCameraEnvelope.visibleComposition(
                realm: realm,
                selectedPlane: parent.store.activePlane
               ) {
                let live = envelope.resolvingMapLibreRepresentation(mapView.centerCoordinate)
                edgeLivePeakLatitudeOvershoot = max(
                    edgeLivePeakLatitudeOvershoot,
                    max(envelope.south - live.latitude, max(live.latitude - envelope.north, 0))
                )
                edgeLivePeakLongitudeOvershoot = max(
                    edgeLivePeakLongitudeOvershoot,
                    max(envelope.west - live.longitude, max(live.longitude - envelope.east, 0))
                )
            }
            if !holdCompassReset(on: mapView) {
                parent.bearing = mapView.direction
            }
            updateAccessibility()
        }

        @MainActor
        private func recordCameraEdgeOvershoot(
            _ coordinate: CLLocationCoordinate2D,
            envelope: osrsRealmCameraEnvelope
        ) {
            edgePeakLatitudeOvershoot = max(
                edgePeakLatitudeOvershoot,
                max(
                    envelope.south - coordinate.latitude,
                    max(coordinate.latitude - envelope.north, 0)
                )
            )
            edgePeakLongitudeOvershoot = max(
                edgePeakLongitudeOvershoot,
                max(
                    envelope.west - coordinate.longitude,
                    max(coordinate.longitude - envelope.east, 0)
                )
            )
        }

        @MainActor
        private func finishCameraEdgePhysics(
            at coordinate: CLLocationCoordinate2D,
            reason: String
        ) {
            guard let mapView else {
                cancelCameraEdgePhysics(reason: reason)
                return
            }
            setCameraFromEdgePhysics(coordinate, mapView: mapView)
            applyVerticalOverscrollTransform(0, mapView: mapView)
            lastEdgeBounceFrameCount = cameraEdgeFrameCount
            lastEdgeBounceDurationSeconds = cameraEdgeStartedAt.map {
                CACurrentMediaTime() - $0
            }
            cancelCameraEdgePhysics(reason: reason, retainLastResult: true)
            persistCamera()
            updateAccessibility()
        }

        @MainActor
        private func cancelCameraEdgePhysics(
            reason: String,
            retainLastResult: Bool = false
        ) {
            cameraEdgeDisplayLink?.invalidate()
            cameraEdgeDisplayLink = nil
            cameraEdgeLastTimestamp = 0
            cameraEdgePhysicsPhase = "idle"
            cameraVelocityXPointsPerSecond = 0
            cameraVelocityYPointsPerSecond = 0
            cameraZoomVelocityLevelsPerSecond = 0
            springLatitude = nil
            springLongitude = nil
            springTarget = nil
            cameraVerticalSpring = nil
            cameraVerticalOverscrollRawPoints = 0
            if let mapView {
                applyVerticalOverscrollTransform(0, mapView: mapView)
            } else {
                cameraVerticalOverscrollPoints = 0
            }
            edgePhysicsWriteInProgress = false
            if !retainLastResult {
                cameraEdgeStartedAt = nil
                cameraEdgeFrameCount = 0
                cameraEdgeFrameIntervalTotal = 0
                cameraEdgeObservedMinimumFPS = .infinity
                cameraEdgeObservedMaximumFPS = 0
                edgePeakLatitudeOvershoot = 0
                edgePeakLongitudeOvershoot = 0
                edgeLivePeakLatitudeOvershoot = 0
                edgeLivePeakLongitudeOvershoot = 0
                edgePeakVisualVerticalOvershootPoints = 0
                zoomMomentumStartZoom = nil
                zoomMomentumPeakContinuation = 0
                cameraPinchFocalPoint = nil
                cameraPinchFocalCoordinate = nil
            }
            _ = reason
        }

        @MainActor
        private func applyNorthCamera() {
            compassResetUntil = CACurrentMediaTime() + 0.55
            guard let mapView else {
                parent.bearing = 0
                return
            }
            mapView.gestureRecognizers?.forEach { recognizer in
                if recognizer is UIRotationGestureRecognizer || recognizer is UIPanGestureRecognizer {
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                }
            }
            var camera = mapView.camera
            camera.heading = 0
            mapView.direction = 0
            mapView.setCamera(
                camera,
                withDuration: 0.18,
                animationTimingFunction: CAMediaTimingFunction(name: .easeOut)
            )
            parent.bearing = 0
        }

        @MainActor
        @discardableResult
        private func holdCompassReset(on mapView: MLNMapView) -> Bool {
            guard CACurrentMediaTime() < compassResetUntil else { return false }
            if abs(osrsNormalizedBearing(mapView.direction)) > 0.25 {
                mapView.direction = 0
            }
            parent.bearing = 0
            return true
        }

        @MainActor
        @discardableResult
        private func handleCameraChanged() -> Bool {
            guard let mapView else { return false }
            if holdCompassReset(on: mapView) { return false }
            parent.bearing = mapView.direction
            guard !clampInProgress,
                  let realm = parent.store.activeRealm,
                  let envelope = osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: parent.store.activePlane
                  ) else { return false }
            let reported = mapView.centerCoordinate
            let resolved = envelope.resolvingMapLibreRepresentation(reported)
            let clamped = envelope.clamped(resolved)
            let representationChanged = abs(reported.longitude - resolved.longitude) > 0.000_001
            guard representationChanged || !envelope.contains(resolved) else {
                updateAccessibility()
                return false
            }
            clampInProgress = true
            mapView.setCenter(clamped, animated: false)
            clampInProgress = false
            updateAccessibility()
            return true
        }

        @MainActor
        private func persistCamera() {
            guard let mapView,
                  let realm = parent.store.activeRealm,
                  parent.isMapReady,
                  cameraAppliedSelection == "\(realm.id):\(parent.store.activePlane)" else { return }
            parent.store.saveCamera(
                osrsRealmPersistedCamera(
                    geometryIdentity: realm.cameraGeometryIdentity,
                    latitude: mapView.centerCoordinate.latitude,
                    longitude: mapView.centerCoordinate.longitude,
                    zoom: mapView.zoomLevel,
                    direction: mapView.direction
                ),
                realmID: realm.id
            )
        }

        @MainActor
        func updateAccessibility() {
            guard let mapView, let realm = parent.store.activeRealm else { return }
            let envelope = osrsRealmCameraEnvelope.visibleComposition(
                realm: realm,
                selectedPlane: parent.store.activePlane
            )
            let snapshot = String(
                format: "centerLat=%.14f;centerLon=%.10f;zoom=%.13f;minZoom=%.13f;floor=%d;ready=true;realm=%@;bearing=%.2f;envelopeWest=%.10f;envelopeSouth=%.10f;envelopeEast=%.10f;envelopeNorth=%.10f;centerEdgeOverflow=true;horizontalWrap=false;edgePhysicsPhase=%@;edgePhysicsFrames=%d;edgePeakLatitudeOvershoot=%.10f;edgePeakLongitudeOvershoot=%.10f;edgeLivePeakLatitudeOvershoot=%.10f;edgeLivePeakLongitudeOvershoot=%.10f;edgeVisualVerticalOffsetPoints=%.5f;edgePeakVisualVerticalOvershootPoints=%.5f;edgeAverageFPS=%.3f;edgeMinimumFPS=%.3f;edgeMaximumFPS=%.3f;screenMaximumFPS=%d;mapPreferredFPS=%d;zoomReleaseVelocity=%.5f;zoomMomentumPeakContinuation=%.5f;lastZoomMomentumDuration=%.5f;lastZoomMomentumFrames=%d;lastEdgeBounceDuration=%.5f;lastEdgeBounceFrames=%d;compassResets=%d",
                locale: Locale(identifier: "en_US_POSIX"),
                mapView.centerCoordinate.latitude,
                mapView.centerCoordinate.longitude,
                mapView.zoomLevel,
                mapView.minimumZoomLevel,
                parent.store.activePlane,
                realm.id,
                mapView.direction,
                envelope?.west ?? .nan,
                envelope?.south ?? .nan,
                envelope?.east ?? .nan,
                envelope?.north ?? .nan,
                cameraEdgePhysicsPhase,
                cameraEdgeFrameCount,
                edgePeakLatitudeOvershoot,
                edgePeakLongitudeOvershoot,
                edgeLivePeakLatitudeOvershoot,
                edgeLivePeakLongitudeOvershoot,
                cameraVerticalOverscrollPoints,
                edgePeakVisualVerticalOvershootPoints,
                cameraEdgeFrameIntervalTotal > 0
                    ? Double(cameraEdgeFrameCount) / cameraEdgeFrameIntervalTotal
                    : .nan,
                cameraEdgeObservedMinimumFPS.isFinite ? cameraEdgeObservedMinimumFPS : .nan,
                cameraEdgeObservedMaximumFPS,
                UIScreen.main.maximumFramesPerSecond,
                mapView.preferredFramesPerSecond.rawValue,
                cameraPinchReleaseVelocityLevelsPerSecond,
                zoomMomentumPeakContinuation,
                lastZoomMomentumDurationSeconds ?? .nan,
                lastZoomMomentumFrameCount,
                lastEdgeBounceDurationSeconds ?? .nan,
                lastEdgeBounceFrameCount,
                parent.mapController.resetInvocationCount
            )
            mapView.accessibilityValue = snapshot
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-exposeMapCameraForUITests") {
                mapView.accessibilityLabel = "OSRS realm map;\(snapshot)"
            }
#endif
        }
    }
}

@MainActor
private final class osrsRealmMapController: ObservableObject {
    @Published private(set) var resetInvocationCount = 0
    weak var mapView: MLNMapView?
    var cancelMapMotion: (() -> Void)?
    var applyNorthCamera: (() -> Void)?

    func resetNorth() {
        resetInvocationCount += 1
        cancelMapMotion?()
        applyNorthCamera?()
        mapView?.direction = 0
    }
}

private struct osrsLiveRealmCamera {
    let coordinate: CLLocationCoordinate2D
    let zoom: Double
    let direction: Double
}

#Preview {
    osrsMapLibreView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

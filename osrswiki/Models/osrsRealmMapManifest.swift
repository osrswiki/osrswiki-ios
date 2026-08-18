import Foundation
import CoreLocation

let osrsEdgeMaximumOvershootFraction = 0.12
let osrsEdgeSpringNaturalFrequency = 14.0
let osrsEdgeSpringDampingRatio = 0.82
let osrsZoomMomentumDecelerationPerSecond = 4.8
let osrsZoomMomentumMaximumVelocity = 6.0
let osrsZoomMomentumMinimumReleaseVelocity = 0.04
let osrsZoomMomentumStopVelocity = 0.01

func osrsElasticAxisPosition(
    requested: Double,
    minimum: Double,
    maximum: Double,
    maximumOvershootFraction: Double = osrsEdgeMaximumOvershootFraction
) -> Double {
    precondition(requested.isFinite && minimum.isFinite && maximum.isFinite)
    precondition(minimum < maximum)
    precondition(maximumOvershootFraction > 0 && maximumOvershootFraction < 0.5)
    guard requested < minimum || requested > maximum else { return requested }
    let edge = requested < minimum ? minimum : maximum
    let direction = requested < minimum ? -1.0 : 1.0
    let distance = abs(requested - edge)
    let limit = (maximum - minimum) * maximumOvershootFraction
    let resistedDistance = limit * distance / (limit + distance)
    return edge + direction * resistedDistance
}

struct osrsDampedSpringAxisState: Equatable {
    let position: Double
    let velocity: Double
}

func osrsStepDampedSpring(
    state: osrsDampedSpringAxisState,
    target: Double,
    elapsedSeconds: Double,
    naturalFrequency: Double = osrsEdgeSpringNaturalFrequency,
    dampingRatio: Double = osrsEdgeSpringDampingRatio
) -> osrsDampedSpringAxisState {
    precondition(target.isFinite && elapsedSeconds.isFinite && elapsedSeconds >= 0)
    precondition(naturalFrequency > 0 && dampingRatio > 0)
    guard elapsedSeconds > 0 else { return state }
    let maximumSubstep = 1.0 / 240.0
    let count = max(1, Int(ceil(elapsedSeconds / maximumSubstep)))
    let dt = elapsedSeconds / Double(count)
    let stiffness = naturalFrequency * naturalFrequency
    let damping = 2 * dampingRatio * naturalFrequency
    var position = state.position
    var velocity = state.velocity
    for _ in 0..<count {
        let acceleration = -stiffness * (position - target) - damping * velocity
        velocity += acceleration * dt
        position += velocity * dt
    }
    return osrsDampedSpringAxisState(position: position, velocity: velocity)
}

func osrsBoundedElasticSpringAxisState(
    state: osrsDampedSpringAxisState,
    minimum: Double,
    maximum: Double,
    maximumOvershootFraction: Double = osrsEdgeMaximumOvershootFraction
) -> osrsDampedSpringAxisState {
    precondition(state.position.isFinite && state.velocity.isFinite)
    precondition(minimum.isFinite && maximum.isFinite && minimum < maximum)
    precondition(maximumOvershootFraction > 0 && maximumOvershootFraction < 0.5)
    let overshootLimit = (maximum - minimum) * maximumOvershootFraction
    let lowerLimit = minimum - overshootLimit
    let upperLimit = maximum + overshootLimit
    if state.position <= lowerLimit {
        return osrsDampedSpringAxisState(
            position: lowerLimit,
            velocity: state.velocity < 0 ? 0 : state.velocity
        )
    }
    if state.position >= upperLimit {
        return osrsDampedSpringAxisState(
            position: upperLimit,
            velocity: state.velocity > 0 ? 0 : state.velocity
        )
    }
    return state
}

func osrsDampedSpringIsSettled(
    state: osrsDampedSpringAxisState,
    target: Double,
    axisSpan: Double
) -> Bool {
    precondition(target.isFinite && axisSpan.isFinite && axisSpan > 0)
    let positionTolerance = max(axisSpan * 0.000_01, 0.000_000_1)
    let velocityTolerance = max(axisSpan * 0.000_5, 0.000_001)
    return abs(state.position - target) <= positionTolerance &&
        abs(state.velocity) <= velocityTolerance
}

/// Converts a pinch recognizer's multiplicative scale velocity to MapLibre zoom levels/second.
/// One doubling of scale is exactly one zoom level.
func osrsPinchZoomVelocityLevelsPerSecond(
    scale: Double,
    scaleVelocityPerSecond: Double
) -> Double {
    precondition(scale.isFinite && scale > 0 && scaleVelocityPerSecond.isFinite)
    return min(
        max(scaleVelocityPerSecond / (scale * log(2)), -osrsZoomMomentumMaximumVelocity),
        osrsZoomMomentumMaximumVelocity
    )
}

func osrsDecayZoomMomentumVelocity(
    _ velocity: Double,
    elapsedSeconds: Double
) -> Double {
    precondition(velocity.isFinite && elapsedSeconds.isFinite && elapsedSeconds >= 0)
    return velocity * exp(-osrsZoomMomentumDecelerationPerSecond * elapsedSeconds)
}

/// Screen-space resistance used when MapLibre's finite Web Mercator world prevents a latitude
/// camera from moving beyond its legal screen bounds. The camera stays strict while its rendered
/// surface follows the finger and springs back.
func osrsResistedScreenOverscroll(distance: Double, limit: Double) -> Double {
    precondition(distance.isFinite && limit.isFinite && limit > 0)
    let magnitude = abs(distance)
    return (distance < 0 ? -1 : 1) * limit * magnitude / (limit + magnitude)
}

func osrsBoundedScreenSpringAxisState(
    _ state: osrsDampedSpringAxisState,
    limit: Double
) -> osrsDampedSpringAxisState {
    precondition(limit.isFinite && limit > 0)
    if state.position <= -limit {
        return osrsDampedSpringAxisState(
            position: -limit,
            velocity: state.velocity < 0 ? 0 : state.velocity
        )
    }
    if state.position >= limit {
        return osrsDampedSpringAxisState(
            position: limit,
            velocity: state.velocity > 0 ? 0 : state.velocity
        )
    }
    return state
}

struct osrsRealmMapManifest: Decodable {
    let schemaVersion: Int
    let candidate: String
    let inputs: Inputs?
    let realms: [osrsRealmMapRecord]

    struct Inputs: Decodable {
        let sourceSnapshots: SourceSnapshots?
    }

    struct SourceSnapshots: Decodable {
        let raster: Raster?
    }

    struct Raster: Decodable {
        let gameBounds: GameBounds
        let gameCoordScale: Int
        let width: Int
        let height: Int
    }

    struct GameBounds: Decodable {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
    }

    static func load(bundle: Bundle = .main) throws -> osrsRealmMapManifest {
        guard let root = bundle.resourceURL?
            .appendingPathComponent("UndergroundRealms", isDirectory: true),
              FileManager.default.fileExists(
                atPath: root.appendingPathComponent("underground-realms.json").path
              ) else {
            throw osrsRealmMapError.missingManifest
        }
        let data = try Data(contentsOf: root.appendingPathComponent("underground-realms.json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }

    func realm(id: String) -> osrsRealmMapRecord? {
        realms.first { $0.id == id }
    }

    var surface: osrsRealmMapRecord? {
        realm(id: "surface-gielinor") ?? realms.first(where: \.isSurface)
    }

    /// The producer publishes only the canonical product catalog: Gielinor Surface and named
    /// native cache world maps. Filtering remains fail-closed in case a malformed or legacy
    /// manifest is supplied. Future in-game captures may corroborate records after generation,
    /// never define this list as a priori generation knowledge.
    var canonicalSelectorRealms: [osrsRealmMapRecord] {
        realms.filter(\.isCanonicalSelectorRealm)
    }

    var rasterProjection: osrsRealmRasterProjection? {
        guard let raster = inputs?.sourceSnapshots?.raster else { return nil }
        return osrsRealmRasterProjection(
            gameMinX: raster.gameBounds.minX,
            gameMaxY: raster.gameBounds.maxY,
            scale: raster.gameCoordScale,
            width: raster.width,
            height: raster.height
        )
    }
}

struct osrsRealmMapRecord: Decodable, Identifiable, Hashable {
    let id: String
    let canonicalName: String
    let aliases: [String]
    let group: String
    let isSurface: Bool
    let mapId: Int?
    let defaultPlane: Int
    let planes: [Int]
    let assets: [osrsRealmMapAsset]

    func asset(plane: Int) -> osrsRealmMapAsset? {
        assets.first { $0.plane == plane }
    }

    var searchableText: String {
        ([canonicalName, id] + aliases).joined(separator: " ").localizedLowercase
    }

    var isCanonicalSelectorRealm: Bool {
        group == "surface" || group == "realms"
    }

    /// One camera belongs to the realm, not to an individual floor. The complete
    /// identity invalidates it whenever any shared-canvas plane is regenerated or
    /// the fresh-camera scale contract changes.
    var cameraGeometryIdentity: String {
        "source-pixel-default-v1|" + assets
            .sorted { $0.plane < $1.plane }
            .map { "\($0.plane)=\($0.geometryIdentity)" }
            .joined(separator: "|")
    }
}

struct osrsRealmMapAsset: Decodable, Hashable {
    let plane: Int
    let mbtilesPath: String
    let mbtilesSha256: String
    let width: Int
    let height: Int
    let minZoom: Int
    let maxZoom: Int
    let canvasSize: Int
    let contentPixelBounds: [Int]
    let contentLatlonBounds: [Double]
    let layoutComponents: [osrsRealmLayoutComponent]

    var west: Double { contentLatlonBounds[0] }
    var south: Double { contentLatlonBounds[1] }
    var east: Double { contentLatlonBounds[2] }
    var north: Double { contentLatlonBounds[3] }

    var geometryIdentity: String {
        "\(mbtilesSha256):\(canvasSize):\(contentPixelBounds.map(String.init).joined(separator: ","))"
    }
}

struct osrsRealmPixelBounds: Decodable, Hashable {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    func contains(x: Double, y: Double) -> Bool {
        x >= Double(minX) && x < Double(maxX) &&
        y >= Double(minY) && y < Double(maxY)
    }
}

struct osrsRealmLayoutComponent: Decodable, Hashable {
    let sourcePixelBounds: osrsRealmPixelBounds
    let assetPixelBounds: osrsRealmPixelBounds
}

struct osrsRealmRasterProjection: Equatable {
    let gameMinX: Int
    let gameMaxY: Int
    let scale: Int
    let width: Int
    let height: Int
}

struct osrsRealmCameraEnvelope: Equatable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double

    func clamped(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: min(max(coordinate.latitude, south), north),
            longitude: min(max(coordinate.longitude, west), east)
        )
    }

    /// Resolves MapLibre's equivalent world-copy longitude back to the finite envelope's
    /// nearest representation. Camera requests still use `clamped(_:)` directly, so a
    /// caller cannot use ±360° to re-enter through the opposite edge.
    func resolvingMapLibreRepresentation(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let candidates = (-2...2).map { coordinate.longitude + Double($0) * 360 }
        let resolvedLongitude = candidates.min { lhs, rhs in
            let lhsDistance = longitudeDistanceFromEnvelope(lhs)
            let rhsDistance = longitudeDistanceFromEnvelope(rhs)
            if lhsDistance == rhsDistance {
                return abs(lhs - coordinate.longitude) < abs(rhs - coordinate.longitude)
            }
            return lhsDistance < rhsDistance
        } ?? coordinate.longitude
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: resolvedLongitude
        )
    }

    private func longitudeDistanceFromEnvelope(_ longitude: Double) -> Double {
        if longitude < west { return west - longitude }
        if longitude > east { return longitude - east }
        return 0
    }

    func contains(_ coordinate: CLLocationCoordinate2D, tolerance: Double = 0.000_001) -> Bool {
        coordinate.longitude >= west - tolerance && coordinate.longitude <= east + tolerance &&
        coordinate.latitude >= south - tolerance && coordinate.latitude <= north + tolerance
    }

    static func visibleComposition(
        realm: osrsRealmMapRecord,
        selectedPlane: Int
    ) -> osrsRealmCameraEnvelope? {
        let assets = selectedPlane == 0
            ? [realm.asset(plane: 0)].compactMap { $0 }
            : [realm.asset(plane: 0), realm.asset(plane: selectedPlane)].compactMap { $0 }
        guard let first = assets.first else { return nil }
        guard Set(assets.map(\.canvasSize)).count == 1 else { return nil }
        return assets.dropFirst().reduce(
            osrsRealmCameraEnvelope(
                west: first.west,
                south: first.south,
                east: first.east,
                north: first.north
            )
        ) { partial, asset in
            osrsRealmCameraEnvelope(
                west: min(partial.west, asset.west),
                south: min(partial.south, asset.south),
                east: max(partial.east, asset.east),
                north: max(partial.north, asset.north)
            )
        }
    }

    /// Minimum zoom that keeps the nearest repeated world copy outside either viewport edge.
    func copySafeMinimumZoom(
        viewportWidth: Double,
        worldWidthAtZoomZero: Double = 512
    ) -> Double? {
        guard viewportWidth.isFinite, viewportWidth > 0,
              worldWidthAtZoomZero.isFinite, worldWidthAtZoomZero > 0 else { return nil }
        let contentFraction = (east - west) / 360
        guard contentFraction > 0, contentFraction < 1 else { return nil }
        let gapFraction = 1 - contentFraction
        return max(0, log2(viewportWidth / (2 * worldWidthAtZoomZero * gapFraction)))
    }

    /// Applies the same no-world-copy zoom floor to Surface and non-surface realms.
    /// This does not shrink the legal center envelope: exact content edges remain valid
    /// camera centers, preserving the established half-viewport overbound behavior.
    func finiteRealmMinimumZoom(
        baseMinimumZoom: Double,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> Double? {
        guard baseMinimumZoom.isFinite, baseMinimumZoom >= 0,
              viewportWidth.isFinite, viewportWidth > 0,
              viewportHeight.isFinite, viewportHeight > 0 else { return nil }
        let northY = Self.webMercatorY(latitude: north)
        let southY = Self.webMercatorY(latitude: south)
        let horizontalPadding = min((west + 180) / 360, (180 - east) / 360)
        let verticalPadding = min(northY, 1 - southY)
        guard horizontalPadding > 0, verticalPadding > 0 else { return nil }
        let horizontalZoom = log2(viewportWidth / (2 * 512 * horizontalPadding))
        let verticalZoom = log2(viewportHeight / (2 * 512 * verticalPadding))
        return max(baseMinimumZoom, max(0, max(horizontalZoom, verticalZoom)))
    }

    /// The producer centers every finite realm in a four-sided transparent Web Mercator
    /// canvas. MapLibre can therefore keep its viewport inside the real world bounds
    /// while the app-owned camera target reaches any exact content edge.
    func screenBoundsAllowingCenterEdgeOverflow() -> osrsRealmScreenBounds? {
        guard west > -180, east < 180, south > -85.0511287798066,
              north < 85.0511287798066 else { return nil }
        return osrsRealmScreenBounds(
            west: -180,
            south: -85.0511287798066,
            east: 180,
            north: 85.0511287798066
        )
    }

    private static func webMercatorY(latitude: Double) -> Double {
        let clamped = min(max(latitude, -85.0511287798066), 85.0511287798066)
        let radians = clamped * .pi / 180
        return (1 - asinh(tan(radians)) / .pi) / 2
    }

}

struct osrsRealmScreenBounds: Equatable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double
}

struct osrsRealmEndpointDestination: Equatable {
    let coordinate: CLLocationCoordinate2D
    let zoom: Double

    static func == (lhs: osrsRealmEndpointDestination, rhs: osrsRealmEndpointDestination) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.zoom == rhs.zoom
    }
}

struct osrsRealmPersistedCamera: Codable, Equatable {
    let geometryIdentity: String
    let latitude: Double
    let longitude: Double
    let zoom: Double
    let direction: Double
}

struct osrsArticleMapRealmResolution {
    let realm: osrsRealmMapRecord
    let destination: osrsRealmEndpointDestination?
    let plane: Int
}

enum osrsArticleMapRealmResolver {
    static func resolve(
        manifest: osrsRealmMapManifest,
        mapId: Int?,
        plane: Int,
        gameX: Int,
        gameY: Int
    ) -> osrsArticleMapRealmResolution? {
        let mapIdMatches: [osrsRealmMapRecord]
        if let mapId {
            mapIdMatches = manifest.realms.filter { $0.mapId == mapId }
        } else {
            mapIdMatches = []
        }
        let searchOrder: [osrsRealmMapRecord]
        if mapIdMatches.isEmpty {
            searchOrder = manifest.realms
        } else {
            let matchedIds = Set(mapIdMatches.map(\.id))
            searchOrder = mapIdMatches + manifest.realms.filter { !matchedIds.contains($0.id) }
        }
        guard !searchOrder.isEmpty else { return nil }

        func mapped(_ realm: osrsRealmMapRecord, plane: Int) -> osrsRealmEndpointDestination? {
            guard let projection = manifest.rasterProjection else { return nil }
            return osrsRealmEndpointMapper.map(
                gameX: gameX,
                gameY: gameY,
                plane: plane,
                realm: realm,
                projection: projection
            )
        }

        for realm in searchOrder {
            if let destination = mapped(realm, plane: plane) {
                return osrsArticleMapRealmResolution(realm: realm, destination: destination, plane: plane)
            }
        }
        for realm in searchOrder {
            for candidatePlane in realm.planes where candidatePlane != plane {
                if let destination = mapped(realm, plane: candidatePlane) {
                    return osrsArticleMapRealmResolution(
                        realm: realm,
                        destination: destination,
                        plane: candidatePlane
                    )
                }
            }
        }

        let fallbackRealm = mapIdMatches.first ?? manifest.surface ?? searchOrder[0]
        let fallbackPlane = fallbackRealm.asset(plane: plane)?.plane ?? fallbackRealm.defaultPlane
        return osrsArticleMapRealmResolution(
            realm: fallbackRealm,
            destination: mapped(fallbackRealm, plane: fallbackPlane),
            plane: fallbackPlane
        )
    }
}

enum osrsRealmEndpointMapper {
    static func map(
        gameX: Int,
        gameY: Int,
        plane: Int,
        realm: osrsRealmMapRecord,
        projection: osrsRealmRasterProjection
    ) -> osrsRealmEndpointDestination? {
        guard projection.scale > 0,
              let asset = realm.asset(plane: plane) else { return nil }
        let sourceX = (Double(gameX - projection.gameMinX) + 0.5) * Double(projection.scale)
        let sourceY = (Double(projection.gameMaxY - gameY) - 0.5) * Double(projection.scale)
        guard sourceX >= 0, sourceX < Double(projection.width),
              sourceY >= 0, sourceY < Double(projection.height) else { return nil }

        let placements: [(Double, Double)] = asset.layoutComponents.compactMap { component in
            guard component.sourcePixelBounds.contains(x: sourceX, y: sourceY) else { return nil }
            let x = Double(component.assetPixelBounds.minX) + sourceX - Double(component.sourcePixelBounds.minX)
            let y = Double(component.assetPixelBounds.minY) + sourceY - Double(component.sourcePixelBounds.minY)
            // `assetPixelBounds` are expressed in the shared padded canvas. The
            // decoded raster width/height remain the unpadded source dimensions,
            // so validating against them would reject otherwise valid endpoints
            // after a realm is translated away from the canvas origin.
            guard x >= 0, x < Double(asset.canvasSize),
                  y >= 0, y < Double(asset.canvasSize) else { return nil }
            return (x, y)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
        }
        guard let placement = placements.first else { return nil }

        let longitude = -180 + 360 * placement.0 / Double(asset.canvasSize)
        let mercatorY = Double.pi * (1 - 2 * placement.1 / Double(asset.canvasSize))
        let latitude = atan(sinh(mercatorY)) * 180 / Double.pi
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard let envelope = osrsRealmCameraEnvelope.visibleComposition(
            realm: realm,
            selectedPlane: plane
        ), envelope.contains(coordinate) else { return nil }
        let zoom = min(Double(asset.maxZoom + 2), min(22, Double(asset.maxZoom + 8)))
        return osrsRealmEndpointDestination(coordinate: coordinate, zoom: zoom)
    }
}

enum osrsRealmDefaultCamera {
    /// Keep one source-pixel density across every realm canvas. A zoom value alone is not
    /// portable between the producer's different power-of-two canvas sizes.
    static func zoom(asset: osrsRealmMapAsset) -> Double {
        precondition(asset.canvasSize > 0, "Realm asset canvas must be positive")
        return osrsMapDefaultView.zoom + log2(
            Double(asset.canvasSize) / osrsMapDefaultView.canvasSize
        )
    }
}

enum osrsSurfaceDefaultCamera {
    static func zoom(asset: osrsRealmMapAsset) -> Double {
        osrsRealmDefaultCamera.zoom(asset: asset)
    }
}

enum osrsRealmMapError: LocalizedError {
    case missingManifest
    case missingRasterProjection
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            "Reviewed realm map assets are not present in this build."
        case .missingRasterProjection:
            "Realm coordinate provenance is missing."
        case .missingAsset(let path):
            "Realm map asset is missing: \(path)"
        }
    }
}

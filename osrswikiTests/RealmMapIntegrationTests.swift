import XCTest
import UIKit
import CoreLocation
@testable import osrswiki

final class RealmMapIntegrationTests: XCTestCase {
    func testApplicationUnlocksTheFullProMotionFrameRateRange() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone") as? Bool,
            true,
            "The iPhone app must opt into refresh rates above the 60 Hz default"
        )
        XCTAssertEqual(
            osrsMapPreferredFrameRate.framesPerSecond.rawValue,
            UIScreen.main.maximumFramesPerSecond
        )
        XCTAssertEqual(
            osrsMapPreferredFrameRate.viewRange.maximum,
            Float(max(UIScreen.main.maximumFramesPerSecond, 60))
        )
        XCTAssertEqual(
            osrsMapPreferredFrameRate.viewRange.preferred,
            osrsMapPreferredFrameRate.viewRange.maximum
        )
        XCTAssertLessThanOrEqual(osrsMapPreferredFrameRate.viewRange.minimum, 24)
    }

    func testElasticCameraEdgeAndSharedSpringAreFrameRateStable() {
        let minimum = -100.0
        let maximum = 100.0
        let cap = (maximum - minimum) * osrsEdgeMaximumOvershootFraction
        XCTAssertEqual(osrsElasticAxisPosition(
            requested: 25,
            minimum: minimum,
            maximum: maximum
        ), 25)
        let farWest = osrsElasticAxisPosition(
            requested: -10_000,
            minimum: minimum,
            maximum: maximum
        )
        let farEast = osrsElasticAxisPosition(
            requested: 10_000,
            minimum: minimum,
            maximum: maximum
        )
        XCTAssertGreaterThan(farWest, minimum - cap)
        XCTAssertLessThan(farWest, minimum)
        XCTAssertLessThan(farEast, maximum + cap)
        XCTAssertGreaterThan(farEast, maximum)

        func run(frameRate: Int) -> osrsDampedSpringAxisState {
            var state = osrsDampedSpringAxisState(position: 118, velocity: 65)
            for _ in 0..<(frameRate * 2) {
                state = osrsStepDampedSpring(
                    state: state,
                    target: 100,
                    elapsedSeconds: 1 / Double(frameRate)
                )
            }
            return state
        }
        let at60 = run(frameRate: 60)
        let at120 = run(frameRate: 120)
        XCTAssertEqual(at60.position, at120.position, accuracy: 0.002)
        XCTAssertEqual(at60.velocity, at120.velocity, accuracy: 0.01)
        XCTAssertTrue(osrsDampedSpringIsSettled(
            state: at120,
            target: 100,
            axisSpan: 200
        ))

        var outward = osrsDampedSpringAxisState(position: 123, velocity: 8_000)
        var maximumObserved = outward.position
        for _ in 0..<240 {
            outward = osrsBoundedElasticSpringAxisState(
                state: osrsStepDampedSpring(
                    state: outward,
                    target: 100,
                    elapsedSeconds: 1.0 / 120.0
                ),
                minimum: minimum,
                maximum: maximum
            )
            maximumObserved = max(maximumObserved, outward.position)
        }
        XCTAssertLessThanOrEqual(maximumObserved, maximum + cap)
        XCTAssertTrue(osrsDampedSpringIsSettled(
            state: outward,
            target: 100,
            axisSpan: 200
        ))
    }

    func testScreenSpaceVerticalSpringAndPinchMomentumAreBoundedAndFrameRateStable() {
        XCTAssertEqual(
            osrsPinchZoomVelocityLevelsPerSecond(scale: 2, scaleVelocityPerSecond: 2 * log(2)),
            1,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            osrsPinchZoomVelocityLevelsPerSecond(scale: 1, scaleVelocityPerSecond: 100),
            osrsZoomMomentumMaximumVelocity,
            accuracy: 0
        )
        XCTAssertEqual(osrsResistedScreenOverscroll(distance: 0, limit: 96), 0)
        XCTAssertGreaterThan(osrsResistedScreenOverscroll(distance: 40, limit: 96), 0)
        XCTAssertLessThan(osrsResistedScreenOverscroll(distance: 10_000, limit: 96), 96)

        let bounded = osrsBoundedScreenSpringAxisState(
            osrsDampedSpringAxisState(position: 120, velocity: 2_000),
            limit: 96
        )
        XCTAssertEqual(bounded.position, 96)
        XCTAssertEqual(bounded.velocity, 0)

        func zoomAfterOneSecond(frameRate: Int) -> Double {
            var velocity = 4.0
            var zoom = 6.0
            for _ in 0..<frameRate {
                let elapsed = 1.0 / Double(frameRate)
                zoom += velocity * elapsed
                velocity = osrsDecayZoomMomentumVelocity(velocity, elapsedSeconds: elapsed)
            }
            return zoom
        }
        XCTAssertEqual(zoomAfterOneSecond(frameRate: 60), zoomAfterOneSecond(frameRate: 120), accuracy: 0.04)
    }

    func testReviewedCanonicalManifestIsBundledAndFinite() throws {
        let manifest = try osrsRealmMapManifest.load()
        XCTAssertEqual(manifest.realms.count, 50)
        XCTAssertEqual(manifest.canonicalSelectorRealms.count, 50)
        XCTAssertTrue(manifest.canonicalSelectorRealms.allSatisfy(\.isCanonicalSelectorRealm))
        XCTAssertNil(manifest.realm(id: "cache-special-region:18-148"))
        XCTAssertNil(manifest.realm(id: "other-map-10000"))

        let surface = try XCTUnwrap(manifest.surface)
        let projection = try XCTUnwrap(manifest.rasterProjection)
        let lumbridge = try XCTUnwrap(osrsRealmEndpointMapper.map(
            gameX: 3222,
            gameY: 3218,
            plane: 0,
            realm: surface,
            projection: projection
        ))
        XCTAssertEqual(lumbridge.coordinate.latitude, 3.6230713262356806, accuracy: 0.000_000_01)
        XCTAssertEqual(lumbridge.coordinate.longitude, 31.92626953125, accuracy: 0.000_000_01)
        XCTAssertEqual(lumbridge.zoom, 8)
        XCTAssertEqual(
            osrsSurfaceDefaultCamera.zoom(asset: try XCTUnwrap(surface.asset(plane: 0))),
            6.3414426741929,
            accuracy: 0.000_000_000_001
        )
        for realmID in [
            "surface-gielinor",
            "cache-world-map:ancient-cavern",
            "cache-world-map:ardent-ocean-underground",
            "cache-world-map:ardougne-underground",
        ] {
            let realm = try XCTUnwrap(manifest.realm(id: realmID))
            let asset = try XCTUnwrap(realm.asset(plane: realm.planes.min() ?? 0))
            XCTAssertEqual(
                osrsRealmDefaultCamera.zoom(asset: asset) - Double(asset.maxZoom),
                0.3414426741929,
                accuracy: 0.000_000_000_001,
                "Every fresh realm must open at the pre-selector surface source-pixel scale"
            )
        }

        let godWars = try XCTUnwrap(manifest.realm(id: "cache-world-map:godwars"))
        XCTAssertEqual(Set(godWars.assets.map(\.canvasSize)).count, 1)
        for plane in godWars.planes {
            let envelope = try XCTUnwrap(osrsRealmCameraEnvelope.visibleComposition(
                realm: godWars,
                selectedPlane: plane
            ))
            XCTAssertLessThan(envelope.east - envelope.west, 360)
        }

        for realm in manifest.realms {
            for plane in realm.planes {
                let envelope = try XCTUnwrap(osrsRealmCameraEnvelope.visibleComposition(
                    realm: realm,
                    selectedPlane: plane
                ), "Missing finite envelope for \(realm.id) plane \(plane)")
                XCTAssertTrue(envelope.west.isFinite)
                XCTAssertTrue(envelope.south.isFinite)
                XCTAssertTrue(envelope.east.isFinite)
                XCTAssertTrue(envelope.north.isFinite)
                XCTAssertLessThanOrEqual(envelope.east - envelope.west, 270)
            }
        }
    }

    func testWikiMapIdSelectsTheMatchingRealmInsteadOfAlwaysUsingSurface() throws {
        let manifest = try osrsRealmMapManifest.load()
        let taverley = try XCTUnwrap(manifest.realms.first { $0.mapId == 20 })
        let resolved = try XCTUnwrap(
            osrsArticleMapRealmResolver.resolve(
                manifest: manifest,
                mapId: 20,
                plane: 0,
                gameX: 2915,
                gameY: 9901
            )
        )
        XCTAssertEqual(resolved.realm.id, taverley.id)
        XCTAssertNotEqual(resolved.realm.id, manifest.surface?.id)
        XCTAssertNotNil(resolved.destination)
    }

    func testLumbridgeSpawnMapsThroughCurrentAssetLayout() throws {
        let manifest = try decodeFixture()
        let surface = try XCTUnwrap(manifest.surface)
        let projection = try XCTUnwrap(manifest.rasterProjection)

        let destination = try XCTUnwrap(osrsRealmEndpointMapper.map(
            gameX: 3222,
            gameY: 3218,
            plane: 0,
            realm: surface,
            projection: projection
        ))

        XCTAssertEqual(destination.coordinate.longitude, 0, accuracy: 0.000_001)
        XCTAssertEqual(destination.coordinate.latitude, 0, accuracy: 0.000_001)
        XCTAssertEqual(destination.zoom, 7)
    }

    func testCanonicalSelectorProjectionDoesNotDeleteHiddenRecords() throws {
        let manifest = try decodeFixture()

        XCTAssertEqual(manifest.canonicalSelectorRealms.map(\.id), ["surface-gielinor"])
        XCTAssertNotNil(manifest.realm(id: "finite-realm"))
    }

    func testVisiblePlaneEnvelopeUsesFiniteUnionAndDirectClamp() throws {
        let manifest = try decodeFixture()
        let realm = try XCTUnwrap(manifest.realm(id: "finite-realm"))
        let envelope = try XCTUnwrap(osrsRealmCameraEnvelope.visibleComposition(
            realm: realm,
            selectedPlane: 1
        ))

        XCTAssertEqual(envelope, osrsRealmCameraEnvelope(
            west: -40,
            south: -20,
            east: 50,
            north: 30
        ))
        let clamped = envelope.clamped(CLLocationCoordinate2D(latitude: 45, longitude: 370))
        XCTAssertEqual(clamped.latitude, 30)
        XCTAssertEqual(clamped.longitude, 50)
        XCTAssertEqual(envelope.clamped(clamped).latitude, clamped.latitude)
        XCTAssertEqual(envelope.clamped(clamped).longitude, clamped.longitude)
    }

    func testCopySafeMinimumZoomMatchesFiniteRealmPolicy() throws {
        let halfWorld = osrsRealmCameraEnvelope(west: -180, south: -60, east: 0, north: 80)

        XCTAssertEqual(
            try XCTUnwrap(halfWorld.copySafeMinimumZoom(viewportWidth: 393)),
            0,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(halfWorld.copySafeMinimumZoom(viewportWidth: 1080)),
            1.0768155970508317,
            accuracy: 0.000_000_001
        )
    }

    func testEveryRealmUsesCopySafeZoomAndAllowsFourSidedCenterEdgeOverflow() throws {
        let surface = osrsRealmCameraEnvelope(
            west: -67.5,
            south: -66.51326044311186,
            east: 67.5,
            north: 66.51326044311186
        )

        let copySafe = try XCTUnwrap(surface.copySafeMinimumZoom(viewportWidth: 393))
        let effective = try XCTUnwrap(surface.finiteRealmMinimumZoom(
            baseMinimumZoom: 0,
            viewportWidth: 393,
            viewportHeight: 852
        ))
        let screenBounds = try XCTUnwrap(surface.screenBoundsAllowingCenterEdgeOverflow())

        XCTAssertEqual(copySafe, 0, accuracy: 0.000_000_001)
        XCTAssertGreaterThan(effective, copySafe)
        XCTAssertEqual(screenBounds.west, -180, accuracy: 0.000_000_001)
        XCTAssertEqual(screenBounds.east, 180, accuracy: 0.000_000_001)
        XCTAssertEqual(screenBounds.north, 85.0511287798066, accuracy: 0.000_000_001)
        XCTAssertEqual(screenBounds.south, -85.0511287798066, accuracy: 0.000_000_001)
        XCTAssertEqual(
            surface.clamped(CLLocationCoordinate2D(latitude: 0, longitude: -180)).longitude,
            surface.west
        )
        XCTAssertEqual(
            surface.clamped(CLLocationCoordinate2D(latitude: 0, longitude: 180)).longitude,
            surface.east
        )
    }

    func testRealmCameraIdentityCoversEveryPlaneInsteadOfSplittingByFloor() throws {
        let manifest = try decodeFixture()
        let realm = try XCTUnwrap(manifest.realm(id: "finite-realm"))

        XCTAssertTrue(realm.cameraGeometryIdentity.contains("0=a:1024:0,0,512,512"))
        XCTAssertTrue(realm.cameraGeometryIdentity.contains("1=b:1024:256,256,768,768"))
        XCTAssertTrue(realm.cameraGeometryIdentity.hasPrefix("source-pixel-default-v1|"))
        XCTAssertEqual(
            realm.cameraGeometryIdentity.components(separatedBy: "|").count,
            realm.planes.count + 1
        )
    }

    func testMapLibreWorldCopyRepresentationResolvesWithoutChangingDirectClamp() {
        let envelope = osrsRealmCameraEnvelope(west: -180, south: -60, east: 0, north: 80)

        let fromPositiveCopy = envelope.resolvingMapLibreRepresentation(
            CLLocationCoordinate2D(latitude: 0, longitude: 359)
        )
        XCTAssertEqual(fromPositiveCopy.longitude, -1)
        XCTAssertEqual(envelope.clamped(fromPositiveCopy).longitude, -1)

        let eastOverpan = envelope.resolvingMapLibreRepresentation(
            CLLocationCoordinate2D(latitude: 0, longitude: 1)
        )
        XCTAssertEqual(eastOverpan.longitude, 1)
        XCTAssertEqual(envelope.clamped(eastOverpan).longitude, 0)

        let westOverpanInPositiveCopy = envelope.resolvingMapLibreRepresentation(
            CLLocationCoordinate2D(latitude: 0, longitude: 179.9)
        )
        XCTAssertEqual(westOverpanInPositiveCopy.longitude, -180.1, accuracy: 0.000_000_1)
        XCTAssertEqual(envelope.clamped(westOverpanInPositiveCopy).longitude, -180)

        XCTAssertEqual(
            envelope.clamped(CLLocationCoordinate2D(latitude: 0, longitude: 360)).longitude,
            0,
            "Direct requests must remain finitely clamped rather than normalized into the envelope"
        )
    }

    private func decodeFixture() throws -> osrsRealmMapManifest {
        let json = """
        {
          "schema_version": 1,
          "candidate": "test",
          "inputs": {"source_snapshots":{"raster":{
            "game_bounds":{"min_x":2199,"min_y":2195,"max_x":4246,"max_y":4242},
            "game_coord_scale":2,"width":4094,"height":4094
          }}},
          "realms": [
            {
              "id":"surface-gielinor","canonical_name":"Gielinor Surface","aliases":[],
              "group":"surface","is_surface":true,"default_plane":0,"planes":[0],
              "assets":[{
                "plane":0,"mbtiles_path":"assets/surface.mbtiles","mbtiles_sha256":"surface",
                "width":4094,"height":4094,"min_zoom":0,"max_zoom":5,"canvas_size":4094,
                "content_pixel_bounds":[0,0,4094,4094],
                "content_latlon_bounds":[-180,-85,180,85],
                "layout_components":[{
                  "source_pixel_bounds":{"min_x":0,"min_y":0,"max_x":4094,"max_y":4094},
                  "asset_pixel_bounds":{"min_x":0,"min_y":0,"max_x":4094,"max_y":4094}
                }]
              }]
            },
            {
              "id":"finite-realm","canonical_name":"Finite Realm","aliases":[],
              "group":"dungeon","is_surface":false,"default_plane":0,"planes":[0,1],
              "assets":[
                {"plane":0,"mbtiles_path":"assets/a.mbtiles","mbtiles_sha256":"a",
                 "width":512,"height":512,"min_zoom":0,"max_zoom":1,"canvas_size":1024,
                 "content_pixel_bounds":[0,0,512,512],"content_latlon_bounds":[-40,-20,20,30],
                 "layout_components":[]},
                {"plane":1,"mbtiles_path":"assets/b.mbtiles","mbtiles_sha256":"b",
                 "width":512,"height":512,"min_zoom":0,"max_zoom":1,"canvas_size":1024,
                 "content_pixel_bounds":[256,256,768,768],"content_latlon_bounds":[-10,-10,50,20],
                 "layout_components":[]}
              ]
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(osrsRealmMapManifest.self, from: Data(json.utf8))
    }
}

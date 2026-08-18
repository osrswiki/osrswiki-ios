import XCTest
import UIKit

final class MapDefaultCenterUITests: XCTestCase {
    func testCompassTapResetsMapToNorth() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForCameraSnapshot(on: mapView).contains("ready=true"))

        mapView.rotate(.pi / 3, withVelocity: 1)
        let rotated = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let rotatedBearing = try XCTUnwrap(cameraValue("bearing", in: rotated))
        XCTAssertGreaterThan(abs(rotatedBearing), 1, "Rotation must make the app-owned compass visible")
        let rotatedLatitude = try XCTUnwrap(cameraValue("centerLat", in: rotated))
        let rotatedLongitude = try XCTUnwrap(cameraValue("centerLon", in: rotated))
        let rotatedZoom = try XCTUnwrap(cameraValue("zoom", in: rotated))

        let compass = app.buttons["realm_map_compass"]
        XCTAssertTrue(compass.waitForExistence(timeout: 3))
        XCTAssertTrue(compass.isHittable)
        compass.tap()

        let reset = waitForNorthCameraSnapshot(on: mapView)
        XCTAssertEqual(try XCTUnwrap(cameraValue("bearing", in: reset)), 0, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(cameraValue("centerLat", in: reset)), rotatedLatitude, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(cameraValue("centerLon", in: reset)), rotatedLongitude, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(cameraValue("zoom", in: reset)), rotatedZoom, accuracy: 0.000_1)
    }

    func testFreshRealmSelectionUsesOneSourcePixelScale() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        let surface = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let surfaceZoom = try XCTUnwrap(cameraValue("zoom", in: surface))
        let relativeDefaultZoom = surfaceZoom - 6

        let cases: [(name: String, id: String, nativeMaximumZoom: Double)] = [
            ("Ancient Cavern", "cache-world-map:ancient-cavern", 3),
            ("Ardent Ocean Underground", "cache-world-map:ardent-ocean-underground", 3),
            ("Ardougne Underground", "cache-world-map:ardougne-underground", 3),
        ]
        for item in cases {
            selectRealm(named: item.name, id: item.id, in: app)
            let snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=\(item.id)")
            let zoom = try XCTUnwrap(cameraValue("zoom", in: snapshot))
            XCTAssertEqual(
                zoom - item.nativeMaximumZoom,
                relativeDefaultZoom,
                accuracy: 0.01,
                "Fresh realm selection should retain the surface camera's source-pixel scale: \(snapshot)"
            )
        }
    }

    func testMapLaunchExposesLumbridgeDefaultCamera() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["map_screen"].waitForExistence(timeout: 10), "Map screen should open directly")

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10), "Native map view should be visible")

        let cameraText = waitForCameraSnapshot(on: mapView)
        XCTAssertTrue(cameraText.contains("ready=true"), "Map camera snapshot should report ready=true: \(cameraText)")

        let centerLat = try XCTUnwrap(cameraValue("centerLat", in: cameraText))
        let centerLon = try XCTUnwrap(cameraValue("centerLon", in: cameraText))
        let zoom = try XCTUnwrap(cameraValue("zoom", in: cameraText))

        // The same Lumbridge source pixel now lives in a centered, four-sided
        // padded Web Mercator canvas. Its geographic representation changes,
        // while the rendered spawn point and source-pixel density do not.
        XCTAssertEqual(centerLat, 3.6230713262356806, accuracy: 0.00000001)
        XCTAssertEqual(centerLon, 31.92626953125, accuracy: 0.00000001)
        XCTAssertEqual(zoom, 6.3414426741929, accuracy: 0.0000001)
    }

    func testFloorSelectionChangesRenderedMapPixels() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["map_screen"].waitForExistence(timeout: 10), "Map screen should open directly")

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10), "Native map view should be visible")
        XCTAssertTrue(waitForCameraSnapshot(on: mapView).contains("ready=true"), "Map should finish rendering before floor comparison")

        mapView.swipeLeft()
        mapView.pinch(withScale: 1.35, velocity: 2)
        let beforeCamera = waitForStableCameraSnapshot(on: mapView, containing: "floor=0")
        let beforeLatitude = try XCTUnwrap(cameraValue("centerLat", in: beforeCamera))
        let beforeLongitude = try XCTUnwrap(cameraValue("centerLon", in: beforeCamera))
        let beforeZoom = try XCTUnwrap(cameraValue("zoom", in: beforeCamera))
        let beforeBearing = try XCTUnwrap(cameraValue("bearing", in: beforeCamera))

        let beforeScreenshot = XCUIScreen.main.screenshot()
        let beforePixels = try mapComparisonPixels(from: beforeScreenshot)

        let floorUp = app.buttons["Increase map floor"]
        XCTAssertTrue(floorUp.waitForExistence(timeout: 5), "Floor up control should exist")
        XCTAssertTrue(floorUp.isHittable, "Floor up control should be hittable")
        floorUp.tap()

        XCTAssertFalse(
            app.otherElements["realm_map_loading"].exists,
            "Changing an already-visible floor must not cover the map with a preparation dialog"
        )

        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 2), "Floor label should update to 1")
        var afterCamera = waitForStableCameraSnapshot(on: mapView, containing: "floor=1")
        assertCamera(
            afterCamera,
            matchesLatitude: beforeLatitude,
            longitude: beforeLongitude,
            zoom: beforeZoom,
            bearing: beforeBearing
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let afterScreenshot = XCUIScreen.main.screenshot()
        let afterPixels = try mapComparisonPixels(from: afterScreenshot)
        let changedRatio = changedPixelRatio(beforePixels, afterPixels, tolerance: 2)

        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "floor-0-before"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
        afterAttachment.name = "floor-1-after"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)

        XCTAssertGreaterThan(
            changedRatio,
            0.005,
            "Selecting floor 1 should change visible map pixels, not only the floor label. Changed ratio: \(changedRatio)"
        )

        for floor in 2...3 {
            floorUp.tap()
            XCTAssertTrue(app.staticTexts[String(floor)].waitForExistence(timeout: 2))
            afterCamera = waitForStableCameraSnapshot(on: mapView, containing: "floor=\(floor)")
            assertCamera(
                afterCamera,
                matchesLatitude: beforeLatitude,
                longitude: beforeLongitude,
                zoom: beforeZoom,
                bearing: beforeBearing
            )
        }
    }

    func testGodWarsRemainsInsideFiniteHorizontalEnvelopeAfterRepeatedSwipes() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForCameraSnapshot(on: mapView).contains("ready=true"))

        let selector = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Map realm,")
        ).firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()

        let search = app.textFields["realm_selector_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("God Wars Dungeon")

        let godWars = app.buttons["realm_row_cache-world-map:godwars"]
        XCTAssertTrue(godWars.waitForExistence(timeout: 5))
        godWars.tap()

        let selected = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars"
        )
        XCTAssertTrue(selected.contains("floor=2"))
        XCTAssertTrue(selected.contains("horizontalWrap=false"))
        let selectedLongitude = try XCTUnwrap(cameraValue("centerLon", in: selected))
        let envelopeWest = try XCTUnwrap(cameraValue("envelopeWest", in: selected))
        let envelopeEast = try XCTUnwrap(cameraValue("envelopeEast", in: selected))
        let minimumZoom = try XCTUnwrap(cameraValue("minZoom", in: selected))

        for _ in 0..<4 {
            mapView.pinch(withScale: 0.2, velocity: -4)
        }
        let zoomedOut = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars"
        )
        XCTAssertEqual(
            try XCTUnwrap(cameraValue("zoom", in: zoomedOut)),
            minimumZoom,
            accuracy: 0.05,
            "Underground realms must expose their audited four-sided copy-safe zoom floor"
        )

        for _ in 0..<16 { mapView.swipeRight() }
        let westSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars",
            differingLongitudeFrom: selectedLongitude
        )
        let west = try XCTUnwrap(cameraValue("centerLon", in: westSnapshot))
        XCTAssertEqual(west, envelopeWest, accuracy: 0.05, "West edge must reach the exact finite center bound")

        for _ in 0..<4 { mapView.swipeRight() }
        let repeatedWestSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars"
        )
        let repeatedWest = try XCTUnwrap(cameraValue("centerLon", in: repeatedWestSnapshot))
        XCTAssertEqual(repeatedWest, west, accuracy: 0.000_1, "Further west-edge swipes must be idempotently clamped")
        let westScreenshot = XCUIScreen.main.screenshot()
        let westAttachment = XCTAttachment(screenshot: westScreenshot)
        westAttachment.name = "god-wars-finite-west-edge"
        westAttachment.lifetime = .keepAlways
        add(westAttachment)

        for _ in 0..<16 { mapView.swipeLeft() }
        let eastSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars",
            differingLongitudeFrom: west
        )
        let east = try XCTUnwrap(cameraValue("centerLon", in: eastSnapshot))
        XCTAssertEqual(east, envelopeEast, accuracy: 0.05, "East edge must reach the exact finite center bound")
        XCTAssertGreaterThan(east, west + 1.0, "West and east finite edges must be distinct")
        XCTAssertTrue(eastSnapshot.contains("horizontalWrap=false"))

        for _ in 0..<4 { mapView.swipeLeft() }
        let repeatedEastSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars"
        )
        let repeatedEast = try XCTUnwrap(cameraValue("centerLon", in: repeatedEastSnapshot))
        XCTAssertEqual(repeatedEast, east, accuracy: 0.000_1, "Further east-edge swipes must be idempotently clamped")
        let eastScreenshot = XCUIScreen.main.screenshot()
        let eastAttachment = XCTAttachment(screenshot: eastScreenshot)
        eastAttachment.name = "god-wars-finite-east-edge"
        eastAttachment.lifetime = .keepAlways
        add(eastAttachment)

        let westPixels = try mapComparisonPixels(from: westScreenshot)
        let eastPixels = try mapComparisonPixels(from: eastScreenshot)
        XCTAssertGreaterThan(
            changedPixelRatio(westPixels, eastPixels, tolerance: 2),
            0.01,
            "Distinct finite edges must produce visibly distinct map pixels"
        )

        for _ in 0..<16 { mapView.swipeDown() }
        let northSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=cache-world-map:godwars"
        )
        let north = try XCTUnwrap(cameraValue("centerLat", in: northSnapshot))
        let envelopeNorth = try XCTUnwrap(cameraValue("envelopeNorth", in: northSnapshot))
        XCTAssertEqual(north, envelopeNorth, accuracy: 0.05, "Underground north edge must reach map center")
        XCTAssertTrue(northSnapshot.contains("centerEdgeOverflow=true"))
        XCTAssertGreaterThan(
            try darkPixelRatio(
                in: XCUIScreen.main.screenshot(),
                normalizedRect: CGRect(x: 0.24, y: 0.14, width: 0.52, height: 0.22)
            ),
            0.75,
            "The underground north edge must expose transparent overbound above the content"
        )
    }

    func testSurfaceKeepsHalfViewportOverboundWithoutRenderingWorldCopies() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        var snapshot = waitForCameraSnapshot(on: mapView)
        XCTAssertTrue(snapshot.contains("realm=surface-gielinor"))
        XCTAssertTrue(snapshot.contains("centerEdgeOverflow=true"))
        XCTAssertTrue(snapshot.contains("horizontalWrap=false"))
        let minimumZoom = try XCTUnwrap(cameraValue("minZoom", in: snapshot))
        let envelopeWest = try XCTUnwrap(cameraValue("envelopeWest", in: snapshot))
        let envelopeEast = try XCTUnwrap(cameraValue("envelopeEast", in: snapshot))
        XCTAssertGreaterThan(minimumZoom, 0, "Surface must use the same copy-safe zoom floor as every realm")

        for _ in 0..<4 {
            mapView.pinch(withScale: 0.2, velocity: -4)
        }
        snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let zoomedOut = try XCTUnwrap(cameraValue("zoom", in: snapshot))
        XCTAssertEqual(zoomedOut, minimumZoom, accuracy: 0.05)

        for _ in 0..<16 { mapView.swipeRight() }
        let westSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=surface-gielinor"
        )
        let west = try XCTUnwrap(cameraValue("centerLon", in: westSnapshot))
        XCTAssertEqual(west, envelopeWest, accuracy: 0.05, "Surface center must reach the exact west content edge")

        for _ in 0..<4 { mapView.swipeRight() }
        let repeatedWest = try XCTUnwrap(cameraValue(
            "centerLon",
            in: waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        ))
        XCTAssertEqual(repeatedWest, west, accuracy: 0.000_1)
        let westScreenshot = XCUIScreen.main.screenshot()
        XCTAssertGreaterThan(
            try darkPixelRatio(in: westScreenshot, normalizedRect: CGRect(x: 0.03, y: 0.24, width: 0.34, height: 0.46)),
            0.92,
            "The west overbound half must be blank rather than the eastern world copy"
        )

        for _ in 0..<24 { mapView.swipeLeft() }
        let eastSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=surface-gielinor",
            differingLongitudeFrom: west
        )
        let east = try XCTUnwrap(cameraValue("centerLon", in: eastSnapshot))
        XCTAssertEqual(east, envelopeEast, accuracy: 0.05, "Surface center must reach the exact east content edge")

        for _ in 0..<4 { mapView.swipeLeft() }
        let repeatedEast = try XCTUnwrap(cameraValue(
            "centerLon",
            in: waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        ))
        XCTAssertEqual(repeatedEast, east, accuracy: 0.000_1)
        let eastScreenshot = XCUIScreen.main.screenshot()
        XCTAssertGreaterThan(
            try darkPixelRatio(in: eastScreenshot, normalizedRect: CGRect(x: 0.63, y: 0.24, width: 0.34, height: 0.46)),
            0.92,
            "The east overbound half must be blank rather than the western world copy"
        )

        for _ in 0..<20 { mapView.swipeDown() }
        let northSnapshot = waitForStableCameraSnapshot(
            on: mapView,
            containing: "realm=surface-gielinor"
        )
        let north = try XCTUnwrap(cameraValue("centerLat", in: northSnapshot))
        let envelopeNorth = try XCTUnwrap(cameraValue("envelopeNorth", in: northSnapshot))
        XCTAssertEqual(north, envelopeNorth, accuracy: 0.05, "Surface north edge must reach the exact visual center")

        for _ in 0..<4 { mapView.swipeDown() }
        let repeatedNorth = try XCTUnwrap(cameraValue(
            "centerLat",
            in: waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        ))
        XCTAssertEqual(repeatedNorth, north, accuracy: 0.000_1)
        let northScreenshot = XCUIScreen.main.screenshot()
        XCTAssertGreaterThan(
            try darkPixelRatio(in: northScreenshot, normalizedRect: CGRect(x: 0.24, y: 0.14, width: 0.52, height: 0.22)),
            0.80,
            "The north overbound half must expose blank background above Gielinor"
        )

        [
            (westScreenshot, "surface-finite-west-overbound"),
            (eastScreenshot, "surface-finite-east-overbound"),
            (northScreenshot, "surface-finite-north-overbound"),
        ].forEach { screenshot, name in
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testEdgeReleaseUsesMultiFrameResistedOverscrollAndSpringBounce() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        var snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let envelopeWest = try XCTUnwrap(cameraValue("envelopeWest", in: snapshot))
        let envelopeEast = try XCTUnwrap(cameraValue("envelopeEast", in: snapshot))
        for _ in 0..<4 {
            mapView.pinch(withScale: 0.2, velocity: -4)
        }
        snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        for _ in 0..<16 { mapView.swipeRight() }
        snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        XCTAssertEqual(
            try XCTUnwrap(cameraValue("centerLon", in: snapshot)),
            envelopeWest,
            accuracy: 0.05
        )

        mapView.swipeRight(velocity: .fast)
        let settled = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let duration = try XCTUnwrap(cameraValue("lastEdgeBounceDuration", in: settled))
        let frameCount = try XCTUnwrap(cameraValue("lastEdgeBounceFrames", in: settled))
        let peakOvershoot = try XCTUnwrap(cameraValue("edgePeakLongitudeOvershoot", in: settled))
        XCTAssertGreaterThanOrEqual(frameCount, 5, "Edge recovery must remain visible across frames")
        XCTAssertGreaterThanOrEqual(duration, 0.08, "Edge recovery must not be a one-frame snap")
        XCTAssertLessThanOrEqual(duration, 2.5, "Edge recovery should settle promptly")
        XCTAssertGreaterThan(peakOvershoot, (envelopeEast - envelopeWest) * 0.0001)
        XCTAssertLessThan(
            peakOvershoot,
            (envelopeEast - envelopeWest) * 0.121
        )
        XCTAssertEqual(
            try XCTUnwrap(cameraValue("centerLon", in: settled)),
            envelopeWest,
            accuracy: 0.05
        )
        XCTAssertTrue(settled.contains("edgePhysicsPhase=idle"))
        XCTAssertTrue(settled.contains("horizontalWrap=false"))
    }

    func testVerticalEdgeReleaseUsesMultiFrameResistedOverscrollAndSpringBounce() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        var snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let envelopeSouth = try XCTUnwrap(cameraValue("envelopeSouth", in: snapshot))
        let envelopeNorth = try XCTUnwrap(cameraValue("envelopeNorth", in: snapshot))
        for _ in 0..<4 {
            mapView.pinch(withScale: 0.2, velocity: -4)
        }
        snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        for _ in 0..<16 { mapView.swipeDown() }
        snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        XCTAssertEqual(
            try XCTUnwrap(cameraValue("centerLat", in: snapshot)),
            envelopeNorth,
            accuracy: 0.05
        )

        mapView.swipeDown(velocity: .fast)
        let settled = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let duration = try XCTUnwrap(cameraValue("lastEdgeBounceDuration", in: settled))
        let frameCount = try XCTUnwrap(cameraValue("lastEdgeBounceFrames", in: settled))
        let peakOvershoot = try XCTUnwrap(cameraValue("edgePeakLatitudeOvershoot", in: settled))
        let livePeakOvershoot = try XCTUnwrap(cameraValue("edgeLivePeakLatitudeOvershoot", in: settled))
        let visualPeak = try XCTUnwrap(
            cameraValue("edgePeakVisualVerticalOvershootPoints", in: settled)
        )
        XCTAssertGreaterThanOrEqual(frameCount, 5, "Vertical edge recovery must remain visible across frames")
        XCTAssertGreaterThanOrEqual(duration, 0.08, "Vertical edge recovery must not be a one-frame snap")
        XCTAssertLessThanOrEqual(duration, 2.5, "Vertical edge recovery should settle promptly")
        XCTAssertEqual(
            livePeakOvershoot,
            0,
            accuracy: 0.000_001,
            "The strict MapLibre camera must remain inside the finite world"
        )
        XCTAssertGreaterThan(
            visualPeak,
            1,
            "The rendered map surface must visibly follow the vertical edge gesture before springing back"
        )
        XCTAssertLessThan(peakOvershoot, (envelopeNorth - envelopeSouth) * 0.121)
        XCTAssertEqual(
            try XCTUnwrap(cameraValue("centerLat", in: settled)),
            envelopeNorth,
            accuracy: 0.05
        )
        XCTAssertTrue(settled.contains("edgePhysicsPhase=idle"))
    }

    func testPinchReleaseContinuesWithBoundedZoomMomentum() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        _ = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")

        let before = cameraSnapshotText(from: mapView)
        let beforeZoom = try XCTUnwrap(cameraValue("zoom", in: before))
        mapView.pinch(withScale: 1.45, velocity: 8)
        let settled = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let afterZoom = try XCTUnwrap(cameraValue("zoom", in: settled))
        let continuation = try XCTUnwrap(cameraValue("zoomMomentumPeakContinuation", in: settled))
        let frameCount = try XCTUnwrap(cameraValue("lastZoomMomentumFrames", in: settled))
        let duration = try XCTUnwrap(cameraValue("lastZoomMomentumDuration", in: settled))
        XCTAssertGreaterThan(
            afterZoom,
            beforeZoom + 0.01,
            "The pinch itself should zoom in"
        )
        XCTAssertGreaterThan(continuation, 0.01)
        XCTAssertGreaterThanOrEqual(frameCount, 2)
        XCTAssertGreaterThan(duration, 0.03)
        XCTAssertLessThan(duration, 2.5)
    }

    func testMapRendererRequestsTheDisplayMaximumRefreshRate() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        let snapshot = waitForStableCameraSnapshot(on: mapView, containing: "realm=surface-gielinor")
        let screenMaximum = try XCTUnwrap(cameraValue("screenMaximumFPS", in: snapshot))
        let mapPreferred = try XCTUnwrap(cameraValue("mapPreferredFPS", in: snapshot))
        XCTAssertEqual(
            mapPreferred,
            screenMaximum,
            "The renderer should request the device's full refresh range instead of MapLibre's adaptive 30/60 default"
        )
    }

    func testRealmSelectorUsesOneCompactThemedSurface() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-forceThemeForUITests",
            "osrs_dark",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
            "-resetRealmMapState",
        ]
        app.launch()

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForCameraSnapshot(on: mapView).contains("ready=true"))

        let selector = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Map realm,")
        ).firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))

        let collapsedScreenshot = XCUIScreen.main.screenshot()
        let collapsedSurfaceSample = try averageRGB(
            in: collapsedScreenshot,
            screenRect: CGRect(
                x: selector.frame.maxX - 76,
                y: selector.frame.midY - 10,
                width: 28,
                height: 20
            ),
            screenSize: app.windows.firstMatch.frame.size
        )
        XCTAssertLessThan(
            collapsedSurfaceSample.maximumChannel,
            80,
            "The collapsed selector must draw its opaque themed surface instead of exposing map pixels: \(collapsedSurfaceSample)"
        )
        let collapsedAttachment = XCTAttachment(screenshot: collapsedScreenshot)
        collapsedAttachment.name = "themed-realm-selector-collapsed"
        collapsedAttachment.lifetime = .keepAlways
        add(collapsedAttachment)

        selector.tap()

        let search = app.textFields["realm_selector_search"]
        let expandedSelector = app.buttons["realm_selector"]
        let firstRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "realm_row_")
        ).firstMatch

        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(expandedSelector.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(search.frame.maxY, firstRow.frame.maxY)
        XCTAssertFalse(app.staticTexts["Choose a realm"].exists)
        XCTAssertFalse(app.staticTexts["Search or browse every available map"].exists)
        XCTAssertFalse(app.buttons["realm_selector_done"].exists)
        XCTAssertLessThan(
            expandedSelector.frame.maxY - search.frame.minY,
            app.windows.firstMatch.frame.height * 0.6
        )
        XCTAssertFalse(
            app.tables.firstMatch.exists,
            "The realm selector should not fall back to mixed stock List and Liquid Glass chrome"
        )
        XCTAssertFalse(
            app.staticTexts["Other_Maps"].exists,
            "Raw producer group metadata must not leak into the user-facing realm selector"
        )

        let expandedScreenshot = XCUIScreen.main.screenshot()
        let selectedEdge = try averageRGB(
            in: expandedScreenshot,
            screenRect: CGRect(
                x: firstRow.frame.minX + 1,
                y: firstRow.frame.midY - 8,
                width: 4,
                height: 16
            ),
            screenSize: app.windows.firstMatch.frame.size
        )
        let selectedInterior = try averageRGB(
            in: expandedScreenshot,
            screenRect: CGRect(
                x: firstRow.frame.maxX - 32,
                y: firstRow.frame.midY - 8,
                width: 12,
                height: 16
            ),
            screenSize: app.windows.firstMatch.frame.size
        )
        XCTAssertGreaterThan(
            selectedEdge.distance(to: selectedInterior),
            5,
            "Selected-row shading must be inset from the allocated row instead of running flush to its edge"
        )

        let attachment = XCTAttachment(screenshot: expandedScreenshot)
        attachment.name = "themed-realm-selector"
        attachment.lifetime = .keepAlways
        add(attachment)

        search.tap()
        search.typeText("other-map-10000")
        XCTAssertTrue(
            app.staticTexts["realm_selector_empty"].waitForExistence(timeout: 3),
            "Wiki-authored map views must remain absent from the canonical selector"
        )
        app.buttons["Clear realm search"].tap()
        search.typeText("Ancient Cavern")
        XCTAssertTrue(
            app.buttons["realm_row_cache-world-map:ancient-cavern"].waitForExistence(timeout: 3),
            "Named native cache realms must remain selectable"
        )
    }

    private func waitForCameraSnapshot(on element: XCUIElement) -> String {
        waitForCameraSnapshot(on: element, containing: "ready=true")
    }

    private func selectRealm(named name: String, id: String, in app: XCUIApplication) {
        let selector = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Map realm,")
        ).firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()

        let search = app.textFields["realm_selector_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let clearSearch = app.buttons["Clear realm search"]
        if clearSearch.exists {
            clearSearch.tap()
        }
        search.tap()
        search.typeText(name)

        let row = app.buttons["realm_row_\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    private func waitForCameraSnapshot(on element: XCUIElement, containing requiredText: String) -> String {
        let deadline = Date().addingTimeInterval(10)
        var latest = cameraSnapshotText(from: element)

        while Date() < deadline {
            latest = cameraSnapshotText(from: element)
            if latest.contains("ready=true") && latest.contains(requiredText) {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return latest
    }

    private func waitForStableCameraSnapshot(
        on element: XCUIElement,
        containing requiredText: String,
        differingLongitudeFrom initialLongitude: Double? = nil
    ) -> String {
        let deadline = Date().addingTimeInterval(10)
        var latest = cameraSnapshotText(from: element)
        var lastObserved = latest
        var stableSince = Date()

        while Date() < deadline {
            latest = cameraSnapshotText(from: element)
            if latest != lastObserved {
                lastObserved = latest
                stableSince = Date()
            }
            let longitude = cameraValue("centerLon", in: latest)
            let hasRequiredChange = initialLongitude.map { initial in
                guard let longitude else { return false }
                return abs(longitude - initial) > 0.000_1
            } ?? true
            if latest.contains("ready=true"),
               latest.contains(requiredText),
               hasRequiredChange,
               Date().timeIntervalSince(stableSince) >= 0.75 {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return latest
    }

    private func waitForNorthCameraSnapshot(on element: XCUIElement) -> String {
        let deadline = Date().addingTimeInterval(10)
        var latest = cameraSnapshotText(from: element)
        while Date() < deadline {
            latest = cameraSnapshotText(from: element)
            if latest.contains("ready=true"),
               let bearing = cameraValue("bearing", in: latest),
               abs(bearing) <= 0.1 {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return latest
    }

    private func cameraSnapshotText(from element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return [element.label, value].filter { !$0.isEmpty }.joined(separator: ";")
    }

    private func cameraValue(_ key: String, in snapshot: String) -> Double? {
        snapshot
            .split(separator: ";")
            .compactMap { component -> Double? in
                let pieces = component.split(separator: "=", maxSplits: 1)
                guard pieces.count == 2, pieces[0] == key else { return nil }
                return Double(pieces[1])
            }
            .first
    }

    private func assertCamera(
        _ snapshot: String,
        matchesLatitude latitude: Double,
        longitude: Double,
        zoom: Double,
        bearing: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actualLatitude = cameraValue("centerLat", in: snapshot),
              let actualLongitude = cameraValue("centerLon", in: snapshot),
              let actualZoom = cameraValue("zoom", in: snapshot),
              let actualBearing = cameraValue("bearing", in: snapshot) else {
            XCTFail("Camera snapshot is incomplete: \(snapshot)", file: file, line: line)
            return
        }
        XCTAssertEqual(actualLatitude, latitude, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actualLongitude, longitude, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actualZoom, zoom, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actualBearing, bearing, accuracy: 0.01, file: file, line: line)
    }

    private func darkPixelRatio(
        in screenshot: XCUIScreenshot,
        normalizedRect: CGRect
    ) throws -> Double {
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation)?.cgImage)
        let cropRect = CGRect(
            x: Double(image.width) * normalizedRect.minX,
            y: Double(image.height) * normalizedRect.minY,
            width: Double(image.width) * normalizedRect.width,
            height: Double(image.height) * normalizedRect.height
        ).integral
        let cropped = try XCTUnwrap(image.cropping(to: cropRect))
        var pixels = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: cropped.width,
            height: cropped.height,
            bitsPerComponent: 8,
            bytesPerRow: cropped.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        let darkPixels = stride(from: 0, to: pixels.count, by: 4).reduce(into: 0) { count, offset in
            if pixels[offset] <= 20 && pixels[offset + 1] <= 20 && pixels[offset + 2] <= 20 {
                count += 1
            }
        }
        return Double(darkPixels) / Double(cropped.width * cropped.height)
    }

    private func averageRGB(
        in screenshot: XCUIScreenshot,
        screenRect: CGRect,
        screenSize: CGSize
    ) throws -> AverageRGB {
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation)?.cgImage)
        let scaleX = Double(image.width) / screenSize.width
        let scaleY = Double(image.height) / screenSize.height
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = CGRect(
            x: screenRect.minX * scaleX,
            y: screenRect.minY * scaleY,
            width: screenRect.width * scaleX,
            height: screenRect.height * scaleY
        ).integral.intersection(imageBounds)
        let cropped = try XCTUnwrap(image.cropping(to: cropRect))
        var pixels = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: cropped.width,
            height: cropped.height,
            bitsPerComponent: 8,
            bytesPerRow: cropped.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[offset])
            green += Double(pixels[offset + 1])
            blue += Double(pixels[offset + 2])
        }
        let count = Double(cropped.width * cropped.height)
        return AverageRGB(red: red / count, green: green / count, blue: blue / count)
    }

    private func mapComparisonPixels(from screenshot: XCUIScreenshot) throws -> PixelBuffer {
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation)?.cgImage)
        let width = image.width
        let height = image.height

        let cropRect = CGRect(
            x: Double(width) * 0.22,
            y: Double(height) * 0.13,
            width: Double(width) * 0.73,
            height: Double(height) * 0.69
        ).integral

        let cropped = try XCTUnwrap(image.cropping(to: cropRect))
        let cropWidth = cropped.width
        let cropHeight = cropped.height
        var pixels = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: cropWidth,
            height: cropHeight,
            bitsPerComponent: 8,
            bytesPerRow: cropWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))

        return PixelBuffer(width: cropWidth, height: cropHeight, rgba: pixels)
    }

    private func changedPixelRatio(_ before: PixelBuffer, _ after: PixelBuffer, tolerance: UInt8) -> Double {
        XCTAssertEqual(before.width, after.width)
        XCTAssertEqual(before.height, after.height)
        XCTAssertEqual(before.rgba.count, after.rgba.count)

        var changedPixels = 0
        let pixelCount = before.width * before.height

        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * 4
            let redChanged = abs(Int(before.rgba[offset]) - Int(after.rgba[offset])) > Int(tolerance)
            let greenChanged = abs(Int(before.rgba[offset + 1]) - Int(after.rgba[offset + 1])) > Int(tolerance)
            let blueChanged = abs(Int(before.rgba[offset + 2]) - Int(after.rgba[offset + 2])) > Int(tolerance)
            if redChanged || greenChanged || blueChanged {
                changedPixels += 1
            }
        }

        return Double(changedPixels) / Double(pixelCount)
    }

    private struct PixelBuffer {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    private struct AverageRGB: CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double

        var maximumChannel: Double { max(red, green, blue) }
        var description: String { "rgb(\(red), \(green), \(blue))" }

        func distance(to other: AverageRGB) -> Double {
            let redDistance = red - other.red
            let greenDistance = green - other.green
            let blueDistance = blue - other.blue
            return (redDistance * redDistance + greenDistance * greenDistance + blueDistance * blueDistance).squareRoot()
        }
    }
}

import XCTest
import WebKit
@testable import osrswiki

final class IOS07MapStabilityTests: XCTestCase {
    func testEmbeddedMapUIKitFrameOwnsArticleGestureHit() {
        let frames = [
            CGRect(x: 20, y: 120, width: 200, height: 200),
            CGRect(x: 20, y: 420, width: 200, height: 200)
        ]
        XCTAssertTrue(osrsEmbeddedMapGestureHitPolicy.owns(point: CGPoint(x: 100, y: 180), visibleFrames: frames))
        XCTAssertTrue(osrsEmbeddedMapGestureHitPolicy.owns(point: CGPoint(x: 100, y: 500), visibleFrames: frames))
        XCTAssertFalse(osrsEmbeddedMapGestureHitPolicy.owns(point: CGPoint(x: 300, y: 180), visibleFrames: frames))
        XCTAssertFalse(osrsEmbeddedMapGestureHitPolicy.owns(point: CGPoint(x: 100, y: 350), visibleFrames: frames))
    }

    func testCollapsibleScriptRemeasuresAllEmbeddedMapsAfterLayoutChanges() throws {
        let assetsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("osrswiki/Assets/web/collapsible_content.js")
        let collapsibleScript = try String(contentsOf: assetsURL, encoding: .utf8)

        XCTAssertTrue(
            collapsibleScript.contains("document.querySelectorAll('.mw-kartographer-map').forEach"),
            "All map placeholders should be measured, not only maps inside collapsed containers."
        )
        XCTAssertTrue(
            collapsibleScript.contains("function scheduleMapRemeasure()"),
            "Map placeholders should be remeasured after late layout changes."
        )
        XCTAssertTrue(
            collapsibleScript.contains("window.addEventListener('resize', scheduleMapRemeasure"),
            "Embedded maps should be remeasured after viewport size changes."
        )
        XCTAssertTrue(
            collapsibleScript.contains("new ResizeObserver(scheduleMapRemeasure)"),
            "Embedded maps should be remeasured after article body or placeholder size changes."
        )
    }

    func testEmbeddedMapVisibilityIsIdempotent() {
        let rect = CGRect(x: 24, y: 120, width: 300, height: 180)
        var state = osrsEmbeddedMapLayoutState(visibleFrame: rect, isVisible: false)

        let firstOpen = state.applyVisibility(isVisible: true)
        let duplicateOpen = state.applyVisibility(isVisible: true)
        XCTAssertEqual(firstOpen, rect)
        XCTAssertEqual(duplicateOpen, rect)

        let firstClose = state.applyVisibility(isVisible: false)
        let duplicateClose = state.applyVisibility(isVisible: false)
        XCTAssertEqual(firstClose.origin.x, rect.origin.x + osrsEmbeddedMapLayoutState.offscreenTranslationX)
        XCTAssertEqual(duplicateClose, firstClose)
    }

    func testEmbeddedMapRemeasureUpdatesVisibleFrameWithoutLosingState() {
        let originalRect = CGRect(x: 24, y: 120, width: 300, height: 180)
        let resizedRect = CGRect(x: 16, y: 180, width: 360, height: 220)
        var state = osrsEmbeddedMapLayoutState(visibleFrame: originalRect, isVisible: true)

        XCTAssertEqual(state.applyVisibility(isVisible: true), originalRect)

        let updatedFrame = state.updateVisibleFrame(resizedRect)
        XCTAssertEqual(updatedFrame, resizedRect)
        XCTAssertEqual(state.applyVisibility(isVisible: true), resizedRect)

        let hiddenFrame = state.applyVisibility(isVisible: false)
        XCTAssertEqual(hiddenFrame.origin.x, resizedRect.origin.x + osrsEmbeddedMapLayoutState.offscreenTranslationX)
        XCTAssertEqual(hiddenFrame.origin.y, resizedRect.origin.y)
        XCTAssertEqual(hiddenFrame.size, resizedRect.size)
    }

    func testEmbeddedMapViewportLayoutAppliesScrollClippingAtomically() {
        let documentFrame = CGRect(x: 20, y: 120, width: 301, height: 180)
        let webViewFrame = CGRect(x: 0, y: 0, width: 390, height: 844)

        let initial = osrsEmbeddedMapViewportLayout.resolve(
            documentFrame: documentFrame,
            webViewFrame: webViewFrame,
            safeAreaTop: 0,
            contentOffset: .zero
        )
        XCTAssertEqual(initial.containerFrame, documentFrame)
        XCTAssertEqual(initial.mapContentFrame, CGRect(x: 0, y: 0, width: 301, height: 180))
        XCTAssertNil(initial.maskFrame)
        XCTAssertTrue(initial.intersectsViewport)

        let partiallyPassed = osrsEmbeddedMapViewportLayout.resolve(
            documentFrame: documentFrame,
            webViewFrame: webViewFrame,
            safeAreaTop: 0,
            contentOffset: CGPoint(x: 0, y: 200)
        )
        XCTAssertEqual(partiallyPassed.containerFrame, CGRect(x: 20, y: 0, width: 301, height: 100))
        XCTAssertEqual(partiallyPassed.mapContentFrame, CGRect(x: 0, y: -80, width: 301, height: 180))
        XCTAssertEqual(partiallyPassed.maskFrame, CGRect(x: 0, y: 0, width: 301, height: 100))
        XCTAssertTrue(partiallyPassed.intersectsViewport)
        XCTAssertTrue(
            osrsEmbeddedMapGestureHitPolicy.owns(
                point: CGPoint(x: 100, y: 80),
                visibleFrames: [partiallyPassed.containerFrame]
            )
        )
        XCTAssertFalse(
            osrsEmbeddedMapGestureHitPolicy.owns(
                point: CGPoint(x: 100, y: 140),
                visibleFrames: [partiallyPassed.containerFrame]
            ),
            "The visually clipped strip below a partially visible map must not own article gestures."
        )

        let partiallyBelow = osrsEmbeddedMapViewportLayout.resolve(
            documentFrame: CGRect(x: 20, y: 760, width: 301, height: 180),
            webViewFrame: webViewFrame,
            safeAreaTop: 0,
            contentOffset: .zero
        )
        XCTAssertEqual(partiallyBelow.containerFrame, CGRect(x: 20, y: 760, width: 301, height: 84))
        XCTAssertEqual(partiallyBelow.mapContentFrame, CGRect(x: 0, y: 0, width: 301, height: 180))
        XCTAssertEqual(partiallyBelow.maskFrame, CGRect(x: 0, y: 0, width: 301, height: 84))
        XCTAssertFalse(
            osrsEmbeddedMapGestureHitPolicy.owns(
                point: CGPoint(x: 100, y: 880),
                visibleFrames: [partiallyBelow.containerFrame]
            ),
            "The visually clipped strip below the WebView must not own article gestures."
        )

        let fullyPassed = osrsEmbeddedMapViewportLayout.resolve(
            documentFrame: documentFrame,
            webViewFrame: webViewFrame,
            safeAreaTop: 0,
            contentOffset: CGPoint(x: 0, y: 400)
        )
        XCTAssertFalse(fullyPassed.intersectsViewport)
        XCTAssertNil(fullyPassed.maskFrame)
    }

    @MainActor
    func testArticleNavigationWaitsForExplicitUnownedDOMTerminalClassification() {
        let state = osrsGestureState.shared
        state.resetState()
        var navigationCount = 0

        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "article-touch-1", isLocalOwner: false)
        state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }
        XCTAssertEqual(navigationCount, 0, "A touchstart classification is not yet terminal")

        state.endJavaScriptGesture(id: "article-touch-1")
        XCTAssertEqual(navigationCount, 1)
        XCTAssertFalse(state.shouldBlockGestures)
        state.resetState()
    }

    @MainActor
    func testDelayedLocalDOMClaimsCannotTriggerArticleNavigation() async throws {
        let state = osrsGestureState.shared

        for delayMilliseconds in [0, 16, 60, 100] {
            state.resetState()
            var navigationCount = 0
            let gestureId = "article-touch-delay-\(delayMilliseconds)"

            let generation = state.beginArticleGesture()
            if delayMilliseconds > 0 {
                try await Task.sleep(
                    nanoseconds: UInt64(delayMilliseconds) * 1_000_000
                )
            }
            XCTAssertEqual(navigationCount, 0, "No timer may authorize navigation")

            state.classifyJavaScriptGesture(id: gestureId, isLocalOwner: true)
            state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }
            state.endJavaScriptGesture(id: gestureId)
            XCTAssertEqual(navigationCount, 0, "A local-content claim must cancel navigation")
        }
        state.resetState()
    }

    @MainActor
    func testOverlappingNativeAndJavaScriptOwnersReleaseIndependently() async throws {
        let state = osrsGestureState.shared
        state.resetState()

        state.classifyJavaScriptGesture(id: "article-touch-map", isLocalOwner: true)
        state.claimNativeGesture(id: "map-pan")
        state.claimNativeGesture(id: "map-pinch")
        state.endNativeGesture(id: "map-pan")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(state.shouldBlockGestures, "The remaining pinch and DOM owner still own the touch")

        state.endNativeGesture(id: "map-pinch")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(state.shouldBlockGestures, "The matching DOM owner has not ended")

        state.endJavaScriptGesture(id: "article-touch-map")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(state.shouldBlockGestures)
        state.resetState()
    }

    @MainActor
    func testNativeMapHandlerCreatesAndRemeasuresSingleContainer() async throws {
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let webView = WKWebView(frame: parentView.bounds)
        parentView.addSubview(webView)

        let handler = osrsNativeMapHandler(webView: webView)
        let mapId = "map-placeholder-0"
        let firstRect = #"{"x":20,"y":120,"width":300,"height":180}"#
        let secondRect = #"{"x":32,"y":180,"width":340,"height":220}"#
        let mapData = #"{"lat":"3094","lon":"3240","zoom":"7","plane":"0"}"#

        handler.onMapPlaceholderMeasured(id: mapId, rectJson: firstRect, mapDataJson: mapData)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(handler.activeMapContainerIdentifiersForTesting, [mapId])
        let firstHiddenFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(firstHiddenFrame.origin.x, 20 + osrsEmbeddedMapLayoutState.offscreenTranslationX)
        XCTAssertEqual(firstHiddenFrame.origin.y, 120)

        handler.onCollapsibleToggled(mapId: mapId, isOpening: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        let awaitingFirstFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(
            awaitingFirstFrame.origin.x,
            20 + osrsEmbeddedMapLayoutState.offscreenTranslationX,
            "The static Wiki fallback must remain visible until the canonical map renders a complete frame"
        )

        handler.markMapRenderedForTesting(id: mapId)
        try await Task.sleep(nanoseconds: 100_000_000)
        let firstOpenFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(firstOpenFrame.origin.x, 20)
        XCTAssertEqual(handler.mapContainerIsHiddenForTesting(id: mapId), false)

        handler.onCollapsibleToggled(mapId: mapId, isOpening: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId)), firstOpenFrame)

        handler.onMapPlaceholderMeasured(id: mapId, rectJson: secondRect, mapDataJson: mapData)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(handler.activeMapContainerIdentifiersForTesting, [mapId])
        let remeasuredOpenFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(remeasuredOpenFrame.origin.x, 32)
        XCTAssertEqual(remeasuredOpenFrame.origin.y, 180)
        XCTAssertEqual(remeasuredOpenFrame.width, 341)
        XCTAssertEqual(remeasuredOpenFrame.height, 220)

        webView.scrollView.contentOffset = CGPoint(x: 0, y: 260)
        try await Task.sleep(nanoseconds: 100_000_000)
        let clippedFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(clippedFrame.origin.y, 0)
        XCTAssertEqual(try XCTUnwrap(handler.mapContentFrameForTesting(id: mapId)).origin.y, -80)
        XCTAssertEqual(try XCTUnwrap(handler.mapMaskFrameForTesting(id: mapId)).height, 140)
        XCTAssertEqual(handler.mapContainerIsHiddenForTesting(id: mapId), false)

        // A delayed JS measurement after the scroll must reproduce, rather than overwrite, the
        // exact KVO layout/mask state.
        handler.onMapPlaceholderMeasured(id: mapId, rectJson: secondRect, mapDataJson: mapData)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId)), clippedFrame)
        XCTAssertEqual(try XCTUnwrap(handler.mapContentFrameForTesting(id: mapId)).origin.y, -80)
        XCTAssertEqual(try XCTUnwrap(handler.mapMaskFrameForTesting(id: mapId)).height, 140)

        webView.scrollView.contentOffset = .zero
        try await Task.sleep(nanoseconds: 100_000_000)

        handler.onCollapsibleToggled(mapId: mapId, isOpening: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        let firstClosedFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        handler.onCollapsibleToggled(mapId: mapId, isOpening: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId)), firstClosedFrame)

        webView.scrollView.contentOffset = CGPoint(x: 0, y: 500)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(handler.mapContainerIsHiddenForTesting(id: mapId), true)
        handler.onCollapsibleToggled(mapId: mapId, isOpening: true)
        webView.scrollView.contentOffset = CGPoint(x: 0, y: 100)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(handler.mapContainerIsHiddenForTesting(id: mapId), false)
        XCTAssertNil(handler.mapMaskFrameForTesting(id: mapId))

        handler.cleanup()
    }

    @MainActor
    func testRapidOpenCloseBeforeFirstMeasurementPreservesTerminalHiddenState() async throws {
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let webView = WKWebView(frame: parentView.bounds)
        parentView.addSubview(webView)

        let handler = osrsNativeMapHandler(webView: webView)
        let mapId = "map-placeholder-race"
        handler.onCollapsibleToggled(mapId: mapId, isOpening: true)
        handler.onCollapsibleToggled(mapId: mapId, isOpening: false)
        handler.onMapPlaceholderMeasured(
            id: mapId,
            rectJson: #"{"x":20,"y":120,"width":300,"height":180}"#,
            mapDataJson: #"{"lat":"3094","lon":"3240","zoom":"7","plane":"0","initiallyVisible":true}"#
        )
        try await Task.sleep(nanoseconds: 500_000_000)
        handler.markMapRenderedForTesting(id: mapId)
        try await Task.sleep(nanoseconds: 100_000_000)

        let closedFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(
            closedFrame.origin.x,
            20 + osrsEmbeddedMapLayoutState.offscreenTranslationX,
            "The last close must override stale initiallyVisible metadata"
        )

        handler.onCollapsibleToggled(mapId: mapId, isOpening: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId)).origin.x, 20)
        handler.cleanup()
    }

    func testMainTabDoesNotStartUnusedBackgroundMapPreloader() throws {
        let viewsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("osrswiki/Views")
        let sourceURLs = [
            viewsURL.appendingPathComponent("CustomMainTabView.swift"),
            viewsURL.appendingPathComponent("MainTabView.swift")
        ]

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("osrsBackgroundMapPreloader.shared.preloadMapInBackground"),
                "\(sourceURL.lastPathComponent) should not build a shared MapLibre instance that the production map view does not attach."
            )
            XCTAssertFalse(
                source.contains("PRIORITY: Starting MapLibre background preloading"),
                "\(sourceURL.lastPathComponent) should not advertise eager MapLibre preloading when the production map is lazy."
            )
        }
    }
}

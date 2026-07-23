import XCTest
import WebKit
@testable import osrswiki

final class IOS07MapStabilityTests: XCTestCase {
    func testCollapsibleScriptRemeasuresAllEmbeddedMapsAfterLayoutChanges() throws {
        let assetsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("osrswiki/Assets/web/collapsible_content.js")
        let collapsibleScript = try String(contentsOf: assetsURL, encoding: .utf8)

        XCTAssertTrue(
            collapsibleScript.contains("const mapPlaceholders = document.querySelectorAll('.mw-kartographer-map');"),
            "All map placeholders should be measured, not only maps inside collapsed containers."
        )
        XCTAssertTrue(
            collapsibleScript.contains("function scheduleMapRemeasure()"),
            "Map placeholders should be remeasured after late layout changes."
        )
        XCTAssertTrue(
            collapsibleScript.contains("window.addEventListener('resize', scheduleMapRemeasure)"),
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
        let firstOpenFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        XCTAssertEqual(firstOpenFrame.origin.x, 20)

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

        handler.onCollapsibleToggled(mapId: mapId, isOpening: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        let firstClosedFrame = try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId))
        handler.onCollapsibleToggled(mapId: mapId, isOpening: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try XCTUnwrap(handler.mapContainerFrameForTesting(id: mapId)), firstClosedFrame)

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

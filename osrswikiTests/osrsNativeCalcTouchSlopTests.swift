import XCTest
@testable import osrswiki

final class osrsNativeCalcTouchSlopTests: XCTestCase {
    func testVerticalSlopBeginsArticlePanAndHorizontalDoesNot() {
        XCTAssertFalse(osrsNativeCalcSlotGeometry.movementExceededSlop(dx: 0, dy: 10, slop: 10))
        XCTAssertTrue(osrsNativeCalcSlotGeometry.movementExceededSlop(dx: 0, dy: 11, slop: 10))
        XCTAssertTrue(osrsNativeCalcSlotGeometry.isVerticalArticlePan(dx: 3, dy: 40))
        XCTAssertFalse(osrsNativeCalcSlotGeometry.isVerticalArticlePan(dx: 40, dy: 3))

        XCTAssertTrue(
            osrsNativeCalcSlotGeometry.shouldBeginVerticalArticlePan(
                translation: CGPoint(x: 2, y: 24)
            ),
            "vertical movement past slop must steal the control and scroll the article"
        )
        XCTAssertFalse(
            osrsNativeCalcSlotGeometry.shouldBeginVerticalArticlePan(
                translation: CGPoint(x: 1, y: 4)
            ),
            "inside slop stays a tap"
        )
        XCTAssertFalse(
            osrsNativeCalcSlotGeometry.shouldBeginVerticalArticlePan(
                translation: CGPoint(x: 48, y: 6)
            ),
            "horizontal pans must not become article vertical scroll or back-swipe"
        )
    }

    func testArticleScrollOffsetKeepsXAndClampsY() {
        let next = osrsNativeCalcSlotGeometry.articleScrollOffset(
            startOffset: CGPoint(x: 12, y: 80),
            translationY: 40,
            contentSize: CGSize(width: 390, height: 2000),
            boundsHeight: 800,
            adjustedInsetTop: 0,
            adjustedInsetBottom: 0
        )
        XCTAssertEqual(next.x, 12, accuracy: 0.01, "a calc-field pan must not become back-swipe")
        XCTAssertEqual(next.y, 40, accuracy: 0.01)

        let clamped = osrsNativeCalcSlotGeometry.articleScrollOffset(
            startOffset: CGPoint(x: 0, y: 0),
            translationY: 80,
            contentSize: CGSize(width: 390, height: 2000),
            boundsHeight: 800,
            adjustedInsetTop: 0,
            adjustedInsetBottom: 0
        )
        XCTAssertEqual(clamped.y, 0, accuracy: 0.01)
    }

    func testPanBridgeCancelsTouchesAndScrollsWebViewScrollView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let overlay = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/osrsNativeCalcSlotOverlay.swift"),
            encoding: .utf8
        )
        let bridge = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/osrsNativeCalcControlPanBridge.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(overlay.contains("osrsNativeCalcControlPanBridge(webView: webView)"))
        XCTAssertTrue(bridge.contains("cancelsTouchesInView = true"))
        XCTAssertTrue(bridge.contains("shouldBeginVerticalArticlePan"))
        XCTAssertTrue(bridge.contains("webView.scrollView"))
        XCTAssertTrue(bridge.contains("setContentOffset"))
        XCTAssertFalse(
            bridge.contains("interactiveArticleSwipe"),
            "vertical pan-from-control must not start article back-swipe"
        )
        let view = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/osrsNativeCalcView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(view.contains("ScrollView("))
    }
}

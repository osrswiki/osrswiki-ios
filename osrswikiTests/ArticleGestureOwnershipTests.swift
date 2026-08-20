import XCTest
@testable import osrswiki

@MainActor
final class ArticleGestureOwnershipTests: XCTestCase {
    private let state = osrsGestureState.shared

    override func setUp() async throws {
        try await super.setUp()
        state.resetState()
    }

    override func tearDown() async throws {
        state.resetState()
        try await super.tearDown()
    }

    func testExplicitUnownedTerminalClassificationAuthorizesNavigation() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "article-touch-1", isLocalOwner: false)
        state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }
        XCTAssertEqual(navigationCount, 0)
        state.endJavaScriptGesture(id: "article-touch-1")

        XCTAssertEqual(navigationCount, 1)
        XCTAssertFalse(state.shouldBlockGestures)
    }

    func testLocalClaimsAtZeroThroughOneHundredMillisecondsCancelNavigation() async throws {
        for delayMilliseconds in [0, 16, 60, 100] {
            state.resetState()
            var navigationCount = 0
            let gestureId = "article-touch-delay-\(delayMilliseconds)"

            let generation = state.beginArticleGesture()
            if delayMilliseconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            }
            XCTAssertEqual(navigationCount, 0, "A timer must never authorize navigation")

            state.classifyJavaScriptGesture(id: gestureId, isLocalOwner: true)
            state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }
            state.endJavaScriptGesture(id: gestureId)
            XCTAssertEqual(navigationCount, 0, "Local content owns delay \(delayMilliseconds) ms")
        }
    }

    func testCancelledUnownedDOMSequenceNeverAuthorizesNavigation() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "article-touch-cancel", isLocalOwner: false)
        state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }
        state.cancelJavaScriptGesture(id: "article-touch-cancel")

        XCTAssertEqual(navigationCount, 0)
        XCTAssertFalse(state.shouldBlockGestures)
    }

    func testJavaScriptEndRemainsLatchedAcrossNativeDragEndTurn() async throws {
        state.claimJavaScriptGesture(id: "bonuses-table")
        state.endJavaScriptGesture(id: "bonuses-table")

        XCTAssertTrue(state.shouldBlockGestures)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(state.shouldBlockGestures)
        try await Task.sleep(nanoseconds: 320_000_000)
        XCTAssertFalse(state.shouldBlockGestures)
    }

    func testOverlappingNativePanAndPinchReleaseOnlyAfterBothEnd() async throws {
        state.claimNativeGesture(id: "map-pan")
        state.claimNativeGesture(id: "map-pinch")
        state.endNativeGesture(id: "map-pan")
        try await Task.sleep(nanoseconds: 380_000_000)

        XCTAssertTrue(state.shouldBlockGestures)
        state.endNativeGesture(id: "map-pinch")
        try await Task.sleep(nanoseconds: 380_000_000)
        XCTAssertFalse(state.shouldBlockGestures)
    }

    func testTeardownResetCancelsPendingNavigationAndReleasesAllOwners() async throws {
        var navigated = false
        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "bonuses-table", isLocalOwner: true)
        state.performNavigationAfterClassification(generation: generation) { navigated = true }
        state.claimNativeGesture(id: "map-pan")
        state.resetState()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(navigated)
        XCTAssertFalse(state.shouldBlockGestures)
    }

    func testMissingDOMBeginFailsClosedAndLaterUnrelatedTouchCannotNavigate() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()

        state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)

        state.classifyJavaScriptGesture(id: "later-unrelated-touch", isLocalOwner: false)
        state.endJavaScriptGesture(id: "later-unrelated-touch")

        XCTAssertEqual(navigationCount, 0)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)
    }

    func testReplacementDOMGenerationCannotResolveEarlierNativeAction() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "article-touch-original", isLocalOwner: false)
        state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }

        state.classifyJavaScriptGesture(id: "article-touch-replacement", isLocalOwner: false)
        state.endJavaScriptGesture(id: "article-touch-replacement")

        XCTAssertEqual(navigationCount, 0)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)
    }

    func testNativeMapClaimVetoesMatchingArticleGeneration() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "article-touch-map", isLocalOwner: false)
        state.claimNativeGesture(id: "map-pan")
        state.endJavaScriptGesture(id: "article-touch-map")
        state.performNavigationAfterClassification(generation: generation) { navigationCount += 1 }

        XCTAssertEqual(navigationCount, 0)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)
    }

    func testDOMPointLocalOwnerVetoesNavigationWithoutTouchMessages() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()

        state.performNavigationAfterPointClassification(
            generation: generation,
            isLocalOwnerAtStartPoint: true
        ) { navigationCount += 1 }

        XCTAssertEqual(navigationCount, 0)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)

        // A later unrelated unowned DOM sequence cannot resolve the finished generation.
        state.classifyJavaScriptGesture(id: "later-unrelated-touch", isLocalOwner: false)
        state.endJavaScriptGesture(id: "later-unrelated-touch")
        XCTAssertEqual(navigationCount, 0)
    }

    func testDOMPointUnownedResultAuthorizesMatchingGenerationExactlyOnce() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()

        state.performNavigationAfterPointClassification(
            generation: generation,
            isLocalOwnerAtStartPoint: false
        ) { navigationCount += 1 }
        state.performNavigationAfterPointClassification(
            generation: generation,
            isLocalOwnerAtStartPoint: false
        ) { navigationCount += 1 }

        XCTAssertEqual(navigationCount, 1)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)
    }

    func testRealLocalDOMOwnerVetoesConflictingUnownedPointResult() {
        var navigationCount = 0
        let generation = state.beginArticleGesture()
        state.classifyJavaScriptGesture(id: "bonuses-table", isLocalOwner: true)

        state.performNavigationAfterPointClassification(
            generation: generation,
            isLocalOwnerAtStartPoint: false
        ) { navigationCount += 1 }

        XCTAssertEqual(navigationCount, 0)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)
    }

    func testUIKitArticlePanPolicyAcceptsHorizontalDirectionsAndRejectsVertical() {
        XCTAssertEqual(
            osrsArticleWebPanPolicy.navigationDirection(
                translation: CGPoint(x: 80, y: 4),
                velocity: CGPoint(x: 500, y: 20)
            ),
            .start
        )
        XCTAssertEqual(
            osrsArticleWebPanPolicy.navigationDirection(
                translation: CGPoint(x: -140, y: 8),
                velocity: CGPoint(x: -500, y: 20)
            ),
            .end
        )
        XCTAssertNil(
            osrsArticleWebPanPolicy.navigationDirection(
                translation: CGPoint(x: 80, y: 48),
                velocity: CGPoint(x: 500, y: 400)
            )
        )
        XCTAssertFalse(osrsArticleWebPanPolicy.isPrimarilyHorizontal(velocity: CGPoint(x: 20, y: 300)))
        XCTAssertFalse(osrsArticleWebPanPolicy.isPrimarilyHorizontal(velocity: CGPoint(x: 300, y: 200)))
        XCTAssertTrue(osrsArticleWebPanPolicy.isPrimarilyHorizontal(velocity: CGPoint(x: 400, y: 100)))
    }

    func testLiveGesturePreferencesGateCallbacksAfterOwnershipWithoutRecreatingCoordinator() throws {
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Amulet_of_glory"))
        let viewModel = ArticleViewModel(pageUrl: url, pageTitle: "Amulet of glory")
        let disabledParent = ArticleWebView(
            viewModel: viewModel,
            onBackGesture: nil,
            onSidebarGesture: nil
        )
        let coordinator = disabledParent.makeCoordinator()
        var backCount = 0
        var contentsCount = 0

        // Disabled actions still complete the same explicit unowned-point arbitration path;
        // only the final dynamic callback lookup is empty.
        coordinator.resolveArticleNavigationForTesting(
            direction: .start,
            isLocalOwnerAtStartPoint: false
        )
        coordinator.resolveArticleNavigationForTesting(
            direction: .end,
            isLocalOwnerAtStartPoint: false
        )
        XCTAssertEqual(backCount, 0)
        XCTAssertEqual(contentsCount, 0)
        XCTAssertFalse(state.hasPendingArticleNavigationForTesting)

        // SwiftUI updateUIView updates this same coordinator's parent. No WebView/coordinator
        // recreation is needed for either preference to become live.
        coordinator.parent = ArticleWebView(
            viewModel: viewModel,
            onBackGesture: { backCount += 1 },
            onSidebarGesture: { contentsCount += 1 }
        )

        // Native-map, DOM-table, and local horizontal-scroll ownership all resolve as local
        // owners and continue to veto callbacks even after the preferences are re-enabled.
        coordinator.resolveArticleNavigationForTesting(
            direction: .start,
            isLocalOwnerAtStartPoint: true
        )
        coordinator.resolveArticleNavigationForTesting(
            direction: .end,
            isLocalOwnerAtStartPoint: true
        )
        XCTAssertEqual(backCount, 0)
        XCTAssertEqual(contentsCount, 0)

        coordinator.resolveArticleNavigationForTesting(
            direction: .start,
            isLocalOwnerAtStartPoint: false
        )
        coordinator.resolveArticleNavigationForTesting(
            direction: .end,
            isLocalOwnerAtStartPoint: false
        )
        XCTAssertEqual(backCount, 1)
        XCTAssertEqual(contentsCount, 1)
    }

    func testMainTabsDoNotInstallACompetingFullScreenHorizontalRecognizer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/MainTabView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains(".osrsHorizontalGestures("))
        XCTAssertTrue(source.contains("TabView(selection:"))
    }

    func testArticleWebViewInstallsNonCancellingSimultaneousUIKitRecognizer() throws {
        var root = URL(fileURLWithPath: #filePath)
        while root.pathComponents.count > 1,
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path) {
            root.deleteLastPathComponent()
        }
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleWebView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("UIPanGestureRecognizer(target: self"))
        XCTAssertTrue(source.contains("recognizer.cancelsTouchesInView = false"))
        XCTAssertTrue(source.contains("shouldRecognizeSimultaneouslyWith"))
        XCTAssertTrue(source.contains("osrsGestureState.shared.beginArticleGesture()"))
        XCTAssertTrue(source.contains("classifyArticleGestureStartPoint("))
        XCTAssertTrue(source.contains("performNavigationAfterPointClassification("))
        XCTAssertTrue(source.contains("OSRSArticleGestureOwnership"))
        XCTAssertTrue(source.contains("recognizer.maximumNumberOfTouches = 1"))
        XCTAssertTrue(source.contains("osrsInteractiveArticleSwipe"))
        XCTAssertTrue(source.contains("interactiveSwipe.update(translation:"))
        XCTAssertTrue(source.contains("onSidebarProgress"))
        XCTAssertTrue(source.contains("onBackProgress"))
        XCTAssertTrue(source.contains("contentsOpenAtStart"))
        XCTAssertTrue(source.contains("commitBackImmediately"))
        XCTAssertTrue(source.contains("shouldBlockGestures"))
        XCTAssertTrue(source.contains("chromeLocked"))
        XCTAssertTrue(source.contains("max(interactiveSwipe.contentsProgress, interactiveSwipe.backProgress) > 0.25"))
        XCTAssertTrue(source.contains("DispatchQueue.main.async"))
        XCTAssertTrue(source.contains("cleanup(resetTransform: false)"))
        XCTAssertTrue(source.contains("interactivePopGestureRecognizer?.isEnabled = false"))
        XCTAssertTrue(source.contains("pendingBackCommitGeneration == generation"))
        XCTAssertTrue(source.contains("pendingBackCommitAuthorized = true"))
        XCTAssertTrue(source.contains("parent.onSidebarGesture?()"))
        XCTAssertTrue(source.contains("isLocalOwnerAtStartPoint: false"))
    }

    func testHorizontalOverflowClaimsTheWholePointerSequence() throws {
        var root = URL(fileURLWithPath: #filePath)
        while root.pathComponents.count > 1,
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path) {
            root.deleteLastPathComponent()
        }
        let source = try String(
            contentsOf: root.appendingPathComponent("shared/js/horizontal_scroll_interceptor.js"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("if (owner && capacity.hasOverflow)"))
        XCTAssertTrue(source.contains("claimLocalSequence(owner)"))
        XCTAssertTrue(source.contains("A horizontally scrollable surface owns the whole pointer sequence"))
        XCTAssertFalse(source.contains("handoffAtEdge"))
        let overflowWalk = try XCTUnwrap(source.range(of: "isOverflowingHorizontalScroller(current)"))
        let protectedReturn = try XCTUnwrap(source.range(of: "if (isInProtectedNonlocalTableRole(target)) return null"))
        XCTAssertTrue(
            overflowWalk.lowerBound < protectedReturn.lowerBound,
            "Overflowing infobox maps and similar surfaces must claim the pointer before the protected-role skip"
        )
    }
}

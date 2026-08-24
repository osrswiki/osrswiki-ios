import XCTest
import UIKit
@testable import osrswiki

final class osrsInteractiveArticleSwipeTests: XCTestCase {
    func testRemainingCommitDurationStaysInAContinuousRange() {
        let settled = osrsInteractiveArticleSwipe.remainingCommitDuration(
            progress: 1,
            velocity: 0,
            distance: 390
        )
        let slow = osrsInteractiveArticleSwipe.remainingCommitDuration(
            progress: 0.35,
            velocity: 180,
            distance: 390
        )
        let flicked = osrsInteractiveArticleSwipe.remainingCommitDuration(
            progress: 0.35,
            velocity: 1_800,
            distance: 390
        )

        XCTAssertEqual(settled, osrsInteractiveArticleSwipe.settleMinDuration, accuracy: 0.001)
        XCTAssertGreaterThan(slow, 0.32, "A slow release must keep travelling instead of snapping in 320ms")
        XCTAssertLessThanOrEqual(slow, osrsInteractiveArticleSwipe.settleMaxDuration)
        XCTAssertLessThan(flicked, slow)
        XCTAssertGreaterThanOrEqual(flicked, osrsInteractiveArticleSwipe.settleMinDuration)
    }

    func testBackPreviewDoesNotParallaxAwayFromTheLivePreviousPage() {
        XCTAssertEqual(osrsInteractiveArticleSwipe.backPreviewParallax, 0, accuracy: 0.001)
    }

    func testContentsSettleDurationUsesRemainingTravelInsteadOfAFixedSnap() {
        let slow = osrsInteractiveArticleSwipe.remainingCommitDuration(
            from: 0.35,
            to: 1,
            velocity: 180,
            distance: 280
        )
        let flicked = osrsInteractiveArticleSwipe.remainingCommitDuration(
            from: 0.35,
            to: 1,
            velocity: 1_800,
            distance: 280
        )
        XCTAssertGreaterThan(slow, 0.32)
        XCTAssertLessThan(flicked, slow)
    }

    func testUniformBlackFlashRejectsBlankFramesButNotDarkTexturedContent() {
        let black = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let darkArticle = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor(white: 0.45, alpha: 1).setFill()
            ctx.fill(CGRect(x: 4, y: 4, width: 24, height: 8))
            ctx.fill(CGRect(x: 6, y: 16, width: 18, height: 10))
        }
        XCTAssertTrue(osrsInteractiveArticleSwipe.isUniformBlackFlash(black))
        XCTAssertFalse(osrsInteractiveArticleSwipe.isUniformBlackFlash(darkArticle))
    }

    func testContentsOverlayStaysTappableSoAVisuallyOpenDrawerCanBeDismissed() {
        XCTAssertTrue(osrsContentsReveal.isVisuallyOpen(isPresented: true, interactiveProgress: 0))
        XCTAssertTrue(osrsContentsReveal.isVisuallyOpen(isPresented: false, interactiveProgress: 1))
        XCTAssertFalse(osrsContentsReveal.isVisuallyOpen(isPresented: false, interactiveProgress: 0))
        XCTAssertTrue(osrsContentsReveal.allowsOverlayHitTesting(isPresented: true, interactiveProgress: 0))
        XCTAssertTrue(osrsContentsReveal.allowsOverlayHitTesting(isPresented: false, interactiveProgress: 0.5))
        XCTAssertTrue(osrsContentsReveal.allowsOverlayHitTesting(isPresented: false, interactiveProgress: 1))
        XCTAssertFalse(osrsContentsReveal.allowsOverlayHitTesting(isPresented: false, interactiveProgress: 0))
        _ = osrsContentsReveal.settleAnimation(from: 0.4, to: 1, velocity: 180)
    }

    func testContentsSettleAnimationUsesCoastFloorWhenVelocityIsZero() {
        let remaining = osrsInteractiveArticleSwipe.remainingDistance(
            from: 0.4,
            to: 1,
            distance: osrsInteractiveArticleSwipe.contentsDrawerWidth
        )
        XCTAssertGreaterThan(remaining, 1)
        let duration = osrsInteractiveArticleSwipe.remainingCommitDuration(
            from: 0.4,
            to: 1,
            velocity: 0,
            distance: osrsInteractiveArticleSwipe.contentsDrawerWidth
        )
        XCTAssertGreaterThan(duration, osrsInteractiveArticleSwipe.settleMinDuration)
        _ = osrsInteractiveArticleSwipe.settleAnimation(
            from: 0.4,
            to: 1,
            velocity: 0,
            distance: osrsInteractiveArticleSwipe.contentsDrawerWidth
        )
    }

    func testOpenContentsRightSwipeLocksContentsAndDecreasesProgress() {
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.lockAxis(
                translation: CGPoint(x: 80, y: 8),
                contentsOpenAtStart: true
            ),
            .contents
        )
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.contentsProgress(
                translationX: 140,
                contentsOpenAtStart: true
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertFalse(
            osrsInteractiveArticleSwipe.shouldCommitContents(
                progress: 0.8,
                velocityX: 0,
                contentsOpenAtStart: true
            )
        )
        XCTAssertTrue(
            osrsInteractiveArticleSwipe.shouldCommitContents(
                progress: 0.6,
                velocityX: 0,
                contentsOpenAtStart: true
            )
        )
        XCTAssertTrue(
            osrsInteractiveArticleSwipe.shouldCommitContents(
                progress: 0.9,
                velocityX: 600,
                contentsOpenAtStart: true
            )
        )
    }

    func testClosedContentsDrawerParksFullyPastTrailingInset() {
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.contentsDrawerTravelDistance,
            osrsInteractiveArticleSwipe.contentsDrawerWidth
                + osrsInteractiveArticleSwipe.contentsDrawerTrailingInset
                + osrsInteractiveArticleSwipe.contentsDrawerParkBleed,
            accuracy: 0.001
        )
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.contentsParkedOffset(panelWidth: 280),
            372,
            accuracy: 0.001
        )
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.contentsParkedOffset(panelWidth: 240),
            332,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(osrsInteractiveArticleSwipe.contentsDrawerTrailingInset, 0)
        XCTAssertGreaterThan(osrsInteractiveArticleSwipe.contentsDrawerParkBleed, 24)
        XCTAssertGreaterThan(
            osrsInteractiveArticleSwipe.contentsParkedOffset(panelWidth: 280),
            280 + osrsInteractiveArticleSwipe.contentsDrawerTrailingInset
        )
    }

    func testClosedContentsLeftSwipeStillOpens() {
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.lockAxis(
                translation: CGPoint(x: -90, y: 10),
                contentsOpenAtStart: false
            ),
            .contents
        )
        XCTAssertEqual(
            osrsInteractiveArticleSwipe.contentsProgress(
                translationX: -140,
                contentsOpenAtStart: false
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertTrue(
            osrsInteractiveArticleSwipe.shouldCommitContents(
                progress: 0.4,
                velocityX: 0,
                contentsOpenAtStart: false
            )
        )
    }

    func testBackSwipeKeepsThePreviousPageLiveInsteadOfADestinationBitmap() throws {
        var root = URL(fileURLWithPath: #filePath)
        while root.pathComponents.count > 1,
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path) {
            root.deleteLastPathComponent()
        }
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/Components/osrsInteractiveArticleSwipe.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("sliding.snapshotView(afterScreenUpdates: false)"))
        XCTAssertFalse(source.contains("window.snapshotView(afterScreenUpdates: false)"))
        XCTAssertTrue(source.contains("livePreviousPageView"))
        XCTAssertTrue(source.contains("restoreLivePreviousPage"))
    }

    func testLivePreviousPageViewIsTheControllerUnderTheTopOfTheStack() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let first = UIViewController()
        first.view.backgroundColor = .red
        let second = UIViewController()
        second.view.backgroundColor = .blue
        let navigation = UINavigationController(rootViewController: first)
        navigation.pushViewController(second, animated: false)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        navigation.view.layoutIfNeeded()
        _ = second.view.window

        let live = osrsInteractiveArticleSwipe.livePreviousPageView(from: second.view)
        XCTAssertTrue(live === first.view)
        XCTAssertNil(osrsInteractiveArticleSwipe.livePreviousPageView(from: first.view))
    }

    func testBackSwipeIgnoresTouchesOnSlidersAndSwitches() {
        let slider = UISlider()
        let thumb = UIView()
        slider.addSubview(thumb)
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: thumb))
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: slider))
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: UISwitch()))
        XCTAssertTrue(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: UIView()))
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: nil))

        let sliderPan = UIPanGestureRecognizer()
        slider.addGestureRecognizer(sliderPan)
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsSimultaneousRecognition(with: sliderPan))

        let canvas = UIView()
        let canvasPan = UIPanGestureRecognizer()
        canvas.addGestureRecognizer(canvasPan)
        XCTAssertTrue(osrsInteractiveBackSwipeTouchPolicy.allowsSimultaneousRecognition(with: canvasPan))
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsSimultaneousRecognition(with: UIPanGestureRecognizer()))
    }

    func testBackSwipeFailsClosedOnHorizontalScrollersAndAllowsVerticalLists() {
        let horizontal = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        horizontal.contentSize = CGSize(width: 900, height: 120)
        XCTAssertTrue(osrsInteractiveBackSwipeTouchPolicy.isHorizontalScroller(horizontal))
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: horizontal))

        let nested = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        horizontal.addSubview(nested)
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: nested))

        let vertical = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        vertical.contentSize = CGSize(width: 320, height: 1400)
        vertical.alwaysBounceVertical = true
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.isHorizontalScroller(vertical))
        XCTAssertTrue(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: vertical))

        let bounceHorizontal = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        bounceHorizontal.alwaysBounceHorizontal = true
        bounceHorizontal.alwaysBounceVertical = false
        bounceHorizontal.contentSize = CGSize(width: 320, height: 120)
        XCTAssertTrue(osrsInteractiveBackSwipeTouchPolicy.isHorizontalScroller(bounceHorizontal))
        XCTAssertFalse(osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: bounceHorizontal))
    }

    func testDestinationCanvasPrefersThePushedNavigationPageNotARootHost() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        root.view.backgroundColor = .red
        let nav = UINavigationController(rootViewController: root)
        let destination = UIViewController()
        destination.view.backgroundColor = .blue
        nav.pushViewController(destination, animated: false)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        nav.view.layoutIfNeeded()

        let canvas = osrsInteractiveArticleSwipe.destinationCanvas(from: destination.view)
        XCTAssertTrue(canvas === destination.view)
        XCTAssertFalse(canvas === root.view)
        XCTAssertFalse(canvas === window)

        destination.view.transform = CGAffineTransform(translationX: 80, y: 0)
        nav.view.transform = CGAffineTransform(translationX: 40, y: 0)
        osrsInteractiveArticleSwipe.resetStuckTranslationTransforms(from: destination.view)
        osrsInteractiveArticleSwipe.resetStuckTranslationTransforms(from: nav.view)
        XCTAssertEqual(destination.view.transform, .identity)
        XCTAssertEqual(nav.view.transform, .identity)
    }
}

final class osrsInteractiveSwipeFrameProbeTests: XCTestCase {
    func testSummaryTreatsSixteenMillisecondFramesAsSixtyHertz() {
        let stats = osrsInteractiveSwipeFrameProbe.summary(samples: [0.016, 0.017, 0.016, 0.018, 0.016])
        XCTAssertEqual(stats.count, 5)
        XCTAssertLessThan(stats.medianMs, 18)
        XCTAssertGreaterThan(stats.medianHz, 50)
        XCTAssertGreaterThan(stats.displayHz, 0)
    }
}

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
}

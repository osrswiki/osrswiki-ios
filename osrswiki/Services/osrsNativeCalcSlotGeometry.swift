import CoreGraphics
import Foundation

enum osrsNativeCalcSlotGeometry {
    /// How often the overlay re-reads the article disclosure `collapsed`
    /// class. A WebView header tap never drives SwiftUI `updateUIView`.
    static let disclosurePollInterval: TimeInterval = 0.2

    /// Form Y in the article WebView. Negative means the slot has scrolled
    /// above the visible article. Never clamp to 0 — that pins the overlay.
    static func formTopY(slotDocumentY: CGFloat, contentOffsetY: CGFloat) -> CGFloat {
        slotDocumentY - contentOffsetY
    }

    static func isPinnedToWebViewTop(
        formTopY: CGFloat,
        slotDocumentY: CGFloat,
        contentOffsetY: CGFloat
    ) -> Bool {
        let unclamped = slotDocumentY - contentOffsetY
        return unclamped < -0.5 && abs(formTopY) < 0.5
    }

    static func formHasLeftViewport(
        formTopY: CGFloat,
        formHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        formTopY + formHeight <= 0 || formTopY >= viewportHeight
    }

    /// The overlay starts at y=0 of the article shell. Painting before the
    /// slot probe returns a real top covers search chrome with the form tail.
    /// Collapsed article disclosures own the header; hiding the overlay then
    /// is what lets Android/iOS expand after collapse.
    static func overlayMayShow(slotResolved: Bool, collapsed: Bool = false) -> Bool {
        slotResolved && !collapsed
    }

    static func overlayCoversArticleHeader(
        overlayIncludesHeader: Bool,
        collapsed: Bool
    ) -> Bool {
        overlayIncludesHeader && collapsed
    }

    /// Host/overlay width on first layout. Leftover gadget/slot shrink-wrap
    /// (much smaller than the article column) is ignored. Intersection must
    /// not change the chosen width.
    static func firstLayoutWidth(
        slotWidth: CGFloat,
        contentColumnWidth: CGFloat,
        viewportWidth: CGFloat,
        intersected: Bool = false
    ) -> CGFloat {
        _ = intersected
        let column: CGFloat
        if contentColumnWidth > 1 {
            column = contentColumnWidth
        } else if viewportWidth > 1 {
            column = viewportWidth
        } else {
            column = slotWidth
        }
        if contentColumnWidth > 1 && slotWidth > 1 && slotWidth < contentColumnWidth * 0.7 {
            return contentColumnWidth
        }
        if slotWidth > 1 {
            return slotWidth
        }
        return column
    }

    /// Visible overlay height inside the collapsible / remaining article
    /// viewport. Tall Agility chrome inner-scrolls; Combat keeps intrinsic
    /// height. Box height wins when it is a real body, not leftover shrink-wrap.
    static func overlayVisibleHeight(
        formHeight: CGFloat,
        viewportHeight: CGFloat,
        formTopY: CGFloat,
        boxHeight: CGFloat = 0
    ) -> CGFloat {
        if formHeight <= 0 { return 0 }
        let remaining = max(0, viewportHeight - max(formTopY, 0))
        var cap = remaining
        if boxHeight > 1, remaining < 1 || boxHeight >= remaining * 0.35 {
            cap = remaining < 1 ? boxHeight : min(cap, boxHeight)
        }
        if cap < 1 { return 0 }
        return min(formHeight, cap)
    }

    /// Width of the overlay frame. Wider-than-box chrome clips to the
    /// collapsible column the same way wide article tables do.
    static func overlayClipWidth(
        slotWidth: CGFloat,
        contentColumnWidth: CGFloat,
        viewportWidth: CGFloat,
        intersected: Bool = false
    ) -> CGFloat {
        let fitted = firstLayoutWidth(
            slotWidth: slotWidth,
            contentColumnWidth: contentColumnWidth,
            viewportWidth: viewportWidth,
            intersected: intersected
        )
        let cap: CGFloat
        if contentColumnWidth > 1 {
            cap = contentColumnWidth
        } else if viewportWidth > 1 {
            cap = viewportWidth
        } else {
            cap = fitted
        }
        return min(fitted, cap)
    }

    /// UIKit analogue of Android `ViewConfiguration.getScaledTouchSlop()`.
    /// UIPanGestureRecognizer begins around this distance.
    static let controlPanSlop: CGFloat = 10

    static func movementExceededSlop(
        dx: CGFloat,
        dy: CGFloat,
        slop: CGFloat = controlPanSlop
    ) -> Bool {
        dx * dx + dy * dy > slop * slop
    }

    static func isVerticalArticlePan(dx: CGFloat, dy: CGFloat) -> Bool {
        abs(dy) >= abs(dx)
    }

    /// True when a control-started pan should cancel the control and scroll
    /// the article. Horizontal pans fail this so chip-row scrollers and
    /// article back-swipe arbitration are not stolen.
    static func shouldBeginVerticalArticlePan(
        translation: CGPoint,
        slop: CGFloat = controlPanSlop
    ) -> Bool {
        movementExceededSlop(dx: translation.x, dy: translation.y, slop: slop) &&
            isVerticalArticlePan(dx: translation.x, dy: translation.y)
    }

    static func articleScrollOffset(
        startOffset: CGPoint,
        translationY: CGFloat,
        contentSize: CGSize,
        boundsHeight: CGFloat,
        adjustedInsetTop: CGFloat,
        adjustedInsetBottom: CGFloat
    ) -> CGPoint {
        var y = startOffset.y - translationY
        let minY = -adjustedInsetTop
        let maxY = max(minY, contentSize.height - boundsHeight + adjustedInsetBottom)
        y = min(max(y, minY), maxY)
        return CGPoint(x: startOffset.x, y: y)
    }
}

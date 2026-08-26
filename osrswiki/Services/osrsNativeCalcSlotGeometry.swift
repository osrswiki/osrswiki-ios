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
}

import CoreGraphics

enum osrsNativeCalcSlotGeometry {
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
    static func overlayMayShow(slotResolved: Bool) -> Bool {
        slotResolved
    }
}

import UIKit

/// Window-scene geometry for layout, scale, and ProMotion.
///
/// `UIScreen.main` is ambiguous on a two-display device and is the layout
/// footgun Apple flags for iPhone Duo / resizable iPhone. Prefer the attached
/// window, then `UIWindowScene.coordinateSpace.bounds`, then a documented
/// last-resort fallback. The Xcode project links the iOS 27.1 SDK
/// (`SDKROOT = iphoneos27.1`); `IPHONEOS_DEPLOYMENT_TARGET` stays 18.5.
enum osrsWindowSceneGeometry {
    /// Hosted unit tests and pre-scene launch only. Not a layout source of truth.
    static let fallbackPhonePortrait = CGSize(width: 390, height: 844)

    static var currentBounds: CGRect {
        bounds(from: nil)
    }

    static var currentSize: CGSize {
        currentBounds.size
    }

    static func bounds(from view: UIView?) -> CGRect {
        if let window = view?.window, isUsable(window.bounds.size) {
            return window.bounds
        }
        if let sceneBounds = view?.window?.windowScene?.coordinateSpace.bounds,
           isUsable(sceneBounds.size) {
            return sceneBounds
        }
        if let scene = connectedWindowScene() {
            let sceneBounds = scene.coordinateSpace.bounds
            if isUsable(sceneBounds.size) {
                return sceneBounds
            }
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            if let window, isUsable(window.bounds.size) {
                return window.bounds
            }
        }
        let screen = UIScreen.main.bounds
        if isUsable(screen.size) {
            return screen
        }
        return CGRect(origin: .zero, size: fallbackPhonePortrait)
    }

    static func size(from view: UIView?) -> CGSize {
        bounds(from: view).size
    }

    static func scale(from view: UIView?) -> CGFloat {
        if let scale = view?.traitCollection.displayScale, scale > 0 {
            return scale
        }
        if let scale = view?.window?.windowScene?.screen.scale, scale > 0 {
            return scale
        }
        if let scale = connectedWindowScene()?.traitCollection.displayScale, scale > 0 {
            return scale
        }
        if let scale = connectedWindowScene()?.screen.scale, scale > 0 {
            return scale
        }
        let screenScale = UIScreen.main.scale
        return screenScale > 0 ? screenScale : 1
    }

    static func maximumFramesPerSecond(from view: UIView? = nil) -> Int {
        if let fps = view?.window?.windowScene?.screen.maximumFramesPerSecond, fps > 0 {
            return fps
        }
        if let fps = connectedWindowScene()?.screen.maximumFramesPerSecond, fps > 0 {
            return fps
        }
        return max(UIScreen.main.maximumFramesPerSecond, 1)
    }

    /// Keyboard frames arrive in screen coordinates. Measure overlap against
    /// the container's maxY (window / scene), never a global main-screen height.
    static func keyboardOverlap(keyboardFrame: CGRect, containerMaxY: CGFloat) -> CGFloat {
        max(0, containerMaxY - keyboardFrame.minY)
    }

    /// Left and right insets are independent. Do not assume `left == right`
    /// on Duo inner display, Split View, or iPhone Mirroring.
    static func contentSize(windowSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGSize {
        CGSize(
            width: max(0, windowSize.width - safeAreaInsets.left - safeAreaInsets.right),
            height: max(0, windowSize.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )
    }

    static func contentSize(from window: UIWindow?) -> CGSize {
        let bounds = window.map(\.bounds) ?? currentBounds
        let insets = window?.safeAreaInsets ?? .zero
        return contentSize(windowSize: bounds.size, safeAreaInsets: insets)
    }

    /// Today's Updates carousel leading/trailing padding when there is no
    /// horizontal side chrome (typical iPhone portrait and iPad).
    static let homeUpdatesCarouselBaseHorizontalPadding: CGFloat = 16

    /// Extra leading/trailing padding from the system horizontal safe area.
    /// Zero on typical iPhone portrait and iPad (`left == right == 0`).
    /// Left and right stay independent: never `left * 2`.
    static func extraHorizontalSafeAreaInsets(
        _ safeAreaInsets: UIEdgeInsets
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: 0,
            left: max(0, safeAreaInsets.left),
            bottom: 0,
            right: max(0, safeAreaInsets.right)
        )
    }

    /// Base overlay padding plus independent horizontal safe-area insets.
    /// Use for custom chrome that is not inside a system bar.
    static func overlayChromeHorizontalInsets(
        base: CGFloat,
        safeAreaInsets: UIEdgeInsets
    ) -> UIEdgeInsets {
        let extra = extraHorizontalSafeAreaInsets(safeAreaInsets)
        return UIEdgeInsets(
            top: 0,
            left: base + extra.left,
            bottom: 0,
            right: base + extra.right
        )
    }

    /// Combined content insets for the Home Updates horizontal carousel.
    ///
    /// Horizontal `ScrollView` ignores the scroll-axis safe area, so Duo's
    /// vertical side rail otherwise covers the first and last cards. This
    /// adds independent `safeAreaInsets.left` / `.right` on top of
    /// `homeUpdatesCarouselBaseHorizontalPadding`.
    ///
    /// When those insets are zero, the result is 16pt on both sides and
    /// non-Duo phone/iPad layout is unchanged. Do not assume left == right.
    static func homeUpdatesCarouselContentInsets(
        safeAreaInsets: UIEdgeInsets
    ) -> UIEdgeInsets {
        overlayChromeHorizontalInsets(
            base: homeUpdatesCarouselBaseHorizontalPadding,
            safeAreaInsets: safeAreaInsets
        )
    }

    /// Snapshot of an iOS 27.1 `ReservedRegion` that unit tests can construct
    /// without the 27.1 SwiftUI types. `frame` is the reserved rect in the
    /// container; `margins` is extra clearance around that rect.
    struct osrsReservedRegionSnapshot: Equatable {
        var frame: CGRect
        var margins: UIEdgeInsets
        var isActive: Bool

        var paddedFrame: CGRect {
            CGRect(
                x: frame.minX - margins.left,
                y: frame.minY - margins.top,
                width: max(0, frame.width + margins.left + margins.right),
                height: max(0, frame.height + margins.top + margins.bottom)
            )
        }
    }

    /// Extra overlay padding so custom chrome clears edge-hugging reserved
    /// regions (active camera occlusions). Interior divisions — the fold when
    /// the device is partially open — do **not** displace the overlay as a
    /// whole. Same rule as article scroll: do not reflow solely for the fold.
    ///
    /// Leading/trailing rails are already handled by window `safeAreaInsets`
    /// (`overlayChromeHorizontalInsets`). Pass those as `alreadyAccounted` so
    /// a vertical-bar occlusion does not double-inset.
    ///
    /// Empty / inactive / zero-size regions yield `.zero` — typical iPhone
    /// portrait and iPad stay unchanged.
    static func overlayEdgeInsetsAvoidingReservedRegions(
        containerSize: CGSize,
        regions: [osrsReservedRegionSnapshot],
        alreadyAccounted: UIEdgeInsets = .zero,
        edgeBand: CGFloat = 80
    ) -> UIEdgeInsets {
        guard containerSize.width > 1, containerSize.height > 1 else { return .zero }
        var raw = UIEdgeInsets.zero
        for region in regions where region.isActive {
            let padded = region.paddedFrame
            guard padded.width > 0, padded.height > 0 else { continue }

            let hugsLeading = padded.minX <= edgeBand
            let hugsTrailing = padded.maxX >= containerSize.width - edgeBand
            let hugsTop = padded.minY <= edgeBand
            let hugsBottom = padded.maxY >= containerSize.height - edgeBand

            // Full-span bands (center fold, full-width hinge) hug both opposite
            // edges. Skip those so continuous canvases are not split.
            if hugsLeading && !hugsTrailing {
                raw.left = max(raw.left, max(0, padded.maxX))
            }
            if hugsTrailing && !hugsLeading {
                raw.right = max(raw.right, max(0, containerSize.width - padded.minX))
            }
            if hugsTop && !hugsBottom {
                raw.top = max(raw.top, max(0, padded.maxY))
            }
            if hugsBottom && !hugsTop {
                raw.bottom = max(raw.bottom, max(0, containerSize.height - padded.minY))
            }
        }
        return UIEdgeInsets(
            top: max(0, raw.top - alreadyAccounted.top),
            left: max(0, raw.left - alreadyAccounted.left),
            bottom: max(0, raw.bottom - alreadyAccounted.bottom),
            right: max(0, raw.right - alreadyAccounted.right)
        )
    }

    static func accessibilityCardWidth(
        isAccessibilitySize: Bool,
        containerWidth: CGFloat,
        standardWidth: CGFloat,
        horizontalInset: CGFloat = 32,
        maxWidth: CGFloat = 398
    ) -> CGFloat {
        guard isAccessibilitySize else { return standardWidth }
        let usable = containerWidth > 1 ? containerWidth : currentSize.width
        return min(max(usable - horizontalInset, 1), maxWidth)
    }

    static func fallbackViewport(viewSize: CGSize, fallback: CGSize) -> CGSize {
        CGSize(
            width: viewSize.width > 0 ? viewSize.width : fallback.width,
            height: viewSize.height > 0 ? viewSize.height : fallback.height
        )
    }

    private static func isUsable(_ size: CGSize) -> Bool {
        size.width > 1 && size.height > 1 && size.width.isFinite && size.height.isFinite
    }

    private static func connectedWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

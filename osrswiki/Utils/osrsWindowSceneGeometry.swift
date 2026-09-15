import UIKit

/// Window-scene geometry for layout, scale, and ProMotion.
///
/// `UIScreen.main` is ambiguous on a two-display device and is the layout
/// footgun Apple flags for iPhone Duo / resizable iPhone. Prefer the attached
/// window, then `UIWindowScene.coordinateSpace.bounds`, then a documented
/// last-resort fallback. This helper compiles on the current SDK (iOS 18.5 /
/// Xcode 16.4 project; Mac builds today use Xcode 26.x).
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

import UIKit
import WebKit

/// Opaque tab/article parchment behind SwiftUI. Must not composite over a
/// still-valid article WK (Find, Name, search keyboard, resign-active).
/// True background resume still mints `osrsResumeCoverWindow` last-good.
@MainActor
enum osrsHostThemeFill {
    static func shouldPaintOpaqueFill(liveArticleWebViewPresent: Bool) -> Bool {
        !liveArticleWebViewPresent
    }

    static func opaqueBackgroundColor(
        themeBackground: UIColor,
        liveArticleWebViewPresent: Bool
    ) -> UIColor {
        shouldPaintOpaqueFill(liveArticleWebViewPresent: liveArticleWebViewPresent)
            ? themeBackground
            : .clear
    }

    static func apply(to window: UIWindow, themeBackground: UIColor) {
        guard osrsSceneCompositor.isAppContentWindow(window) else {
            // TF42 whole-page fill (cycle 49): UIKit's UITextEffectsWindow is
            // a full-screen window above the scene window, created the moment
            // a text field takes first responder (Find, search, Name).
            // Painting it opaque theme fill blanks the whole page behind the
            // keyboard. Never paint non-app-content windows; clear any fill a
            // pre-guard pass left behind.
            restoreSystemWindow(window, theme: themeBackground)
            return
        }
        let live = osrsSceneCompositor.containsLiveArticleWebView(window)
        let color = opaqueBackgroundColor(
            themeBackground: themeBackground,
            liveArticleWebViewPresent: live
        )
        window.backgroundColor = color
        window.isOpaque = shouldPaintOpaqueFill(liveArticleWebViewPresent: live)
        paint(window.rootViewController, color: color)
        if live {
            clearParkedWebViewFill(window)
            clearThemeColoredHostViews(window, theme: themeBackground)
        }
    }

    private static func clearParkedWebViewFill(_ view: UIView) {
        if osrsSceneCompositor.containsLiveArticleWebView(view),
           let webView = view as? WKWebView {
            // Keep theme parchment on a loaded article. Forcing under-page /
            // background / scrollView to clear is the Find black compositor
            // (Phase A). Type-1 fill was UITextEffectsWindow, not this WK.
            webView.isOpaque = false
            webView.scrollView.isOpaque = false
        }
        for child in view.subviews {
            clearParkedWebViewFill(child)
        }
    }

    /// SwiftUI/UIKit parchment on hosting views still composites over a live
    /// WK after Find/keyboard parks GPU tiles. Clear matching fills; do not
    /// nil `WKWebView.layer.contents`.
    private static func clearThemeColoredHostViews(_ view: UIView, theme: UIColor) {
        if view is WKWebView {
            return
        }
        if !(view is UIImageView), isThemeFill(view.backgroundColor, theme: theme) {
            view.backgroundColor = .clear
            view.isOpaque = false
        }
        if let layerColor = view.layer.backgroundColor,
           isThemeFill(UIColor(cgColor: layerColor), theme: theme) {
            view.layer.backgroundColor = UIColor.clear.cgColor
        }
        for child in view.subviews {
            clearThemeColoredHostViews(child, theme: theme)
        }
    }

    private static func isThemeFill(_ color: UIColor?, theme: UIColor) -> Bool {
        guard let color else { return false }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var themeRed: CGFloat = 0, themeGreen: CGFloat = 0, themeBlue: CGFloat = 0, themeAlpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              theme.getRed(&themeRed, green: &themeGreen, blue: &themeBlue, alpha: &themeAlpha) else {
            return false
        }
        return alpha > 0.5
            && abs(red - themeRed) < 0.03
            && abs(green - themeGreen) < 0.03
            && abs(blue - themeBlue) < 0.03
    }

    static func applyToAppWindows(themeBackground: UIColor) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { apply(to: $0, themeBackground: themeBackground) }
    }

    private static func restoreSystemWindow(_ window: UIWindow, theme: UIColor) {
        if isThemeFill(window.backgroundColor, theme: theme) {
            window.backgroundColor = nil
            window.isOpaque = false
        }
        if let root = window.rootViewController,
           isThemeFill(root.view.backgroundColor, theme: theme) {
            root.view.backgroundColor = nil
            root.view.isOpaque = false
        }
    }

    private static func paint(_ controller: UIViewController?, color: UIColor) {
        guard let controller else { return }
        controller.view.backgroundColor = color
        controller.view.isOpaque = color.cgColor.alpha > 0.01
        for child in controller.children {
            paint(child, color: color)
        }
    }
}

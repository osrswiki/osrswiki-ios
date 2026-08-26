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
        }
    }

    private static func clearParkedWebViewFill(_ view: UIView) {
        if osrsSceneCompositor.containsLiveArticleWebView(view),
           let webView = view as? WKWebView {
            webView.isOpaque = false
            webView.backgroundColor = UIColor.clear
            webView.underPageBackgroundColor = UIColor.clear
            webView.scrollView.isOpaque = false
            webView.scrollView.backgroundColor = UIColor.clear
        }
        for child in view.subviews {
            clearParkedWebViewFill(child)
        }
    }

    static func applyToAppWindows(themeBackground: UIColor) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { apply(to: $0, themeBackground: themeBackground) }
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

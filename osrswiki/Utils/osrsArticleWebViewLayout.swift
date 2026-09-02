import CoreGraphics
import Foundation

/// WKWebView has no intrinsic size. iPad `NavigationStack` / `TabView` can
/// propose unspecified or zero height, which collapses the article body to
/// empty parchment while overlay chrome still paints.
enum osrsArticleWebViewLayout {
    static func resolvedSize(
        proposedWidth: CGFloat?,
        proposedHeight: CGFloat?,
        windowSize: CGSize
    ) -> CGSize {
        CGSize(
            width: usable(proposedWidth) ?? fallback(windowSize.width),
            height: usable(proposedHeight) ?? fallback(windowSize.height)
        )
    }

    static func isUsableArticleFrame(_ size: CGSize) -> Bool {
        size.width > 1 && size.height > 1
    }

    private static func usable(_ value: CGFloat?) -> CGFloat? {
        guard let value, value.isFinite, value > 1 else { return nil }
        return value
    }

    private static func fallback(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 1 ? value : 1
    }
}

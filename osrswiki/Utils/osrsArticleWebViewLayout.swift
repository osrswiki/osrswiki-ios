import CoreGraphics
import Foundation
import UIKit

/// WKWebView has no intrinsic size. iPad `NavigationStack` / `TabView` can
/// propose unspecified or zero height, which collapses the article body to
/// empty parchment while overlay chrome still paints.
///
/// A non-zero frame is not enough. Creating the view at `.zero` and loading a
/// themed placeholder HTML commits empty-parchment GPU tiles; iOS 26 then
/// delays `_updateVisibleContentRects` across the later live-resize and leaves
/// those tiles on screen after the real article DOM has already settled.
enum osrsArticleWebViewLayout {
    static let minimumUsableDimension: CGFloat = 80

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
        size.width > minimumUsableDimension && size.height > minimumUsableDimension
    }

    static func initialFrame(windowSize: CGSize = UIScreen.main.bounds.size) -> CGRect {
        CGRect(origin: .zero, size: resolvedSize(
            proposedWidth: nil,
            proposedHeight: nil,
            windowSize: windowSize
        ))
    }

    static func didBecomeUsable(previous: CGSize, next: CGSize) -> Bool {
        !isUsableArticleFrame(previous) && isUsableArticleFrame(next)
    }

    private static func usable(_ value: CGFloat?) -> CGFloat? {
        guard let value, value.isFinite, value > minimumUsableDimension else { return nil }
        return value
    }

    private static func fallback(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > minimumUsableDimension ? value : minimumUsableDimension
    }
}

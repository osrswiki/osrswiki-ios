import UIKit
import WebKit

/// Restores article WKScrollView chrome after UIRefreshControl settles.
/// CSS already bakes `--osrs-article-safe-area-top` + chrome clearance into
/// document padding, so a leftover native top inset or a parked negative
/// offset shows up as an empty band above the title.
enum osrsArticleRefreshSettlement {
    static let layoutEpsilon: CGFloat = 1.5

    struct Snapshot: Equatable {
        var contentInset: UIEdgeInsets
        var adjustedContentInset: UIEdgeInsets
        var contentOffset: CGPoint
        var titleDocumentY: CGFloat
        var titleViewportY: CGFloat
    }

    static func configure(_ scrollView: UIScrollView) {
        scrollView.bounces = true
        // CSS already bakes safe-area + overlay chrome into html padding.
        // `.always` lets UIRefreshControl rest at -adjustedContentInset.top
        // after PTR, which is an empty band above the title on iOS 26.
        scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 26.0, *) {
            scrollView.contentInset.bottom = 0
            scrollView.verticalScrollIndicatorInsets.bottom = 0
        } else {
            scrollView.contentInset.bottom = 64
            scrollView.verticalScrollIndicatorInsets.bottom = 64
        }
    }

    static func snapshot(
        from scrollView: UIScrollView,
        titleDocumentY: CGFloat = 0,
        titleViewportY: CGFloat = 0
    ) -> Snapshot {
        Snapshot(
            contentInset: scrollView.contentInset,
            adjustedContentInset: scrollView.adjustedContentInset,
            contentOffset: scrollView.contentOffset,
            titleDocumentY: titleDocumentY,
            titleViewportY: titleViewportY
        )
    }

    static func matches(
        _ lhs: Snapshot,
        _ rhs: Snapshot,
        epsilon: CGFloat = layoutEpsilon
    ) -> Bool {
        insetsMatch(lhs.contentInset, rhs.contentInset, epsilon: epsilon)
            && insetsMatch(lhs.adjustedContentInset, rhs.adjustedContentInset, epsilon: epsilon)
            && abs(lhs.contentOffset.x - rhs.contentOffset.x) <= epsilon
            && abs(lhs.contentOffset.y - rhs.contentOffset.y) <= epsilon
            && abs(lhs.titleDocumentY - rhs.titleDocumentY) <= epsilon
            && abs(lhs.titleViewportY - rhs.titleViewportY) <= epsilon
    }

    /// Ends the refresh control and restores the fresh-open rest state:
    /// no leftover UIRefreshControl top inset, document origin at offset 0,
    /// and `window.scrollY = 0`. Reload can leave WebKit's JS scroll at the
    /// adjusted-inset value while UIKit `contentOffset.y` already reads 0,
    /// which either parks an empty band above the title or tucks the title
    /// under overlay chrome.
    @MainActor
    static func settle(_ webView: WKWebView) {
        applyImmediate(scrollView: webView.scrollView, webView: webView)
        reapplyAfterRefreshControlAnimation(scrollView: webView.scrollView, webView: webView)
    }

    @MainActor
    static func settle(_ scrollView: UIScrollView) {
        applyImmediate(scrollView: scrollView, webView: nil)
        reapplyAfterRefreshControlAnimation(scrollView: scrollView, webView: nil)
    }

    @MainActor
    private static func reapplyAfterRefreshControlAnimation(
        scrollView: UIScrollView,
        webView: WKWebView?
    ) {
        DispatchQueue.main.async {
            applyImmediate(scrollView: scrollView, webView: webView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            applyImmediate(scrollView: scrollView, webView: webView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            applyImmediate(scrollView: scrollView, webView: webView)
        }
    }

    @MainActor
    private static func applyImmediate(scrollView: UIScrollView, webView: WKWebView?) {
        configure(scrollView)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollView.refreshControl?.endRefreshing()
        var inset = scrollView.contentInset
        inset.top = 0
        scrollView.contentInset = inset
        if scrollView.contentOffset.y <= layoutEpsilon {
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: 0),
                animated: false
            )
        }
        CATransaction.commit()
        scrollView.layoutIfNeeded()
        webView?.evaluateJavaScript(
            "window.scrollTo(0, 0); document.documentElement.scrollTop = 0; if (document.body) document.body.scrollTop = 0;"
        ) { _, _ in
            if scrollView.contentOffset.y <= layoutEpsilon {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: 0),
                    animated: false
                )
            }
        }
    }

    private static func insetsMatch(
        _ lhs: UIEdgeInsets,
        _ rhs: UIEdgeInsets,
        epsilon: CGFloat
    ) -> Bool {
        abs(lhs.top - rhs.top) <= epsilon
            && abs(lhs.left - rhs.left) <= epsilon
            && abs(lhs.bottom - rhs.bottom) <= epsilon
            && abs(lhs.right - rhs.right) <= epsilon
    }
}

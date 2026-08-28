import os
import UIKit
import WebKit

enum osrsWebViewThemePaint {
    private static let logger = Logger(
        subsystem: "com.omiyawaki.osrswiki",
        category: "ARTICLEVIEW"
    )

    /// Unpainted WK compositor is system white. Uniform dark/parchment is a
    /// healthy themed article or first-paint, not a parked blank.
    static func isUnpaintedSystemFill(
        minLuminance: Int,
        maxLuminance: Int,
        meanLuminance: Int
    ) -> Bool {
        meanLuminance >= 220 && (maxLuminance - minLuminance) < 40
    }

    /// A WKWebView snapshot with no contrast is a parked layer tree, even
    /// when the fill is the theme color rather than system white.
    static func isUniformFill(
        minLuminance: Int,
        maxLuminance: Int
    ) -> Bool {
        (maxLuminance - minLuminance) < 16
    }

    static func isUnpaintedSystemFill(_ image: UIImage?) -> Bool {
        guard let stats = luminanceStats(image) else { return true }
        return isUnpaintedSystemFill(
            minLuminance: stats.min,
            maxLuminance: stats.max,
            meanLuminance: stats.mean
        )
    }

    static func isUniformFill(_ image: UIImage?) -> Bool {
        guard let stats = luminanceStats(image) else { return true }
        return isUniformFill(minLuminance: stats.min, maxLuminance: stats.max)
    }

    static func luminanceRange(_ image: UIImage?) -> Int {
        guard let stats = luminanceStats(image) else { return 0 }
        return stats.max - stats.min
    }

    static func luminanceStats(_ image: UIImage?) -> (min: Int, max: Int, mean: Int)? {
        guard let image else { return nil }
        let sample = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(sample, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: sample))
        guard let tiny = UIGraphicsGetImageFromCurrentImageContext()?.cgImage,
              let data = tiny.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let count = tiny.width * tiny.height
        guard count > 0 else { return nil }
        var minLuminance = 255
        var maxLuminance = 0
        var total = 0
        for index in 0..<count {
            let offset = index * 4
            let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
            total += luminance
        }
        return (minLuminance, maxLuminance, total / count)
    }

    @MainActor
    static func apply(to webView: WKWebView, theme: any osrsThemeProtocol) {
        let pageColor = UIColor(theme.background)
        // Type-1 whole-page fill was UITextEffectsWindow (C49), not WK
        // under-page. Isolating a loaded article to clear left black
        // compositor after C53 stopped last-good pin. Keep theme parchment
        // behind live tiles for Find/search/Name and first paint alike.
        let compositorFill = pageColor
        webView.underPageBackgroundColor = compositorFill
        webView.backgroundColor = compositorFill
        webView.scrollView.backgroundColor = compositorFill
        webView.isOpaque = false
        webView.scrollView.isOpaque = false
        paintViewTree(webView, root: webView, color: compositorFill)
    }

    static var keepCompositorAliveScript: String {
        """
        (function(){
          if (window.__osrsKeepAlive) return 'keep=alive';
          window.__osrsKeepAlive = true;
          var st = document.createElement('style');
          st.id = 'osrs-compositor-keep-alive-style';
          st.textContent = '@keyframes osrsKeepAlive{from{transform:translate3d(0,0,0)}to{transform:translate3d(0,0,1px)}}';
          (document.head || document.documentElement).appendChild(st);
          var el = document.createElement('div');
          el.id = 'osrs-compositor-keep-alive';
          el.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;pointer-events:none;will-change:transform;animation:osrsKeepAlive 0.4s linear infinite;';
          (document.documentElement || document.body).appendChild(el);
          function tick(){
            if (!window.__osrsKeepAlive) return;
            el.style.transform = 'translateZ(' + ((Date.now() % 2) * 0.01) + 'px)';
            requestAnimationFrame(tick);
          }
          requestAnimationFrame(tick);
          return 'keep=alive';
        })();
        """
    }

    /// Tiny themed document so WKWebView's compositor is not the system-white
    /// default while paint HTML / parse HTML is still on its way.
    static func placeholderHTML(theme: any osrsThemeProtocol) -> String {
        let isDark = theme is osrsDarkTheme
        let background = isDark ? "#28221d" : "#e2dbc8"
        let foreground = isDark ? "#f4eaea" : "#000000"
        let themeClass = isDark ? " theme-osrs-dark" : ""
        return """
        <!doctype html><html class="\(themeClass.trimmingCharacters(in: .whitespaces))"><head>\
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">\
        <style>html,body{background:\(background)!important;color:\(foreground)!important;margin:0;min-height:100vh;}</style>\
        </head><body></body></html>
        """
    }

    static func documentStartPaintScript(theme: any osrsThemeProtocol) -> String {
        let isDark = theme is osrsDarkTheme
        let background = isDark ? "#28221d" : "#e2dbc8"
        let foreground = isDark ? "#f4eaea" : "#000000"
        return """
        (function(){
          var root = document.documentElement;
          if (!root) return;
          root.style.backgroundColor = '\(background)';
          root.style.color = '\(foreground)';
          if (document.body) {
            document.body.style.backgroundColor = '\(background)';
            document.body.style.color = '\(foreground)';
          }
        })();
        """
    }

    @MainActor
    static func loadPlaceholderIfEmpty(in webView: WKWebView, theme: any osrsThemeProtocol) {
        apply(to: webView, theme: theme)
        let current = webView.url?.absoluteString
        if current == nil || current == "about:blank" {
            webView.loadHTMLString(placeholderHTML(theme: theme), baseURL: nil)
        }
    }

    @MainActor
    private static func paintViewTree(_ view: UIView, root: WKWebView, color: UIColor) {
        let name = NSStringFromClass(type(of: view))
        let isWebKitSurface = name.contains("Compositing") || name.contains("WKContent")
        // WebKit-internal scroll views (WKChildScrollView composited-overflow
        // scrollports) host scrolled web content whose alpha intentionally
        // reveals WebKit's own page tile below. An app opaque fill there
        // covers the correctly painted tile — device-proven as the
        // Uncharged-left parchment band (gutter spec Phase 16,
        // gutterDeepestParchment=WKChildScrollView bg=theme parchment). Only
        // the WKWebView's own top-level scrollView keeps the theme underlay;
        // every other scroll view in the WK subtree stays unpainted (nil, the
        // WebKit default), and a previously painted one is healed back to nil.
        let isForeignScroller = view is UIScrollView && view !== root.scrollView
        if isWebKitSurface || isForeignScroller {
            view.isOpaque = false
            view.backgroundColor = isForeignScroller ? nil : .clear
        } else {
            view.backgroundColor = color
            let transparent = color.cgColor.alpha < 0.05
            view.isOpaque = !transparent && !(view is WKWebView || view is UIScrollView)
        }
        view.subviews.forEach { paintViewTree($0, root: root, color: color) }
    }

    @MainActor
    static func apply(to webView: WKWebView, usesDarkTheme: Bool) {
        apply(to: webView, theme: usesDarkTheme ? osrsDarkTheme() : osrsLightTheme())
    }

    @MainActor
    static func noteWebContentProcessTerminated(_ webView: WKWebView, theme: (any osrsThemeProtocol)? = nil) {
        let message = "Web content process terminated; recovering article document"
        NSLog("⚠️ ARTICLEVIEW: %@", message)
        logger.error("\(message, privacy: .public)")
        if let theme {
            apply(to: webView, theme: theme)
        }
    }
}

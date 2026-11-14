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
        let size = image.size
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            return nil
        }
        guard let cgImage = image.cgImage else { return nil }
        return luminanceStats(cgImage)
    }

    /// Sample CPU-readable pixels only. App Store 2.1.0 (67) crashed in
    /// `vConvert_PermuteChannels_ARGB8888_CV_vec` when `UIImage.draw` converted
    /// a WKWebView takeSnapshot (CVPixelBuffer / HDR) into a 16×16 RGB context.
    /// Default UIGraphicsImageRenderer output on P3 is 16-bit half-float
    /// (bitmapInfo 0x1101, kCGColorSpaceExtendedSRGB); 8-bit-only sampling made
    /// every compositor snapshot look like a uniform fill.
    static func luminanceStats(_ image: CGImage) -> (min: Int, max: Int, mean: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bitsPerComponent = image.bitsPerComponent
        guard bitsPerComponent == 8 || bitsPerComponent == 16 || bitsPerComponent == 32 else {
            return nil
        }
        let bitsPerPixel = image.bitsPerPixel
        guard bitsPerPixel > 0, bitsPerPixel % 8 == 0 else { return nil }
        let bytesPerComponent = bitsPerComponent / 8
        let bytesPerPixel = bitsPerPixel / 8
        guard bytesPerComponent > 0, bytesPerPixel > 0, bytesPerPixel % bytesPerComponent == 0 else {
            return nil
        }
        let channelCount = bytesPerPixel / bytesPerComponent
        guard channelCount == 1 || channelCount == 3 || channelCount == 4 else { return nil }

        let bytesPerRow = image.bytesPerRow
        guard bytesPerRow >= width * bytesPerPixel else { return nil }
        guard let data = image.dataProvider?.data else { return nil }
        let length = CFDataGetLength(data)
        guard length > 0,
              let bytes = CFDataGetBytePtr(data),
              length >= (height - 1) * bytesPerRow + width * bytesPerPixel else {
            return nil
        }

        let bitmapInfo = image.bitmapInfo
        let isFloat = bitmapInfo.contains(.floatComponents)
        let byteOrder = bitmapInfo.intersection(.byteOrderMask)
        let littleEndian = osrsComponentBytesAreLittleEndian(
            byteOrder: byteOrder,
            isFloat: isFloat
        )
        guard let channels = osrsColorChannelIndices(
            channelCount: channelCount,
            alphaInfo: image.alphaInfo,
            byteOrder: byteOrder,
            bitsPerComponent: bitsPerComponent
        ) else {
            return nil
        }
        let lastChannel = max(channels.r, channels.g, channels.b)
        guard lastChannel < channelCount else { return nil }

        let gridX = min(16, width)
        let gridY = min(16, height)
        var minLuminance = 255
        var maxLuminance = 0
        var total = 0
        var count = 0
        for cellRow in 0..<gridY {
            let y0 = cellRow * height / gridY
            let y1 = (cellRow + 1) * height / gridY
            let cellHeight = max(1, y1 - y0)
            let stepY = max(1, cellHeight / 8)
            for cellColumn in 0..<gridX {
                let x0 = cellColumn * width / gridX
                let x1 = (cellColumn + 1) * width / gridX
                let cellWidth = max(1, x1 - x0)
                let stepX = max(1, cellWidth / 8)
                var cellTotal = 0
                var cellCount = 0
                var y = y0
                while y < y1 {
                    var x = x0
                    while x < x1 {
                        let pixelOffset = y * bytesPerRow + x * bytesPerPixel
                        if let luminance = osrsLuminanceByte(
                            bytes: bytes,
                            length: length,
                            pixelOffset: pixelOffset,
                            bytesPerComponent: bytesPerComponent,
                            channels: channels,
                            bitsPerComponent: bitsPerComponent,
                            isFloat: isFloat,
                            littleEndian: littleEndian
                        ) {
                            cellTotal += luminance
                            cellCount += 1
                        }
                        x += stepX
                    }
                    y += stepY
                }
                guard cellCount > 0 else { continue }
                let cellMean = cellTotal / cellCount
                minLuminance = min(minLuminance, cellMean)
                maxLuminance = max(maxLuminance, cellMean)
                total += cellMean
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (minLuminance, maxLuminance, total / count)
    }

    private static func osrsComponentBytesAreLittleEndian(
        byteOrder: CGBitmapInfo,
        isFloat: Bool
    ) -> Bool {
        if byteOrder == .byteOrder16Little || byteOrder == .byteOrder32Little {
            return true
        }
        if byteOrder == .byteOrder16Big || byteOrder == .byteOrder32Big {
            return false
        }
        // Default integer CG bitmaps are historically big-endian; float
        // snapshots on iOS (half-float P3 renderer) are host/little-endian.
        return isFloat
    }

    /// Component indices of R, G, B in memory. premulFirst + byteOrder32Little
    /// is BGRA, not ARGB.
    private static func osrsColorChannelIndices(
        channelCount: Int,
        alphaInfo: CGImageAlphaInfo,
        byteOrder: CGBitmapInfo,
        bitsPerComponent: Int
    ) -> (r: Int, g: Int, b: Int)? {
        if channelCount == 1 {
            return (0, 0, 0)
        }
        if channelCount == 3 {
            return (0, 1, 2)
        }
        guard channelCount == 4 else { return nil }

        let alphaFirst: Bool
        switch alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            alphaFirst = true
        default:
            alphaFirst = false
        }

        let swap32Little = bitsPerComponent == 8 && byteOrder == .byteOrder32Little
        if swap32Little {
            // Conceptual ARGB stored as a little-endian 32-bit word is BGRA.
            // Conceptual RGBA stored that way is ABGR.
            return alphaFirst ? (2, 1, 0) : (3, 2, 1)
        }
        return alphaFirst ? (1, 2, 3) : (0, 1, 2)
    }

    private static func osrsLuminanceByte(
        bytes: UnsafePointer<UInt8>,
        length: Int,
        pixelOffset: Int,
        bytesPerComponent: Int,
        channels: (r: Int, g: Int, b: Int),
        bitsPerComponent: Int,
        isFloat: Bool,
        littleEndian: Bool
    ) -> Int? {
        let lastOffset = pixelOffset + max(channels.r, channels.g, channels.b) * bytesPerComponent
        guard pixelOffset >= 0, lastOffset + bytesPerComponent <= length else {
            return nil
        }
        func sample(_ componentIndex: Int) -> Int? {
            osrsNormalizedChannelByte(
                bytes: bytes,
                offset: pixelOffset + componentIndex * bytesPerComponent,
                bitsPerComponent: bitsPerComponent,
                isFloat: isFloat,
                littleEndian: littleEndian
            )
        }
        if channels.r == channels.g && channels.g == channels.b {
            return sample(channels.r)
        }
        guard let red = sample(channels.r),
              let green = sample(channels.g),
              let blue = sample(channels.b) else {
            return nil
        }
        return (red + green + blue) / 3
    }

    private static func osrsNormalizedChannelByte(
        bytes: UnsafePointer<UInt8>,
        offset: Int,
        bitsPerComponent: Int,
        isFloat: Bool,
        littleEndian: Bool
    ) -> Int? {
        if isFloat {
            let value: Float
            if bitsPerComponent == 16 {
                let bits = osrsReadUInt16(bytes, offset: offset, littleEndian: littleEndian)
                value = Float(Float16(bitPattern: bits))
            } else if bitsPerComponent == 32 {
                let bits = osrsReadUInt32(bytes, offset: offset, littleEndian: littleEndian)
                value = Float(bitPattern: bits)
            } else {
                return nil
            }
            let clamped = value.isFinite ? min(max(value, 0), 1) : 0
            return Int(clamped * 255.0)
        }
        if bitsPerComponent == 8 {
            return Int(bytes[offset])
        }
        if bitsPerComponent == 16 {
            let raw = Float(osrsReadUInt16(bytes, offset: offset, littleEndian: littleEndian)) / 65535.0
            return Int(min(max(raw, 0), 1) * 255.0)
        }
        if bitsPerComponent == 32 {
            let raw = Float(osrsReadUInt32(bytes, offset: offset, littleEndian: littleEndian))
                / Float(UInt32.max)
            return Int(min(max(raw, 0), 1) * 255.0)
        }
        return nil
    }

    private static func osrsReadUInt16(
        _ bytes: UnsafePointer<UInt8>,
        offset: Int,
        littleEndian: Bool
    ) -> UInt16 {
        let b0 = UInt16(bytes[offset])
        let b1 = UInt16(bytes[offset + 1])
        return littleEndian ? b0 | (b1 << 8) : (b0 << 8) | b1
    }

    private static func osrsReadUInt32(
        _ bytes: UnsafePointer<UInt8>,
        offset: Int,
        littleEndian: Bool
    ) -> UInt32 {
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1])
        let b2 = UInt32(bytes[offset + 2])
        let b3 = UInt32(bytes[offset + 3])
        if littleEndian {
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
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
        // every other view in the WK subtree stays unpainted (nil, the
        // WebKit default). iPad dumps showed anonymous UIViews at the full
        // document size (820x38352 opaque parchment) covering GPU tiles.
        let isForeignScroller = view is UIScrollView && view !== root.scrollView
        let isInternalWKView = view !== root && view !== root.scrollView
        if isWebKitSurface || isForeignScroller || isInternalWKView {
            view.isOpaque = false
            view.backgroundColor = (isForeignScroller || isInternalWKView) ? nil : .clear
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

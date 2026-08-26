#if DEBUG
import UIKit
import WebKit

/// Same-second dump for the TF 41 whole-page fill. Logging only. Do not
/// change compositor, WK, or layer.contents.
@MainActor
enum osrsBlankViewFirstResponderDump {
    private static var lastReason: String = ""
    private static var lastStamp: TimeInterval = 0

    static func capture(reason: String) {
        emit(reason: reason + "+0")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            emit(reason: reason + "+80ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            emit(reason: reason + "+250ms")
        }
    }

    private static func emit(reason: String) {
        let now = Date().timeIntervalSince1970
        if reason == lastReason, now - lastStamp < 0.03 {
            return
        }
        lastReason = reason
        lastStamp = now

        var lines: [String] = []
        lines.append("osrsBlankFR reason=\(reason) t=\(now)")
        lines.append(
            "cover passthrough=\(osrsResumeFrameOverlay.isPassthroughInstalled) adopted=\(osrsResumeFrameOverlay.hasAdoptedLiveRoot) hasFrame=\(osrsResumeFrameOverlay.hasCapturedFrame)"
        )

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var windows: [UIWindow] = []
        for scene in scenes {
            windows.append(contentsOf: scene.windows)
        }
        lines.append("scenes=\(scenes.count) windows=\(windows.count)")

        var tabBars: [String] = []
        var webs: [WKWebView] = []
        for window in windows {
            let level = window.windowLevel.rawValue
            let kind = NSStringFromClass(type(of: window))
            lines.append(
                "window \(kind) key=\(window.isKeyWindow) hidden=\(window.isHidden) alpha=\(String(format: "%.2f", window.alpha)) level=\(level) frame=\(fmt(window.frame))"
            )
            collect(in: window, tabBars: &tabBars, webs: &webs)
            let points = [
                CGPoint(x: window.bounds.midX, y: 80),
                CGPoint(x: window.bounds.midX, y: window.bounds.midY * 0.35),
                CGPoint(x: window.bounds.midX, y: window.bounds.midY),
            ]
            for point in points {
                let hit = window.hitTest(point, with: nil)
                let hitName = hit.map { NSStringFromClass(type(of: $0)) } ?? "nil"
                lines.append(
                    "hit \(kind) (\(Int(point.x)),\(Int(point.y))) -> \(hitName) hidden=\(hit?.isHidden ?? true) alpha=\(String(format: "%.2f", hit?.alpha ?? -1))"
                )
            }
            if window.isKeyWindow || window is osrsResumeCoverWindow {
                osrsSceneCompositor.dumpWindow(window)
            }
        }
        lines.append("tabBars: \(tabBars.isEmpty ? "none" : tabBars.joined(separator: " | "))")

        if let responder = findFirstResponder() {
            lines.append("firstResponder=\(NSStringFromClass(type(of: responder)))")
        } else {
            lines.append("firstResponder=nil")
        }

        for web in webs {
            let scroll = web.scrollView
            lines.append(
                "WK \(fmt(web.frame)) hidden=\(web.isHidden) alpha=\(String(format: "%.2f", web.alpha)) opaque=\(web.isOpaque) insetAdj=\(scroll.contentInsetAdjustmentBehavior.rawValue) contentInset=\(inset(scroll.contentInset)) adjusted=\(inset(scroll.adjustedContentInset)) offset=\(Int(scroll.contentOffset.y))"
            )
            web.evaluateJavaScript(viewportScript) { result, error in
                let js = (result as? String) ?? String(describing: error)
                NSLog("osrsBlankFR js %@", js)
                print("osrsBlankFR js \(js)")
            }
        }

        let text = lines.joined(separator: "\n")
        NSLog("osrsBlankFR\n%@", text)
        print("osrsBlankFR\n\(text)")
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent("osrs-blank-fr-dump.txt")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func collect(in view: UIView, tabBars: inout [String], webs: inout [WKWebView]) {
        if let tab = view as? UITabBar {
            tabBars.append(
                "alpha=\(String(format: "%.2f", tab.alpha)) hidden=\(tab.isHidden) z=\(Int(tab.layer.zPosition)) frame=\(fmt(tab.frame))"
            )
        }
        if let web = view as? WKWebView, web.bounds.width > 8, web.bounds.height > 8 {
            webs.append(web)
        }
        for child in view.subviews {
            collect(in: child, tabBars: &tabBars, webs: &webs)
        }
    }

    private static func findFirstResponder() -> UIResponder? {
        var found: UIResponder?
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                found = firstResponder(in: window)
                if found != nil { return found }
            }
        }
        return found
    }

    private static func firstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let found = firstResponder(in: child) { return found }
        }
        return nil
    }

    private static func fmt(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }

    private static func inset(_ insets: UIEdgeInsets) -> String {
        "t\(Int(insets.top)),l\(Int(insets.left)),b\(Int(insets.bottom)),r\(Int(insets.right))"
    }

    private static let viewportScript = """
        (function() {
          var vv = window.visualViewport;
          return JSON.stringify({
            innerH: window.innerHeight,
            vvH: vv ? vv.height : null,
            closed: document.querySelectorAll('.collapsible-closed').length,
            collapsed: document.querySelectorAll('.collapsible-container.collapsed').length,
            title: document.title
          });
        })()
        """
}
#endif

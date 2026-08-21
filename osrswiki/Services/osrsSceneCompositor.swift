//
//  osrsSceneCompositor.swift
//  osrswiki
//
//  Resume recovery for the on-screen UIWindow / UIHostingController, not the
//  WKWebView document. A background snapshot on iOS 26 can leave the window
//  showing only `backgroundColor` (theme parchment) even while WebKit still
//  has a healthy DOM. Destroying SwiftUI identity or window subviews makes
//  that worse.
//

import UIKit
import WebKit

@MainActor
enum osrsSceneCompositor {
    static func restoreResumedScenes() {
        let windows = appContentWindows()
        print(
            "🪟 osrsSceneCompositor restore scenes=\(UIApplication.shared.connectedScenes.count) appWindows=\(windows.count) openSessions=\(UIApplication.shared.openSessions.count)"
        )
        pruneEmptyDuplicateSessions()
        for window in windows {
            restore(window)
        }
    }

    /// iOS 26 snapshots UIKitPlatformViewHost / TabView containers for the
    /// app switcher and can leave `layer.contents` as an opaque theme fill
    /// that hides live subviews. Do not clear WKWebView or image layers.
    static func clearFrozenHostSnapshots(in view: UIView) {
        if view is WKWebView || view is UIImageView {
            return
        }
        let name = NSStringFromClass(type(of: view))
        if isIntentionallyHiddenChrome(view) {
            for child in view.subviews {
                clearFrozenHostSnapshots(in: child)
            }
            return
        }
        let isHostContainer = name.contains("Hosting")
            || name.contains("PlatformView")
            || name.contains("UILayoutContainer")
            || name.contains("UITransitionView")
            || name.contains("DropShadow")
            || name.contains("UIViewControllerWrapper")
        if isHostContainer {
            view.layer.contents = nil
            view.isOpaque = false
            view.layer.shouldRasterize = false
            view.layer.setNeedsDisplay()
        }
        for child in view.subviews {
            clearFrozenHostSnapshots(in: child)
        }
    }

    /// Unhide live hosting views and drop shallow iOS snapshot overlays that
    /// sit on top of them. Do not delete a view that still hosts WKWebView or
    /// a deep SwiftUI tree.
    static func restore(_ window: UIWindow) {
        window.isHidden = false
        window.alpha = 1
        window.layer.contents = nil
        window.layer.shouldRasterize = false
        removeStaleSnapshotOverlays(from: window)
        if let root = window.rootViewController {
            root.view.isHidden = false
            root.view.alpha = 1
            removeStaleSnapshotOverlays(from: root.view)
            clearFrozenHostSnapshots(in: root.view)
            revealLiveViews(root.view)
            root.view.setNeedsLayout()
            root.view.layoutIfNeeded()
            clearFrozenHostSnapshots(in: root.view)
            nudgeLayer(root.view)
        }
        dumpWindow(window)
    }

    private static func appContentWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter(isAppContentWindow)
    }

    static func isAppContentWindow(_ window: UIWindow) -> Bool {
        let name = NSStringFromClass(type(of: window))
        if name.contains("TextEffects")
            || name.contains("Keyboard")
            || name.contains("StatusBar")
            || name.contains("EditingOverlay") {
            return false
        }
        if window is osrsResumedSceneWindow {
            return window.rootViewController != nil
        }
        return window.rootViewController != nil
    }

    static func osrsUnhideResumedHostViews(in window: UIWindow) {
        guard isAppContentWindow(window) else { return }
        restore(window)
    }

    private static func pruneEmptyDuplicateSessions() {
        let applicationSessions = UIApplication.shared.openSessions.filter {
            $0.role == .windowApplication
        }
        guard applicationSessions.count > 1 else { return }

        let ranked = applicationSessions.sorted { lhs, rhs in
            hierarchySize(for: lhs) > hierarchySize(for: rhs)
        }
        guard let keeper = ranked.first, hierarchySize(for: keeper) > 8 else { return }
        for session in ranked.dropFirst() where hierarchySize(for: session) <= 8 {
            print("🪟 osrsSceneCompositor destroying empty duplicate scene \(session.persistentIdentifier)")
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
        }
    }

    private static func hierarchySize(for session: UISceneSession) -> Int {
        guard let scene = session.scene as? UIWindowScene else { return 0 }
        return scene.windows.reduce(0) { $0 + descendantCount($1) }
    }

    private static func revealLiveViews(_ view: UIView) {
        if view is WKWebView {
            restoreOpaque(view)
            return
        }
        let name = NSStringFromClass(type(of: view))
        if isIntentionallyHiddenChrome(view) {
            return
        }
        let hostsWebKit = containsWebView(view)
        let shouldRestore = (hostsWebKit || name.contains("Hosting") || name.contains("PlatformView"))
            && descendantCount(view) > 8
        if shouldRestore {
            restoreOpaque(view)
        }
        for child in view.subviews {
            revealLiveViews(child)
        }
    }

    private static func restoreOpaque(_ view: UIView) {
        view.isHidden = false
        if view.alpha < 0.95 {
            view.alpha = 1
        }
        if view.layer.opacity < 0.95 {
            view.layer.opacity = 1
        }
    }

    private static func removeStaleSnapshotOverlays(from root: UIView) {
        for subview in root.subviews {
            if shouldRemoveSnapshotOverlay(subview) {
                let name = NSStringFromClass(type(of: subview))
                print("🪟 osrsSceneCompositor removing overlay \(name) descendants=\(descendantCount(subview)) alpha=\(subview.alpha)")
                subview.removeFromSuperview()
                continue
            }
            removeStaleSnapshotOverlays(from: subview)
        }
    }

    private static func shouldRemoveSnapshotOverlay(_ view: UIView) -> Bool {
        if isIntentionallyHiddenChrome(view) || containsWebView(view) {
            return false
        }
        let name = NSStringFromClass(type(of: view))
        let namedOverlay = name.localizedCaseInsensitiveContains("snapshot")
            || name.localizedCaseInsensitiveContains("replicant")
            || name.localizedCaseInsensitiveContains("portalcopy")
        let shallowCover = isFullScreenContent(view) && descendantCount(view) <= 6
        return namedOverlay && (descendantCount(view) <= 12 || shallowCover)
    }

    private static func isFullScreenContent(_ view: UIView) -> Bool {
        guard let window = view.window else { return false }
        let name = NSStringFromClass(type(of: view))
        if name.localizedCaseInsensitiveContains("TabBar") {
            return false
        }
        return view.bounds.width >= window.bounds.width * 0.9
            && view.bounds.height >= window.bounds.height * 0.45
    }

    private static func containsWebView(_ view: UIView) -> Bool {
        if view is WKWebView {
            return true
        }
        return view.subviews.contains { containsWebView($0) }
    }

    private static func isIntentionallyHiddenChrome(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.localizedCaseInsensitiveContains("TabBar")
            || name.localizedCaseInsensitiveContains("FloatingBar")
            || name.contains("_UIGraphicsView")
    }

    private static func nudgeLayer(_ view: UIView) {
        view.layer.setNeedsLayout()
        view.layer.setNeedsDisplay()
        view.layer.displayIfNeeded()
        let alpha = view.alpha
        view.alpha = min(1, max(0.99, alpha * 0.997))
        DispatchQueue.main.async {
            view.alpha = alpha
        }
    }

    private static func descendantCount(_ view: UIView) -> Int {
        view.subviews.reduce(1) { $0 + descendantCount($1) }
    }

    private static func windowLooksCompositorBlank(_ window: UIWindow) -> Bool {
        let bounds = window.bounds
        guard bounds.width > 16, bounds.height > 16 else { return false }
        let sample = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: sample)
        let image = renderer.image { _ in
            window.drawHierarchy(
                in: CGRect(origin: .zero, size: sample),
                afterScreenUpdates: false
            )
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
        }
        let count = cgImage.width * cgImage.height
        guard count > 0 else { return false }
        var minLuminance = 255
        var maxLuminance = 0
        for index in 0..<count {
            let offset = index * 4
            let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
        }
        return (maxLuminance - minLuminance) < 10
    }

    private static func dumpWindow(_ window: UIWindow) {
        var lines: [String] = []
        func walk(_ view: UIView, depth: Int) {
            let name = NSStringFromClass(type(of: view))
            let isWeb = view is WKWebView
            guard (depth < 14 || isWeb), lines.count < 180 else { return }
            let contents = view.layer.contents == nil ? "nil" : "set"
            lines.append(
                String(
                    repeating: "  ",
                    count: depth
                ) + "\(name) alpha=\(String(format: "%.2f", view.alpha)) hidden=\(view.isHidden) z=\(Int(view.layer.zPosition)) contents=\(contents) raster=\(view.layer.shouldRasterize) frame=\(Int(view.frame.minX)),\(Int(view.frame.minY)) \(Int(view.frame.width))x\(Int(view.frame.height)) desc=\(descendantCount(view))"
            )
            for child in view.subviews {
                walk(child, depth: depth + 1)
            }
        }
        walk(window, depth: 0)
        let text = lines.joined(separator: "\n")
        print("🪟 osrsSceneCompositor dump\n\(text)")
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("osrs-scene-dump.txt") {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

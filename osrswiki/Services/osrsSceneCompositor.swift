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

    /// iOS 26 snapshots UIKitPlatformViewHost / TabView / floating-bar
    /// containers. A *uniform* theme fill hides live subviews and should be
    /// dropped immediately. A high-contrast snapshot is the last painted
    /// article frame — keep it until WKWebView health recovers, then call
    /// `revealLiveArticleLayers`.
    static func clearFrozenHostSnapshots(in view: UIView, force: Bool = false) {
        if view is WKWebView || view is UIImageView {
            return
        }
        if isCapsuleTabBar(view) {
            for child in view.subviews {
                clearFrozenHostSnapshots(in: child, force: force)
            }
            return
        }
        let name = NSStringFromClass(type(of: view))
        let isHostContainer = name.contains("Hosting")
            || name.contains("PlatformView")
            || name.contains("UILayoutContainer")
            || name.contains("UITransitionView")
            || name.contains("DropShadow")
            || name.contains("UIViewControllerWrapper")
            || name.contains("FloatingBar")
            || name.contains("_UITabBarContainer")
            || name.contains("UIDropShadowView")
            || view.superview is UIWindow
        if isHostContainer || isFullScreenContent(view) {
            // iOS 26 parks an IOSurface in `layer.contents` on every host above
            // WKWebView. That surface is not always a CGImage, so a luminance
            // probe cannot see it. The live WebView (often 10k+ pt tall) is
            // already in the tree; the snapshot is what hides it.
            if force || containsWebView(view) || layerContentsLookUniform(view) {
                view.layer.contents = nil
                view.layer.shouldRasterize = false
                view.layer.setNeedsDisplay()
                view.layer.setNeedsLayout()
            }
        }
        for child in view.subviews {
            clearFrozenHostSnapshots(in: child, force: force)
        }
    }

    /// Drop remaining host snapshots after the article document is healthy
    /// so the live WKWebView and SwiftUI chrome are not stuck behind the
    /// last SpringBoard frame.
    static func revealLiveArticleLayers(from webView: WKWebView) {
        guard let window = webView.window ?? appContentWindows().first else { return }
        osrsResumeFrameOverlay.revealWhenLiveWebViewPaints(webView, window: window)
        print("🪟 osrsSceneCompositor revealed live article layers")
    }

    static func coverLayerLooksUniform(_ view: UIView) -> Bool {
        layerContentsLookUniform(view)
    }

    /// Unhide live hosting views and drop shallow iOS snapshot overlays that
    /// sit on top of them. Do not delete a view that still hosts WKWebView or
    /// a deep SwiftUI tree. IOSurface snapshots on host layers (often not a
    /// CGImage) hide the live article; strip them, then recommit HTML if the
    /// window is still a uniform theme fill.
    static func restore(_ window: UIWindow) {
        window.isHidden = false
        window.alpha = 1
        window.layer.shouldRasterize = false
        window.layer.contents = nil
        removeStaleSnapshotOverlays(from: window)
        if let root = window.rootViewController {
            root.view.isHidden = false
            root.view.alpha = 1
            removeStaleSnapshotOverlays(from: root.view)
            stripNonImageLayerContents(in: root.view)
            revealLiveViews(root.view)
            reparentWebViews(in: root.view)
            root.view.setNeedsLayout()
            root.view.layoutIfNeeded()
            root.view.layer.contents = nil
            // iOS 26 can composite the window layer (backgroundColor /
            // layer.contents) while child views never get another draw pass
            // (MAUI #35729, nevermeant.dev parked WebContent). Cover using
            // those window-layer paths; do not lift the cover just because
            // drawHierarchy still sees the live tree.
            osrsResumeFrameOverlay.install(on: window)
            if containsWebView(root.view) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard containsWebView(root.view) else { return }
                    osrsResumeFrameOverlay.install(on: window)
                    if windowLooksCompositorBlank(window) {
                        NotificationCenter.default.post(name: .osrsSceneCompositorLooksBlank, object: window)
                    }
                }
            }
        }
        dumpWindow(window)
    }

    static func captureResumeFrame(from window: UIWindow) {
        osrsResumeFrameOverlay.capture(from: window)
    }

    /// didMoveToWindow is what WKContentView uses to mark WebContent Visible.
    /// After an iOS 26 scene resume the view can stay parented while WebKit
    /// still believes it is NotVisible.
    static func reparentWebViews(in view: UIView) {
        if let webView = view as? WKWebView, let parent = webView.superview {
            let frame = webView.frame
            let index = parent.subviews.firstIndex(of: webView) ?? parent.subviews.count
            webView.removeFromSuperview()
            parent.insertSubview(webView, at: min(index, parent.subviews.count))
            webView.frame = frame
            webView.isHidden = false
            webView.alpha = 1
            return
        }
        view.subviews.forEach { reparentWebViews(in: $0) }
    }

    static func stripNonImageLayerContents(in view: UIView) {
        if !(view is UIImageView) {
            view.layer.contents = nil
            view.layer.shouldRasterize = false
        }
        for child in view.subviews {
            stripNonImageLayerContents(in: child)
        }
    }

    private static func appContentWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter(isAppContentWindow)
    }

    static func isAppContentWindow(_ window: UIWindow) -> Bool {
        if window is osrsResumeCoverWindow {
            return false
        }
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
        isCapsuleTabBar(view) || NSStringFromClass(type(of: view)).contains("_UIGraphicsView")
    }

    private static func isCapsuleTabBar(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        guard name.localizedCaseInsensitiveContains("TabBar") else { return false }
        if name.contains("Container") || name.contains("Wrapper") {
            return false
        }
        return view.bounds.height > 20 && view.bounds.height < 140
    }

    private static func clearUniformLayerContents(_ layer: CALayer) {
        guard layerContentsLookUniform(layer) else { return }
        layer.contents = nil
        layer.shouldRasterize = false
        layer.setNeedsDisplay()
    }

    private static func layerContentsLookUniform(_ view: UIView) -> Bool {
        layerContentsLookUniform(view.layer)
    }

    private static func layerContentsLookUniform(_ layer: CALayer) -> Bool {
        guard let image = cgImage(from: layer) else { return false }
        let width = min(24, image.width)
        let height = min(24, image.height)
        guard width > 0, height > 0 else { return false }
        let sample = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: sample)
        let tiny = renderer.image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: sample))
        }
        guard let cgImage = tiny.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
        }
        let count = cgImage.width * cgImage.height
        guard count > 0 else { return false }
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
        let range = maxLuminance - minLuminance
        if range < 16 {
            return true
        }
        return osrsWebViewThemePaint.isUnpaintedSystemFill(
            minLuminance: minLuminance,
            maxLuminance: maxLuminance,
            meanLuminance: total / count
        )
    }

    private static func cgImage(from layer: CALayer) -> CGImage? {
        guard let contents = layer.contents else { return nil }
        let cf = contents as CFTypeRef
        guard CFGetTypeID(cf) == CGImage.typeID else { return nil }
        return (cf as! CGImage)
    }

    private static func nudgeLayer(_ view: UIView) {
        view.layer.setNeedsLayout()
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
        var total = 0
        for index in 0..<count {
            let offset = index * 4
            let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
            total += luminance
        }
        return osrsWebViewThemePaint.isUnpaintedSystemFill(
            minLuminance: minLuminance,
            maxLuminance: maxLuminance,
            meanLuminance: total / count
        ) || osrsWebViewThemePaint.isUniformFill(
            minLuminance: minLuminance,
            maxLuminance: maxLuminance
        )
    }

    private static func dumpWindow(_ window: UIWindow) {
        var lines: [String] = []
        func walk(_ view: UIView, depth: Int) {
            let name = NSStringFromClass(type(of: view))
            let isWeb = view is WKWebView
            guard (depth < 22 || isWeb), lines.count < 240 else { return }
            let contents = view.layer.contents == nil ? "nil" : "set"
            let attached = view.window != nil
            lines.append(
                String(
                    repeating: "  ",
                    count: depth
                ) + "\(name) alpha=\(String(format: "%.2f", view.alpha)) hidden=\(view.isHidden) z=\(Int(view.layer.zPosition)) contents=\(contents) raster=\(view.layer.shouldRasterize) win=\(attached) frame=\(Int(view.frame.minX)),\(Int(view.frame.minY)) \(Int(view.frame.width))x\(Int(view.frame.height)) desc=\(descendantCount(view))"
            )
            for child in view.subviews {
                walk(child, depth: depth + 1)
            }
        }
        walk(window, depth: 0)
        let header = "appState=\(UIApplication.shared.applicationState.rawValue) scene=\(window.windowScene?.activationState.rawValue ?? -1) key=\(window.isKeyWindow)\n"
        let text = header + lines.joined(separator: "\n")
        print("🪟 osrsSceneCompositor dump\n\(text)")
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("osrs-scene-dump.txt") {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Last rendered article+chrome frame, captured before WebKit parks.
///
/// iOS 26 can leave a scene compositing only each `UIWindow`'s own layer
/// (`backgroundColor` / `layer.contents`) after SplashBoard snapshots.
/// Child views — including `UIImageView` overlays and `WKWebView` — never
/// get another draw pass (dotnet/maui#35729). Paint the last good frame
/// through those window-layer paths, not as a subview.
final class osrsResumeCoverWindow: UIWindow {}

@MainActor
enum osrsResumeFrameOverlay {
    private static var lastGoodFrame: UIImage?
    private static var lastGoodRange: Int = 0
    private static var overlayWindow: osrsResumeCoverWindow?
    private static var coveredWindow: UIWindow?
    private static var previousBackgroundColor: UIColor?

    static func capture(from window: UIWindow) {
        let bounds = window.bounds
        guard bounds.width > 16, bounds.height > 16 else { return }
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        consider(image)
        findWebView(in: window)?.takeSnapshot(with: nil) { snapshot, _ in
            guard let snapshot else { return }
            Task { @MainActor in
                consider(snapshot)
            }
        }
    }

    private static func consider(_ image: UIImage) {
        if osrsWebViewThemePaint.isUniformFill(image)
            || osrsWebViewThemePaint.isUnpaintedSystemFill(image) {
            return
        }
        let range = osrsWebViewThemePaint.luminanceRange(image)
        guard range > lastGoodRange else { return }
        lastGoodFrame = image
        lastGoodRange = range
        persistCapturedFrame(image)
        NSLog(
            "osrsResumeFrameOverlay captured %dx%d range=%d",
            Int(image.size.width),
            Int(image.size.height),
            range
        )
    }

    static func install(on root: UIView) {
        guard let image = lastGoodFrame else { return }
        guard let window = root as? UIWindow, let scene = window.windowScene else {
            return
        }
        paintWindowLayer(window, image: image)
        installCoverWindow(image, on: scene, above: window)
    }

    /// The cover is the only framebuffer iOS 26 still composites after a
    /// SplashBoard resume. A later parked-WK snapshot can look healthy while
    /// the LCD is still blank, so do not lift the cover from this probe.
    static func revealWhenLiveWebViewPaints(_ webView: WKWebView, window: UIWindow) {
        install(on: window)
    }

    static func discard() {
        if let window = coveredWindow {
            remove(from: window)
            return
        }
        overlayWindow?.isHidden = true
        overlayWindow?.layer.contents = nil
        overlayWindow?.windowScene = nil
        overlayWindow = nil
    }

    private static func paintWindowLayer(_ window: UIWindow, image: UIImage) {
        if coveredWindow !== window {
            previousBackgroundColor = window.backgroundColor
            coveredWindow = window
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.backgroundColor = UIColor(patternImage: image)
        if let cgImage = image.cgImage {
            window.layer.contents = cgImage
            window.layer.contentsGravity = .resize
            window.layer.contentsScale = image.scale
        }
        CATransaction.commit()
        NSLog(
            "osrsResumeFrameOverlay painted scene window layer range=%d",
            lastGoodRange
        )
    }

    private static func installCoverWindow(
        _ image: UIImage,
        on scene: UIWindowScene,
        above content: UIWindow
    ) {
        let overlay = overlayWindow ?? osrsResumeCoverWindow(windowScene: scene)
        overlay.windowScene = scene
        overlay.frame = scene.coordinateSpace.bounds
        overlay.windowLevel = .alert
        overlay.isOpaque = true
        overlay.isHidden = false
        overlay.isUserInteractionEnabled = false
        overlay.rootViewController = nil
        overlay.backgroundColor = UIColor(patternImage: image)
        if let cgImage = image.cgImage {
            overlay.layer.contents = cgImage
            overlay.layer.contentsGravity = .resize
            overlay.layer.contentsScale = image.scale
        }
        overlay.makeKeyAndVisible()
        content.makeKey()
        overlayWindow = overlay
        NSLog(
            "osrsResumeFrameOverlay installed cover window key=%d level=%.1f range=%d",
            overlay.isKeyWindow ? 1 : 0,
            overlay.windowLevel.rawValue,
            lastGoodRange
        )
    }

    static func remove(from root: UIView) {
        if let window = coveredWindow ?? root as? UIWindow {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            window.layer.contents = nil
            window.backgroundColor = previousBackgroundColor
                ?? UIColor(osrsAppRoot.themeManager.currentTheme.background)
            CATransaction.commit()
        }
        coveredWindow = nil
        previousBackgroundColor = nil
        overlayWindow?.isHidden = true
        overlayWindow?.layer.contents = nil
        overlayWindow?.windowScene = nil
        overlayWindow = nil
        (root as? UIWindow)?.makeKeyAndVisible()
    }

    private static func persistCapturedFrame(_ image: UIImage) {
        guard let data = image.pngData(),
              let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("osrs-resume-last-good.png") else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for child in view.subviews {
            if let webView = findWebView(in: child) {
                return webView
            }
        }
        return nil
    }
}

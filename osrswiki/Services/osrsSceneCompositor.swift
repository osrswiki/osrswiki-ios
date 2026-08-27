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

import Darwin
import IOSurface
import QuartzCore
import UIKit
import WebKit

@MainActor
enum osrsSceneCompositor {
    private static var pendingBackgroundRestore = false
    private static var lastCssCaptionLines: [String] = []

    static func shouldRestoreResumeCover(didLeaveToBackground: Bool) -> Bool {
        didLeaveToBackground
    }

    static func noteDidEnterBackground() {
        pendingBackgroundRestore = true
    }

    static func restoreResumedScenes() {
        guard shouldRestoreResumeCover(didLeaveToBackground: pendingBackgroundRestore) else {
            return
        }
        pendingBackgroundRestore = false
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
    /// app switcher. A uniform *CGImage* snapshot can hide live subviews and
    /// should be dropped. Live PlatformView IOSurfaces are not CGImages, so
    /// `layerContentsLookUniform` stays false and those layers are kept.
    /// Skip-if-contains-WK is wrong: UIDropShadowView / a plain UIView can
    /// hold the switcher CGImage *and* the live WK tree.
    static func clearFrozenHostSnapshots(in view: UIView, force: Bool = false) {
        if view is WKWebView || view is UIImageView || isPreparedWarmer(view) {
            return
        }
        _ = force
        if isIntentionallyHiddenChrome(view) {
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
            || name == "UIView"
            || name.hasSuffix(".UIView")
        if (isHostContainer || isLargeSnapshotCover(view)) && layerContentsLookUniform(view) {
            view.layer.contents = nil
            view.isOpaque = false
            view.layer.shouldRasterize = false
            view.layer.setNeedsDisplay()
        }
        for child in view.subviews {
            clearFrozenHostSnapshots(in: child, force: force)
        }
    }

    /// SpringBoard can restamp `UIWindow.layer.contents` after `restore()`.
    /// Strip only uniform CGImages / the window snapshot. Never nil IOSurfaces.
    static func stripSwitcherSnapshot(from window: UIWindow) {
        window.layer.contents = nil
        window.layer.shouldRasterize = false
        window.rootViewController?.view.layer.contents = nil
        clearFrozenHostSnapshots(in: window)
    }

    /// After `loadHTMLString` replaces WK compositing views, force the new
    /// layer tree through `didMoveToWindow` so GPU tiles can attach.
    /// Find, calc Name, and article→search all put overlay first-responder
    /// chrome on the live tree. `removeFromSuperview` during that overlay
    /// parks WK GPU tiles and the window collapses to the theme fill.
    static func wakeLiveArticleWebView(_ webView: WKWebView) {
        if isPreparedWarmer(webView) {
            return
        }
        if shouldPreserveLiveHierarchy() {
            preserveLiveWebViewWithoutReparent(webView)
            return
        }
        reparentWebViews(in: webView)
        clearFrozenWebKitScrollSnapshot(webView)
        webView.layer.setNeedsDisplay()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        if let window = webView.window {
            stripSwitcherSnapshot(from: window)
        }
    }

    static func preserveLiveWebViewWithoutReparent(_ webView: WKWebView) {
        webView.isHidden = false
        webView.alpha = 1
        webView.scrollView.isHidden = false
        webView.scrollView.alpha = 1
        // Do not nil WKScrollView.layer.contents here. Resume already
        // recorded that as dropping live iOS 26 GPU tiles to the theme fill.
        webView.layer.setNeedsDisplay()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
    }

    /// Bottom-bar Find hides overlay chrome and expands collapsibles *before*
    /// UIFindInteraction is in the tree. Keyboard willShow has the same race.
    /// Depth is the overlay session itself (Find, Name, search), not a Find skip.
    private static var liveOverlaySessionDepth = 0

    static func beginLiveOverlaySession() {
        liveOverlaySessionDepth += 1
        for window in allSceneWindows() where isAppContentWindow(window) {
            rememberPaintedArticle(from: window)
        }
        osrsHostThemeFill.applyToAppWindows(
            themeBackground: UIColor(osrsAppRoot.themeManager.currentTheme.background)
        )
        for window in allSceneWindows() {
            if let webView = firstLiveArticleWebView(in: window) {
                osrsWebViewThemePaint.apply(
                    to: webView,
                    theme: osrsAppRoot.themeManager.currentTheme
                )
            }
        }
        // Find/search/Name must not stamp last-good. The leftover parked
        // sibling freezes the pre-overlay viewport over live Find hits.
        // Clear any leftover sibling. Do not nil live WK layer.contents.
        for window in allSceneWindows() {
            removeParkedArticlePaint(from: window)
        }
        // Cycle 51: no parked-metal-fill cover. The whole-page overlay fill
        // was never WindowServer Metal above the scene tree; it was this
        // app painting the full-screen UITextEffectsWindow opaque theme fill
        // (cycle 49). osrsHostThemeFill.apply(to:) now guards that, so the
        // live tree stays visible and Find highlights are not hidden under a
        // stale bitmap.
        for window in allSceneWindows() where isAppContentWindow(window) {
            dumpWindow(window, reason: "overlay-depth-\(liveOverlaySessionDepth)")
        }
    }

    static func endLiveOverlaySession() {
        liveOverlaySessionDepth = max(0, liveOverlaySessionDepth - 1)
        if liveOverlaySessionDepth == 0 {
            for window in allSceneWindows() {
                removeParkedArticlePaint(from: window)
                if let webView = firstLiveArticleWebView(in: window) {
                    webView.scrollView.isHidden = false
                    webView.isHidden = false
                    webView.alpha = 1
                    webView.scrollView.alpha = 1
                }
            }
        }
    }

    static let parkedArticlePaintIdentifier = "osrs_parked_article_paint"
    private static var parkedArticleLastGood: UIImage?

    /// Keep a painted article bitmap while GPU tiles are still live. Find then
    /// parks Metal and `drawHierarchy` is a uniform page color; pin that last-good
    /// as a sibling, not a cover `UIWindow`.
    static func rememberPaintedArticle(_ image: UIImage) {
        guard !osrsWebViewThemePaint.isUniformFill(image),
              !osrsWebViewThemePaint.isUnpaintedSystemFill(image) else {
            return
        }
        parkedArticleLastGood = image
        osrsResumeFrameOverlay.rememberPaintedArticle(image)
    }

    static func rememberPaintedArticle(from view: UIView) {
        let bounds = view.bounds
        guard bounds.width > 8, bounds.height > 8 else { return }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            view.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        rememberPaintedArticle(image)
    }

    /// Last painted article as a sibling of WK in the live tree. iOS 26 parks
    /// Metal tiles independently of `CALayer.contents`; this is not a cover
    /// `UIWindow` and does not nil WK layer contents.
    static func pinParkedArticlePaint(from webView: WKWebView, completion: (() -> Void)? = nil) {
        if isPreparedWarmer(webView) {
            completion?()
            return
        }
        guard webView.superview != nil else {
            completion?()
            return
        }
        webView.evaluateJavaScript(osrsWebViewThemePaint.keepCompositorAliveScript)
        let snapshotView: UIView = webView.window ?? webView
        let bounds = snapshotView.bounds
        var liveImage: UIImage?
        if bounds.width > 8, bounds.height > 8 {
            liveImage = UIGraphicsImageRenderer(bounds: bounds).image { _ in
                snapshotView.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
        }
        if let liveImage {
            rememberPaintedArticle(liveImage)
        }
        let image = lastPaintedArticleImage(preferring: liveImage)
        if let existing = parkedArticlePaintView(
            in: webView.window?.rootViewController?.view ?? webView.superview ?? webView
        ), existing.image != nil {
            if let image, !osrsWebViewThemePaint.isUniformFill(image) {
                existing.image = image
            }
            existing.frame = existing.superview?.bounds ?? webView.frame
            if let parent = existing.superview {
                parent.bringSubviewToFront(existing)
                raiseFindNavigatorAboveParkedPaint(in: parent, paint: existing)
            }
            if let image, !osrsWebViewThemePaint.isUniformFill(image) {
                pinLastGoodOnWebViewLayer(webView, image: image)
            }
            completion?()
            return
        }
        guard let image, !osrsWebViewThemePaint.isUniformFill(image) else {
            completion?()
            return
        }
        let parent = webView.window?.rootViewController?.view ?? webView.superview
        guard let parent else {
            completion?()
            return
        }
        let paint = parkedArticlePaintView(in: parent) ?? UIImageView()
        paint.image = image
        paint.contentMode = .scaleToFill
        paint.frame = parent.bounds
        paint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        paint.isUserInteractionEnabled = false
        paint.accessibilityIdentifier = parkedArticlePaintIdentifier
        paint.accessibilityElementsHidden = true
        paint.isHidden = false
        paint.alpha = 1
        if paint.superview != parent {
            parent.addSubview(paint)
        }
        parent.bringSubviewToFront(paint)
        raiseFindNavigatorAboveParkedPaint(in: parent, paint: paint)
        pinLastGoodOnWebViewLayer(webView, image: image)
        completion?()
    }

    /// Parked Metal IOSurface sits on WK's own layer, above UIKit siblings.
    /// Stamp last-good there. Never `contents = nil`.
    private static func pinLastGoodOnWebViewLayer(_ webView: WKWebView, image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        webView.layer.contents = cgImage
        webView.layer.contentsScale = image.scale
        webView.layer.contentsGravity = .resize
        webView.scrollView.layer.contents = cgImage
        webView.scrollView.layer.contentsScale = image.scale
        webView.scrollView.layer.contentsGravity = .resize
        CATransaction.commit()
    }

    private static func lastPaintedArticleImage(preferring liveImage: UIImage?) -> UIImage? {
        if let liveImage,
           !osrsWebViewThemePaint.isUniformFill(liveImage),
           !osrsWebViewThemePaint.isUnpaintedSystemFill(liveImage) {
            return liveImage
        }
        if let parkedArticleLastGood,
           !osrsWebViewThemePaint.isUniformFill(parkedArticleLastGood) {
            return parkedArticleLastGood
        }
        return osrsResumeFrameOverlay.paintedArticleImage
    }

    static func removeParkedArticlePaint(from view: UIView) {
        if let imageView = view as? UIImageView,
           imageView.accessibilityIdentifier == parkedArticlePaintIdentifier {
            imageView.removeFromSuperview()
            return
        }
        view.subviews.forEach { removeParkedArticlePaint(from: $0) }
    }

    private static func parkedArticlePaintView(in view: UIView) -> UIImageView? {
        if let imageView = view as? UIImageView,
           imageView.accessibilityIdentifier == parkedArticlePaintIdentifier {
            return imageView
        }
        for child in view.subviews {
            if let found = parkedArticlePaintView(in: child) {
                return found
            }
        }
        return nil
    }

    private static func raiseFindNavigatorAboveParkedPaint(in parent: UIView, paint: UIView) {
        if let find = findNavigatorView(in: parent),
           find !== paint,
           find.superview == parent {
            parent.insertSubview(find, aboveSubview: paint)
        }
    }

    /// Find, calc Name, and article→search all put a text field or Find
    /// navigator first-responder over the live article/search tree.
    /// Keyboard / TextEffects windows are part of that overlay, so this
    /// walks every scene window, not only the app content window.
    static func shouldPreserveLiveHierarchy() -> Bool {
        if liveOverlaySessionDepth > 0 {
            return true
        }
        for window in allSceneWindows() {
            if let responder = window.value(forKey: "firstResponder") as? UIResponder,
               isOverlayFirstResponder(responder) {
                return true
            }
            if overlayFirstResponder(in: window) != nil {
                return true
            }
            if findNavigatorView(in: window) != nil {
                return true
            }
        }
        return false
    }

    private static func allSceneWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    private static func overlayFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder, isOverlayFirstResponder(view) {
            return view
        }
        for child in view.subviews {
            if let found = overlayFirstResponder(in: child) {
                return found
            }
        }
        return nil
    }

    private static func isOverlayFirstResponder(_ responder: UIResponder) -> Bool {
        if responder is UITextField || responder is UITextView {
            return true
        }
        let name = NSStringFromClass(type(of: responder))
        return name.contains("FindNavigator")
            || name.contains("UIFindBar")
            || name.contains("SearchBar")
            || name.contains("SearchTextField")
    }

    private static func findNavigatorView(in root: UIView) -> UIView? {
        let name = NSStringFromClass(type(of: root))
        if name.contains("FindNavigator") || name.contains("UIFindBar") {
            return root
        }
        for child in root.subviews {
            if let found = findNavigatorView(in: child) {
                return found
            }
        }
        return nil
    }

    /// Drop remaining host snapshots after the article document is healthy
    /// so the live WKWebView and SwiftUI chrome are not stuck behind the
    /// last SpringBoard frame.
    static func revealLiveArticleLayers(from webView: WKWebView) {
        guard webView.window ?? appContentWindows().first != nil else { return }
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
        if osrsResumeFrameOverlay.hasAdoptedLiveRoot {
            osrsResumeFrameOverlay.makeOverlayKeyIfInstalled()
            if let overlay = osrsResumeFrameOverlay.adoptedPrimaryWindow {
                dumpWindow(overlay)
            }
            return
        }
        window.isHidden = false
        window.alpha = 1
        // If resign-active captured a live Glory+chrome frame, keep it on the
        // window layer. iOS 26 Safari resume parks subview compositing, so
        // nilling contents leaves only backgroundColor. Hit-testing still
        // uses the live tree under that bitmap.
        if !osrsResumeFrameOverlay.hasCapturedFrame {
            window.layer.contents = nil
        }
        window.layer.shouldRasterize = false
        window.layer.setNeedsDisplay()
        parkPreparedWarmerHosts(in: window)
        removeStaleSnapshotOverlays(from: window)
        if let root = window.rootViewController {
            root.view.isHidden = false
            root.view.alpha = 1
            clearFrozenHostSnapshots(in: root.view)
            revealLiveViews(root.view)
            root.view.setNeedsLayout()
            root.view.layoutIfNeeded()
            clearFrozenHostSnapshots(in: root.view)
            nudgeLayer(root.view)
        }
        osrsResumeFrameOverlay.installOnWindowLayer(window)
        if let scene = window.windowScene {
            osrsResumeFrameOverlay.installPassthroughResumePixels(on: scene)
        }
        osrsResumeFrameOverlay.scheduleRevealWhenLiveWebViewPaints()
        dumpWindow(window)
        // osrsSceneCompositorLooksBlank must not be posted from restore():
        // that rebuilt the article WKWebView during the compositor race and
        // left a themed blank with no chrome.
    }

    static func captureResumeFrame(from window: UIWindow) {
        osrsResumeFrameOverlay.capture(from: window)
    }

    /// didMoveToWindow is what WKContentView uses to mark WebContent Visible.
    /// After an iOS 26 scene resume the view can stay parented while WebKit
    /// still believes it is NotVisible.
    static func reparentWebViews(in view: UIView) {
        if isPreparedWarmer(view) {
            return
        }
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

    /// iOS 26 parks a viewport-sized IOSurface on `WKScrollView.layer.contents`
    /// while the live `WKContentView` (often 10k+ pt tall) stays in the tree.
    /// That surface is what the LCD shows after resume — usually a uniform
    /// theme fill — even though the article document is healthy.
    static func clearFrozenWebKitScrollSnapshot(_ webView: WKWebView) {
        if isPreparedWarmer(webView) {
            return
        }
        if shouldPreserveLiveHierarchy() {
            return
        }
        let scroll = webView.scrollView
        scroll.layer.contents = nil
        scroll.layer.shouldRasterize = false
        scroll.isOpaque = false
        scroll.backgroundColor = .clear
        scroll.layer.setNeedsDisplay()
        webView.scrollView.setNeedsLayout()
    }

    static func stripNonImageLayerContents(in view: UIView) {
        if isPreparedWarmer(view) {
            return
        }
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
        if let overlay = window as? osrsResumeCoverWindow {
            return overlay.rootViewController is osrsAppSceneViewController
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

    private static func parkPreparedWarmerHosts(in view: UIView) {
        if isPreparedWarmer(view) {
            if let window = view.window {
                var frame = window.bounds
                frame.origin.x = window.bounds.width
                view.frame = frame
            }
            view.alpha = 0.01
            view.isUserInteractionEnabled = false
            return
        }
        view.subviews.forEach { parkPreparedWarmerHosts(in: $0) }
    }

    private static func revealLiveViews(_ view: UIView) {
        if isPreparedWarmer(view) {
            return
        }
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
        if isPreparedWarmer(view) {
            return
        }
        view.isHidden = false
        if view.alpha < 0.95 {
            view.alpha = 1
        }
        if view.layer.opacity < 0.95 {
            view.layer.opacity = 1
        }
    }

    static let osrsPreparedArticleHostIdentifier = "osrs_prepared_article_host"

    private static func isPreparedWarmer(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node.accessibilityIdentifier == osrsPreparedArticleHostIdentifier {
                return true
            }
            current = node.superview
        }
        return false
    }

    static func containsLiveArticleWebView(_ view: UIView) -> Bool {
        firstLiveArticleWebView(in: view) != nil
    }

    static func firstLiveArticleWebView(in view: UIView) -> WKWebView? {
        if isPreparedWarmer(view) {
            return nil
        }
        if let webView = view as? WKWebView {
            return webView
        }
        for child in view.subviews {
            if let found = firstLiveArticleWebView(in: child) {
                return found
            }
        }
        return nil
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

    private static func isLargeSnapshotCover(_ view: UIView) -> Bool {
        let bounds = view.bounds
        guard bounds.width >= 160, bounds.height >= 160 else { return false }
        guard let window = view.window else {
            return bounds.width >= 200 && bounds.height >= 200
        }
        return bounds.width >= window.bounds.width * 0.8
            && bounds.height >= window.bounds.height * 0.35
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

    static func dumpWindow(_ window: UIWindow, reason: String = "dump") {
        var lines: [String] = []
        let keyWindow = allSceneWindows().first(where: \.isKeyWindow)
        let keyClass = keyWindow.map { NSStringFromClass(type(of: $0)) } ?? "nil"
        lines.append(
            "reason=\(reason) t=\(Date().timeIntervalSince1970) overlayDepth=\(liveOverlaySessionDepth)"
        )
        lines.append(
            "passthrough=\(osrsResumeFrameOverlay.isPassthroughInstalled) adopted=\(osrsResumeFrameOverlay.hasAdoptedLiveRoot) hasFrame=\(osrsResumeFrameOverlay.hasCapturedFrame)"
        )
        lines.append(
            "keyClass=\(keyClass) windowClass=\(NSStringFromClass(type(of: window))) key=\(window.isKeyWindow)"
        )
        if let responder = firstResponder(in: window) ?? findFirstResponder() {
            lines.append("firstResponder=\(NSStringFromClass(type(of: responder)))")
        } else {
            lines.append("firstResponder=nil")
        }
        lines.append("wkBackground=\(webViewIsBackground(in: window))")
        final class CssProbe {
            var lines: [String] = ["cssCap=pending"]
            var finished = false
        }
        let cssProbe = CssProbe()
        if let webView = firstLiveArticleWebView(in: window) {
            requestCssComputedCaptionTabber(in: webView) { result in
                cssProbe.lines = result
                cssProbe.finished = true
            }
        } else {
            cssProbe.lines = ["cssCap=no-wk"]
            cssProbe.finished = true
        }
        let cssEarlyDeadline = Date().addingTimeInterval(0.2)
        while !cssProbe.finished, Date() < cssEarlyDeadline {
            RunLoop.current.run(mode: .common, before: Date().addingTimeInterval(0.02))
        }
        var tabBars: [String] = []
        collectTabBars(in: window, into: &tabBars)
        lines.append("tabBar \(tabBars.isEmpty ? "none" : tabBars.joined(separator: " | "))")
        let hits = [
            ("y=80", CGPoint(x: window.bounds.midX, y: 80)),
            ("y=mid", CGPoint(x: window.bounds.midX, y: window.bounds.midY)),
            ("y=aboveKb", CGPoint(x: window.bounds.midX, y: max(window.bounds.maxY - 120, 80))),
        ]
        for (label, point) in hits {
            let hit = window.hitTest(point, with: nil)
            let hitName = hit.map { NSStringFromClass(type(of: $0)) } ?? "nil"
            lines.append(
                "hit \(label) (\(Int(point.x)),\(Int(point.y))) -> \(hitName) hidden=\(hit?.isHidden ?? true) alpha=\(String(format: "%.2f", hit?.alpha ?? -1))"
            )
        }
        func walk(_ view: UIView, depth: Int) {
            let name = NSStringFromClass(type(of: view))
            let isWeb = view is WKWebView
                || name.contains("WK")
                || name.contains("Compositing")
            guard (depth < 22 || isWeb), lines.count < 360 else { return }
            let contents = view.layer.contents == nil ? "nil" : "set"
            let kind = layerContentsKind(view.layer.contents)
            var extra = ""
            if let scroll = view as? UIScrollView {
                extra = " insetAdj=\(scroll.contentInsetAdjustmentBehavior.rawValue)"
            }
            let attached = view.window != nil
            let aid = view.accessibilityIdentifier ?? ""
            let bg = describeDumpColor(view.backgroundColor)
            let layerClass = NSStringFromClass(type(of: view.layer))
            lines.append(
                String(repeating: "  ", count: depth)
                    + "\(name) alpha=\(String(format: "%.2f", view.alpha)) hidden=\(view.isHidden) z=\(Int(view.layer.zPosition)) contents=\(contents) kind=\(kind) opaque=\(view.isOpaque) bg=\(bg) layer=\(layerClass) aid=\(aid) raster=\(view.layer.shouldRasterize) win=\(attached) frame=\(Int(view.frame.minX)),\(Int(view.frame.minY)) \(Int(view.frame.width))x\(Int(view.frame.height)) desc=\(descendantCount(view))\(extra)"
            )
            for child in view.subviews {
                walk(child, depth: depth + 1)
            }
        }
        walk(window, depth: 0)
        // Dump-only C49-class census. Do not call the C46 client-info SPI
        // that crashed launch. Names which process CAContext paints the
        // Uncharged-left crop and the live caption/tabber computed style.
        appendAllContextCensus(for: window, into: &lines)
        let cssDeadline = Date().addingTimeInterval(0.15)
        while !cssProbe.finished, Date() < cssDeadline {
            RunLoop.current.run(mode: .common, before: Date().addingTimeInterval(0.02))
        }
        if !cssProbe.finished {
            cssProbe.lines = lastCssCaptionLines.isEmpty ? ["cssCap=timeout"] : lastCssCaptionLines
            if !lastCssCaptionLines.isEmpty {
                cssProbe.lines.insert("cssCap=stale-cache", at: 0)
            }
        } else {
            lastCssCaptionLines = cssProbe.lines
        }
        lines.append(contentsOf: cssProbe.lines)
        let header = "appState=\(UIApplication.shared.applicationState.rawValue) scene=\(window.windowScene?.activationState.rawValue ?? -1) key=\(window.isKeyWindow) sceneWindows=\(window.windowScene?.windows.count ?? -1) overlay=\(osrsResumeFrameOverlay.hasCapturedFrame)\n"
        let text = header + lines.joined(separator: "\n")
        print("🪟 osrsSceneCompositor dump\n\(text)")
        NSLog("osrsSceneCompositor dump\n%@", text)
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? text.write(
                to: dir.appendingPathComponent("osrs-scene-dump.txt"),
                atomically: true,
                encoding: .utf8
            )
            try? text.write(
                to: dir.appendingPathComponent("osrs-blank-fr-dump.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    static func layerContentsKind(_ contents: Any?) -> String {
        guard let contents else { return "nil" }
        let cf = contents as CFTypeRef
        let typeID = CFGetTypeID(cf)
        if typeID == CGImage.typeID {
            return "CGImage"
        }
        if typeID == IOSurfaceGetTypeID() {
            return "IOSurface"
        }
        return NSStringFromClass(type(of: contents as AnyObject))
    }

    private static func describeDumpColor(_ color: UIColor?) -> String {
        guard let color else { return "nil" }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return String(describing: color)
        }
        return String(
            format: "rgba(%.0f,%.0f,%.0f,%.2f)",
            red * 255,
            green * 255,
            blue * 255,
            alpha
        )
    }

    private static func collectTabBars(in view: UIView, into tabBars: inout [String]) {
        if let tab = view as? UITabBar {
            tabBars.append(
                "alpha=\(String(format: "%.2f", tab.alpha)) hidden=\(tab.isHidden) z=\(Int(tab.layer.zPosition)) frame=\(Int(tab.frame.minX)),\(Int(tab.frame.minY)) \(Int(tab.frame.width))x\(Int(tab.frame.height))"
            )
        }
        for child in view.subviews {
            collectTabBars(in: child, into: &tabBars)
        }
    }

    private static func findFirstResponder() -> UIResponder? {
        for window in allSceneWindows() {
            if let found = firstResponder(in: window) {
                return found
            }
        }
        return nil
    }

    private static func firstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder {
            return view
        }
        for child in view.subviews {
            if let found = firstResponder(in: child) {
                return found
            }
        }
        return nil
    }

    private static func webViewIsBackground(in window: UIWindow) -> String {
        guard let webView = firstLiveArticleWebView(in: window) else { return "no-wk" }
        let selector = NSSelectorFromString("_isBackground")
        guard webView.responds(to: selector), let method = webView.method(for: selector) else {
            return "n/a"
        }
        typealias BackgroundIMP = @convention(c) (AnyObject, Selector) -> Bool
        let imp = unsafeBitCast(method, to: BackgroundIMP.self)
        return imp(webView, selector) ? "true" : "false"
    }

    /// Process-local CAContext roots + Release-safe layer render (C44/C49).
    /// Do not call the C46 client-info SPI that crashed launch.
    private static func appendAllContextCensus(for window: UIWindow, into lines: inout [String]) {
        let windows = allSceneWindows()
        for (index, candidate) in windows.prefix(8).enumerated() {
            let cls = NSStringFromClass(type(of: candidate))
            let ctx = compositorContextId(of: candidate)
            lines.append(
                "winCtx=win\(index)(\(cls)) level=\(Int(candidate.windowLevel.rawValue)) hidden=\(candidate.isHidden) opaque=\(candidate.isOpaque) bg=\(describeDumpColor(candidate.backgroundColor)) ctx=\(ctx)"
            )
        }
        let contexts = allCAContexts()
        if contexts.isEmpty {
            lines.append("allCtx=n/a")
            appendContextLayerWalk(for: window, into: &lines)
            return
        }
        lines.append("allCtx=\(contexts.count)")
        let scale = window.traitCollection.displayScale
        for (index, context) in contexts.prefix(8).enumerated() {
            let idString = compositorContextId(of: context)
            let contextId = UInt32(idString) ?? 0
            var owner = "ORPHAN"
            for (winIndex, candidate) in windows.enumerated() {
                if compositorContextId(of: candidate) == idString {
                    owner = "win\(winIndex)(\(NSStringFromClass(type(of: candidate))))"
                    break
                }
            }
            var rootName = "nil"
            var rootLayer: CALayer?
            var rootSize = "0x0"
            var rootHidden = true
            var subCount = 0
            if context.responds(to: NSSelectorFromString("layer")),
               let layer = context.value(forKey: "layer") as? CALayer {
                rootLayer = layer
                rootName = NSStringFromClass(type(of: layer))
                rootSize = "\(Int(layer.bounds.width))x\(Int(layer.bounds.height))"
                rootHidden = layer.isHidden
                subCount = layer.sublayers?.count ?? 0
            }
            let render: String
            if let rootLayer, contextId != 0 {
                render = renderLayerMeanStd(
                    contextId: contextId,
                    layer: rootLayer,
                    scale: scale,
                    gutterIn: window.bounds
                )
            } else {
                render = "n/a"
            }
            lines.append(
                "allCtx\(index)=id=\(idString) owner=\(owner) root=\(rootName) \(rootSize) hidden=\(rootHidden) subs=\(subCount) \(render)"
            )
        }
        appendContextLayerWalk(for: window, into: &lines)
    }

    private static func appendContextLayerWalk(for window: UIWindow, into lines: inout [String]) {
        guard window.layer.responds(to: NSSelectorFromString("context")),
              let context = window.layer.value(forKey: "context") as AnyObject?,
              context.responds(to: NSSelectorFromString("layer")),
              let root = context.value(forKey: "layer") as? CALayer else {
            lines.append("ctxL=n/a")
            return
        }
        var owned = Set<ObjectIdentifier>()
        func collect(_ view: UIView) {
            owned.insert(ObjectIdentifier(view.layer))
            for child in view.subviews {
                collect(child)
            }
        }
        collect(window)
        var count = 0
        func walk(_ layer: CALayer, depth: Int) {
            guard depth < 6, count < 24 else { return }
            let name = NSStringFromClass(type(of: layer))
            let owner: String
            if layer === window.layer {
                owner = "WINDOW-LAYER"
            } else if owned.contains(ObjectIdentifier(layer)) {
                owner = "VIEW"
            } else {
                owner = "UNOWNED"
            }
            let bg: String
            if let cg = layer.backgroundColor {
                bg = describeDumpColor(UIColor(cgColor: cg))
            } else {
                bg = "nil"
            }
            let contents = layer.contents == nil ? "nil" : "set"
            lines.append(
                String(repeating: "  ", count: depth)
                    + "ctxL \(name) owner=\(owner) frame=\(Int(layer.frame.minX)),\(Int(layer.frame.minY)) \(Int(layer.frame.width))x\(Int(layer.frame.height)) z=\(Int(layer.zPosition)) hidden=\(layer.isHidden) op=\(String(format: "%.2f", layer.opacity)) opaque=\(layer.isOpaque) bg=\(bg) contents=\(contents) kind=\(layerContentsKind(layer.contents)) subs=\(layer.sublayers?.count ?? 0)"
            )
            count += 1
            for sub in layer.sublayers ?? [] {
                walk(sub, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
    }

    private static func requestCssComputedCaptionTabber(
        in webView: WKWebView,
        completion: @escaping ([String]) -> Void
    ) {
        let script = """
        (() => {
          const css = (el) => {
            if (!el) return null;
            const s = getComputedStyle(el);
            const r = el.getBoundingClientRect();
            return {
              tag: el.tagName,
              cls: (el.className || '').toString().slice(0, 80),
              id: el.id || '',
              text: (el.textContent || '').trim().slice(0, 24),
              bg: s.backgroundColor,
              image: s.backgroundImage,
              isolation: s.isolation,
              overflow: s.overflow + '/' + s.overflowX + '/' + s.overflowY,
              opacity: s.opacity,
              mix: s.mixBlendMode,
              transform: s.transform,
              rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]
            };
          };
          const compact = (label, info) => {
            if (!info) return label + '=missing';
            return label + '=tag=' + info.tag + ' cls=' + info.cls + ' id=' + info.id
              + ' text=' + JSON.stringify(info.text)
              + ' bg=' + info.bg + ' image=' + String(info.image).slice(0, 40)
              + ' isolation=' + info.isolation + ' overflow=' + info.overflow
              + ' opacity=' + info.opacity + ' mix=' + info.mix
              + ' transform=' + String(info.transform).slice(0, 24)
              + ' rect=' + info.rect.join(',');
          };
          const buttons = Array.from(document.querySelectorAll(
            '.infobox-bonuses .infobox-buttons .button, .infobox-buttons .button, caption .button'
          ));
          const uncharged = buttons.find((el) => (el.textContent || '').trim() === 'Uncharged') || null;
          const caption = uncharged ? uncharged.closest('caption, .infobox-switch-buttons-caption') : document.querySelector('.infobox-switch-buttons-caption, caption');
          const row = uncharged ? uncharged.closest('.infobox-buttons') : document.querySelector('.infobox-bonuses .infobox-buttons, .infobox-buttons');
          const table = uncharged ? uncharged.closest('table') : document.querySelector('table.infobox-bonuses, table.infobox');
          let fromPoint = null;
          let point = [0, 0];
          if (uncharged) {
            const r = uncharged.getBoundingClientRect();
            point = [Math.max(2, r.left - 14), r.top + Math.min(10, r.height / 2)];
            fromPoint = document.elementFromPoint(point[0], point[1]);
          }
          const ancestors = [];
          let node = fromPoint;
          for (let i = 0; i < 8 && node && node !== document.body; i++) {
            ancestors.push(compact('a' + i, css(node)));
            node = node.parentElement;
          }
          return [
            compact('cssUncharged', css(uncharged)),
            compact('cssCap', css(caption)),
            compact('cssButtons', css(row)),
            compact('cssTable', css(table)),
            compact('cssBody', css(document.body)),
            compact('cssFromPoint', css(fromPoint)) + ' pt=' + point.join(','),
            'cssAncestors=' + (ancestors.join(' | ') || 'none')
          ].join('\\n');
        })()
        """
        webView.evaluateJavaScript(script) { value, error in
            let result: String
            if let error {
                result = "cssCap=error \(error.localizedDescription)"
            } else if let text = value as? String {
                result = text
            } else {
                result = "cssCap=\(String(describing: value))"
            }
            completion(
                result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            )
        }
    }

    private static func allCAContexts() -> [NSObject] {
        let selector = NSSelectorFromString("allContexts")
        guard let contextClass = NSClassFromString("CAContext") as? NSObject.Type,
              contextClass.responds(to: selector),
              let method = class_getClassMethod(contextClass, selector) else {
            return []
        }
        typealias AllContextsIMP = @convention(c) (AnyClass, Selector) -> Any?
        let imp = unsafeBitCast(method_getImplementation(method), to: AllContextsIMP.self)
        guard let raw = imp(contextClass, selector) else { return [] }
        if let array = raw as? [NSObject] {
            return array
        }
        if let array = raw as? NSArray {
            return array.compactMap { $0 as? NSObject }
        }
        return []
    }

    private static func compositorContextId(of object: AnyObject) -> String {
        for key in ["contextId", "_contextId", "contextID", "_contextID"] {
            if object.responds(to: NSSelectorFromString(key)),
               let number = object.value(forKey: key) as? NSNumber {
                return String(number.uint32Value)
            }
        }
        return "n/a"
    }

    /// C44/C49 Release-safe render of one CAContext root. Crops a fixed
    /// y=148 band (historical; misses a scrolled chip row) plus an
    /// Uncharged-locked gutter found by a parchment→chip edge scan.
    private static func renderLayerMeanStd(
        contextId: UInt32,
        layer: CALayer,
        scale: CGFloat,
        gutterIn bounds: CGRect
    ) -> String {
        let pixelW = max(8, Int((max(layer.bounds.width, bounds.width) * scale).rounded()))
        let pixelH = max(8, Int((max(layer.bounds.height, bounds.height) * scale).rounded()))
        let bytesPerRow = pixelW * 4
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: pixelW,
            .height: pixelH,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: 0x4247_5241
        ]
        guard let surface = IOSurface(properties: properties) else {
            return "render=n/a"
        }
        guard let quartz = dlopen(
            "/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
            RTLD_NOW
        ) else {
            return "render=n/a"
        }
        defer { dlclose(quartz) }
        let symbol = dlsym(quartz, "CARenderServerRenderLayerWithTransform")
        guard Int(bitPattern: symbol) != 0 else {
            return "render=n/a"
        }
        typealias RenderIMP = @convention(c) (
            mach_port_t,
            UInt32,
            UInt64,
            IOSurfaceRef,
            Int32,
            Int32,
            UnsafePointer<CATransform3D>
        ) -> Void
        let render = unsafeBitCast(symbol, to: RenderIMP.self)
        var transform = CATransform3DMakeScale(scale, scale, 1)
        let layerId = UInt64(UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        render(0, contextId, layerId, unsafeBitCast(surface, to: IOSurfaceRef.self), 0, 0, &transform)
        return ioSurfaceCropSummary(
            surface,
            width: pixelW,
            height: pixelH,
            bytesPerRow: bytesPerRow,
            scale: scale,
            logicalBounds: bounds
        )
    }

    private static func ioSurfaceCropSummary(
        _ surface: IOSurface,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        scale: CGFloat,
        logicalBounds: CGRect
    ) -> String {
        let cropHeight = max(1, min(height, Int(Double(height) * 0.45)))
        IOSurfaceLock(unsafeBitCast(surface, to: IOSurfaceRef.self), IOSurfaceLockOptions(), nil)
        defer {
            IOSurfaceUnlock(unsafeBitCast(surface, to: IOSurfaceRef.self), IOSurfaceLockOptions(), nil)
        }
        let base = IOSurfaceGetBaseAddress(unsafeBitCast(surface, to: IOSurfaceRef.self))
        guard Int(bitPattern: base) != 0 else { return "render=n/a" }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        func sample(x0: Int, y0: Int, x1: Int, y1: Int) -> (r: Double, g: Double, b: Double, a: Double, std: Double) {
            let left = max(0, min(width, x0))
            let right = max(left + 1, min(width, x1))
            let top = max(0, min(height, y0))
            let bottom = max(top + 1, min(height, y1))
            var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumA = 0.0
            var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
            let n = Double((right - left) * (bottom - top))
            for y in top..<bottom {
                let row = ptr.advanced(by: y * bytesPerRow)
                for x in left..<right {
                    let o = x * 4
                    let b = Double(row[o])
                    let g = Double(row[o + 1])
                    let r = Double(row[o + 2])
                    let a = Double(row[o + 3])
                    sumR += r; sumG += g; sumB += b; sumA += a
                    sumR2 += r * r; sumG2 += g * g; sumB2 += b * b
                }
            }
            let meanR = sumR / n, meanG = sumG / n, meanB = sumB / n, meanA = sumA / n
            let varR = max(0, sumR2 / n - meanR * meanR)
            let varG = max(0, sumG2 / n - meanG * meanG)
            let varB = max(0, sumB2 / n - meanB * meanB)
            return (meanR, meanG, meanB, meanA, sqrt((varR + varG + varB) / 3))
        }

        let top = sample(x0: 0, y0: 0, x1: width, y1: cropHeight)
        let sx = Double(width) / max(1, logicalBounds.width)
        let sy = Double(height) / max(1, logicalBounds.height)
        let gx0 = Int(28 * sx), gy0 = Int(148 * sy)
        let gx1 = Int(48 * sx), gy1 = Int(168 * sy)
        let gutter = sample(x0: gx0, y0: gy0, x1: gx1, y1: gy1)
        // Lock to Uncharged: scan logical y 160–280 / x 70–170 for a
        // parchment→chip edge, then sample 12px left of that edge.
        func distParchment(r: Double, g: Double, b: Double) -> Double {
            let dr = r - 40, dg = g - 34, db = b - 29
            return sqrt(dr * dr + dg * dg + db * db)
        }
        var uncharged = "unchargedY=n/a ugutter=n/a"
        // Chip row has several parchment→button edges (Uncharged, 1, 2, …).
        // A single edge at y≈160 is the infobox chrome, not Uncharged.
        rowScan: for ly in stride(from: 180, through: 260, by: 2) {
            let y = Int(Double(ly) * sy)
            guard y >= 0, y < height else { continue }
            let row = ptr.advanced(by: y * bytesPerRow)
            var prevR = 0.0, prevG = 0.0, prevB = 0.0
            var jumps: [Int] = []
            for lx in 70...250 {
                let x = Int(Double(lx) * sx)
                guard x >= 0, x < width else { continue }
                let o = x * 4
                let b = Double(row[o])
                let g = Double(row[o + 1])
                let r = Double(row[o + 2])
                if lx > 70 {
                    let dPrev = distParchment(r: prevR, g: prevG, b: prevB)
                    let dHere = distParchment(r: r, g: g, b: b)
                    if dPrev < 12, dHere > 18, r > 48 {
                        jumps.append(lx)
                    }
                }
                prevR = r
                prevG = g
                prevB = b
            }
            if jumps.count >= 3, let lx = jumps.first, lx >= 100 {
                let leftX = Int(Double(lx - 16) * sx)
                let rightX = Int(Double(lx - 4) * sx)
                let topY = Int(Double(ly) * sy)
                let botY = Int(Double(ly + 12) * sy)
                let ug = sample(x0: leftX, y0: topY, x1: rightX, y1: botY)
                uncharged = String(
                    format: "unchargedY=%d ugutter=rgb(%.0f,%.0f,%.0f) ugStd=%.2f ugA=%.0f",
                    ly, ug.r, ug.g, ug.b, ug.std, ug.a
                )
                break rowScan
            }
        }
        return String(
            format: "render=mean=rgb(%.0f,%.0f,%.0f) std=%.2f meanA=%.0f crop=%dx%d gutter=rgb(%.0f,%.0f,%.0f) gStd=%.2f gA=%.0f %@",
            top.r, top.g, top.b, top.std, top.a, width, cropHeight,
            gutter.r, gutter.g, gutter.b, gutter.std, gutter.a,
            uncharged
        )
    }
}

/// Last rendered article+chrome frame, captured before WebKit parks.
/// iOS 26 Safari resume parks the live UIWindow's compositor surface, so
/// LCD pixels come from this overlay. WindowServer delivers hits to the
/// frontmost window; returning nil from hitTest does not fall through.
/// This window stays key and returns the live tree's hit view so SwiftUI
/// and WK gesture recognizers still fire.
final class osrsResumeCoverWindow: UIWindow {
    weak var osrsHitTarget: UIWindow?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let target = osrsHitTarget else {
            return super.hitTest(point, with: event)
        }
        return target.hitTest(convert(point, to: target), with: event)
    }
}

@MainActor
enum osrsResumeFrameOverlay {
    private static var lastGoodFrame: UIImage?
    private static var lastGoodRange: Int = 0
    private static var overlayWindow: osrsResumeCoverWindow?
    private static var coveredWindow: UIWindow?
    private static var previousBackgroundColor: UIColor?

    static var hasCapturedFrame: Bool { lastGoodFrame != nil }
    static var paintedArticleImage: UIImage? { lastGoodFrame }

    static func rememberPaintedArticle(_ image: UIImage) {
        consider(image)
    }

    static func capture(from window: UIWindow) {
        let bounds = window.bounds
        guard bounds.width > 16, bounds.height > 16 else { return }
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        consider(image)
        // Do not takeSnapshot a WKWebView: the first WebView in the tree can
        // be a process-warmer, and the bitmap has no app chrome.
    }

    private static func consider(_ image: UIImage) {
        #if DEBUG
        let cfg = "Debug"
        #else
        let cfg = "Release"
        #endif
        let uniform = osrsWebViewThemePaint.isUniformFill(image)
            || osrsWebViewThemePaint.isUnpaintedSystemFill(image)
        let range = osrsWebViewThemePaint.luminanceRange(image)
        if uniform {
            NSLog(
                "osrsResumeFrameOverlay capture skip cfg=%@ uniform=1 range=%d %dx%d",
                cfg,
                range,
                Int(image.size.width),
                Int(image.size.height)
            )
            return
        }
        guard range > lastGoodRange else {
            NSLog(
                "osrsResumeFrameOverlay capture skip cfg=%@ range=%d last=%d",
                cfg,
                range,
                lastGoodRange
            )
            return
        }
        lastGoodFrame = image
        lastGoodRange = range
        persistCapturedFrame(image)
        NSLog(
            "osrsResumeFrameOverlay captured cfg=%@ %dx%d range=%d",
            cfg,
            Int(image.size.width),
            Int(image.size.height),
            range
        )
    }

    /// Put the last live article+chrome bitmap on this window's layer so
    /// Safari resume is the same view even when iOS 26 parks subview
    /// compositing. Hits still go to the live tree, not a second UIWindow.
    static var isPassthroughInstalled: Bool {
        overlayWindow != nil && overlayWindow?.isHidden == false
    }

    static var hasAdoptedLiveRoot: Bool {
        overlayWindow?.rootViewController is osrsAppSceneViewController
    }

    static var adoptedPrimaryWindow: UIWindow? {
        hasAdoptedLiveRoot ? overlayWindow : nil
    }

    static var onAdoptedPrimary: ((UIWindow) -> Void)?

    static func makeOverlayKeyIfInstalled() {
        guard isPassthroughInstalled, let overlay = overlayWindow else { return }
        overlay.makeKey()
    }

    static func adoptLiveRootIfNeeded() {
        guard let overlay = overlayWindow, overlay.isHidden == false else { return }
        if overlay.rootViewController is osrsAppSceneViewController {
            overlay.osrsHitTarget = nil
            overlay.isUserInteractionEnabled = true
            overlay.makeKey()
            return
        }
        guard let live = overlay.osrsHitTarget,
              let root = live.rootViewController as? osrsAppSceneViewController else {
            return
        }
        overlay.osrsHitTarget = nil
        overlay.isUserInteractionEnabled = true
        let lastGoodImage = overlay.rootViewController?.view.subviews
            .compactMap { $0 as? UIImageView }
            .first { $0.accessibilityIdentifier == "osrs_resume_passthrough_frame" }?
            .image ?? lastGoodFrame
        live.rootViewController = nil
        overlay.rootViewController = root
        if let bounds = overlay.windowScene?.coordinateSpace.bounds {
            overlay.frame = bounds
        }
        root.view.frame = overlay.bounds
        if let image = lastGoodImage {
            let imageView = root.view.subviews
                .compactMap { $0 as? UIImageView }
                .first { $0.accessibilityIdentifier == "osrs_resume_passthrough_frame" }
                ?? UIImageView()
            imageView.image = image
            imageView.frame = overlay.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            imageView.accessibilityIdentifier = "osrs_resume_passthrough_frame"
            if imageView.superview !== root.view {
                root.view.insertSubview(imageView, at: 0)
            } else {
                root.view.sendSubviewToBack(imageView)
            }
        }
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()
        overlay.makeKeyAndVisible()
        // The parked original window is now empty. Leaving it visible under
        // a .statusBar overlay lets bottom-chrome hits miss the live tree.
        live.isUserInteractionEnabled = false
        live.isHidden = true
        onAdoptedPrimary?(overlay)
        osrsHostThemeFill.apply(
            to: overlay,
            themeBackground: UIColor(osrsAppRoot.themeManager.currentTheme.background)
        )
        osrsSceneCompositor.dumpWindow(overlay)
        NSLog("osrsResumeFrameOverlay adopted live root")
        scheduleRevealWhenLiveWebViewPaints()
    }

    static func installOnWindowLayer(_ window: UIWindow) {
        if hasAdoptedLiveRoot { return }
        guard let image = lastGoodFrame, let cgImage = image.cgImage else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.layer.contents = cgImage
        window.layer.contentsScale = image.scale
        window.layer.contentsGravity = .resize
        window.layer.shouldRasterize = false
        CATransaction.commit()
        coveredWindow = window
        if let scene = window.windowScene {
            installPassthroughResumePixels(on: scene)
        }
        NSLog(
            "osrsResumeFrameOverlay installed %dx%d on window layer passthrough will follow",
            Int(image.size.width * image.scale),
            Int(image.size.height * image.scale)
        )
    }

    /// Magenta-in-window proved Safari resume does not composite the live
    /// UIWindow's subviews. A cover window at `.statusBar` is a second
    /// compositor surface. After the last-good bitmap is on screen, the
    /// existing `osrsAppSceneViewController` moves onto this window so
    /// hits and pixels share one compositor target. Recreating
    /// UIHostingController is still forbidden.
    static func installPassthroughResumePixels(on windowScene: UIWindowScene) {
        if hasAdoptedLiveRoot {
            overlayWindow?.windowScene = windowScene
            overlayWindow?.makeKey()
            return
        }
        guard let image = lastGoodFrame else { return }
        let overlay = overlayWindow ?? osrsResumeCoverWindow(windowScene: windowScene)
        overlay.windowScene = windowScene
        overlay.frame = windowScene.coordinateSpace.bounds
        overlay.windowLevel = .statusBar
        overlay.isUserInteractionEnabled = true
        overlay.backgroundColor = .clear
        overlay.isHidden = false
        overlay.osrsHitTarget = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0 !== overlay && osrsSceneCompositor.isAppContentWindow($0) }
        let host = overlay.rootViewController ?? UIViewController()
        if !(host is osrsAppSceneViewController) {
            host.view.isUserInteractionEnabled = false
            host.view.backgroundColor = .clear
            host.view.frame = overlay.bounds
            if overlay.rootViewController !== host {
                overlay.rootViewController = host
            }
            let imageView = host.view.subviews.compactMap { $0 as? UIImageView }.first ?? UIImageView()
            imageView.image = image
            imageView.frame = overlay.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            imageView.accessibilityIdentifier = "osrs_resume_passthrough_frame"
            if imageView.superview !== host.view {
                host.view.addSubview(imageView)
            }
        }
        overlayWindow = overlay
        overlay.makeKey()
        NSLog(
            "osrsResumeFrameOverlay passthrough %dx%d interaction=1 key=%d target=%d",
            Int(image.size.width * image.scale),
            Int(image.size.height * image.scale),
            overlay.isKeyWindow ? 1 : 0,
            overlay.osrsHitTarget == nil ? 0 : 1
        )
        DispatchQueue.main.async {
            adoptLiveRootIfNeeded()
        }
    }

    static func blitPassthroughResumePixels(from window: UIWindow) {
        guard !hasAdoptedLiveRoot else { return }
        guard let overlay = overlayWindow, overlay.isHidden == false else { return }
        let bounds = window.bounds
        guard bounds.width > 16, bounds.height > 16 else { return }
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        if osrsWebViewThemePaint.isUniformFill(image)
            || osrsWebViewThemePaint.isUnpaintedSystemFill(image) {
            return
        }
        lastGoodFrame = image
        lastGoodRange = max(lastGoodRange, osrsWebViewThemePaint.luminanceRange(image))
        if let imageView = overlay.rootViewController?.view.subviews
            .compactMap({ $0 as? UIImageView }).first {
            imageView.image = image
            return
        }
        if let scene = window.windowScene {
            installPassthroughResumePixels(on: scene)
        }
    }

    static func install(on root: UIView) {
        let window = (root as? UIWindow) ?? root.window
        guard let window else { return }
        installOnWindowLayer(window)
    }

    /// Keep last-good only while live WK is not compositing after background.
    /// Once tiles paint, the passthrough UIImageView and window.layer stamp
    /// must come down. Do not drop the cover at didEnterBackground.
    static func revealWhenLiveWebViewPaints() {
        guard lastGoodIsCoveringLiveArticle else { return }
        guard liveArticleIsPainting() else { return }
        removeLastGoodCover()
    }

    static func scheduleRevealWhenLiveWebViewPaints() {
        for delayNs in [0, 80_000_000, 250_000_000, 500_000_000] as [UInt64] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delayNs))) {
                revealWhenLiveWebViewPaints()
            }
        }
    }

    static var lastGoodIsCoveringLiveArticle: Bool {
        firstPassthroughImageView() != nil
            || overlayWindow?.layer.contents != nil
            || coveredWindow?.layer.contents != nil
    }

    static func liveArticleIsPainting() -> Bool {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { osrsSceneCompositor.isAppContentWindow($0) }
        for window in windows {
            if let webView = osrsSceneCompositor.firstLiveArticleWebView(in: window),
               articleWebViewLooksPainted(webView) {
                return true
            }
        }
        return false
    }

    private static func articleWebViewLooksPainted(_ webView: WKWebView) -> Bool {
        if looksPainted(webView) { return true }
        if let host = webView.superview, !(host is UIWindow), looksPainted(host) {
            return true
        }
        return false
    }

    private static func looksPainted(_ view: UIView) -> Bool {
        let bounds = view.bounds
        guard bounds.width > 8, bounds.height > 8 else { return false }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return !osrsWebViewThemePaint.isUniformFill(image)
    }

    static func discard() {
        if liveArticleIsPainting() {
            removeLastGoodCover()
            return
        }
        if overlayWindow != nil && overlayWindow?.isHidden == false {
            NSLog("osrsResumeFrameOverlay discard skipped; live WK not painting yet")
            return
        }
        if let window = coveredWindow {
            remove(from: window)
            return
        }
        overlayWindow?.isHidden = true
        overlayWindow?.layer.contents = nil
        overlayWindow?.windowScene = nil
        overlayWindow = nil
    }

    static func remove(from root: UIView) {
        if liveArticleIsPainting() {
            removeLastGoodCover()
            return
        }
        if overlayWindow != nil && overlayWindow?.isHidden == false {
            NSLog("osrsResumeFrameOverlay discard skipped; live WK not painting yet")
            return
        }
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

    private static func removeLastGoodCover() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayWindow?.layer.contents = nil
        coveredWindow?.layer.contents = nil
        if let overlay = overlayWindow {
            stripPassthrough(from: overlay)
        }
        if let covered = coveredWindow {
            stripPassthrough(from: covered)
        }
        CATransaction.commit()
        if hasAdoptedLiveRoot {
            coveredWindow = nil
            NSLog("osrsResumeFrameOverlay last-good removed; live WK painting")
            return
        }
        overlayWindow?.isHidden = true
        overlayWindow?.layer.contents = nil
        overlayWindow?.windowScene = nil
        overlayWindow = nil
        coveredWindow = nil
        previousBackgroundColor = nil
        NSLog("osrsResumeFrameOverlay discarded; live WK painting")
    }

    private static func stripPassthrough(from view: UIView) {
        for subview in view.subviews {
            if let imageView = subview as? UIImageView,
               imageView.accessibilityIdentifier == "osrs_resume_passthrough_frame" {
                imageView.removeFromSuperview()
            } else {
                stripPassthrough(from: subview)
            }
        }
    }

    static func firstPassthroughImageView() -> UIImageView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            if let found = firstPassthroughImageView(in: window) {
                return found
            }
        }
        if let overlay = overlayWindow, let found = firstPassthroughImageView(in: overlay) {
            return found
        }
        return nil
    }

    static func firstPassthroughImageView(in view: UIView) -> UIImageView? {
        if let imageView = view as? UIImageView,
           imageView.accessibilityIdentifier == "osrs_resume_passthrough_frame" {
            return imageView
        }
        for child in view.subviews {
            if let found = firstPassthroughImageView(in: child) {
                return found
            }
        }
        return nil
    }

    private static func persistCapturedFrame(_ image: UIImage) {
        guard let data = image.pngData(),
              let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("osrs-resume-last-good.png") else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

import SwiftUI
import UIKit

/// Owns the scene's one UIWindow. The content host is `osrsAppSceneViewController`
/// with a single `UIHostingController(CustomMainTabView)` child for the process
/// lifetime. iOS 26 can leave SpringBoard's parchment snapshot on screen after
/// a background; resume restores that same window through `osrsSceneCompositor`.
/// Substituting a parallel wiki `WKWebView` is not a resume strategy.
final class osrsSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var needsResumeRestore = false
    private var didLeaveToBackground = false
    private var resumeDisplayLink: CADisplayLink?
    private var isAttaching = false
    private var finishedFirstActivation = false
    private var appObservers: [NSObjectProtocol] = []
    private var appHost: UIViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        print("🪟 osrsSceneDelegate willConnect session=\(session.persistentIdentifier)")
        NSLog("osrsSceneDelegate willConnect session=%@", session.persistentIdentifier)
        observeApplicationLifecycle()
        attachPrimaryWindow(to: windowScene, reason: "connect")
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        nil
    }

    func scene(_ scene: UIScene, restoreInteractionStateWith stateRestorationActivity: NSUserActivity) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
        markNeedsResumeRestore(reason: "sceneWillResignActive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        didLeaveToBackground = true
        osrsSceneCompositor.noteDidEnterBackground()
        markNeedsResumeRestore(reason: "sceneDidEnterBackground")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        handleBecameActive(scene, reason: "sceneDidBecomeActive")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()
        resumeDisplayLink?.invalidate()
        resumeDisplayLink = nil
    }

    private func observeApplicationLifecycle() {
        guard appObservers.isEmpty else { return }
        let center = NotificationCenter.default
        appObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markNeedsResumeRestore(reason: "applicationWillResignActive")
        })
        appObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.didLeaveToBackground = true
            osrsSceneCompositor.noteDidEnterBackground()
            self?.markNeedsResumeRestore(reason: "applicationDidEnterBackground")
        })
        appObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let scene = self?.window?.windowScene ?? UIApplication.shared.connectedScenes.first else {
                return
            }
            self?.handleBecameActive(scene, reason: "applicationDidBecomeActive")
        })
    }

    private func markNeedsResumeRestore(reason: String) {
        needsResumeRestore = true
        osrsAppRoot.appState.noteApplicationDidEnterBackground()
        osrsAppRoot.appState.rememberResumableArticle()
        osrsPreparedArticleWebViewStore.shared.detachFromKeyWindowForResume()
        if let window {
            osrsSceneCompositor.captureResumeFrame(from: window)
        }
        print("🪟 osrsSceneDelegate mark resume reason=\(reason)")
        NSLog("osrsSceneDelegate mark resume reason=%@", reason)
    }

    private func handleBecameActive(_ scene: UIScene, reason: String) {
        osrsAppRoot.themeManager.applyPersistedThemeToWindows()
        osrsAppRoot.applyGlobalTheming()
        guard let windowScene = scene as? UIWindowScene else { return }
        if !finishedFirstActivation {
            finishedFirstActivation = true
            print("🪟 osrsSceneDelegate first activation skip replace trigger=\(reason)")
            NSLog("osrsSceneDelegate first activation skip replace trigger=%@", reason)
            return
        }
        guard needsResumeRestore else { return }
        needsResumeRestore = false
        guard didLeaveToBackground else { return }
        didLeaveToBackground = false
        print("🪟 osrsSceneDelegate resume compositor trigger=\(reason)")
        NSLog("osrsSceneDelegate resume compositor trigger=%@", reason)
        restoreResumedScene(on: windowScene, reason: reason)
        osrsAppRoot.appState.noteApplicationDidBecomeActive()
        // 8a413: a same-window geometry nudge after Safari unparks UIKit
        // children. Window bounce / nilling windowScene left parchment.
        DispatchQueue.main.async { [weak self] in
            self?.nudgeCompositor(on: windowScene)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.nudgeCompositor(on: windowScene)
        }
    }

    private var sceneContainer: osrsAppSceneViewController? {
        window?.rootViewController as? osrsAppSceneViewController
    }

    func replacePrimaryWindow(on windowScene: UIWindowScene, reason: String) {
        attachPrimaryWindow(to: windowScene, reason: reason)
    }

    private func attachPrimaryWindow(
        to windowScene: UIWindowScene,
        reason: String
    ) {
        guard !isAttaching else { return }
        isAttaching = true
        defer { isAttaching = false }

        let theme = osrsAppRoot.themeManager.currentTheme
        let bounds = windowScene.coordinateSpace.bounds
        // Reuse the scene window. Creating a replacement UIWindow and detaching
        // the original (windowScene = nil) leaves iOS 26 compositing the
        // parchment snapshot instead of the live root.
        let sceneWindow = existingSceneWindow(on: windowScene) ?? osrsResumedSceneWindow(windowScene: windowScene)
        sceneWindow.frame = bounds
        sceneWindow.bounds = bounds
        sceneWindow.windowLevel = .normal
        sceneWindow.overrideUserInterfaceStyle = osrsAppRoot.themeManager.currentColorScheme == .dark ? .dark : .light
        sceneWindow.layer.contents = nil
        sceneWindow.layer.shouldRasterize = false

        let container = sceneContainer ?? osrsAppSceneViewController()
        if sceneWindow.rootViewController !== container {
            replaceRootViewController(on: sceneWindow, with: container)
        }
        if container.osrsContent == nil {
            let host = appHost ?? UIHostingController(rootView: osrsAppRoot.rootView)
            appHost = host
            container.osrsInstall(host)
        }
        osrsHostThemeFill.apply(to: sceneWindow, themeBackground: UIColor(theme.background))
        sceneWindow.makeKeyAndVisible()
        window = sceneWindow

        osrsResumeFrameOverlay.onAdoptedPrimary = { [weak self] overlay in
            self?.window = overlay
        }

        UIApplication.shared.requestSceneSessionRefresh(windowScene.session)
        print(
            "🪟 osrsSceneDelegate attach reason=\(reason) host=CustomMainTabView sceneWindows=\(windowScene.windows.count) key=\(sceneWindow.isKeyWindow) frame=\(Int(sceneWindow.frame.width))x\(Int(sceneWindow.frame.height))"
        )
        NSLog(
            "osrsSceneDelegate attach reason=%@ host=CustomMainTabView key=%d",
            reason,
            sceneWindow.isKeyWindow ? 1 : 0
        )
        osrsSceneCompositor.restore(sceneWindow)
        startResumeDisplayLink()
    }

    private func restoreResumedScene(on windowScene: UIWindowScene, reason: String) {
        guard let window, window.windowScene === windowScene else {
            attachPrimaryWindow(to: windowScene, reason: reason)
            return
        }
        // Keep this scene's existing UIWindow and CustomMainTabView host.
        // Minting a second window (or nilling windowScene) left iOS 26
        // compositing only backgroundColor. Rebinding UIHostingController
        // dropped WKContentView to 0x0.
        osrsHostThemeFill.apply(
            to: window,
            themeBackground: UIColor(osrsAppRoot.themeManager.currentTheme.background)
        )
        window.overrideUserInterfaceStyle = osrsAppRoot.themeManager.currentColorScheme == .dark ? .dark : .light
        reconnectSwiftUIHostToWindow()
        osrsPreparedArticleWebViewStore.shared.detachFromKeyWindowForResume()
        // Safari leave parks SpringBoard's scene snapshot over the live
        // window (theme fill + ◀ Safari, no hits). Activating this same
        // session and bouncing windowLevel on this window — not
        // windowScene = nil — is what 4bcb7f27 used to lift that snapshot.
        // LCD pixels then come from a .statusBar overlay that is key and
        // returns the live tree from hitTest. Cover windows at .alert
        // ate hits without forwarding and are gone.
        if window is osrsResumeCoverWindow {
            window.makeKeyAndVisible()
        } else {
            window.windowLevel = .statusBar
            window.makeKeyAndVisible()
            CATransaction.flush()
            window.windowLevel = .normal
            window.makeKeyAndVisible()
        }
        UIApplication.shared.requestSceneSessionActivation(
            windowScene.session,
            userActivity: nil,
            options: nil
        )
        UIApplication.shared.requestSceneSessionRefresh(windowScene.session)
        osrsSceneCompositor.restore(window)
        startResumeDisplayLink()
        print("🪟 osrsSceneDelegate restore same SwiftUI host reason=\(reason)")
        NSLog("osrsSceneDelegate restore same SwiftUI host reason=%@", reason)
    }

    /// Re-parent the existing CustomMainTabView host. Recreating the
    /// UIHostingController would reset ArticleView @StateObject. Do not
    /// `removeFromSuperview` when already attached: that parks WK GPU tiles.
    private func reconnectSwiftUIHostToWindow() {
        guard let window, let container = sceneContainer, let host = appHost else { return }
        host.loadViewIfNeeded()
        let hostView = host.view!
        if host.parent !== container || hostView.superview !== container.view || hostView.window == nil {
            container.osrsInstall(host)
        } else {
            hostView.isHidden = false
            hostView.alpha = 1
            hostView.layer.shouldRasterize = false
            container.view.bringSubviewToFront(hostView)
        }
        hostView.isHidden = false
        hostView.alpha = 1
        hostView.layer.shouldRasterize = false
        window.makeKeyAndVisible()
        CATransaction.flush()
        print(
            "🪟 osrsSceneDelegate reconnect host window=\(hostView.window != nil) key=\(window.isKeyWindow) scene=\(window.windowScene?.activationState.rawValue ?? -1) app=\(UIApplication.shared.applicationState.rawValue)"
        )
    }

    private func existingSceneWindow(on windowScene: UIWindowScene) -> UIWindow? {
        if let window, window.windowScene === windowScene {
            return window
        }
        return windowScene.windows.first { candidate in
            let name = NSStringFromClass(type(of: candidate))
            return !name.contains("TextEffects")
                && !name.contains("Keyboard")
                && !name.contains("StatusBar")
        }
    }

    private func replaceRootViewController(on window: UIWindow, with root: UIViewController) {
        root.view.frame = window.bounds
        UIView.performWithoutAnimation {
            window.rootViewController = root
        }
        root.view.layer.contents = nil
        window.layer.contents = nil
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()
        window.layoutIfNeeded()
        CATransaction.flush()
    }

    private func nudgeCompositor(on windowScene: UIWindowScene) {
        if osrsResumeFrameOverlay.hasAdoptedLiveRoot {
            osrsResumeFrameOverlay.makeOverlayKeyIfInstalled()
            return
        }
        guard let window, window.windowScene === windowScene else { return }
        if !osrsResumeFrameOverlay.hasCapturedFrame {
            window.layer.contents = nil
            window.rootViewController?.view.layer.contents = nil
        }
        let original = window.frame
        window.frame = original.insetBy(dx: 0, dy: 1)
        window.layoutIfNeeded()
        CATransaction.flush()
        window.frame = original
        window.layoutIfNeeded()
        _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        ) { error in
            print("🪟 osrsSceneDelegate geometry error: \(error)")
        }
        UIApplication.shared.requestSceneSessionRefresh(windowScene.session)
        osrsSceneCompositor.restore(window)
        if osrsResumeFrameOverlay.isPassthroughInstalled {
            osrsResumeFrameOverlay.makeOverlayKeyIfInstalled()
        } else {
            window.makeKeyAndVisible()
        }
        print("🪟 osrsSceneDelegate nudge key=\(window.isKeyWindow) overlay=\(osrsResumeFrameOverlay.isPassthroughInstalled) frame=\(Int(window.frame.width))x\(Int(window.frame.height))")
        NSLog("osrsSceneDelegate nudge key=%d overlay=%d", window.isKeyWindow ? 1 : 0, osrsResumeFrameOverlay.isPassthroughInstalled ? 1 : 0)
    }

    private func startResumeDisplayLink() {
        resumeDisplayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tickResumeFrame))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
        }
        link.add(to: .main, forMode: .common)
        resumeDisplayLink = link
    }

    @objc private func tickResumeFrame() {
        if osrsResumeFrameOverlay.hasAdoptedLiveRoot {
            resumeDisplayLink?.invalidate()
            resumeDisplayLink = nil
            return
        }
        guard let window else { return }
        window.isHidden = false
        window.alpha = 1
        osrsResumeFrameOverlay.blitPassthroughResumePixels(from: window)
        window.rootViewController?.view.setNeedsLayout()
        if !osrsResumeFrameOverlay.isPassthroughInstalled {
            resumeDisplayLink?.invalidate()
            resumeDisplayLink = nil
        }
    }
}

/// Permanent UIKit window root. The SwiftUI app lives as a child so the
/// window's compositor target stays UIKit while `CustomMainTabView` remains
/// the only content host.
final class osrsAppSceneViewController: UIViewController {
    private(set) var osrsContent: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        if let window = view.window {
            osrsHostThemeFill.apply(
                to: window,
                themeBackground: UIColor(osrsAppRoot.themeManager.currentTheme.background)
            )
        } else {
            view.backgroundColor = UIColor(osrsAppRoot.themeManager.currentTheme.background)
        }
    }

    func osrsInstall(_ child: UIViewController) {
        osrsContent?.willMove(toParent: nil)
        osrsContent?.view.removeFromSuperview()
        osrsContent?.removeFromParent()
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.view.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(child.view)
        child.didMove(toParent: self)
        osrsContent = child
        view.layer.contents = nil
        view.setNeedsLayout()
        view.layoutIfNeeded()
        CATransaction.flush()
    }
}

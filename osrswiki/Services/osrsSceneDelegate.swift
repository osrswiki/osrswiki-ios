import SwiftUI
import UIKit

/// Owns the scene's one UIWindow. iOS 26 can keep SpringBoard's background
/// snapshot on screen after a Settings round-trip even when extra windows
/// become key. Replacing the primary window's root (not stacking a second
/// UIWindow, not detaching the scene window) is the resume path.
final class osrsSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var needsResumeReplace = false
    private var resumeDisplayLink: CADisplayLink?
    private var isReplacing = false
    private var finishedFirstActivation = false
    private var appObservers: [NSObjectProtocol] = []

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        print("🪟 osrsSceneDelegate willConnect session=\(session.persistentIdentifier)")
        NSLog("osrsSceneDelegate willConnect session=%@", session.persistentIdentifier)
        observeApplicationLifecycle()
        attachPrimaryWindow(to: windowScene, resumeArticle: false, isResume: false, reason: "connect")
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        nil
    }

    func scene(_ scene: UIScene, restoreInteractionStateWith stateRestorationActivity: NSUserActivity) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
        markNeedsResumeReplace(reason: "sceneWillResignActive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        markNeedsResumeReplace(reason: "sceneDidEnterBackground")
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
            self?.markNeedsResumeReplace(reason: "applicationWillResignActive")
        })
        appObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markNeedsResumeReplace(reason: "applicationDidEnterBackground")
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
        appObservers.append(center.addObserver(
            forName: .osrsResumableArticleDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let windowScene = self?.window?.windowScene else { return }
            self?.installForegroundArticleHostIfNeeded(on: windowScene, reason: "foreground-article")
        })
    }

    private func markNeedsResumeReplace(reason: String) {
        needsResumeReplace = true
        osrsAppRoot.appState.noteApplicationDidEnterBackground()
        osrsAppRoot.appState.rememberResumableArticle()
        print("🪟 osrsSceneDelegate mark resume reason=\(reason)")
        NSLog("osrsSceneDelegate mark resume reason=%@", reason)
        // A UIHostingController window root that backgrounds on iOS 26 keeps
        // SpringBoard's parchment snapshot even after a later root replace.
        // Switching to the UIKit article host before the snapshot is taken
        // is the resume path that actually reaches the LCD.
        guard !(sceneContainer?.osrsContent is osrsResumedArticleViewController),
              osrsAppRoot.appState.resumableArticleURL != nil,
              let windowScene = window?.windowScene else {
            return
        }
        replacePrimaryWindow(on: windowScene, reason: "resign-\(reason)")
    }

    private func handleBecameActive(_ scene: UIScene, reason: String) {
        osrsAppRoot.themeManager.applyPersistedThemeToWindows()
        osrsAppRoot.applyGlobalTheming()
        guard let windowScene = scene as? UIWindowScene else { return }
        if !needsResumeReplace {
            if !finishedFirstActivation {
                finishedFirstActivation = true
                print("🪟 osrsSceneDelegate first activation skip replace trigger=\(reason)")
                NSLog("osrsSceneDelegate first activation skip replace trigger=%@", reason)
                // UIHostingController as the window root poisons iOS 26 resume.
                // Install the UIKit article host while still foregrounded so
                // SpringBoard snapshots UIKit, not SwiftUI.
                DispatchQueue.main.async { [weak self] in
                    self?.installForegroundArticleHostIfNeeded(on: windowScene, reason: "foreground-article")
                }
            }
            return
        }
        finishedFirstActivation = true
        needsResumeReplace = false
        print("🪟 osrsSceneDelegate resume replace trigger=\(reason)")
        NSLog("osrsSceneDelegate resume replace trigger=%@", reason)
        replacePrimaryWindow(on: windowScene, reason: reason)
        osrsAppRoot.appState.noteApplicationDidBecomeActive()
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

    private func installForegroundArticleHostIfNeeded(on windowScene: UIWindowScene, reason: String) {
        guard osrsAppRoot.appState.resumableArticleURL != nil else { return }
        if sceneContainer?.osrsContent is osrsResumedArticleViewController { return }
        if window?.rootViewController is osrsResumedArticleViewController { return }
        print("🪟 osrsSceneDelegate foreground article host reason=\(reason)")
        NSLog("osrsSceneDelegate foreground article host reason=%@", reason)
        replacePrimaryWindow(on: windowScene, reason: reason)
    }

    func replacePrimaryWindow(on windowScene: UIWindowScene, reason: String) {
        let isResume = reason != "connect"
        attachPrimaryWindow(
            to: windowScene,
            resumeArticle: osrsAppRoot.appState.resumableArticleURL != nil,
            isResume: isResume,
            reason: reason
        )
    }

    private func attachPrimaryWindow(
        to windowScene: UIWindowScene,
        resumeArticle: Bool,
        isResume: Bool,
        reason: String
    ) {
        guard !isReplacing else { return }
        isReplacing = true
        defer { isReplacing = false }

        let theme = osrsAppRoot.themeManager.currentTheme
        let bounds = windowScene.coordinateSpace.bounds
        // Reuse the scene window. Creating a replacement UIWindow and detaching
        // the original (windowScene = nil) leaves iOS 26 compositing the
        // parchment snapshot instead of the live root.
        let sceneWindow = existingSceneWindow(on: windowScene) ?? osrsResumedSceneWindow(windowScene: windowScene)
        sceneWindow.frame = bounds
        sceneWindow.bounds = bounds
        sceneWindow.windowLevel = .normal
        sceneWindow.backgroundColor = UIColor(theme.background)
        sceneWindow.overrideUserInterfaceStyle = osrsAppRoot.themeManager.currentColorScheme == .dark ? .dark : .light
        sceneWindow.layer.contents = nil
        sceneWindow.layer.shouldRasterize = false

        let articleURL = osrsAppRoot.appState.resumableArticleURL
        let root: UIViewController
        if isResume {
            // Remounting CustomMainTabView after background freezes the LCD on
            // the parchment snapshot. Always replace with the UIKit article host.
            root = osrsResumedArticleViewController(
                appState: osrsAppRoot.appState,
                themeManager: osrsAppRoot.themeManager,
                articleURL: articleURL,
                webView: nil
            )
        } else if resumeArticle {
            root = osrsResumedArticleViewController(
                appState: osrsAppRoot.appState,
                themeManager: osrsAppRoot.themeManager,
                articleURL: articleURL,
                webView: nil
            )
        } else {
            let host = UIHostingController(rootView: osrsAppRoot.rootView)
            host.view.backgroundColor = UIColor(theme.background)
            root = host
        }

        let container = sceneContainer ?? osrsAppSceneViewController()
        container.view.backgroundColor = UIColor(theme.background)
        if sceneWindow.rootViewController !== container {
            replaceRootViewController(on: sceneWindow, with: container)
        }
        container.osrsInstall(root)
        sceneWindow.makeKeyAndVisible()
        window = sceneWindow

        UIApplication.shared.requestSceneSessionRefresh(windowScene.session)
        print(
            "🪟 osrsSceneDelegate attach reason=\(reason) resumeArticle=\(resumeArticle) url=\(articleURL?.absoluteString ?? "none") sceneWindows=\(windowScene.windows.count) key=\(sceneWindow.isKeyWindow) frame=\(Int(sceneWindow.frame.width))x\(Int(sceneWindow.frame.height))"
        )
        NSLog(
            "osrsSceneDelegate attach reason=%@ resumeArticle=%d url=%@ key=%d",
            reason,
            resumeArticle ? 1 : 0,
            articleURL?.absoluteString ?? "none",
            sceneWindow.isKeyWindow ? 1 : 0
        )
        osrsSceneCompositor.restore(sceneWindow)
        startResumeDisplayLink()
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
        guard let window, window.windowScene === windowScene else { return }
        window.layer.contents = nil
        window.rootViewController?.view.layer.contents = nil
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
        print("🪟 osrsSceneDelegate nudge key=\(window.isKeyWindow) frame=\(Int(window.frame.width))x\(Int(window.frame.height))")
        NSLog("osrsSceneDelegate nudge key=%d", window.isKeyWindow ? 1 : 0)
    }

    private func startResumeDisplayLink() {
        resumeDisplayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tickResumeFrame))
        link.add(to: .main, forMode: .common)
        resumeDisplayLink = link
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.resumeDisplayLink?.invalidate()
            self?.resumeDisplayLink = nil
        }
    }

    @objc private func tickResumeFrame() {
        window?.layer.contents = nil
        window?.layer.setNeedsDisplay()
        window?.rootViewController?.view.layer.setNeedsDisplay()
        window?.rootViewController?.view.setNeedsLayout()
    }
}

/// Permanent UIKit window root. UIHostingController as the scene window's
/// rootViewController poisons iOS 26 resume; this container keeps the
/// window's compositor target UIKit for the process lifetime.
final class osrsAppSceneViewController: UIViewController {
    private(set) var osrsContent: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(osrsAppRoot.themeManager.currentTheme.background)
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

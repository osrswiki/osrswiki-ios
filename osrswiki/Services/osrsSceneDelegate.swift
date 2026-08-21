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
        print("🪟 osrsSceneDelegate resume compositor trigger=\(reason)")
        NSLog("osrsSceneDelegate resume compositor trigger=%@", reason)
        restoreResumedScene(on: windowScene, reason: reason)
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
        sceneWindow.backgroundColor = UIColor(theme.background)
        sceneWindow.overrideUserInterfaceStyle = osrsAppRoot.themeManager.currentColorScheme == .dark ? .dark : .light
        sceneWindow.layer.contents = nil
        sceneWindow.layer.shouldRasterize = false

        let container = sceneContainer ?? osrsAppSceneViewController()
        container.view.backgroundColor = UIColor(theme.background)
        if sceneWindow.rootViewController !== container {
            replaceRootViewController(on: sceneWindow, with: container)
        }
        if container.osrsContent == nil {
            let host = appHost ?? UIHostingController(rootView: osrsAppRoot.rootView)
            host.view.backgroundColor = UIColor(theme.background)
            appHost = host
            container.osrsInstall(host)
        }
        sceneWindow.makeKeyAndVisible()
        window = sceneWindow

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
        window.backgroundColor = UIColor(osrsAppRoot.themeManager.currentTheme.background)
        window.overrideUserInterfaceStyle = osrsAppRoot.themeManager.currentColorScheme == .dark ? .dark : .light
        window.layer.contents = nil
        window.makeKeyAndVisible()
        UIApplication.shared.requestSceneSessionRefresh(windowScene.session)
        osrsSceneCompositor.restore(window)
        startResumeDisplayLink()
        print("🪟 osrsSceneDelegate restore same SwiftUI host reason=\(reason)")
        NSLog("osrsSceneDelegate restore same SwiftUI host reason=%@", reason)
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

/// Permanent UIKit window root. The SwiftUI app lives as a child so the
/// window's compositor target stays UIKit while `CustomMainTabView` remains
/// the only content host.
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

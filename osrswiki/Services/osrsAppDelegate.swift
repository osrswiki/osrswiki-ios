import UIKit

@main
final class osrsAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        osrsAppRoot.start()
        osrsAppRoot.applyGlobalTheming()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "osrs.default.scene.v2",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = osrsSceneDelegate.self
        print("🪟 osrsAppDelegate configurationForConnecting role=\(connectingSceneSession.role.rawValue)")
        return configuration
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        print("🪟 osrsAppDelegate discarded sessions=\(sceneSessions.count)")
    }
}

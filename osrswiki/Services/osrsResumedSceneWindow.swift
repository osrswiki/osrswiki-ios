//
//  osrsResumedSceneWindow.swift
//  osrswiki
//
//  iOS 26 WindowGroup UIHostingView can stop compositing UIKit children
//  (WKWebView, Liquid Glass) after a scene resume. The live view tree is
//  still there; the framebuffer is the SwiftUI theme fill. Tweaking layers
//  inside that host does not reconnect them.
//
//  After a real background, osrsSceneDelegate keeps the scene's one UIWindow
//  and the same CustomMainTabView host, then asks osrsSceneCompositor to
//  restore. Do not stack a second UIWindow or load the public wiki as a
//  parallel article product.
//

import UIKit

final class osrsResumedSceneWindow: UIWindow {
    static func bindRuntime(appState: AppState, themeManager: osrsThemeManager) {
        _ = appState
        _ = themeManager
    }

    static func reconnectAfterBackground() {
        print("🪟 osrsResumedSceneWindow resume: deferred to osrsSceneDelegate compositor restore")
    }
}

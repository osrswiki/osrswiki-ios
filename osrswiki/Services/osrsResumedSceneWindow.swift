//
//  osrsResumedSceneWindow.swift
//  osrswiki
//
//  iOS 26 WindowGroup UIHostingView can stop compositing UIKit children
//  (WKWebView, Liquid Glass) after a scene resume. The live view tree is
//  still there; the framebuffer is the SwiftUI theme fill. Tweaking layers
//  inside that host does not reconnect them.
//
//  After a real background, osrsSceneDelegate keeps the same
//  CustomMainTabView host and scene container. A fresh osrsResumedSceneWindow
//  is only a compositor surface for that same root — not a second article
//  product and not a cover window. Do not load the public wiki in parallel.
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

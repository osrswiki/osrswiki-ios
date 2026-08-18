//
//  GlobalOverlayManager.swift
//  OSRS Wiki
//
//  Global overlay system for positioning views at the same hierarchy level
//  Enables true +Z overlay instead of +Y positioning
//

import SwiftUI

@MainActor
class GlobalOverlayManager: ObservableObject {
    @Published private(set) var articleBottomBar: AnyView?
    @Published private(set) var articleBottomBarOwner: String?
    @Published private(set) var mainTabBarHiddenOwner: String?
    @Published private(set) var articleBottomBarExitProgress: CGFloat = 0
    
    /// Show article bottom bar overlay at exact same coordinates as main tab bar
    func showArticleBottomBar<Content: View>(owner: String, @ViewBuilder content: () -> Content) {
        articleBottomBarOwner = owner
        articleBottomBar = AnyView(content())
    }
    
    /// Hide article bottom bar overlay
    func hideArticleBottomBar(owner: String) {
        guard articleBottomBarOwner == owner else { return }
        articleBottomBarOwner = nil
        articleBottomBar = nil
        articleBottomBarExitProgress = 0
    }

    func hideMainTabBar(owner: String) {
        mainTabBarHiddenOwner = owner
    }

    func showMainTabBar(owner: String) {
        guard mainTabBarHiddenOwner == owner else { return }
        mainTabBarHiddenOwner = nil
    }

    func setArticleBottomBarExitProgress(_ progress: CGFloat) {
        articleBottomBarExitProgress = min(1, max(0, progress))
    }
}

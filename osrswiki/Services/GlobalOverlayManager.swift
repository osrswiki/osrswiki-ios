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
    @Published private(set) var articleBottomBarCovered: Bool = false
    
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
        articleBottomBarCovered = false
    }

    func hideMainTabBar(owner: String) {
        mainTabBarHiddenOwner = owner
    }

    func showMainTabBar(owner: String) {
        guard mainTabBarHiddenOwner == owner else { return }
        mainTabBarHiddenOwner = nil
    }

    func setArticleBottomBarExitProgress(_ progress: CGFloat) {
        let clamped = min(1, max(0, progress))
        guard abs(articleBottomBarExitProgress - clamped) > 0.0005 else { return }
        articleBottomBarExitProgress = clamped
    }

    func setArticleBottomBarCovered(_ covered: Bool) {
        guard articleBottomBarCovered != covered else { return }
        articleBottomBarCovered = covered
    }
}

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
    @Published var articleBottomBar: AnyView?
    
    /// Show article bottom bar overlay at exact same coordinates as main tab bar
    func showArticleBottomBar<Content: View>(@ViewBuilder content: () -> Content) {
        articleBottomBar = AnyView(content())
    }
    
    /// Hide article bottom bar overlay
    func hideArticleBottomBar() {
        articleBottomBar = nil
    }
}
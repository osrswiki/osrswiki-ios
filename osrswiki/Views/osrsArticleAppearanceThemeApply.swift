import SwiftUI

/// Live theme apply for an already-mounted article. Theme changes from the
/// article-presented Appearances sheet must retint the existing document and
/// chrome in place — they must not destroy the WKWebView or unclaim the bar.
enum osrsArticleAppearanceThemeApply {
    /// Resume compositor restore is for scene foreground, not an in-app theme
    /// pick. Installing the resume overlay while Appearances is presented can
    /// leave a chrome-less dead surface.
    static func shouldRestoreSceneCompositorOnThemePaint(isLiveSelectionChange: Bool) -> Bool {
        !isLiveSelectionChange
    }

    @MainActor
    static func applyToExistingArticle(
        theme: any osrsThemeProtocol,
        themeManager: osrsThemeManager,
        viewModel: ArticleViewModel
    ) {
        viewModel.applyLiveTheme(theme, themeManager: themeManager)
        UIApplication.refreshFloatingTabBarMaterial()
    }

    @MainActor
    static func articleChromeIsClaimed(
        overlayManager: GlobalOverlayManager?,
        articleIdentity: String
    ) -> Bool {
        overlayManager?.articleBottomBarOwner == articleIdentity
            && overlayManager?.articleBottomBar != nil
    }
}

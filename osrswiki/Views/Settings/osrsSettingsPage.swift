import SwiftUI

/// Shared Settings-page chrome used by More-pushed list screens.
struct osrsSettingsPageModifier: ViewModifier {
    @EnvironmentObject private var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) private var osrsTheme
    let title: String
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(osrsTheme.background))
            .foregroundStyle(Color(osrsTheme.primaryTextColor))
            .tint(Color(osrsTheme.primary))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .toolbarBackground(Color(osrsTheme.background), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(themeManager.currentColorScheme, for: .navigationBar)
            .id(themeManager.selectedTheme)
            .osrsInteractiveBackSwipe()
    }
}

extension View {
    func osrsSettingsPage(
        title: String,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline
    ) -> some View {
        modifier(osrsSettingsPageModifier(title: title, titleDisplayMode: titleDisplayMode))
    }
}

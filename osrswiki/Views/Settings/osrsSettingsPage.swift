import SwiftUI

/// Shared Settings-page chrome used by More-pushed list screens.
struct osrsSettingsPageModifier: ViewModifier {
    @Environment(\.osrsTheme) private var osrsTheme
    let title: String
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(osrsTheme.background))
            .foregroundStyle(Color(osrsTheme.primaryTextColor))
            .osrsMoreDestinationChrome(title: title, titleDisplayMode: titleDisplayMode)
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

import SwiftUI

/// Shared chrome for every pushed More destination.
///
/// iOS 26 keeps the system material navigation bar (the Donate/About/Feedback
/// look). Older OS versions keep an opaque surface bar. Theme safety comes from
/// `osrsLiveThemeApplier`, not from painting the bar with a solid page color.
struct osrsMoreDestinationChromeModifier: ViewModifier {
    @EnvironmentObject private var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) private var osrsTheme
    let title: String
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .tint(Color(osrsTheme.primary))
            .toolbarColorScheme(themeManager.currentColorScheme, for: .navigationBar)
            .modifier(osrsLegacyOpaqueNavigationSurface())
            .osrsInteractiveBackSwipe()
            .onAppear(perform: applyLiveTheme)
            .onChange(of: themeManager.currentTheme.primary) { _, _ in
                applyLiveTheme()
            }
            .onChange(of: themeManager.selectedTheme) { _, _ in
                applyLiveTheme()
            }
    }

    private func applyLiveTheme() {
        osrsLiveThemeApplier.apply(
            themeManager.currentTheme,
            colorScheme: themeManager.currentColorScheme
        )
    }
}

private struct osrsLegacyOpaqueNavigationSurface: ViewModifier {
    @Environment(\.osrsTheme) private var osrsTheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(Color(osrsTheme.surface), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

extension View {
    func osrsMoreDestinationChrome(
        title: String,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline
    ) -> some View {
        modifier(
            osrsMoreDestinationChromeModifier(title: title, titleDisplayMode: titleDisplayMode)
        )
    }
}

import SwiftUI

/// Shared Settings-page chrome used by More-pushed list screens.
struct osrsSettingsPageModifier: ViewModifier {
    let title: String
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.osrsBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .osrsInteractiveBackSwipe()
    }
}

extension View {
    func osrsSettingsPage(
        title: String,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large
    ) -> some View {
        modifier(osrsSettingsPageModifier(title: title, titleDisplayMode: titleDisplayMode))
    }
}

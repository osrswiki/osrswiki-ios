import SwiftUI

extension View {
    /// Rebuild the NavigationStack hosting controller after a scene resume.
    /// Changing only the article destination identity leaves a dead iOS 26
    /// stack host showing the window background.
    func osrsResumedNavigationHost(_ generation: UInt64) -> some View {
        id("osrs-navigation-host-\(generation)")
    }
}

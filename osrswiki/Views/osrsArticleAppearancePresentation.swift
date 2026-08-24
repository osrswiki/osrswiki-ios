import Combine
import Foundation
import SwiftUI

/// Presentation intent for article-presented Appearances.
///
/// Keep this separate from theme paint: interactive dismiss must clear the
/// flag, and a later article `onAppear` / environment refresh must not set it
/// true again. Bottom-bar Appearance still presents through
/// `ArticleViewModel.performAppearanceAction` → `.showAppearanceSettings`.
@MainActor
final class osrsArticleAppearancePresentation: ObservableObject {
    static let redisplaySuppressionInterval: TimeInterval = 0.45

    @Published private(set) var isPresented = false
    @Published private(set) var highlightFloorNumbering = false

    private var consumedLaunchPresentation = false
    private var suppressPresentUntil: TimeInterval = 0

    var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { self.isPresented },
            set: { newValue in
                if newValue {
                    self.present()
                } else {
                    self.dismiss()
                }
            }
        )
    }

    func present(
        highlightFloorNumbering: Bool = false,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard now >= suppressPresentUntil else { return }
        self.highlightFloorNumbering = highlightFloorNumbering
        isPresented = true
    }

    func handleShowAppearanceNotification(
        _ notification: Notification,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        present(
            highlightFloorNumbering: (notification.userInfo?["highlightFloorNumbering"] as? Bool) == true,
            now: now
        )
    }

    func dismiss(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        isPresented = false
        highlightFloorNumbering = false
        suppressPresentUntil = now + Self.redisplaySuppressionInterval
    }

    /// Article chrome `onAppear` / environment refresh. Launch-arg open is
    /// consumed once so a sheet dismiss cannot immediately re-present.
    func handleArticleChromeUpdate(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
#if DEBUG
        if arguments.contains("-startArticleShowAppearance") {
            guard !consumedLaunchPresentation else { return }
            consumedLaunchPresentation = true
            present(
                highlightFloorNumbering: arguments.contains("-highlightFloorNumberingOnAppearance"),
                now: now
            )
            return
        }
#endif
        _ = now
    }
}

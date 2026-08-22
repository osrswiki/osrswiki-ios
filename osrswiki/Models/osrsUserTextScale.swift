import SwiftUI
import UIKit

extension DynamicTypeSize {
    /// Combine iOS Dynamic Type with the in-app Appearance text-size slider.
    /// 100% keeps the system size; 85% steps down once; 140% steps up three.
    func osrsApplyingUserScale(_ scale: Double) -> DynamicTypeSize {
        let steps: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]
        guard let index = steps.firstIndex(of: self) else { return self }
        let delta: Int
        switch scale {
        case ..<0.90: delta = -1
        case ..<0.97: delta = 0
        case ..<1.08: delta = 0
        case ..<1.18: delta = 1
        case ..<1.30: delta = 2
        default: delta = 3
        }
        return steps[min(steps.count - 1, max(0, index + delta))]
    }

    /// Map SwiftUI Dynamic Type (including the in-app slider) onto UIKit text styles.
    var osrsUIContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }

    func osrsPreferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: osrsUIContentSizeCategory)
        )
    }
}

struct osrsUserTextScaleModifier: ViewModifier {
    @EnvironmentObject private var themeManager: osrsThemeManager
    @Environment(\.dynamicTypeSize) private var systemSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(systemSize.osrsApplyingUserScale(themeManager.articleTextScale))
    }
}

extension View {
    func osrsUserTextScaled() -> some View {
        modifier(osrsUserTextScaleModifier())
    }
}

import SwiftUI

enum osrsStaticSettingsPreviewAssets {
    static let logicalPreviewSize = CGSize(width: 82, height: 120)

    static func themeImageName(for theme: osrsThemeSelection) -> String {
        switch theme {
        case .osrsLight:
            return "settings_preview_theme_light"
        case .osrsDark:
            return "settings_preview_theme_dark"
        case .automatic:
            return "settings_preview_theme_auto"
        }
    }

    static func tableImageName(collapsed: Bool, theme: any osrsThemeProtocol) -> String {
        let themePrefix = theme.name.lowercased().contains("dark") ? "dark" : "light"
        let state = collapsed ? "collapsed" : "expanded"
        return "settings_preview_table_\(themePrefix)_\(state)"
    }
}

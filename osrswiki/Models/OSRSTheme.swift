//
//  OSRSTheme.swift
//  OSRS Wiki
//
//  Created on iOS theming research session
//  Modern SwiftUI theming architecture based on ShapeStyle pattern
//

import SwiftUI

// MARK: - Theme Protocol

/// Protocol defining the semantic color structure for OSRS themes
/// Mirrors Android's semantic color architecture for cross-platform consistency
protocol osrsThemeProtocol {
    // MARK: - Material Design Foundation Colors (guaranteed contrast pairs)
    
    // Primary colors - main brand colors
    var primary: Color { get }
    var onPrimary: Color { get }
    var primaryContainer: Color { get }
    var onPrimaryContainer: Color { get }
    
    // Surface colors - backgrounds and cards
    var surface: Color { get }
    var onSurface: Color { get }
    var surfaceVariant: Color { get }
    var onSurfaceVariant: Color { get }
    
    // Background colors
    var background: Color { get }
    var onBackground: Color { get }
    
    // Secondary colors
    var secondary: Color { get }
    var onSecondary: Color { get }
    var secondaryContainer: Color { get }
    var onSecondaryContainer: Color { get }
    
    // Accent and functional colors
    var accent: Color { get }
    var link: Color { get }
    var error: Color { get }
    var onError: Color { get }
    var outline: Color { get }
    
    // MARK: - App-Specific Semantic Colors (parallel to Android attrs.xml)
    
    /// Main paper/parchment background - equivalent to Android's ?attr/paper_color
    var paperColor: Color { get }
    
    /// Primary text on surfaces - equivalent to Android's ?attr/primary_text_color
    var primaryTextColor: Color { get }
    
    /// Secondary text on surfaces - equivalent to Android's ?attr/secondary_text_color
    /// Guaranteed to have proper contrast on surface colors
    var secondaryTextColor: Color { get }
    
    /// Border color for UI elements - equivalent to Android's ?attr/border_color
    var borderColor: Color { get }
    
    /// Bottom navigation background - equivalent to Android's ?attr/bottom_nav_background_color
    var bottomNavBackgroundColor: Color { get }
    
    /// Placeholder icon/text color - equivalent to Android's ?attr/placeholder_color
    var placeholderColor: Color { get }
    
    /// Search box background - equivalent to Android's ?attr/search_box_background_color
    var searchBoxBackgroundColor: Color { get }
    
    /// Map control text color - equivalent to Android's ?attr/map_control_text
    var mapControlTextColor: Color { get }
    
    /// Map control background color - equivalent to Android's ?attr/map_control_background
    var mapControlBackgroundColor: Color { get }
    
    /// Bottom navigation inactive color - equivalent to Android's @color/bottom_nav_inactive
    var bottomNavInactiveColor: Color { get }
    
    // MARK: - Legacy Convenience Properties (for backwards compatibility)
    
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var border: Color { get }
    var divider: Color { get }
}

// MARK: - Theme Style Enum

/// Semantic color styles for use with osrsThemeColor ShapeStyle
/// Mirrors Android's semantic color system for cross-platform consistency
enum osrsThemeStyle: Hashable {
    // MARK: - Material Design Foundation Colors
    case primary, onPrimary, primaryContainer, onPrimaryContainer
    case surface, onSurface, surfaceVariant, onSurfaceVariant
    case background, onBackground
    case secondary, onSecondary, secondaryContainer, onSecondaryContainer
    case accent, link, error, onError, outline
    
    // MARK: - App-Specific Semantic Colors (parallel to Android attrs.xml)
    case paperColor
    case primaryTextColor
    case secondaryTextColor
    case borderColor
    case bottomNavBackgroundColor
    case placeholderColor
    case searchBoxBackgroundColor
    case mapControlTextColor
    case mapControlBackgroundColor
    case bottomNavInactiveColor
    
    // MARK: - Legacy (for backwards compatibility)
    case textPrimary, textSecondary
    case border, divider
}

// MARK: - Custom ShapeStyle Implementation

/// Custom ShapeStyle that resolves colors based on the current OSRS theme
/// This enables natural SwiftUI color usage like `.foregroundStyle(.osrsPrimary)`
struct osrsThemeColor: ShapeStyle, Hashable {
    private let style: osrsThemeStyle
    
    init(_ style: osrsThemeStyle) {
        self.style = style
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(style)
    }
    
    static func == (lhs: osrsThemeColor, rhs: osrsThemeColor) -> Bool {
        return lhs.style == rhs.style
    }
    
    func resolve(in environment: EnvironmentValues) -> Color {
        let theme = environment.osrsTheme
        
        switch style {
        // MARK: - Material Design Foundation Colors
        case .primary: return theme.primary
        case .onPrimary: return theme.onPrimary
        case .primaryContainer: return theme.primaryContainer
        case .onPrimaryContainer: return theme.onPrimaryContainer
            
        case .surface: return theme.surface
        case .onSurface: return theme.onSurface
        case .surfaceVariant: return theme.surfaceVariant
        case .onSurfaceVariant: return theme.onSurfaceVariant
            
        case .background: return theme.background
        case .onBackground: return theme.onBackground
            
        case .secondary: return theme.secondary
        case .onSecondary: return theme.onSecondary
        case .secondaryContainer: return theme.secondaryContainer
        case .onSecondaryContainer: return theme.onSecondaryContainer
            
        case .accent: return theme.accent
        case .link: return theme.link
        case .error: return theme.error
        case .onError: return theme.onError
        case .outline: return theme.outline
            
        // MARK: - App-Specific Semantic Colors
        case .paperColor: return theme.paperColor
        case .primaryTextColor: return theme.primaryTextColor
        case .secondaryTextColor: return theme.secondaryTextColor
        case .borderColor: return theme.borderColor
        case .bottomNavBackgroundColor: return theme.bottomNavBackgroundColor
        case .placeholderColor: return theme.placeholderColor
        case .searchBoxBackgroundColor: return theme.searchBoxBackgroundColor
        case .mapControlTextColor: return theme.mapControlTextColor
        case .mapControlBackgroundColor: return theme.mapControlBackgroundColor
        case .bottomNavInactiveColor: return theme.bottomNavInactiveColor
            
        // MARK: - Legacy (for backwards compatibility)
        case .textPrimary: return theme.textPrimary
        case .textSecondary: return theme.textSecondary
        case .border: return theme.border
        case .divider: return theme.divider
        }
    }
}

// MARK: - ShapeStyle Extensions

/// Extensions to enable natural color usage throughout the app
/// Usage: .foregroundStyle(.osrsPrimary) or .background(.osrsSurface)
extension ShapeStyle where Self == osrsThemeColor {
    // MARK: - Material Design Foundation Colors
    static var osrsPrimary: osrsThemeColor { osrsThemeColor(.primary) }
    static var osrsOnPrimary: osrsThemeColor { osrsThemeColor(.onPrimary) }
    static var osrsPrimaryContainer: osrsThemeColor { osrsThemeColor(.primaryContainer) }
    static var osrsOnPrimaryContainer: osrsThemeColor { osrsThemeColor(.onPrimaryContainer) }
    
    static var osrsSurface: osrsThemeColor { osrsThemeColor(.surface) }
    static var osrsOnSurface: osrsThemeColor { osrsThemeColor(.onSurface) }
    static var osrsSurfaceVariant: osrsThemeColor { osrsThemeColor(.surfaceVariant) }
    static var osrsOnSurfaceVariant: osrsThemeColor { osrsThemeColor(.onSurfaceVariant) }
    
    static var osrsBackground: osrsThemeColor { osrsThemeColor(.background) }
    static var osrsOnBackground: osrsThemeColor { osrsThemeColor(.onBackground) }
    
    static var osrsSecondary: osrsThemeColor { osrsThemeColor(.secondary) }
    static var osrsOnSecondary: osrsThemeColor { osrsThemeColor(.onSecondary) }
    static var osrsSecondaryContainer: osrsThemeColor { osrsThemeColor(.secondaryContainer) }
    static var osrsOnSecondaryContainer: osrsThemeColor { osrsThemeColor(.onSecondaryContainer) }
    
    static var osrsAccent: osrsThemeColor { osrsThemeColor(.accent) }
    static var osrsLink: osrsThemeColor { osrsThemeColor(.link) }
    static var osrsError: osrsThemeColor { osrsThemeColor(.error) }
    static var osrsOnError: osrsThemeColor { osrsThemeColor(.onError) }
    static var osrsOutline: osrsThemeColor { osrsThemeColor(.outline) }
    
    // MARK: - App-Specific Semantic Colors (parallel to Android attrs.xml)
    static var osrsPaperColor: osrsThemeColor { osrsThemeColor(.paperColor) }
    static var osrsPrimaryTextColor: osrsThemeColor { osrsThemeColor(.primaryTextColor) }
    static var osrsSecondaryTextColor: osrsThemeColor { osrsThemeColor(.secondaryTextColor) }
    static var osrsBorderColor: osrsThemeColor { osrsThemeColor(.borderColor) }
    static var osrsBottomNavBackgroundColor: osrsThemeColor { osrsThemeColor(.bottomNavBackgroundColor) }
    static var osrsPlaceholderColor: osrsThemeColor { osrsThemeColor(.placeholderColor) }
    static var osrsSearchBoxBackgroundColor: osrsThemeColor { osrsThemeColor(.searchBoxBackgroundColor) }
    static var osrsMapControlTextColor: osrsThemeColor { osrsThemeColor(.mapControlTextColor) }
    static var osrsMapControlBackgroundColor: osrsThemeColor { osrsThemeColor(.mapControlBackgroundColor) }
    static var osrsBottomNavInactiveColor: osrsThemeColor { osrsThemeColor(.bottomNavInactiveColor) }
    
    // MARK: - Legacy (for backwards compatibility)
    static var osrsTextPrimary: osrsThemeColor { osrsThemeColor(.textPrimary) }
    static var osrsTextSecondary: osrsThemeColor { osrsThemeColor(.textSecondary) }
    static var osrsBorder: osrsThemeColor { osrsThemeColor(.border) }
    static var osrsDivider: osrsThemeColor { osrsThemeColor(.divider) }
}

// MARK: - Color Extensions

/// Extensions to enable Color usage: Color.osrsPrimary
extension Color {
    // Primary colors
    static var osrsPrimary: osrsThemeColor { osrsThemeColor(.primary) }
    static var osrsOnPrimary: osrsThemeColor { osrsThemeColor(.onPrimary) }
    static var osrsPrimaryContainer: osrsThemeColor { osrsThemeColor(.primaryContainer) }
    static var osrsOnPrimaryContainer: osrsThemeColor { osrsThemeColor(.onPrimaryContainer) }
    
    // Surface colors
    static var osrsSurface: osrsThemeColor { osrsThemeColor(.surface) }
    static var osrsOnSurface: osrsThemeColor { osrsThemeColor(.onSurface) }
    static var osrsSurfaceVariant: osrsThemeColor { osrsThemeColor(.surfaceVariant) }
    static var osrsOnSurfaceVariant: osrsThemeColor { osrsThemeColor(.onSurfaceVariant) }
    
    // Background colors
    static var osrsBackground: osrsThemeColor { osrsThemeColor(.background) }
    static var osrsOnBackground: osrsThemeColor { osrsThemeColor(.onBackground) }
    
    // Secondary colors
    static var osrsSecondary: osrsThemeColor { osrsThemeColor(.secondary) }
    static var osrsOnSecondary: osrsThemeColor { osrsThemeColor(.onSecondary) }
    static var osrsSecondaryContainer: osrsThemeColor { osrsThemeColor(.secondaryContainer) }
    static var osrsOnSecondaryContainer: osrsThemeColor { osrsThemeColor(.onSecondaryContainer) }
    
    // Accent and functional colors
    static var osrsAccent: osrsThemeColor { osrsThemeColor(.accent) }
    static var osrsLink: osrsThemeColor { osrsThemeColor(.link) }
    static var osrsError: osrsThemeColor { osrsThemeColor(.error) }
    static var osrsOnError: osrsThemeColor { osrsThemeColor(.onError) }
    static var osrsOutline: osrsThemeColor { osrsThemeColor(.outline) }
    
    // Text colors
    static var osrsTextPrimary: osrsThemeColor { osrsThemeColor(.textPrimary) }
    static var osrsTextSecondary: osrsThemeColor { osrsThemeColor(.textSecondary) }
    
    // Specialized colors
    static var osrsBorder: osrsThemeColor { osrsThemeColor(.border) }
    static var osrsDivider: osrsThemeColor { osrsThemeColor(.divider) }
    
}

// MARK: - Color Extension for Direct Color Access

extension Color {
    // Primary colors
    static var osrsPrimaryColor: Color { osrsLightTheme().primary }
    static var osrsOnPrimaryColor: Color { osrsLightTheme().onPrimary }
    static var osrsPrimaryContainerColor: Color { osrsLightTheme().primaryContainer }
    static var osrsOnPrimaryContainerColor: Color { osrsLightTheme().onPrimaryContainer }
    
    // Surface colors
    static var osrsSurfaceColor: Color { osrsLightTheme().surface }
    static var osrsOnSurfaceColor: Color { osrsLightTheme().onSurface }
    static var osrsSurfaceVariantColor: Color { osrsLightTheme().surfaceVariant }
    static var osrsOnSurfaceVariantColor: Color { osrsLightTheme().onSurfaceVariant }
    
    // Background colors
    static var osrsBackgroundColor: Color { osrsLightTheme().background }
    static var osrsOnBackgroundColor: Color { osrsLightTheme().onBackground }
    
    // Secondary colors
    static var osrsSecondaryColor: Color { osrsLightTheme().secondary }
    static var osrsOnSecondaryColor: Color { osrsLightTheme().onSecondary }
    static var osrsSecondaryContainerColor: Color { osrsLightTheme().secondaryContainer }
    static var osrsOnSecondaryContainerColor: Color { osrsLightTheme().onSecondaryContainer }
    
    // Accent and functional colors
    static var osrsAccentColor: Color { osrsLightTheme().accent }
    static var osrsErrorColor: Color { osrsLightTheme().error }
    static var osrsOnErrorColor: Color { osrsLightTheme().onError }
    
    // Outline and utility colors
    static var osrsOutlineColor: Color { osrsLightTheme().outline }
    
    // Text colors
    static var osrsTextPrimaryColor: Color { osrsLightTheme().textPrimary }
    static var osrsTextSecondaryColor: Color { osrsLightTheme().textSecondary }
    
    // Specialized colors
    static var osrsBorderColor: Color { osrsLightTheme().border }
    static var osrsDividerColor: Color { osrsLightTheme().divider }
}

// MARK: - Environment Integration

/// Custom environment key for OSRS theme
struct osrsThemeKey: EnvironmentKey {
    static let defaultValue: any osrsThemeProtocol = osrsLightTheme()
}

extension EnvironmentValues {
    /// Access the current OSRS theme from the environment
    var osrsTheme: any osrsThemeProtocol {
        get { self[osrsThemeKey.self] }
        set { self[osrsThemeKey.self] = newValue }
    }
}

// MARK: - Theme Implementations

/// OSRS Light Theme - matches Android osrs_light theme colors with semantic delegation
struct osrsLightTheme: osrsThemeProtocol {
    // MARK: - Material Design Foundation Colors
    
    // Primary colors - main OSRS brown branding
    let primary = Color(hex: "#4C3D2A")           // osrs_brown_deep
    let onPrimary = Color(hex: "#F0E6D2")         // osrs_text_light
    let primaryContainer = Color(hex: "#D2B48C")   // osrs_parchment_medium
    let onPrimaryContainer = Color(hex: "#3A2E1C") // osrs_text_dark
    
    // Surface colors - parchment backgrounds
    let surface = Color(hex: "#E2DBC8")           // osrs_parchment_light
    let onSurface = Color(hex: "#3A2E1C")         // osrs_text_dark
    let surfaceVariant = Color(hex: "#d8ccb4")    // osrs_parchment_surface_light
    let onSurfaceVariant = Color(hex: "#3A2E1C")  // osrs_text_dark
    
    // Background colors
    let background = Color(hex: "#E2DBC8")        // osrs_parchment_light
    let onBackground = Color(hex: "#3A2E1C")      // osrs_text_dark
    
    // Secondary colors
    let secondary = Color(hex: "#4C3D2A")         // osrs_brown_deep
    let onSecondary = Color(hex: "#F0E6D2")       // osrs_text_light
    let secondaryContainer = Color(hex: "#D2B48C") // osrs_parchment_medium
    let onSecondaryContainer = Color(hex: "#000000") // black
    
    // Accent and functional colors
    let accent = Color(hex: "#FFB800")            // osrs_gold
    let link = Color(hex: "#936039")              // link_color_osrs_light
    let error = Color(hex: "#B00020")             // color_error
    let onError = Color(hex: "#FFFFFF")           // white
    let outline = Color(hex: "#4C3D2A")           // osrs_brown_deep
    
    // MARK: - App-Specific Semantic Colors (parallel to Android attrs.xml)
    
    /// Equivalent to Android: ?attr/paper_color → ?attr/colorSurface
    var paperColor: Color { surface }             // osrs_parchment_light
    
    /// Equivalent to Android: ?attr/primary_text_color → ?attr/colorOnSurface
    var primaryTextColor: Color { onSurface }     // osrs_text_dark
    
    /// Equivalent to Android: secondary_text_color → @color/osrs_text_secondary_light
    var secondaryTextColor: Color { Color(hex: "#8B7355") } // osrs_text_secondary_light
    
    /// Equivalent to Android: ?attr/border_color → ?attr/colorSurfaceVariant
    var borderColor: Color { surfaceVariant }     // osrs_parchment_surface_light
    
    /// Equivalent to Android: ?attr/bottom_nav_background_color → ?attr/paper_color
    var bottomNavBackgroundColor: Color { paperColor } // delegates to paper_color
    
    /// Equivalent to Android: ?attr/placeholder_color → @color/osrs_brown_deep
    var placeholderColor: Color { primary }       // osrs_brown_deep
    
    /// Equivalent to Android: ?attr/search_box_background_color → #1A000000
    var searchBoxBackgroundColor: Color { Color.black.opacity(0.1) } // #1A000000
    
    /// Equivalent to Android: ?attr/map_control_text → @color/gray_very_light (#fbfbfb)
    var mapControlTextColor: Color { Color(hex: "#fbfbfb") } // gray_very_light
    
    /// Equivalent to Android: ?attr/map_control_background → @color/black (#000000)
    var mapControlBackgroundColor: Color { Color.black } // black
    
    /// Equivalent to Android: @color/bottom_nav_inactive → #663A2E1C (40% opacity of #3A2E1C)
    var bottomNavInactiveColor: Color { Color(hex: "#9e9583") } // bottom_nav_inactive - pre-calculated 40% alpha blend
    
    // MARK: - Legacy (for backwards compatibility)
    var textPrimary: Color { primaryTextColor }   // delegates to semantic
    var textSecondary: Color { secondaryTextColor } // delegates to semantic
    var border: Color { borderColor }             // delegates to semantic
    var divider: Color { Color(hex: "#D2B48C").opacity(0.5) } // osrs_parchment_medium with opacity
}

/// OSRS Dark Theme - matches Android osrs_dark theme colors with semantic delegation
struct osrsDarkTheme: osrsThemeProtocol {
    // MARK: - Material Design Foundation Colors
    
    // Primary colors - inverted for dark mode visibility
    let primary = Color(hex: "#D2B48C")           // osrs_parchment_medium - light brown for buttons in dark mode
    let onPrimary = Color(hex: "#28221d")         // osrs_parchment_dark - dark text on light buttons
    let primaryContainer = Color(hex: "#28221d")   // osrs_parchment_dark
    let onPrimaryContainer = Color(hex: "#f4eaea") // osrs_text_light_alt
    
    // Surface colors - dark parchment backgrounds
    let surface = Color(hex: "#28221d")           // osrs_parchment_dark
    let onSurface = Color(hex: "#f4eaea")         // osrs_text_light_alt
    let surfaceVariant = Color(hex: "#3e3529")    // osrs_interface_grey_dark
    let onSurfaceVariant = Color(hex: "#f4eaea")  // osrs_text_light_alt - Android uses same as onSurface
    
    // Background colors
    let background = Color(hex: "#28221d")        // osrs_parchment_dark
    let onBackground = Color(hex: "#f4eaea")      // osrs_text_light_alt
    
    // Secondary colors - match Android exactly
    let secondary = Color(hex: "#f4eaea")         // osrs_text_light_alt - same as Android colorSecondary
    let onSecondary = Color(hex: "#4C3D2A")       // osrs_brown_deep
    let secondaryContainer = Color(hex: "#28221d") // osrs_parchment_dark
    let onSecondaryContainer = Color(hex: "#d4af37") // osrs_gold_muted - gold only for accents
    
    // Accent and functional colors
    let accent = Color(hex: "#d4af37")            // osrs_gold_muted - gold reserved for accents
    let link = Color(hex: "#b79d7e")              // link_color_osrs_dark
    let error = Color(hex: "#B00020")             // color_error
    let onError = Color(hex: "#FFFFFF")           // white
    let outline = Color(hex: "#D2B48C")           // osrs_parchment_medium - light outline for dark mode
    
    // MARK: - App-Specific Semantic Colors (parallel to Android attrs.xml)
    
    /// Equivalent to Android: ?attr/paper_color → ?attr/colorSurface
    var paperColor: Color { surface }             // osrs_parchment_dark
    
    /// Equivalent to Android: ?attr/primary_text_color → ?attr/colorOnSurface
    var primaryTextColor: Color { onSurface }     // osrs_text_light_alt
    
    /// Equivalent to Android: secondary_text_color → osrs_text_secondary_light (unified brown)
    var secondaryTextColor: Color { Color(hex: "#8B7355") } // osrs_text_secondary_light - unified across themes
    
    /// Equivalent to Android: ?attr/border_color → ?attr/colorSurfaceVariant
    var borderColor: Color { surfaceVariant }     // osrs_interface_grey_dark
    
    /// Equivalent to Android: ?attr/bottom_nav_background_color → ?attr/paper_color
    var bottomNavBackgroundColor: Color { paperColor } // delegates to paper_color
    
    /// Equivalent to Android: ?attr/placeholder_color → @color/osrs_text_light_alt
    var placeholderColor: Color { onSurface }     // osrs_text_light_alt
    
    /// Equivalent to Android: ?attr/search_box_background_color → #1A000000
    var searchBoxBackgroundColor: Color { Color.white.opacity(0.1) } // light overlay on dark background
    
    /// Equivalent to Android: ?attr/map_control_text → @color/gray_very_light (#fbfbfb)
    var mapControlTextColor: Color { Color(hex: "#fbfbfb") } // gray_very_light
    
    /// Equivalent to Android: ?attr/map_control_background → @color/black (#000000)
    var mapControlBackgroundColor: Color { Color.black } // black
    
    /// Equivalent to Android: @color/bottom_nav_inactive → #663A2E1C (40% opacity of #3A2E1C)
    var bottomNavInactiveColor: Color { Color(hex: "#9e9583") } // bottom_nav_inactive - pre-calculated 40% alpha blend - same for dark theme
    
    // MARK: - Legacy (for backwards compatibility)
    var textPrimary: Color { primaryTextColor }   // delegates to semantic
    var textSecondary: Color { secondaryTextColor } // delegates to semantic
    var border: Color { borderColor }             // delegates to semantic
    var divider: Color { Color(hex: "#3e3529") }  // osrs_interface_grey_dark
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// Initialize Color from hex string
    /// Usage: Color(hex: "#FF0000") or Color(hex: "FF0000")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
//
//  osrsThemeManager.swift
//  OSRS Wiki
//
//  Created on iOS theming research session
//  Theme management with persistence and automatic system integration
//

import SwiftUI
import Combine

// MARK: - Theme Selection

/// Available theme options for user selection
enum osrsThemeSelection: String, CaseIterable {
    case automatic = "automatic"
    case osrsLight = "osrs_light"
    case osrsDark = "osrs_dark"
    
    var displayName: String {
        switch self {
        case .automatic:
            return "Follow system"
        case .osrsLight:
            return "Light"
        case .osrsDark:
            return "Dark"
        }
    }
    
    var description: String {
        switch self {
        case .automatic:
            return "Follows your system setting"
        case .osrsLight:
            return "Clean and bright interface"
        case .osrsDark:
            return "Easy on the eyes in low light"
        }
    }
    
    /// Get the theme instance based on color scheme (for automatic)
    func theme(for colorScheme: ColorScheme?) -> any osrsThemeProtocol {
        switch self {
        case .automatic:
            return colorScheme == .dark ? osrsDarkTheme() : osrsLightTheme()
        case .osrsLight:
            return osrsLightTheme()
        case .osrsDark:
            return osrsDarkTheme()
        }
    }
    
    /// Get the intended color scheme for SwiftUI's environment
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            return nil // Let system decide
        case .osrsLight:
            return .light
        case .osrsDark:
            return .dark
        }
    }
}

// MARK: - Theme Manager

/// Observable theme manager that handles theme selection, persistence, and system integration
@MainActor
class osrsThemeManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Currently selected theme option
    @Published var selectedTheme: osrsThemeSelection = .automatic {
        didSet {
            saveThemeSelection()
            updateCurrentTheme()
        }
    }
    
    /// Current resolved theme based on selection and system state
    @Published private(set) var currentTheme: any osrsThemeProtocol = osrsLightTheme()
    
    /// Current color scheme for SwiftUI environment
    @Published private(set) var currentColorScheme: ColorScheme? = nil
    
    /// System color scheme tracking
    @Published private(set) var systemColorScheme: ColorScheme = .light
    
    /// Collapse tables setting
    @Published var collapseTables: Bool = true {
        didSet {
            saveCollapseTablesSettings()
        }
    }
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let themeSelectionKey = "osrs_theme_selection"
    private let collapseTablesKey = "collapseTables"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Detect system color scheme immediately to prevent flash
        let currentSystemScheme = UITraitCollection.current.userInterfaceStyle == .dark ? ColorScheme.dark : ColorScheme.light
        systemColorScheme = currentSystemScheme
        
        loadSavedTheme()
        loadCollapseTablesSettings()
        updateCurrentTheme()
        setupSystemColorSchemeObserver()
        // Note: Navigation bar and global theming is now handled in osrswikiApp.swift
    }
    
    // MARK: - Public Methods
    
    /// Set the theme selection and persist it
    func setTheme(_ theme: osrsThemeSelection) {
        selectedTheme = theme
    }
    
    /// Update system color scheme (called from app level)
    func updateSystemColorScheme(_ colorScheme: ColorScheme) {
        systemColorScheme = colorScheme
        updateCurrentTheme()
    }
    
    /// Set the collapse tables setting and persist it
    func setCollapseTables(_ enabled: Bool) {
        collapseTables = enabled
    }
    
    /// Get theme colors for WebView JavaScript injection
    func getWebViewColors() -> WebViewThemeColors {
        if let lightTheme = currentTheme as? osrsLightTheme {
            return WebViewThemeColors(
                surface: lightTheme.surface.toHex(),
                onSurface: lightTheme.onSurface.toHex(),
                primary: lightTheme.primary.toHex(),
                background: lightTheme.background.toHex(),
                accent: lightTheme.accent.toHex()
            )
        } else if let darkTheme = currentTheme as? osrsDarkTheme {
            return WebViewThemeColors(
                surface: darkTheme.surface.toHex(),
                onSurface: darkTheme.onSurface.toHex(),
                primary: darkTheme.primary.toHex(),
                background: darkTheme.background.toHex(),
                accent: darkTheme.accent.toHex()
            )
        } else {
            // Fallback to light theme colors
            let fallback = osrsLightTheme()
            return WebViewThemeColors(
                surface: fallback.surface.toHex(),
                onSurface: fallback.onSurface.toHex(),
                primary: fallback.primary.toHex(),
                background: fallback.background.toHex(),
                accent: fallback.accent.toHex()
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSavedTheme() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let forcedThemeIndex = arguments.firstIndex(of: "-forceThemeForUITests"),
           forcedThemeIndex + 1 < arguments.count,
           let forcedTheme = osrsThemeSelection(rawValue: arguments[forcedThemeIndex + 1]) {
            selectedTheme = forcedTheme
            return
        }
#endif

        if let savedThemeRaw = userDefaults.string(forKey: themeSelectionKey),
           let savedTheme = osrsThemeSelection(rawValue: savedThemeRaw) {
            selectedTheme = savedTheme
        }
    }
    
    private func saveThemeSelection() {
        userDefaults.set(selectedTheme.rawValue, forKey: themeSelectionKey)
    }
    
    private func loadCollapseTablesSettings() {
        collapseTables = userDefaults.bool(forKey: collapseTablesKey)
        // Default to true if no setting exists
        if !userDefaults.objectExists(forKey: collapseTablesKey) {
            collapseTables = true
        }
    }
    
    private func saveCollapseTablesSettings() {
        userDefaults.set(collapseTables, forKey: collapseTablesKey)
    }
    
    private func updateCurrentTheme() {
        let resolvedColorScheme = selectedTheme == .automatic ? systemColorScheme : nil
        currentTheme = selectedTheme.theme(for: resolvedColorScheme)
        currentColorScheme = selectedTheme.colorScheme ?? systemColorScheme
        
        // Note: Global theming is now handled in osrswikiApp.swift to avoid duplication
        print("🎨 [THEME MANAGER] Theme updated: \(selectedTheme.displayName)")
    }
    
    private func setupSystemColorSchemeObserver() {
        // Note: This will be called from the app level when system color scheme changes
        // The updateSystemColorScheme method handles the actual updates
    }
    
    // Note: Navigation bar and control theming is now handled globally in osrswikiApp.swift
    // This eliminates the whack-a-mole problem by applying theming at the app root level
}

// MARK: - WebView Integration

/// Colors formatted for WebView JavaScript injection
struct WebViewThemeColors {
    let surface: String
    let onSurface: String
    let primary: String
    let background: String
    let accent: String
    
    /// Generate JavaScript to inject theme colors
    func generateJavaScript() -> String {
        return """
        document.documentElement.style.setProperty('--osrs-surface', '\(surface)');
        document.documentElement.style.setProperty('--osrs-on-surface', '\(onSurface)');
        document.documentElement.style.setProperty('--osrs-primary', '\(primary)');
        document.documentElement.style.setProperty('--osrs-background', '\(background)');
        document.documentElement.style.setProperty('--osrs-accent', '\(accent)');
        
        // Legacy color variables for compatibility
        document.documentElement.style.setProperty('--color-surface', '\(surface)');
        document.documentElement.style.setProperty('--color-on-surface', '\(onSurface)');
        document.documentElement.style.setProperty('--color-primary', '\(primary)');
        document.documentElement.style.setProperty('--color-background', '\(background)');
        """
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    /// Check if an object exists for the given key
    func objectExists(forKey key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

// MARK: - Color Hex Conversion

extension Color {
    /// Convert Color to hex string for WebView injection
    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let rgb = Int(red * 255) << 16 | Int(green * 255) << 8 | Int(blue * 255)
        return String(format: "#%06X", rgb)
    }
}

// MARK: - Preview Support

/// Theme manager instance for SwiftUI previews
extension osrsThemeManager {
    static let preview: osrsThemeManager = {
        let manager = osrsThemeManager()
        manager.selectedTheme = .osrsLight
        return manager
    }()
    
    static let previewDark: osrsThemeManager = {
        let manager = osrsThemeManager()
        manager.selectedTheme = .osrsDark
        return manager
    }()
}

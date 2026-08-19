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
    @Published var collapseTables: Bool = false {
        didSet {
            saveCollapseTablesSettings()
        }
    }

    /// Wrap table cells instead of keeping them on one horizontally scrolling line.
    @Published var wrapTableCells: Bool = false {
        didSet {
            saveWrapTableCellsSettings()
        }
    }

    /// Reader preferences use explicit defaults so an upgrade preserves the gestures and
    /// typography that existing installs already had before these controls were introduced.
    @Published private(set) var articleTextScale: Double = 1.0
    @Published private(set) var swipeRightToGoBackEnabled: Bool = true
    @Published private(set) var swipeLeftToShowContentsEnabled: Bool = true
    @Published private(set) var floorNumberingMode: osrsArticleFloorNumberingMode = .auto
    
    // MARK: - Private Properties
    
    static let articleTextScaleRange = 0.85 ... 1.40

    private let userDefaults: UserDefaults
    private let themeSelectionKey = "osrs_theme_selection"
    private let collapseTablesKey = "collapseTables"
    private let wrapTableCellsKey = "osrs_wrap_table_cells"
    private let articleTextScaleKey = "osrs_article_text_scale"
    private let swipeRightToGoBackKey = "osrs_swipe_right_back_enabled"
    private let swipeLeftToShowContentsKey = "osrs_swipe_left_contents_enabled"
    private let floorNumberingKey = osrsArticleFloorNumberingMode.persistenceKey
    private let readerPreferencesMigrationKey = "osrs_reader_preferences_migration_version"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetReaderPreferencesForUITests") {
            [
                collapseTablesKey,
                wrapTableCellsKey,
                articleTextScaleKey,
                swipeRightToGoBackKey,
                swipeLeftToShowContentsKey,
                floorNumberingKey,
                readerPreferencesMigrationKey
            ].forEach { userDefaults.removeObject(forKey: $0) }
        }
#endif
        // Detect system color scheme immediately to prevent flash
        let currentSystemScheme = UITraitCollection.current.userInterfaceStyle == .dark ? ColorScheme.dark : ColorScheme.light
        systemColorScheme = currentSystemScheme
        
        loadSavedTheme()
        loadCollapseTablesSettings()
        loadWrapTableCellsSettings()
        loadReaderPreferences()
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
        guard systemColorScheme != colorScheme else { return }
        systemColorScheme = colorScheme
        updateCurrentTheme()
    }
    
    /// Set the collapse tables setting and persist it
    func setCollapseTables(_ enabled: Bool) {
        collapseTables = enabled
    }

    /// Set whether table cells wrap onto multiple lines.
    func setWrapTableCells(_ enabled: Bool) {
        wrapTableCells = enabled
    }

    func setArticleTextScale(_ scale: Double) {
        let clamped = min(max(scale, Self.articleTextScaleRange.lowerBound), Self.articleTextScaleRange.upperBound)
        articleTextScale = clamped
        userDefaults.set(clamped, forKey: articleTextScaleKey)
    }

    func setSwipeRightToGoBackEnabled(_ enabled: Bool) {
        swipeRightToGoBackEnabled = enabled
        userDefaults.set(enabled, forKey: swipeRightToGoBackKey)
    }

    func setSwipeLeftToShowContentsEnabled(_ enabled: Bool) {
        swipeLeftToShowContentsEnabled = enabled
        userDefaults.set(enabled, forKey: swipeLeftToShowContentsKey)
    }

    func setFloorNumberingMode(_ mode: osrsArticleFloorNumberingMode) {
        floorNumberingMode = mode
        userDefaults.set(mode.rawValue, forKey: floorNumberingKey)
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
        // Inspect existence before assigning so didSet cannot persist a stale default
        // before the stored value is read. Fresh installs leave tables expanded.
        if userDefaults.objectExists(forKey: collapseTablesKey) {
            collapseTables = userDefaults.bool(forKey: collapseTablesKey)
        } else {
            collapseTables = false
        }
    }
    
    private func saveCollapseTablesSettings() {
        userDefaults.set(collapseTables, forKey: collapseTablesKey)
    }

    private func loadWrapTableCellsSettings() {
        if userDefaults.objectExists(forKey: wrapTableCellsKey) {
            wrapTableCells = userDefaults.bool(forKey: wrapTableCellsKey)
        } else {
            wrapTableCells = false
        }
    }

    private func saveWrapTableCellsSettings() {
        userDefaults.set(wrapTableCells, forKey: wrapTableCellsKey)
    }

    private func loadReaderPreferences() {
        if userDefaults.objectExists(forKey: articleTextScaleKey) {
            setArticleTextScale(userDefaults.double(forKey: articleTextScaleKey))
        } else {
            setArticleTextScale(1.0)
        }

        if userDefaults.objectExists(forKey: swipeRightToGoBackKey) {
            swipeRightToGoBackEnabled = userDefaults.bool(forKey: swipeRightToGoBackKey)
        } else {
            setSwipeRightToGoBackEnabled(true)
        }

        if userDefaults.objectExists(forKey: swipeLeftToShowContentsKey) {
            swipeLeftToShowContentsEnabled = userDefaults.bool(forKey: swipeLeftToShowContentsKey)
        } else {
            setSwipeLeftToShowContentsEnabled(true)
        }

        floorNumberingMode = osrsArticleFloorNumberingMode.resolved(userDefaults: userDefaults)

        // Version one formalizes the legacy defaults above. Keeping a versioned marker makes
        // future key renames or value-shape migrations deterministic instead of heuristic.
        if userDefaults.integer(forKey: readerPreferencesMigrationKey) < 1 {
            userDefaults.set(1, forKey: readerPreferencesMigrationKey)
        }
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

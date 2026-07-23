//
//  osrsTypography.swift
//  OSRS Wiki
//
//  Created for iOS typography theming to match Android system
//  Comprehensive OSRS typography with Alegreya and system fonts
//

import SwiftUI

// MARK: - OSRS Typography Extensions

extension Font {
    // MARK: - Display Text (Major headings, hero text)
    
    /// Display style using Alegreya Bold - 32pt equivalent
    static let osrsDisplay: Font = {
        let fontNames = ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 32) != nil {
                NSLog("OSRS FONT DEBUG: osrsDisplay - Using \(fontName)")
                return Font.custom(fontName, size: 32)
            }
        }
        NSLog("OSRS FONT DEBUG: osrsDisplay - FALLBACK to system bold")
        return Font.system(size: 32, weight: .bold, design: .serif)
    }()
    
    // MARK: - Headlines (Section headers, major navigation)
    
    /// Headline style using Alegreya Bold - 28pt equivalent
    static let osrsHeadline: Font = {
        let fontNames = ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 28) != nil {
                NSLog("OSRS FONT DEBUG: osrsHeadline - Using \(fontName)")
                return Font.custom(fontName, size: 28)
            }
        }
        NSLog("OSRS FONT DEBUG: osrsHeadline - FALLBACK to system bold")
        return Font.system(size: 28, weight: .bold, design: .serif)
    }()
    
    // MARK: - Titles (Card titles, page titles, important text)
    
    /// Title style using Alegreya Medium - 20pt equivalent
    static let osrsTitle: Font = {
        let fontNames = ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya Regular"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 20) != nil {
                NSLog("OSRS FONT DEBUG: osrsTitle - Using \(fontName)")
                return Font.custom(fontName, size: 20)
            }
        }
        NSLog("OSRS FONT DEBUG: osrsTitle - FALLBACK to system medium")
        return Font.system(size: 20, weight: .medium, design: .serif)
    }()
    
    /// Title Bold style using Alegreya Bold - 20pt equivalent
    static let osrsTitleBold: Font = {
        let fontNames = ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 20) != nil {
                return Font.custom(fontName, size: 20)
            }
        }
        return Font.system(size: 20, weight: .bold, design: .serif)
    }()
    
    /// List title style using Alegreya Medium - 20pt equivalent
    static let osrsListTitle: Font = {
        let fontNames = ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya Regular"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 20) != nil {
                return Font.custom(fontName, size: 20)
            }
        }
        return Font.system(size: 20, weight: .medium, design: .serif)
    }()
    
    /// List title bold style using Alegreya Bold - 20pt equivalent
    static let osrsListTitleBold: Font = {
        let fontNames = ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 20) != nil {
                return Font.custom(fontName, size: 20)
            }
        }
        return Font.system(size: 20, weight: .bold, design: .serif)
    }()
    
    // MARK: - Body Text (Article content, descriptions, longer text)
    
    /// Body text using system font - 16pt equivalent
    static let osrsBody = Font.system(size: 16, weight: .regular)
    
    /// Body medium using system font - 14pt equivalent
    static let osrsBodyMedium = Font.system(size: 14, weight: .regular)
    
    /// Body small using system font - 12pt equivalent
    static let osrsBodySmall = Font.system(size: 12, weight: .regular)
    
    /// Body large using system font - 16pt equivalent
    static let osrsBodyLarge = Font.system(size: 16, weight: .regular)
    
    // MARK: - UI Labels (Buttons, navigation, short UI text)
    
    /// Label medium using system font - 14pt equivalent
    static let osrsLabel = Font.system(size: 14, weight: .medium)
    
    /// Label large using system font - 18pt equivalent
    static let osrsLabelLarge = Font.system(size: 18, weight: .medium)
    
    /// Label bold using system font - 14pt equivalent
    static let osrsLabelBold = Font.system(size: 14, weight: .bold)
    
    // MARK: - Caption Text (Metadata, timestamps, auxiliary info)
    
    /// Caption text using system font - 12pt equivalent
    static let osrsCaption = Font.system(size: 12, weight: .regular)
    
    // MARK: - Monospace (Code, technical text)
    
    /// Monospace text using system monospace - 14pt equivalent
    static let osrsMono = Font.system(size: 14, weight: .regular, design: .monospaced)
    
    /// Monospace bold text using system monospace - 14pt equivalent
    static let osrsMonoBold = Font.system(size: 14, weight: .bold, design: .monospaced)
    
    /// Monospace small text using system monospace - 12pt equivalent
    static let osrsMonoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
    
    /// Monospace large text using system monospace - 16pt equivalent
    static let osrsMonoLarge = Font.system(size: 16, weight: .regular, design: .monospaced)
    
    // MARK: - Small Caps Styles (Using Alegreya SC when available)
    
    /// Navigation small caps using Alegreya SC - 12pt equivalent
    static let osrsNavigationSmallCaps: Font = {
        let fontNames = ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 12) != nil {
                return Font.custom(fontName, size: 12)
            }
        }
        return Font.system(size: 12, weight: .medium)
    }()
    
    /// Section header small caps using Alegreya SC Bold - 24pt equivalent (increased for proper prominence with authentic small caps)
    static let osrsSectionHeaderSmallCaps: Font = {
        let fontNames = ["AlegreyaSC-Bold", "alegreya_sc_bold", "Alegreya SC Bold", "alegreya_sc_medium", "AlegreyaSC-Medium"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 24) != nil {
                return Font.custom(fontName, size: 24)
            }
        }
        return Font.system(size: 24, weight: .bold)
    }()
    
    /// Metadata small caps using Alegreya SC - 12pt equivalent
    static let osrsMetadataSmallCaps: Font = {
        let fontNames = ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 12) != nil {
                return Font.custom(fontName, size: 12)
            }
        }
        return Font.system(size: 12, weight: .medium)
    }()
    
    /// Button small caps using Alegreya SC - 13pt equivalent
    static let osrsButtonSmallCaps: Font = {
        let fontNames = ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 13) != nil {
                return Font.custom(fontName, size: 13)
            }
        }
        return Font.system(size: 13, weight: .medium)
    }()
    
    /// Tag small caps using Alegreya SC - 13pt equivalent
    static let osrsTagSmallCaps: Font = {
        let fontNames = ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 13) != nil {
                return Font.custom(fontName, size: 13)
            }
        }
        return Font.system(size: 13, weight: .medium)
    }()
    
    // MARK: - UI Specific Styles
    
    /// Search bar text using system font - 16pt equivalent
    static let osrsSearchBar = Font.system(size: 16, weight: .regular)
    
    /// Navigation text using system font - 12pt equivalent
    static let osrsNavigation = Font.system(size: 12, weight: .regular)
    
    /// UI Navigation text using system font - 14pt equivalent
    static let osrsUINavigation = Font.system(size: 14, weight: .medium)
    
    /// UI Button text using system font - 12pt equivalent
    static let osrsUIButton = Font.system(size: 12, weight: .regular)
    
    /// UI Hint text using system font - 16pt equivalent
    static let osrsUIHint = Font.system(size: 16, weight: .regular)
    
    /// UI Form Label text using system font - 14pt equivalent
    static let osrsUIFormLabel = Font.system(size: 14, weight: .medium)
    
    /// UI Helper text using system font - 12pt equivalent
    static let osrsUIHelper = Font.system(size: 12, weight: .regular)
    
    /// UI Toolbar text using system font - 18pt equivalent
    static let osrsUIToolbar = Font.system(size: 18, weight: .medium)
    
    // MARK: - Preference Styles
    
    /// Preference title text using system font - 16pt equivalent
    static let osrsPreferenceTitle = Font.system(size: 16, weight: .regular)
    
    /// Preference summary text using system font - 13pt equivalent
    static let osrsPreferenceSummary = Font.system(size: 13, weight: .regular)
}

// MARK: - Typography Style Helpers

extension Text {
    /// Apply OSRS display style with proper line spacing
    func osrsDisplayStyle() -> some View {
        self
            .font(.osrsDisplay)
            .lineSpacing(8) // 1.2 line height equivalent
    }
    
    /// Apply OSRS headline style with proper line spacing
    func osrsHeadlineStyle() -> some View {
        self
            .font(.osrsHeadline)
            .lineSpacing(6) // 1.2 line height equivalent
    }
    
    /// Apply OSRS title style with proper line spacing
    func osrsTitleStyle() -> some View {
        self
            .font(.osrsTitle)
            .lineSpacing(6) // 1.3 line height equivalent
    }
    
    /// Apply OSRS body style with proper line spacing
    func osrsBodyStyle() -> some View {
        self
            .font(.osrsBody)
            .lineSpacing(3) // 1.2 line height equivalent
    }
    
    /// Apply OSRS small caps style with proper spacing
    func osrsSmallCapsStyle() -> some View {
        self
            .font(.osrsNavigationSmallCaps)
            .tracking(0.5) // Letter spacing equivalent
            .textCase(.uppercase)
    }
    
    /// Apply OSRS monospace style with proper line spacing
    func osrsMonoStyle() -> some View {
        self
            .font(.osrsMono)
            .lineSpacing(6) // 1.4 line height equivalent
    }
}

// MARK: - Typography Environment

/// Typography environment key for consistent theming
struct osrsTypographyKey: EnvironmentKey {
    static let defaultValue = true // Enable OSRS typography by default
}

extension EnvironmentValues {
    var osrsTypography: Bool {
        get { self[osrsTypographyKey.self] }
        set { self[osrsTypographyKey.self] = newValue }
    }
}

// MARK: - Font Registration Helper

/// Helper to register custom fonts if needed
struct osrsFontRegistrar {
    /// Register Alegreya fonts for OSRS theming using modern iOS approach
    static func registerFonts() {
        NSLog("🔧 OSRS: Starting modern font registration...")
        
        // Use Bundle.main.urls approach recommended for modern iOS
        guard let fontURLs = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else {
            NSLog("❌ OSRS: No TTF files found in bundle")
            return
        }
        
        NSLog("📄 OSRS: Found \(fontURLs.count) TTF files in bundle")
        
        // Register all found TTF fonts
        for fontURL in fontURLs {
            let fileName = fontURL.lastPathComponent
            var errorRef: Unmanaged<CFError>?
            
            if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &errorRef) {
                NSLog("✅ OSRS: Successfully registered font: \(fileName)")
            } else {
                if let error = errorRef?.takeRetainedValue() {
                    NSLog("❌ OSRS: Failed to register font \(fileName): \(error)")
                } else {
                    NSLog("❌ OSRS: Failed to register font \(fileName): Unknown error")
                }
            }
        }
        
        // Verify Alegreya fonts are now available
        NSLog("🧪 OSRS: Testing font availability...")
        let testFonts = ["Alegreya-Bold", "Alegreya-Medium", "AlegreyaSC-Regular"]
        for fontName in testFonts {
            let isAvailable = UIFont(name: fontName, size: 16) != nil
            NSLog("   \(fontName): \(isAvailable ? "✅ Available" : "❌ Not available")")
        }
        
        // List all Alegreya font families
        let alegreyaFamilies = UIFont.familyNames.filter { $0.lowercased().contains("alegreya") }
        if !alegreyaFamilies.isEmpty {
            NSLog("📝 OSRS: Available Alegreya font families:")
            for family in alegreyaFamilies {
                NSLog("   Family: \(family)")
                for fontName in UIFont.fontNames(forFamilyName: family) {
                    NSLog("     Font: \(fontName)")
                }
            }
        } else {
            NSLog("⚠️ OSRS: No Alegreya font families found")
        }
    }
    
    /// Check if custom fonts are available
    static func areCustomFontsAvailable() -> Bool {
        // Test multiple font name variations for Alegreya
        let alegreyaVariations = ["Alegreya", "Alegreya-Regular", "Alegreya-Medium", "alegreya_medium"]
        let alegreyaSCVariations = ["Alegreya SC", "AlegreyaSC", "alegreya_sc_regular"]
        
        let alegreyaAvailable = alegreyaVariations.contains { UIFont(name: $0, size: 16) != nil }
        let alegreyaSCAvailable = alegreyaSCVariations.contains { UIFont(name: $0, size: 16) != nil }
        
        if !alegreyaAvailable || !alegreyaSCAvailable {
            print("⚠️ OSRS Typography: Custom fonts not available, falling back to system fonts")
            print("📝 Available fonts: \(UIFont.familyNames.sorted())")
            return false
        }
        
        return true
    }
    
    /// Get the correct font name for a given style, with automatic fallback
    static func fontName(style: osrsFontStyle) -> String {
        // First test if any Alegreya fonts are available at all
        let allAlegreyaVariations = [
            "Alegreya", "Alegreya-Regular", "Alegreya-Medium", "Alegreya-Bold", "Alegreya-SemiBold",
            "alegreya_medium", "alegreya_bold", "alegreya_semibold", "alegreya_extrabold",
            "Alegreya SC", "AlegreyaSC", "alegreya_sc_regular", "alegreya_sc_medium", "alegreya_sc_bold"
        ]
        
        switch style {
        case .display, .headline:
            // Try Alegreya Bold variations
            let boldVariations = ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold", "Alegreya-SemiBold", "alegreya_semibold"]
            for variation in boldVariations {
                if UIFont(name: variation, size: 16) != nil {
                    print("✅ Using font for \(style): \(variation)")
                    return variation
                }
            }
            // Fallback to any available Alegreya font
            for variation in allAlegreyaVariations {
                if UIFont(name: variation, size: 16) != nil {
                    print("⚠️ Fallback font for \(style): \(variation)")
                    return variation
                }
            }
            print("❌ No Alegreya fonts found for \(style), using Times-Bold")
            return "Times-Bold" // System serif bold fallback
            
        case .title, .listTitle:
            // Try Alegreya Medium/Regular variations
            let mediumVariations = ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya"]
            for variation in mediumVariations {
                if UIFont(name: variation, size: 16) != nil {
                    print("✅ Using font for \(style): \(variation)")
                    return variation
                }
            }
            // Fallback to any available Alegreya font
            for variation in allAlegreyaVariations {
                if UIFont(name: variation, size: 16) != nil {
                    print("⚠️ Fallback font for \(style): \(variation)")
                    return variation
                }
            }
            print("❌ No Alegreya fonts found for \(style), using Times-Roman")
            return "Times-Roman" // System serif fallback
            
        case .smallCaps:
            // Try Alegreya SC variations
            let scVariations = ["Alegreya SC", "alegreya_sc_regular", "alegreya_sc_medium", "alegreya_sc_bold", "AlegreyaSC"]
            for variation in scVariations {
                if UIFont(name: variation, size: 16) != nil {
                    print("✅ Using font for \(style): \(variation)")
                    return variation
                }
            }
            // Fallback to regular Alegreya if SC not available
            for variation in allAlegreyaVariations {
                if UIFont(name: variation, size: 16) != nil {
                    print("⚠️ Fallback font for \(style): \(variation)")
                    return variation
                }
            }
            print("❌ No Alegreya fonts found for \(style), using Times-Roman")
            return "Times-Roman" // System serif fallback
            
        case .body, .mono:
            return "System" // These should use system fonts anyway
        }
    }
    
    /// Get fallback fonts for OSRS styles when custom fonts aren't available
    static func fallbackFont(for style: osrsFontStyle) -> Font {
        switch style {
        case .display, .headline:
            return .system(.title, design: .serif, weight: .bold)
        case .title, .listTitle:
            return .system(.title2, design: .serif, weight: .medium)
        case .smallCaps:
            return .system(.caption, design: .default, weight: .medium)
        case .body:
            return .system(.body, design: .default, weight: .regular)
        case .mono:
            return .system(.body, design: .monospaced, weight: .regular)
        }
    }
}

// MARK: - Font Style Enumeration

enum osrsFontStyle {
    case display
    case headline
    case title
    case listTitle
    case body
    case smallCaps
    case mono
}

// MARK: - Typography Preview Helper

#if DEBUG
struct osrsTypographyPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Display Style")
                        .osrsDisplayStyle()
                        .foregroundStyle(.osrsOnSurface)
                    
                    Text("Headline Style")
                        .osrsHeadlineStyle()
                        .foregroundStyle(.osrsOnSurface)
                    
                    Text("Title Style")
                        .osrsTitleStyle()
                        .foregroundStyle(.osrsOnSurface)
                    
                    Text("Body Text Style - This shows how longer content looks with proper line spacing and the selected font family.")
                        .osrsBodyStyle()
                        .foregroundStyle(.osrsOnSurface)
                    
                    Text("Small Caps Style")
                        .osrsSmallCapsStyle()
                        .foregroundStyle(.osrsOnSurfaceVariant)
                    
                    Text("Monospace Style - Code and technical text")
                        .osrsMonoStyle()
                        .foregroundStyle(.osrsOnSurface)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Font Availability Status:")
                        .font(.headline)
                        .foregroundStyle(.osrsOnSurface)
                    
                    Text("Custom fonts available: \(osrsFontRegistrar.areCustomFontsAvailable() ? "✅ Yes" : "❌ No")")
                        .font(.caption)
                        .foregroundStyle(.osrsOnSurfaceVariant)
                    
                    Text("Using system font fallbacks when custom fonts are unavailable")
                        .font(.caption)
                        .foregroundStyle(.osrsOnSurfaceVariant)
                }
            }
            .padding()
        }
        .navigationTitle("OSRS Typography")
        .background(.osrsBackground)
    }
}

#Preview {
    NavigationView {
        osrsTypographyPreview()
            .environmentObject(osrsThemeManager.preview)
            .environment(\.osrsTheme, osrsLightTheme())
    }
}
#endif
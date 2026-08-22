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
    private static func osrsRelativeCustom(
        names: [String],
        size: CGFloat,
        relativeTo style: Font.TextStyle,
        fallbackWeight: Font.Weight,
        design: Font.Design = .serif
    ) -> Font {
        for fontName in names {
            if UIFont(name: fontName, size: size) != nil {
                return Font.custom(fontName, size: size, relativeTo: style)
            }
        }
        return Font.system(style, design: design).weight(fallbackWeight)
    }

    // MARK: - Display Text (Major headings, hero text)
    
    static let osrsDisplay: Font = osrsRelativeCustom(
        names: ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"],
        size: 32,
        relativeTo: .largeTitle,
        fallbackWeight: .bold
    )

    // MARK: - Headlines (Section headers, major navigation)

    static let osrsHeadline: Font = osrsRelativeCustom(
        names: ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"],
        size: 28,
        relativeTo: .title,
        fallbackWeight: .bold
    )

    // MARK: - Titles (Card titles, page titles, important text)

    static let osrsTitle: Font = osrsRelativeCustom(
        names: ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya Regular"],
        size: 20,
        relativeTo: .title3,
        fallbackWeight: .medium
    )

    static let osrsTitleBold: Font = osrsRelativeCustom(
        names: ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"],
        size: 20,
        relativeTo: .title3,
        fallbackWeight: .bold
    )

    static let osrsListTitle: Font = osrsRelativeCustom(
        names: ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya Regular"],
        size: 20,
        relativeTo: .title3,
        fallbackWeight: .medium
    )

    static let osrsListTitleBold: Font = osrsRelativeCustom(
        names: ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"],
        size: 20,
        relativeTo: .title3,
        fallbackWeight: .bold
    )

    // MARK: - Body Text (Article content, descriptions, longer text)

    static let osrsBody = Font.body
    static let osrsBodyMedium = Font.subheadline
    static let osrsBodySmall = Font.caption
    static let osrsBodyLarge = Font.body

    // MARK: - UI Labels (Buttons, navigation, short UI text)

    static let osrsLabel = Font.subheadline.weight(.medium)
    static let osrsLabelLarge = Font.headline
    static let osrsLabelBold = Font.subheadline.weight(.bold)

    // MARK: - Caption Text (Metadata, timestamps, auxiliary info)

    static let osrsCaption = Font.caption

    // MARK: - Monospace (Code, technical text)

    static let osrsMono = Font.body.monospaced()
    static let osrsMonoBold = Font.body.monospaced().weight(.bold)
    static let osrsMonoSmall = Font.caption.monospaced()
    static let osrsMonoLarge = Font.body.monospaced()
    
    // MARK: - Small Caps Styles (Using Alegreya SC when available)
    
    /// Navigation small caps using Alegreya SC - 12pt equivalent
    static let osrsNavigationSmallCaps = osrsRelativeCustom(
        names: ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"],
        size: 12,
        relativeTo: .caption,
        fallbackWeight: .medium,
        design: .default
    )

    /// Section header small caps using Alegreya SC Bold - 24pt equivalent
    static let osrsSectionHeaderSmallCaps = osrsRelativeCustom(
        names: ["AlegreyaSC-Bold", "alegreya_sc_bold", "Alegreya SC Bold", "alegreya_sc_medium", "AlegreyaSC-Medium"],
        size: 24,
        relativeTo: .title2,
        fallbackWeight: .bold,
        design: .default
    )

    /// Metadata small caps using Alegreya SC - 12pt equivalent
    static let osrsMetadataSmallCaps = osrsRelativeCustom(
        names: ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"],
        size: 12,
        relativeTo: .caption,
        fallbackWeight: .medium,
        design: .default
    )

    /// Button small caps using Alegreya SC - 13pt equivalent
    static let osrsButtonSmallCaps = osrsRelativeCustom(
        names: ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"],
        size: 13,
        relativeTo: .footnote,
        fallbackWeight: .medium,
        design: .default
    )

    /// Tag small caps using Alegreya SC - 13pt equivalent
    static let osrsTagSmallCaps = osrsRelativeCustom(
        names: ["AlegreyaSC-Regular", "alegreya_sc_regular", "Alegreya SC Regular", "Alegreya SC"],
        size: 13,
        relativeTo: .footnote,
        fallbackWeight: .medium,
        design: .default
    )
    
    // MARK: - UI Specific Styles
    
    static let osrsSearchBar = Font.body
    static let osrsNavigation = Font.caption
    static let osrsUINavigation = Font.subheadline.weight(.medium)
    static let osrsUIButton = Font.caption
    static let osrsUIHint = Font.body
    static let osrsUIFormLabel = Font.subheadline.weight(.medium)
    static let osrsUIHelper = Font.caption
    static let osrsUIToolbar = Font.headline
    
    // MARK: - Preference Styles
    
    static let osrsPreferenceTitle = Font.body
    static let osrsPreferenceSummary = Font.footnote
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
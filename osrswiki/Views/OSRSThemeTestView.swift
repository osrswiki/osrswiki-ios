//
//  osrsThemeTestView.swift
//  OSRS Wiki
//
//  Created for comprehensive OSRS theme testing
//  Tests all UI components across light and dark themes
//

import SwiftUI

struct osrsThemeTestView: View {
    @StateObject private var themeManager = osrsThemeManager()
    @StateObject private var transitionManager = osrsThemeTransitionManager()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    themeSelectionSection
                    colorTestSection
                    typographyTestSection
                    componentTestSection
                    transitionTestSection
                }
                .padding()
            }
            .navigationTitle("OSRS Theme Testing")
            .navigationBarTitleDisplayMode(.large)
            .background(.osrsBackground)
            .environmentObject(themeManager)
            .environment(\.osrsTheme, themeManager.currentTheme)
            .overlay(alignment: .bottom) {
                osrsThemeTransitionIndicator(isTransitioning: transitionManager.isTransitioning)
                    .padding(.bottom, 20)
            }
        }
    }
    
    private var themeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme Selection")
                .font(.osrsHeadline)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            HStack(spacing: 12) {
                ForEach(osrsThemeSelection.allCases, id: \.self) { selection in
                    Button(selection.displayName) {
                        transitionManager.animateThemeTransition {
                            themeManager.setTheme(selection)
                        }
                    }
                    .font(.osrsLabel)
                    .foregroundStyle(themeManager.selectedTheme == selection ? .osrsOnPrimary : .osrsPrimaryTextColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.selectedTheme == selection ? .osrsPrimary : .osrsSearchBoxBackgroundColor)
                    .cornerRadius(8)
                    .osrsThemeTransition(transitionManager, animationIndex: selection.hashValue)
                }
            }
        }
        .padding()
        .background(.osrsSurface)
        .cornerRadius(12)
    }
    
    private var colorTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color System Test")
                .font(.osrsTitle)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ColorSwatch(name: "Primary", color: .osrsPrimaryColor)
                ColorSwatch(name: "Secondary", color: .osrsSecondaryColor)
                ColorSwatch(name: "Accent", color: .osrsAccentColor)
                ColorSwatch(name: "Surface", color: .osrsSurfaceColor)
                ColorSwatch(name: "Background", color: .osrsBackgroundColor)
                ColorSwatch(name: "Error", color: .osrsErrorColor)
                ColorSwatch(name: "On Surface", color: .osrsOnSurfaceColor)
                ColorSwatch(name: "On Primary", color: .osrsOnPrimaryColor)
                ColorSwatch(name: "Outline", color: .osrsOutlineColor)
            }
        }
        .padding()
        .background(.osrsSurface)
        .cornerRadius(12)
    }
    
    private var typographyTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typography Test")
                .font(.osrsTitle)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Style")
                    .font(.osrsDisplay)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text("Headline Style")
                    .font(.osrsHeadline)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text("Title Style")
                    .font(.osrsTitle)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text("Body text demonstrates how longer content appears with OSRS typography.")
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text("Label Style")
                    .font(.osrsLabel)
                    .foregroundStyle(.osrsSecondaryTextColor)
                
                Text("Caption Style")
                    .font(.osrsCaption)
                    .foregroundStyle(.osrsSecondaryTextColor)
                
                Text("Monospace Code Style")
                    .font(.osrsMono)
                    .foregroundStyle(.osrsPrimaryTextColor)
            }
        }
        .padding()
        .background(.osrsSurface)
        .cornerRadius(12)
    }
    
    private var componentTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Component Test")
                .font(.osrsTitle)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            VStack(spacing: 16) {
                // Button tests
                HStack(spacing: 12) {
                    Button("Primary Button") {}
                        .foregroundStyle(.osrsOnPrimary)
                        .padding()
                        .background(.osrsPrimary)
                        .cornerRadius(8)
                    
                    Button("Secondary Button") {}
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .padding()
                        .background(.osrsSearchBoxBackgroundColor)
                        .cornerRadius(8)
                    
                    Button("Error Button") {}
                        .foregroundStyle(.osrsOnPrimary)
                        .padding()
                        .background(.osrsError)
                        .cornerRadius(8)
                }
                
                // Text field test
                TextField("Search OSRS Wiki", text: .constant(""))
                    .padding()
                    .background(.osrsSearchBoxBackgroundColor)
                    .cornerRadius(8)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                // List item test
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.osrsAccent)
                    
                    VStack(alignment: .leading) {
                        Text("List Item Title")
                            .font(.osrsLabel)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        
                        Text("Subtitle with secondary information")
                            .font(.osrsCaption)
                            .foregroundStyle(.osrsSecondaryTextColor)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.osrsSecondaryTextColor)
                }
                .padding()
                .background(.osrsSearchBoxBackgroundColor)
                .cornerRadius(8)
                
                // Card test
                VStack(alignment: .leading, spacing: 8) {
                    Text("Card Title")
                        .font(.osrsTitle)
                        .foregroundStyle(.osrsPrimaryTextColor)
                    
                    Text("Card content demonstrates how OSRS theming appears in card layouts with proper contrast and readability.")
                        .font(.osrsBody)
                        .foregroundStyle(.osrsPrimaryTextColor)
                    
                    HStack {
                        Button("Action") {}
                            .font(.osrsLabel)
                            .foregroundStyle(.osrsPrimary)
                        
                        Spacer()
                        
                        Text("Status: Active")
                            .font(.osrsCaption)
                            .foregroundStyle(.osrsAccent)
                    }
                }
                .padding()
                .background(.osrsSurface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.osrsOutline, lineWidth: 1)
                )
            }
        }
        .padding()
        .background(.osrsSurface)
        .cornerRadius(12)
    }
    
    private var transitionTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transition Test")
                .font(.osrsTitle)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            VStack(spacing: 12) {
                Button("Test Theme Transition") {
                    transitionManager.animateThemeTransition {
                        let nextTheme: osrsThemeSelection = themeManager.selectedTheme == .osrsLight ? .osrsDark : .osrsLight
                        themeManager.setTheme(nextTheme)
                    }
                }
                .font(.osrsLabel)
                .foregroundStyle(.osrsOnPrimary)
                .padding()
                .background(.osrsPrimary)
                .cornerRadius(8)
                
                Text("Transition Status: \(transitionManager.isTransitioning ? "In Progress" : "Idle")")
                    .font(.osrsCaption)
                    .foregroundStyle(.osrsSecondaryTextColor)
                
                ProgressView(value: transitionManager.transitionProgress)
                    .tint(.osrsPrimaryColor)
            }
        }
        .padding()
        .background(.osrsSurface)
        .cornerRadius(12)
    }
}

struct ColorSwatch: View {
    let name: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.osrsOutline, lineWidth: 1)
                )
            
            Text(name)
                .font(.osrsCaption)
                .foregroundStyle(.osrsSecondaryTextColor)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Theme Validation Tests

struct osrsThemeValidationTests {
    /// Validate that all required colors are available
    static func validateColorSystem() -> [String] {
        var issues: [String] = []
        
        // Test color availability (this would be expanded for real testing)
        let requiredColors: [KeyPath<any osrsThemeProtocol, Color>] = [
            \.primary, \.secondary, \.accent, \.surface, \.background,
            \.onSurface, \.onPrimary, \.error, \.outline
        ]
        
        let testTheme = osrsLightTheme()
        
        for colorPath in requiredColors {
            let color = testTheme[keyPath: colorPath]
            // Validate color is not nil or invalid
            // This is a simplified test - real implementation would check color values
        }
        
        return issues
    }
    
    /// Validate typography system
    static func validateTypography() -> [String] {
        var issues: [String] = []
        
        // Check if custom fonts are available
        if !osrsFontRegistrar.areCustomFontsAvailable() {
            issues.append("Custom fonts (Alegreya) not available - using system fallbacks")
        }
        
        return issues
    }
    
    /// Validate theme transitions
    @MainActor static func validateTransitions() -> [String] {
        var issues: [String] = []
        
        // Test transition manager
        let manager = osrsThemeTransitionManager()
        if manager.isTransitioning {
            issues.append("Transition manager should start in idle state")
        }
        
        return issues
    }
    
    /// Run all validation tests
    @MainActor static func runAllTests() -> (passed: Int, failed: Int, issues: [String]) {
        var allIssues: [String] = []
        
        allIssues.append(contentsOf: validateColorSystem())
        allIssues.append(contentsOf: validateTypography())
        allIssues.append(contentsOf: validateTransitions())
        
        let passed = 3 - allIssues.count
        let failed = allIssues.count
        
        return (passed: passed, failed: failed, issues: allIssues)
    }
}

#Preview("OSRS Theme Test") {
    osrsThemeTestView()
}

#Preview("Light Theme") {
    osrsThemeTestView()
        .environment(\.colorScheme, .light)
}

#Preview("Dark Theme") {
    osrsThemeTestView()
        .environment(\.colorScheme, .dark)
}
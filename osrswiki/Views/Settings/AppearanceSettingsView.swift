//
//  AppearanceSettingsView.swift
//  OSRS Wiki
//
//  Complete rewrite to match Android appearance page exactly with visual previews
//

import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        List {
                Section {
                    // Theme selection row
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Theme")
                            .font(.body)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        
                        // Three cards horizontally arranged, right-aligned
                        HStack(spacing: 8) {
                            Spacer()
                            
                            osrsThemePreviewCard(
                                theme: .osrsLight,
                                isSelected: themeManager.selectedTheme == .osrsLight,
                                onSelect: { themeManager.setTheme(.osrsLight) }
                            )
                            
                            osrsThemePreviewCard(
                                theme: .osrsDark,
                                isSelected: themeManager.selectedTheme == .osrsDark,
                                onSelect: { themeManager.setTheme(.osrsDark) }
                            )
                            
                            osrsThemePreviewCard(
                                theme: .automatic,
                                isSelected: themeManager.selectedTheme == .automatic,
                                onSelect: { themeManager.setTheme(.automatic) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    
                    // Table preferences row
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tables")
                            .font(.body)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        
                        HStack(spacing: 8) {
                            Spacer()
                            
                            // Expanded preview
                            osrsTablePreviewCard(
                                title: "Expanded",
                                subtitle: "",
                                isSelected: !themeManager.collapseTables,
                                collapsed: false,
                                onSelect: { themeManager.setCollapseTables(false) }
                            )
                            
                            // Collapsed preview
                            osrsTablePreviewCard(
                                title: "Collapsed", 
                                subtitle: "",
                                isSelected: themeManager.collapseTables,
                                collapsed: true,
                                onSelect: { themeManager.setCollapseTables(true) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .background(.osrsBackground)
            .accessibilityIdentifier("appearance_screen")
            // Hybrid Approach: NavigationStack for context, UIKit theming for reliability
            .onAppear {
                updateNavigationBarAppearance()
            }
            .onChange(of: themeManager.selectedTheme) { oldValue, newValue in
                print("🔄 AppearanceSettingsView: Theme changed from \(oldValue) to \(newValue) - applying UIKit navigation bar theming")
                updateNavigationBarAppearance()
            }
        // No view recreation - maintains navigation state
    }
    
    /// Direct UIKit navigation bar theming to bypass SwiftUI limitations
    private func updateNavigationBarAppearance() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let navigationController = findNavigationController(in: window.rootViewController) else {
                return
            }
            
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            // Apply theme colors directly
            let currentTheme = themeManager.currentTheme
            appearance.backgroundColor = UIColor(currentTheme.surface)
            appearance.titleTextAttributes = [.foregroundColor: UIColor(currentTheme.onSurface)]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(currentTheme.onSurface)]
            
            // Apply to navigation bar
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.compactAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
            
            // Set tint color for back buttons and navigation items
            navigationController.navigationBar.tintColor = UIColor(currentTheme.primary)
            
            // Update color scheme for status bar and buttons
            navigationController.overrideUserInterfaceStyle = themeManager.currentColorScheme == .dark ? .dark : .light
            
            print("📱 Applied UIKit navigation bar theming: \(themeManager.selectedTheme)")
        }
    }
    
    /// Helper to find the navigation controller in the view hierarchy
    private func findNavigationController(in viewController: UIViewController?) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        
        for child in viewController?.children ?? [] {
            if let found = findNavigationController(in: child) {
                return found
            }
        }
        
        return nil
    }
}

/// Theme preview card with actual rendered preview (matches Android exactly)
struct osrsThemePreviewCard: View {
    let theme: osrsThemeSelection
    let isSelected: Bool
    let onSelect: () -> Void
    
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Maximized preview image area - uses most of button space
                ZStack(alignment: .center) {
                    Color(osrsTheme.surfaceVariant)
                    
                    Image(osrsStaticSettingsPreviewAssets.themeImageName(for: theme))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 82, height: 120)
                        .clipped()
                }
                .frame(width: 82, height: 120)
                .background(Color(osrsTheme.surfaceVariant))
                .cornerRadius(6)
                
                // Compact title - minimal space
                Text(theme.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .frame(width: 90)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color(osrsTheme.surfaceVariant))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color(osrsTheme.primary) : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color(osrsTheme.primary))
                    .font(.system(size: 16))
                    .offset(x: -6, y: 6)
            }
        }
    }
}

/// Table preview card showing expanded or collapsed state (matches Android exactly)
struct osrsTablePreviewCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let collapsed: Bool
    let onSelect: () -> Void
    
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Maximized table preview image - uses most of button space
                ZStack(alignment: .center) {
                    Color(osrsTheme.surfaceVariant)
                    
                    Image(osrsStaticSettingsPreviewAssets.tableImageName(collapsed: collapsed, theme: themeManager.currentTheme))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 82, height: 120)
                        .clipped()
                }
                .frame(width: 82, height: 120)
                .background(Color(osrsTheme.surfaceVariant))
                .cornerRadius(6)
                
                // Compact title - minimal space
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .frame(width: 90)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color(osrsTheme.surfaceVariant))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color(osrsTheme.primary) : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color(osrsTheme.primary))
                    .font(.system(size: 16))
                    .offset(x: -6, y: 6)
            }
        }
    }
}

#Preview {
    AppearanceSettingsView()
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

#Preview("Dark Theme") {
    AppearanceSettingsView()
        .environmentObject(osrsThemeManager.previewDark)
        .environment(\.osrsTheme, osrsDarkTheme())
        .preferredColorScheme(.dark)
}

//
//  AboutView.swift
//  OSRS Wiki
//
//  Updated to match Android About page exactly
//

import SwiftUI

struct AboutView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @EnvironmentObject var themeManager: osrsThemeManager
    
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                titleSection
                versionSection
                creditsSection
                privacySection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 64)
        }
        .accessibilityIdentifier("about_screen")
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .background(.osrsBackground)
        .onAppear {
            updateNavigationBarAppearance()
        }
        .onChange(of: themeManager.selectedTheme) { oldValue, newValue in
            updateNavigationBarAppearance()
        }
    }
    
    private var titleSection: some View {
        Text("OSRS Wiki App")
            .font(.osrsDisplay)
            .foregroundStyle(.osrsOnSurface)
            .multilineTextAlignment(.center)
    }
    
    private var versionSection: some View {
        Text("Version \(appVersion) (\(buildNumber))")
            .font(.osrsBody)
            .foregroundStyle(.osrsPrimaryTextColor)
            .multilineTextAlignment(.center)
    }
    
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Credits & Acknowledgments")
                .font(.osrsHeadline)
                .foregroundStyle(.osrsOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "Old School RuneScape",
                    description: "Jagex®, RuneScape®, and Old School RuneScape® are registered and/or unregistered trademarks of Jagex in the United Kingdom, the United States, the European Union and other territories."
                )
                
                Button(action: openOSRS) {
                    HStack {
                        Text("Visit OSRS")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "OSRS Wiki",
                    description: "All information and game content fetched by this app is provided by the Old School Runescape Wiki. This app would not be possible without the wiki itself."
                )
                
                Button(action: openWiki) {
                    HStack {
                        Text("Visit OSRS Wiki")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "OpenRS2",
                    description: "OpenRS2 provides the game cache archive and decryption keys that provides the game data used to generate the map. The OpenRS2 Archive preserves and maintains accessible OSRS game data for the community."
                )
                
                Button(action: openOpenRS2) {
                    HStack {
                        Text("Visit OpenRS2 Archive")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "MapLibre",
                    description: "MapLibre provides the open-source map rendering engine that powers both the native map tab and embedded maps within wiki articles. The MapLibre SDK enables seamless integration of OSRS game maps with modern mobile mapping capabilities."
                )
                
                Button(action: openMapLibre) {
                    HStack {
                        Text("Visit MapLibre")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "Wikipedia",
                    description: "This app's design and architecture were influenced by the Wikipedia app. In the spirit of both Oldschool Runescape Wiki and Wikipedia's free and open source principles, the OSRS Wiki app is and will always be free."
                )
                
                Button(action: openWikipedia) {
                    HStack {
                        Text("Visit Wikipedia")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
    }
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy Policy")
                .font(.osrsHeadline)
                .foregroundStyle(.osrsOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("The OSRS Wiki App collects minimal user data, primarily voice search recordings processed locally and temporarily, and usage metrics to improve app functionality. The app does not permanently store personal information.")
                .font(.osrsBody)
                .foregroundStyle(.osrsPrimaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: openPrivacyPolicy) {
                HStack {
                    Text("View Privacy Policy")
                    Image(systemName: "arrow.up.right")
                }
                .font(.osrsBody)
                .foregroundStyle(.osrsPrimary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func creditItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.osrsTitle)
                .foregroundStyle(.osrsOnSurface)
            
            Text(description)
                .font(.osrsBody)
                .foregroundStyle(.osrsPrimaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Actions
    private func openOSRS() {
        if let url = URL(string: "https://oldschool.runescape.com/") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openWiki() {
        if let url = URL(string: "https://oldschool.runescape.wiki/") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openOpenRS2() {
        if let url = URL(string: "https://archive.openrs2.org/") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openMapLibre() {
        if let url = URL(string: "https://maplibre.org/") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openWikipedia() {
        if let url = URL(string: "https://www.wikipedia.org/") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openPrivacyPolicy() {
        if let url = URL(string: "https://osrswiki.github.io/osrswiki-privacy-policy/") {
            UIApplication.shared.open(url)
        }
    }
    
    /// Direct UIKit navigation bar theming to match AppearanceSettingsView
    private func updateNavigationBarAppearance() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let navigationController = findNavigationController(in: window.rootViewController) else {
                return
            }
            
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            // Apply theme colors directly (matching AppearanceSettingsView)
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
            
            print("📱 Applied UIKit navigation bar theming to AboutView: \(themeManager.selectedTheme)")
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

#Preview {
    NavigationView {
        AboutView()
            .environmentObject(osrsThemeManager.preview)
            .environment(\.osrsTheme, osrsLightTheme())
    }
}

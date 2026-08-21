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
        .background(.osrsBackground)
        .osrsMoreDestinationChrome(title: "About")
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
                
                osrsOutboundLinkRow(title: "Visit OSRS", action: openOSRS)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "OSRS Wiki",
                    description: "All information and game content fetched by this app is provided by the Old School Runescape Wiki. This app would not be possible without the wiki itself."
                )
                
                osrsOutboundLinkRow(title: "Visit OSRS Wiki", action: openWiki)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "OpenRS2",
                    description: "OpenRS2 provides the game cache archive and decryption keys that provides the game data used to generate the map. The OpenRS2 Archive preserves and maintains accessible OSRS game data for the community."
                )
                
                osrsOutboundLinkRow(title: "Visit OpenRS2 Archive", action: openOpenRS2)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "MapLibre",
                    description: "MapLibre provides the open-source map rendering engine that powers both the native map tab and embedded maps within wiki articles. The MapLibre SDK enables seamless integration of OSRS game maps with modern mobile mapping capabilities."
                )
                
                osrsOutboundLinkRow(title: "Visit MapLibre", action: openMapLibre)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                creditItem(
                    title: "Wikipedia",
                    description: "This app's design and architecture were influenced by the Wikipedia app. In the spirit of both Oldschool Runescape Wiki and Wikipedia's free and open source principles, the OSRS Wiki app is and will always be free."
                )
                
                osrsOutboundLinkRow(title: "Visit Wikipedia", action: openWikipedia)
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
            
            osrsOutboundLinkRow(title: "View Privacy Policy", action: openPrivacyPolicy)
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
}

#Preview {
    NavigationView {
        AboutView()
            .environmentObject(osrsThemeManager.preview)
            .environment(\.osrsTheme, osrsLightTheme())
    }
}

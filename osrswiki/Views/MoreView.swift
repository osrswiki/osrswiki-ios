//
//  MoreView.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI

struct MoreView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @StateObject private var viewModel = MoreViewModel()
    
    var body: some View {
        NavigationStack(path: $appState.moreNavigationStack) {
            List {
                Section {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        MoreRowView(
                            iconName: "paintbrush.fill",
                            iconColor: Color(osrsTheme.primary),
                            title: "Appearance"
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    .accessibilityIdentifier("more_appearance")
                    
                    NavigationLink(destination: DonateView()) {
                        MoreRowView(
                            iconName: "heart.fill",
                            iconColor: Color(osrsTheme.primary),
                            title: "Donate"
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    .accessibilityIdentifier("more_donate")
                    
                    NavigationLink(destination: AboutView()) {
                        MoreRowView(
                            iconName: "info.circle.fill",
                            iconColor: Color(osrsTheme.primary),
                            title: "About"
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    .accessibilityIdentifier("more_about")
                    
                    NavigationLink(destination: FeedbackView()) {
                        MoreRowView(
                            iconName: "envelope.fill",
                            iconColor: Color(osrsTheme.primary),
                            title: "Feedback"
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    .accessibilityIdentifier("more_feedback")
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .background(.osrsBackground)
            .overlay(alignment: .topLeading) {
                osrsAccessibilityMarker(identifier: "more_screen", label: "More screen")
            }
            .navigationDestination(for: MoreNavigationDestination.self) { destination in
                switch destination {
                case .appearance:
                    AppearanceSettingsView()
                case .donate:
                    DonateView()
                case .about:
                    AboutView()
                case .feedback:
                    FeedbackView()
                case .article(let articleDestination):
                    ArticleView(
                        pageTitle: articleDestination.title,
                        pageUrl: articleDestination.url,
                        navigationIdentity: articleDestination.navigationIdentity,
                        snippet: articleDestination.snippet,
                        thumbnailUrl: articleDestination.thumbnailUrl,
                        savedPageId: articleDestination.savedPageId
                    )
                    .id(articleDestination.navigationIdentity)
                    .environmentObject(appState)
                    .environmentObject(themeManager)
                    .environment(\.osrsTheme, osrsTheme)
                }
            }
            // Hybrid Approach: NavigationStack for context, UIKit theming for reliability
            .onAppear {
                updateNavigationBarAppearance()
            }
            .onChange(of: themeManager.selectedTheme) { oldValue, newValue in
                print("🔄 MoreView: Theme changed from \(oldValue) to \(newValue) - applying UIKit navigation bar theming")
                updateNavigationBarAppearance()
            }
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
            
            print("📱 Applied UIKit navigation bar theming to MoreView: \(themeManager.selectedTheme)")
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

struct MoreRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let iconName: String
    let iconColor: Color
    let title: String
    
    var body: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 16) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.body.weight(.medium))
                .dynamicTypeSize(.xSmall ... .accessibility1)
                .frame(width: 28, height: 28)
            
            Text(title)
                .font(.body)
                .dynamicTypeSize(.xSmall ... .accessibility2)
                .foregroundStyle(.osrsPrimaryTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 6 : 0)
        .contentShape(Rectangle())
    }
}

#Preview {
    MoreView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

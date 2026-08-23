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

                    NavigationLink(destination: osrsDownloadSettingsView()) {
                        MoreRowView(
                            iconName: "arrow.down.circle.fill",
                            iconColor: Color(osrsTheme.primary),
                            title: "Downloads"
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    .accessibilityIdentifier("more_downloads")
                    
                    NavigationLink(destination: FeedbackView()) {
                        MoreRowView(
                            iconName: "envelope.fill",
                            iconColor: Color(osrsTheme.primary),
                            title: "Feedback"
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                    .accessibilityIdentifier("more_feedback")

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
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .background(.osrsBackground)
            .overlay(alignment: .topLeading) {
                osrsAccessibilityMarker(identifier: "more_screen", label: "More screen")
            }
            .navigationDestination(for: MoreNavigationDestination.self) { destination in
                switch destination {
                case .appearance:
                    AppearanceSettingsView()
                case .downloads:
                    osrsDownloadSettingsView()
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
            .onAppear {
                osrsLiveThemeApplier.apply(
                    themeManager.currentTheme,
                    colorScheme: themeManager.currentColorScheme
                )
                DonationManager.prefetchProductsIfNeeded()
            }
            .onChange(of: themeManager.selectedTheme) { _, _ in
                osrsLiveThemeApplier.apply(
                    themeManager.currentTheme,
                    colorScheme: themeManager.currentColorScheme
                )
            }
            .onChange(of: themeManager.currentTheme.primary) { _, _ in
                osrsLiveThemeApplier.apply(
                    themeManager.currentTheme,
                    colorScheme: themeManager.currentColorScheme
                )
            }
        }
        .osrsResumedNavigationHost(appState.navigationHostGeneration)
        // No view recreation - maintains navigation state
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

//
//  osrsArticleSearchBar.swift
//  osrswiki
//
//  Created on iOS search bar UI session
//

import SwiftUI

enum osrsArticleMenuAction {
    case share, goToTop, copyLink, refresh, openInBrowser, pageHistory, reportIssue
}

/// A reusable search bar component that matches the Android article page design
struct osrsArticleSearchBar: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSearchPresented = false
    @State private var isMenuPresented = false
    @State private var searchText = ""
    @EnvironmentObject var appState: AppState
    // Use shared speech manager from AppState to prevent resource conflicts

    let onBackAction: () -> Void
    let onSearchAction: () -> Void
    let onMenuAction: (osrsArticleMenuAction) -> Void
    let onVoiceSearchAction: (() -> Void)?

    init(
        onBackAction: @escaping () -> Void,
        onSearchAction: @escaping () -> Void,
        onMenuAction: @escaping (osrsArticleMenuAction) -> Void,
        onVoiceSearchAction: (() -> Void)? = nil
    ) {
        self.onBackAction = onBackAction
        self.onSearchAction = onSearchAction
        self.onMenuAction = onMenuAction
        self.onVoiceSearchAction = onVoiceSearchAction
    }

    var body: some View {
        let controlHeight = osrsSearchControlGeometry.height(for: dynamicTypeSize)
        let searchHeight = controlHeight
        let compactSearchTitle = dynamicTypeSize.isAccessibilitySize ? "Search" : "Search OSRS Wiki"

        // Same 48pt glass contract as the home launcher: 80pt leading control,
        // flexible field, 80pt trailing control. Extra horizontal padding here
        // would sit the bar inside the home search's width.
        HStack(spacing: 0) {
            Button(action: onBackAction) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .osrsFloatingGlass(in: Circle(), fallback: Color(osrsTheme.surfaceVariant))
            .frame(width: 80, alignment: .center)
            .accessibilityIdentifier("article_back_button")
            .accessibilityLabel("Back")

            HStack(spacing: 8) {
                Button(action: onSearchAction) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(osrsTheme.placeholderColor)
                            .font(.body)

                        Text(compactSearchTitle)
                            .foregroundStyle(osrsTheme.placeholderColor)
                            .font(.body)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search OSRS Wiki")
                .accessibilityIdentifier("article_search_launcher")

                osrsVoiceSearchButton(
                    action: {
                        if let voiceSearchAction = onVoiceSearchAction {
                            voiceSearchAction()
                        } else {
                            appState.speechManager.startVoiceRecognition()
                        }
                    },
                    state: appState.speechManager.currentState,
                    accessibilityIdentifier: "article_voice_search"
                )
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 0)
            .frame(height: searchHeight)
            .osrsFloatingGlass(
                in: osrsSearchControlGeometry.pillShape(height: searchHeight),
                fallback: Color(osrsTheme.surfaceVariant)
            )
            .frame(maxWidth: .infinity)

            Menu {
                Button("Share") { onMenuAction(.share) }
                Button("Go to Top") { onMenuAction(.goToTop) }
                Button("Copy Link") { onMenuAction(.copyLink) }
                Button("Refresh Page") { onMenuAction(.refresh) }
                Button("Open in Browser") { onMenuAction(.openInBrowser) }
                Button("View Page History") { onMenuAction(.pageHistory) }
                Button("Report Issue") { onMenuAction(.reportIssue) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(90))
            }
            .osrsFloatingGlass(in: Circle(), fallback: Color(osrsTheme.surfaceVariant))
            .frame(width: 80, alignment: .center)
            .accessibilityIdentifier("article_page_menu")
        }
        .padding(.vertical, 0)
    }
}

private struct osrsChromeSurfaceModifier: ViewModifier {
    @Environment(\.osrsTheme) private var osrsTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .containerShape(Capsule())
                .glassEffect(.regular, in: Capsule())
                .clipShape(Capsule())
        } else {
            content
                .background(Color(osrsTheme.surface), in: Capsule())
                .clipShape(Capsule())
        }
    }
}

extension View {
    /// One availability-gated chrome surface for article bars. A single effect per bar keeps
    /// Liquid Glass restrained, while Reduce Transparency and older systems remain opaque.
    func osrsChromeSurface() -> some View {
        modifier(osrsChromeSurfaceModifier())
    }
}

#Preview {
    VStack {
        osrsArticleSearchBar(
            onBackAction: {},
            onSearchAction: {},
            onMenuAction: { _ in },
            onVoiceSearchAction: {}
        )
        Spacer()
    }
    .environmentObject(AppState())
    .environment(\.osrsTheme, osrsLightTheme())
}

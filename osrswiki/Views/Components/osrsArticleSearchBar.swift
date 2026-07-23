//
//  osrsArticleSearchBar.swift
//  osrswiki
//
//  Created on iOS search bar UI session
//

import SwiftUI

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
    let onMenuAction: () -> Void
    let onVoiceSearchAction: (() -> Void)?

    init(
        onBackAction: @escaping () -> Void,
        onMenuAction: @escaping () -> Void,
        onVoiceSearchAction: (() -> Void)? = nil
    ) {
        self.onBackAction = onBackAction
        self.onMenuAction = onMenuAction
        self.onVoiceSearchAction = onVoiceSearchAction
    }

    var body: some View {
        let scale = osrsArticleDynamicTypeScaling.toolbarScale(for: dynamicTypeSize)
        let iconSize = min(18 * scale, 24)
        let searchIconSize = min(16 * scale, 22)
        let textSize = min(16 * scale, 22)
        let buttonSize = min(44 * scale, 60)
        let searchHeight = min(36 * scale, 52)
        let voiceButtonSize = min(32 * scale, 44)
        let compactSearchTitle = dynamicTypeSize.isAccessibilitySize ? "Search" : "Search OSRS Wiki"

        HStack(spacing: 0) {
            // Back button
            Button(action: onBackAction) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .font(.system(size: iconSize, weight: .medium))
                    .frame(width: buttonSize, height: buttonSize)
            }
            .accessibilityIdentifier("article_back_button")
            .accessibilityLabel("Back")

            // Search bar container
            HStack(spacing: 8) {
                Button(action: {
                    appState.navigateToSearch()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(osrsTheme.placeholderColor)
                            .font(.system(size: searchIconSize))

                        Text(compactSearchTitle)
                            .foregroundStyle(osrsTheme.placeholderColor)
                            .font(.system(size: textSize))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search OSRS Wiki")

                // Voice search button - always show for consistency
                osrsVoiceSearchButton(
                    action: {
                        if let voiceSearchAction = onVoiceSearchAction {
                            voiceSearchAction()
                        } else {
                            appState.speechManager.startVoiceRecognition()
                        }
                    },
                    state: appState.speechManager.currentState
                )
                .frame(width: voiceButtonSize, height: voiceButtonSize)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: searchHeight)
            .background(osrsTheme.surfaceVariant)
            .cornerRadius(searchHeight / 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Menu button (more options)
            Button(action: onMenuAction) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .font(.system(size: iconSize, weight: .medium))
                    .frame(width: buttonSize, height: buttonSize)
                    .rotationEffect(.degrees(90))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(osrsTheme.surface)
    }
}

#Preview {
    VStack {
        osrsArticleSearchBar(
            onBackAction: {},
            onMenuAction: {},
            onVoiceSearchAction: {}
        )
        Spacer()
    }
    .environmentObject(AppState())
    .environment(\.osrsTheme, osrsLightTheme())
}

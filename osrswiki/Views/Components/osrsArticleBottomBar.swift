//
//  osrsArticleBottomBar.swift
//  osrswiki
//
//  Created on iOS bottom bar implementation session
//  Replicates Android PageActionBar functionality and layout
//

import SwiftUI

struct osrsArticleBottomBar: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // Action callbacks - matching Android functionality
    let onSaveAction: () -> Void
    let onFindInPageAction: () -> Void
    let onAppearanceAction: () -> Void
    let onContentsAction: () -> Void
    
    // State properties - matching Android state management
    let isBookmarked: Bool
    let saveState: osrsArticleBottomBarSaveState
    let saveProgress: Double
    let hasTableOfContents: Bool
    
    var body: some View {
        let barHeight = osrsArticleDynamicTypeScaling.toolbarHeight(for: dynamicTypeSize)

        HStack(spacing: 0) {
            osrsBottomBarButton(
                iconName: saveButtonIconName,
                text: saveButtonText,
                action: onSaveAction,
                isEnabled: saveState != .downloading,
                tintColor: saveButtonTintColor,
                dynamicTypeSize: dynamicTypeSize,
                barHeight: barHeight,
                accessibilityIdentifier: "article_save_button"
            )

            osrsBottomBarButton(
                iconName: "doc.text.magnifyingglass",
                text: "Find",
                action: onFindInPageAction,
                dynamicTypeSize: dynamicTypeSize,
                barHeight: barHeight,
                accessibilityIdentifier: "article_find_button"
            )

            osrsBottomBarButton(
                iconName: "paintbrush",
                text: "Appearance",
                action: onAppearanceAction,
                dynamicTypeSize: dynamicTypeSize,
                barHeight: barHeight,
                accessibilityIdentifier: "article_appearance_button"
            )

            osrsBottomBarButton(
                iconName: "list.bullet",
                text: "Contents",
                action: onContentsAction,
                isEnabled: true,
                dynamicTypeSize: dynamicTypeSize,
                barHeight: barHeight,
                accessibilityIdentifier: "article_contents_button"
            )
            .accessibilityValue(hasTableOfContents ? "Ready" : "Loading")
        }
        .frame(height: osrsOverlayChromeMetrics.floatingBarHeight)
        .osrsFloatingGlass(
            in: Capsule(),
            fallback: Color(osrsTheme.surface)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("article_bottom_bar")
    }
    
    // MARK: - Save Button State Management
    
    private var saveButtonIconName: String {
        switch saveState {
        case .notSaved:
            return "bookmark"
        case .downloading:
            return "arrow.down.circle"
        case .saved:
            return "bookmark.fill"
        case .error:
            return "exclamationmark.triangle"
        }
    }
    
    private var saveButtonText: String {
        switch saveState {
        case .notSaved:
            return "Save"
        case .downloading:
            return "Saving... \(Int(saveProgress * 100))%"
        case .saved:
            return "Saved"
        case .error:
            return "Retry"
        }
    }
    
    private var saveButtonTintColor: Color {
        switch saveState {
        case .notSaved:
            return osrsTheme.placeholderColor
        case .downloading:
            return osrsTheme.placeholderColor.opacity(0.4)
        case .saved:
            return osrsTheme.primaryTextColor
        case .error:
            return .red
        }
    }
}

// MARK: - Individual Bottom Bar Button Component

struct osrsBottomBarButton: View {
    @Environment(\.osrsTheme) var osrsTheme
    
    let iconName: String
    let text: String
    let action: () -> Void
    let isEnabled: Bool
    let tintColor: Color?
    let dynamicTypeSize: DynamicTypeSize
    let barHeight: CGFloat
    let accessibilityIdentifier: String
    
    init(
        iconName: String,
        text: String,
        action: @escaping () -> Void,
        isEnabled: Bool = true,
        tintColor: Color? = nil,
        dynamicTypeSize: DynamicTypeSize,
        barHeight: CGFloat,
        accessibilityIdentifier: String
    ) {
        self.iconName = iconName
        self.text = text
        self.action = action
        self.isEnabled = isEnabled
        self.tintColor = tintColor
        self.dynamicTypeSize = dynamicTypeSize
        self.barHeight = barHeight
        self.accessibilityIdentifier = accessibilityIdentifier
    }
    
    var body: some View {
        let toolbarScale = osrsArticleDynamicTypeScaling.toolbarScale(for: dynamicTypeSize)
        let iconSize = min(20 * toolbarScale, 30)
        let labelSize = min(10 * toolbarScale, 16)
        let iconHeight = min(max(iconSize + 2, 22), 32)

        Button(action: action) {
            VStack(spacing: 1) { // Tighter spacing for smaller height
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(effectiveTintColor)
                    .frame(height: iconHeight)
                
                Text(compactText)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundColor(effectiveTintColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1) // Single line like native tabs
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
            .contentShape(Rectangle()) // Ensure entire button area is tappable
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
    }
    
    private var effectiveTintColor: Color {
        if let tintColor = tintColor {
            return isEnabled ? tintColor : tintColor.opacity(0.4)
        }
        return isEnabled ? osrsTheme.placeholderColor : osrsTheme.placeholderColor.opacity(0.4)
    }

    private var compactText: String {
        guard dynamicTypeSize.isAccessibilitySize else { return text }
        switch text {
        case "Appearance": return "Text"
        case let value where value.hasPrefix("Saving"): return "Saving"
        default: return text
        }
    }
}

// MARK: - Preview

#Preview("Light Theme") {
    VStack {
        Spacer()
        osrsArticleBottomBar(
            onSaveAction: { print("Save tapped") },
            onFindInPageAction: { print("Find tapped") },
            onAppearanceAction: { print("Appearance tapped") },
            onContentsAction: { print("Contents tapped") },
            isBookmarked: false,
            saveState: .notSaved,
            saveProgress: 0.0,
            hasTableOfContents: true
        )
    }
    .environment(\.osrsTheme, osrsLightTheme())
}

#Preview("Dark Theme - Saving") {
    VStack {
        Spacer()
        osrsArticleBottomBar(
            onSaveAction: { print("Save tapped") },
            onFindInPageAction: { print("Find tapped") },
            onAppearanceAction: { print("Appearance tapped") },
            onContentsAction: { print("Contents tapped") },
            isBookmarked: false,
            saveState: .downloading,
            saveProgress: 0.65,
            hasTableOfContents: false
        )
    }
    .environment(\.osrsTheme, osrsDarkTheme())
}

#Preview("Saved State") {
    VStack {
        Spacer()
        osrsArticleBottomBar(
            onSaveAction: { print("Save tapped") },
            onFindInPageAction: { print("Find tapped") },
            onAppearanceAction: { print("Appearance tapped") },
            onContentsAction: { print("Contents tapped") },
            isBookmarked: true,
            saveState: .saved,
            saveProgress: 1.0,
            hasTableOfContents: true
        )
    }
    .environment(\.osrsTheme, osrsLightTheme())
}

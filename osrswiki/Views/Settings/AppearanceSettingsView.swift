//
//  AppearanceSettingsView.swift
//  OSRS Wiki
//

import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) private var osrsTheme
    var highlightFloorNumbering: Bool = false
    @State private var floorNumberingPulse = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section("Display") {
                    LabeledContent {
                        Picker("Theme", selection: themeSelection) {
                            ForEach(osrsThemeSelection.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("appearance_theme_picker")
                    } label: {
                        osrsAppearancePreferenceLabel(
                            icon: "circle.lefthalf.filled",
                            title: "Theme",
                            summary: themeManager.selectedTheme.description
                        )
                    }
                    .listRowBackground(Color(osrsTheme.surfaceVariant))

                    Toggle(isOn: collapseTables) {
                        osrsAppearancePreferenceLabel(
                            icon: "tablecells",
                            title: "Collapse tables",
                            summary: "Start article tables collapsed"
                        )
                    }
                    .accessibilityIdentifier("appearance_collapse_tables_toggle")
                    .listRowBackground(Color(osrsTheme.surfaceVariant))

                    Toggle(isOn: wrapTableCells) {
                        osrsAppearancePreferenceLabel(
                            icon: "text.alignleft",
                            title: "Wrap table cells",
                            summary: "Let table text wrap onto multiple lines"
                        )
                    }
                    .accessibilityIdentifier("appearance_wrap_table_cells_toggle")
                    .listRowBackground(Color(osrsTheme.surfaceVariant))

                    LabeledContent {
                        Picker("Floor numbering", selection: floorNumberingSelection) {
                            ForEach(osrsArticleFloorNumberingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("appearance_floor_numbering_picker")
                    } label: {
                        osrsAppearancePreferenceLabel(
                            icon: "building.2",
                            title: "Floor numbering",
                            summary: themeManager.floorNumberingMode.summary
                        )
                    }
                    .id("floor_numbering")
                    .transaction { $0.animation = nil }
                    .animation(nil, value: themeManager.floorNumberingMode)
                    .listRowBackground(
                        floorNumberingPulse
                            ? Color(osrsTheme.primary).opacity(0.28)
                            : Color(osrsTheme.surfaceVariant)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            osrsAppearancePreferenceLabel(
                                icon: "textformat.size",
                                title: "Article text size",
                                summary: "Adjust article text without changing app controls"
                            )

                            Spacer(minLength: 8)

                            Text(articleTextScaleLabel)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(Color(osrsTheme.secondaryTextColor))
                                .accessibilityHidden(true)
                        }

                        Slider(
                            value: articleTextScale,
                            in: osrsThemeManager.articleTextScaleRange,
                            step: 0.05
                        ) {
                            Text("Article text size")
                        } minimumValueLabel: {
                            Image(systemName: "textformat.size.smaller")
                        } maximumValueLabel: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .tint(Color(osrsTheme.primary))
                        .accessibilityIdentifier("appearance_article_text_scale")
                        .accessibilityValue(articleTextScaleLabel)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                }

                Section("Navigation") {
                    Toggle(isOn: swipeRightToGoBack) {
                        osrsAppearancePreferenceLabel(
                            icon: "arrow.left",
                            title: "Swipe right to go back",
                            summary: "Navigate back from an article with a horizontal swipe"
                        )
                    }
                    .accessibilityIdentifier("appearance_swipe_right_back_toggle")
                    .listRowBackground(Color(osrsTheme.surfaceVariant))

                    Toggle(isOn: swipeLeftToShowContents) {
                        osrsAppearancePreferenceLabel(
                            icon: "arrow.right",
                            title: "Swipe left for contents",
                            summary: "Open an article’s table of contents with a horizontal swipe"
                        )
                    }
                    .accessibilityIdentifier("appearance_swipe_left_contents_toggle")
                    .listRowBackground(Color(osrsTheme.surfaceVariant))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(osrsTheme.background))
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("appearance_screen")
            .onAppear {
                guard highlightFloorNumbering else { return }
                proxy.scrollTo("floor_numbering", anchor: .center)
                floorNumberingPulse = true
                withAnimation(.easeInOut(duration: 0.18).repeatCount(5, autoreverses: true)) {
                    floorNumberingPulse.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        floorNumberingPulse = false
                    }
                }
            }
        }
    }

    private var themeSelection: Binding<osrsThemeSelection> {
        Binding(
            get: { themeManager.selectedTheme },
            set: themeManager.setTheme
        )
    }

    private var collapseTables: Binding<Bool> {
        Binding(
            get: { themeManager.collapseTables },
            set: themeManager.setCollapseTables
        )
    }

    private var wrapTableCells: Binding<Bool> {
        Binding(
            get: { themeManager.wrapTableCells },
            set: themeManager.setWrapTableCells
        )
    }

    private var articleTextScale: Binding<Double> {
        Binding(
            get: { themeManager.articleTextScale },
            set: themeManager.setArticleTextScale
        )
    }

    private var swipeRightToGoBack: Binding<Bool> {
        Binding(
            get: { themeManager.swipeRightToGoBackEnabled },
            set: themeManager.setSwipeRightToGoBackEnabled
        )
    }

    private var swipeLeftToShowContents: Binding<Bool> {
        Binding(
            get: { themeManager.swipeLeftToShowContentsEnabled },
            set: themeManager.setSwipeLeftToShowContentsEnabled
        )
    }

    private var floorNumberingSelection: Binding<osrsArticleFloorNumberingMode> {
        Binding(
            get: { themeManager.floorNumberingMode },
            set: themeManager.setFloorNumberingMode
        )
    }

    private var articleTextScaleLabel: String {
        "\(Int((themeManager.articleTextScale * 100).rounded()))%"
    }
}

private struct osrsAppearancePreferenceLabel: View {
    @Environment(\.osrsTheme) private var osrsTheme

    let icon: String
    let title: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(osrsTheme.primary))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color(osrsTheme.primaryTextColor))

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color(osrsTheme.secondaryTextColor))
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environmentObject(osrsThemeManager.preview)
    .environment(\.osrsTheme, osrsLightTheme())
}

#Preview("Dark Theme") {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environmentObject(osrsThemeManager.previewDark)
    .environment(\.osrsTheme, osrsDarkTheme())
    .preferredColorScheme(.dark)
}

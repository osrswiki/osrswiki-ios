//
//  AppearanceSettingsView.swift
//  OSRS Wiki
//

import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) private var osrsTheme
    var highlightFloorNumbering: Bool = false
    var usesLargeTitle: Bool = true
    @State private var floorNumberingPulse = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Picker("Theme", selection: themeSelection) {
                        ForEach(osrsThemeSelection.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .accessibilityIdentifier("appearance_theme_picker")
                } footer: {
                    Text(themeManager.selectedTheme.description)
                }
                .listRowBackground(rowBackground)

                Section {
                    Toggle("Collapse tables", isOn: collapseTables)
                        .accessibilityIdentifier("appearance_collapse_tables_toggle")
                } footer: {
                    Text("Start article tables collapsed")
                }
                .listRowBackground(rowBackground)

                Section {
                    Toggle("Wrap table cells", isOn: wrapTableCells)
                        .accessibilityIdentifier("appearance_wrap_table_cells_toggle")
                } footer: {
                    Text("Let table text wrap onto multiple lines")
                }
                .listRowBackground(rowBackground)

                Section {
                    Picker("Floor numbering", selection: floorNumberingSelection) {
                        ForEach(osrsArticleFloorNumberingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("appearance_floor_numbering_picker")
                    .id("floor_numbering")
                    .transaction { $0.animation = nil }
                    .animation(nil, value: themeManager.floorNumberingMode)
                    .listRowBackground(
                        floorNumberingPulse
                            ? Color(osrsTheme.primary).opacity(0.28)
                            : Color(osrsTheme.surfaceVariant)
                    )
                } footer: {
                    Text(themeManager.floorNumberingMode.summary)
                }

                Section {
                    HStack {
                        Text("Article text size")
                        Spacer()
                        Text(articleTextScaleLabel)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Color(osrsTheme.secondaryTextColor))
                            .accessibilityHidden(true)
                    }
                    Slider(
                        value: articleTextScale,
                        in: osrsThemeManager.articleTextScaleRange,
                        step: 0.05
                    ) {
                        Text("Article text size")
                    }
                    .tint(Color(osrsTheme.primary))
                    .accessibilityIdentifier("appearance_article_text_scale")
                    .accessibilityValue(articleTextScaleLabel)
                } footer: {
                    Text("Adjust article text without changing app controls")
                }
                .listRowBackground(rowBackground)

                Section {
                    Toggle("Swipe right to go back", isOn: swipeRightToGoBack)
                        .accessibilityIdentifier("appearance_swipe_right_back_toggle")
                    Toggle("Swipe left for contents", isOn: swipeLeftToShowContents)
                        .accessibilityIdentifier("appearance_swipe_left_contents_toggle")
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Navigate back from an article, or open its table of contents, with a horizontal swipe")
                }
                .listRowBackground(rowBackground)
            }
            .osrsSettingsPage(
                title: "Appearance",
                titleDisplayMode: usesLargeTitle ? .large : .inline
            )
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

    private var rowBackground: Color {
        Color(osrsTheme.surfaceVariant)
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

#Preview("Sheet") {
    NavigationStack {
        AppearanceSettingsView(usesLargeTitle: false)
    }
    .environmentObject(osrsThemeManager.preview)
    .environment(\.osrsTheme, osrsLightTheme())
}

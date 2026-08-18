//
//  CustomMainTabView.swift
//  OSRS Wiki
//
//  Custom tab navigation to bypass iOS 18 SwiftUI TabView limitations
//  Provides perfect color control and cross-platform consistency
//

import SwiftUI

struct CustomMainTabView: View {
    @StateObject private var appState = AppState()
    @StateObject private var overlayManager = GlobalOverlayManager()
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.colorScheme) private var environmentColorScheme
    @State private var hasStartedBackgroundGeneration = false
    @State private var hasAppeared = false // Track if view has appeared to prevent initial animation
    @State private var backgroundTasks: Set<Task<Void, Never>> = []

    var body: some View {
        ZStack {
            Color(themeManager.currentTheme.background)
                .ignoresSafeArea()

            rootTabContent

#if DEBUG
            VStack {
                osrsAccessibilityMarker(
                    identifier: "deep_navigation_fixture_audit_state",
                    label: appState.deepNavigationFixtureAuditDebugLabel
                )
                Spacer()
            }
            .allowsHitTesting(false)
#endif
        }
        .environmentObject(appState)
        .environmentObject(overlayManager)
        .environment(\.osrsTheme, themeManager.currentTheme)
        .overlayManager(overlayManager)
        // Automatic must remain a nil host preference so SwiftUI follows the system directly.
        // Feeding the resolved environment scheme back into preferredColorScheme can create a
        // HostPreferences AttributeGraph cycle while iOS 26 builds an accessibility snapshot.
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
        .onAppear {
            // Mark that the view has appeared to enable transitions for future tab bar show/hide
            hasAppeared = true

            // Signal to coordinator that main view has appeared
            AppLaunchCoordinator.shared.markMainViewAppeared()

            // Signal that tab bar is rendered (since it starts visible)
            AppLaunchCoordinator.shared.markTabBarRendered()

            // Update system color scheme on appear
            if themeManager.selectedTheme == .automatic {
                themeManager.updateSystemColorScheme(environmentColorScheme)
            }

            // Signal that theme has been applied
            AppLaunchCoordinator.shared.markThemeApplied()
            osrsWebViewProcessWarmer.warmIfNeeded()

            // DEBUG: Log theme information
            print("🎨 [MAIN TAB] onAppear - Selected theme: \(themeManager.selectedTheme)")
            print("🎨 [MAIN TAB] onAppear - Environment color scheme: \(environmentColorScheme)")
            print("🎨 [MAIN TAB] onAppear - Current theme type: \(type(of: themeManager.currentTheme))")

            // Color extraction writes a diagnostics file and must never run during production.
#if DEBUG
            if osrsTestEnvironment.isRunningSimulatorUITestHarness {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    ColorExtractor.exportColorsToJSON(themeManager: themeManager)
                }
            }
#endif

            // Start background tasks only once after main interface is loaded
            if !hasStartedBackgroundGeneration {
                hasStartedBackgroundGeneration = true

#if DEBUG
                if appState.isBackgroundPreloadingDisabledForTests {
                    print("🧪 Main interface loaded - background preloading disabled by launch argument")
                    return
                }
#endif

                print("🔄 Main interface loaded - static settings preview assets ready")

                let previewTask = Task { @MainActor in
                    // Check for cancellation before starting
                    guard !Task.isCancelled else { return }

                    // Reserved for lightweight post-launch tasks.
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                    guard !Task.isCancelled else { return }
                }

                backgroundTasks.insert(previewTask)
            }
        }
        .onDisappear {
            // Cancel all background tasks when view disappears
            for task in backgroundTasks {
                task.cancel()
            }
            backgroundTasks.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Update system color scheme when app becomes active
            let currentSystemScheme: ColorScheme = UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
            if themeManager.selectedTheme == .automatic {
                themeManager.updateSystemColorScheme(currentSystemScheme)
            }
        }
        .onChange(of: environmentColorScheme) { _, newColorScheme in
            // Update theme manager when system color scheme changes
            print("🎨 [MAIN TAB] Environment color scheme changed to: \(newColorScheme)")
            if themeManager.selectedTheme == .automatic {
                themeManager.updateSystemColorScheme(newColorScheme)
            }
            print("🎨 [MAIN TAB] After update - Current theme type: \(type(of: themeManager.currentTheme))")
        }
        .animation(nil, value: overlayManager.mainTabBarHiddenOwner)
        .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
            Button("OK") {
                appState.clearError()
            }
        } message: {
            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var rootTabContent: some View {
        if #available(iOS 26.0, *) {
            nativeTabContent
        } else {
            legacyTabContent
        }
    }

    private var legacyTabContent: some View {
        ZStack {
            VStack(spacing: 0) {
                selectedRootView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if overlayManager.mainTabBarHiddenOwner == nil {
                    CustomTabBar()
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(hasAppeared ? AnyTransition.move(edge: .bottom).combined(with: .opacity) : .identity)
                }
            }

            if let articleBottomBar = overlayManager.articleBottomBar {
                VStack(spacing: 0) {
                    Spacer()
                    articleBottomBar
                        .ignoresSafeArea(.all, edges: .bottom)
                }
                .offset(x: overlayManager.articleBottomBarExitProgress * UIScreen.main.bounds.width)
            }
        }
    }

    @available(iOS 26.0, *)
    private var nativeTabContent: some View {
        TabView(selection: nativeTabSelection) {
            nativeTab(NewsView(), item: .news)
            nativeTab(SavedPagesView(), item: .saved)
            nativeTab(SearchView(), item: .search)
            nativeTab(MapView(), item: .map)
            nativeTab(MoreView(), item: .more)
        }
        .tint(Color(themeManager.currentTheme.primary))
        // Do not use `.toolbarVisibility(.hidden)` for the article overlay.
        // On iOS 26 that leaves the Liquid Glass capsule composited underneath
        // the article bar. Alpha-hide keeps the layer warm for an instant back.
        .transaction { $0.animation = nil }
        // Minimize retints the glass as it settles, which snaps the map-tab bar
        // at the end of the darkening. Keep a stable floating bar.
        .tabBarMinimizeBehavior(.never)
        .onAppear {
            UIApplication.applyStableTabBarAppearance()
            UIApplication.setFloatingTabBarHidden(overlayManager.mainTabBarHiddenOwner != nil)
        }
        .onChange(of: overlayManager.mainTabBarHiddenOwner) { _, owner in
            UIApplication.setFloatingTabBarHidden(owner != nil)
        }
        .onChange(of: appState.selectedTab) { _, _ in
            UIApplication.refreshFloatingTabBarMaterial()
        }
        .overlay {
            if let articleBottomBar = overlayManager.articleBottomBar {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    articleBottomBar
                        .padding(.bottom, osrsOverlayChromeMetrics.screenEdgeGap)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .offset(x: overlayManager.articleBottomBarExitProgress * UIScreen.main.bounds.width)
            }
        }
    }

    @available(iOS 26.0, *)
    private func nativeTab<Content: View>(
        _ content: Content,
        item: TabItem
    ) -> some View {
        content
            .tabItem {
                Label(
                    item.title,
                    systemImage: appState.selectedTab == item ? item.selectedIconName : item.iconName
                )
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityIdentifier(item.accessibilityIdentifier)
            }
            .tag(item)
    }

    private var nativeTabSelection: Binding<TabItem> {
        Binding(
            get: { appState.selectedTab },
            set: appState.setSelectedTab
        )
    }

    @ViewBuilder
    private var selectedRootView: some View {
        switch appState.selectedTab {
        case .news:
            NewsView()
        case .saved:
            SavedPagesView()
        case .search:
            SearchView()
        case .map:
            MapView()
        case .more:
            MoreView()
        }
    }
}

#Preview {
    CustomMainTabView()
        .environmentObject(osrsThemeManager.preview)
}

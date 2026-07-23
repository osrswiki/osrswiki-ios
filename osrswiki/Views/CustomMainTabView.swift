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
    @State private var isTabBarVisible = true
    @State private var hasAppeared = false // Track if view has appeared to prevent initial animation
    @State private var backgroundTasks: Set<Task<Void, Never>> = []

    var body: some View {
        ZStack {
            // Background color to prevent flash - use theme's background color immediately
            Color(themeManager.currentTheme.background)
                .ignoresSafeArea()

            // Main content area
            VStack(spacing: 0) {
                // Content view based on selected tab
                Group {
                    switch appState.selectedTab {
                    case .news:
                        // Remove nested NavigationStack - NewsView has its own NavigationStack
                        NewsView()
                    case .saved:
                        // Remove nested NavigationStack - SavedPagesView has its own NavigationStack
                        SavedPagesView()
                    case .search:
                        // Remove nested NavigationStack - SearchView has its own NavigationStack
                        SearchView()
                    case .map:
                        // Remove nested NavigationStack - MapView has its own NavigationStack
                        MapView()
                    case .more:
                        MoreView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Custom tab bar at bottom - extend to safe area
                if isTabBarVisible {
                    CustomTabBar()
                        .background(Color(themeManager.currentTheme.surface))
                        .ignoresSafeArea(.container, edges: .bottom)
                        // Only apply transition after initial appearance to prevent launch animation
                        .transition(hasAppeared ? AnyTransition.move(edge: .bottom).combined(with: .opacity) : .identity)
                }
            }
            .environmentObject(appState)
            .environmentObject(overlayManager)
            .environment(\.osrsTheme, themeManager.currentTheme)
            .overlayManager(overlayManager) // Also provide via environment key

            // Global article bottom bar overlay - positioned at same coordinates as main tab bar
            if let articleBottomBar = overlayManager.articleBottomBar {
                VStack {
                    Spacer()
                    articleBottomBar
                        .environment(\.osrsTheme, themeManager.currentTheme) // Apply theme environment to overlay
                        .background(Color(themeManager.currentTheme.surface))
                        .ignoresSafeArea(.all, edges: .bottom) // Same positioning as main tab bar, ignore keyboard
                }
            }

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
        .preferredColorScheme(themeManager.currentColorScheme) // Use theme manager's color scheme
        .onAppear {
            // Mark that the view has appeared to enable transitions for future tab bar show/hide
            hasAppeared = true

            // Signal to coordinator that main view has appeared
            AppLaunchCoordinator.shared.markMainViewAppeared()

            // Signal that tab bar is rendered (since it starts visible)
            AppLaunchCoordinator.shared.markTabBarRendered()

            // Update system color scheme on appear
            themeManager.updateSystemColorScheme(environmentColorScheme)

            // Signal that theme has been applied
            AppLaunchCoordinator.shared.markThemeApplied()

            // DEBUG: Log theme information
            print("🎨 [MAIN TAB] onAppear - Selected theme: \(themeManager.selectedTheme)")
            print("🎨 [MAIN TAB] onAppear - Environment color scheme: \(environmentColorScheme)")
            print("🎨 [MAIN TAB] onAppear - Current theme type: \(type(of: themeManager.currentTheme))")

            // DEBUG: Extract actual colors for testing
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                ColorExtractor.exportColorsToJSON(themeManager: themeManager)
            }

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
            themeManager.updateSystemColorScheme(currentSystemScheme)
        }
        .onChange(of: environmentColorScheme) { _, newColorScheme in
            // Update theme manager when system color scheme changes
            print("🎨 [MAIN TAB] Environment color scheme changed to: \(newColorScheme)")
            themeManager.updateSystemColorScheme(newColorScheme)
            print("🎨 [MAIN TAB] After update - Current theme type: \(type(of: themeManager.currentTheme))")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hideCustomTabBar"))) { _ in
            withAnimation(.easeInOut(duration: osrsBottomBarTransition.visibilityAnimationDuration)) {
                isTabBarVisible = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showCustomTabBar"))) { _ in
            withAnimation(.easeInOut(duration: osrsBottomBarTransition.visibilityAnimationDuration)) {
                isTabBarVisible = true
            }
        }
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
}

#Preview {
    CustomMainTabView()
        .environmentObject(osrsThemeManager.preview)
}

//
//  OSRS_WikiApp.swift
//  OSRS Wiki
//
//  Created by Osamu Miyawaki on 7/29/25.
//

import SwiftUI

@main
struct osrswikiApp: App {
    @StateObject private var themeManager = osrsThemeManager()
    
    init() {
        // Register custom fonts when app starts
        print("🚀 App starting...")
#if DEBUG
        if osrsTestEnvironment.isRunningHostedXCTest {
            print("🧪 App: Skipping font registration for hosted XCTest")
        } else {
            osrsFontRegistrar.registerFonts()
            print("✅ Font registration completed")
        }
#else
        osrsFontRegistrar.registerFonts()
        print("✅ Font registration completed")
#endif
        
        // Initialize proxy service for offline functionality (iOS 17+ only)
        if #available(iOS 17.0, *) {
#if DEBUG
            if osrsTestEnvironment.isRunningHostedXCTest &&
                !osrsTestEnvironment.allowsProxyStartupDuringTests {
                print("🧪 App: Skipping proxy service startup for hosted XCTest")
            } else {
                Task { @MainActor in
                    print("🔧 App: Initializing proxy service for offline functionality...")
                    // Access the shared instance to trigger initialization
                    _ = ProxyInterceptorService.shared
                    print("✅ App: Proxy service initialized and ready")
                }
            }
#else
            Task { @MainActor in
                print("🔧 App: Initializing proxy service for offline functionality...")
                // Access the shared instance to trigger initialization
                _ = ProxyInterceptorService.shared
                print("✅ App: Proxy service initialized and ready")
            }
#endif
        }
        
        // Note: Removed complex tile pre-warming service
        // Simple loading state approach is more effective and less jarring
    }
    
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if let exportRequest = osrsSettingsPreviewExportRequest.current {
            osrsSettingsPreviewTableExportView(request: exportRequest)
                .environmentObject(themeManager)
                .background(Color(exportRequest.theme.background))
                .tint(Color(exportRequest.theme.primary))
                .accentColor(Color(exportRequest.theme.primary))
                .onAppear {
                    updateGlobalTheming()
                }
        } else {
            mainView
        }
#else
        mainView
#endif
    }

    private var mainView: some View {
        CustomMainTabView()
            .environmentObject(themeManager)
            // Set background immediately to prevent flash
            .background(Color(themeManager.currentTheme.background))
            // GLOBAL APP THEMING - This cascades to ALL UI components
            .tint(Color(themeManager.currentTheme.primary))
            .accentColor(Color(themeManager.currentTheme.primary))
            // Update global theming when theme changes
            .onChange(of: themeManager.currentTheme.primary) { _, _ in
                updateGlobalTheming()
            }
            .onAppear {
                // Initialize global theming when app starts
                updateGlobalTheming()
#if DEBUG
                guard !osrsTestEnvironment.disablesStartupSideEffects else {
                    print("🧪 App: Skipping keyboard prewarming for deterministic test launch")
                    return
                }
#endif
                // Pre-warm keyboard only after UI is fully ready to prevent animations
                AppLaunchCoordinator.shared.performKeyboardPrewarmingWhenReady()
            }
    }
    
    /// Configure comprehensive global theming that applies to ALL UI components
    private func updateGlobalTheming() {
        let primaryColor = UIColor(themeManager.currentTheme.primary)
        
        print("🎨 [GLOBAL THEMING] Applying comprehensive app-wide theming")
        print("🎨 [GLOBAL THEMING] Primary color: \(primaryColor)")
        
        // COMPREHENSIVE UI COMPONENT THEMING
        // This ensures EVERY component uses our theme colors by default
        
        UINavigationBar.appearance().tintColor = primaryColor
        UITabBar.appearance().tintColor = primaryColor
        UITableView.appearance().backgroundColor = UIColor(themeManager.currentTheme.background)
        UITableViewCell.appearance().backgroundColor = UIColor(themeManager.currentTheme.surface)
        UICollectionView.appearance().backgroundColor = UIColor(themeManager.currentTheme.background)

        if #available(iOS 26.0, *) {
            // Keep Liquid Glass, but pin scroll-edge and standard to the same
            // clear material so Map's dark content cannot rematerialize the bar
            // into a frosted capsule at the end of the adaptive tint.
            UIApplication.applyStableTabBarAppearance()
        } else {
            // The compatibility path keeps the exact opaque surfaces used on iOS 18.5–25.
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = UIColor(themeManager.currentTheme.surface)
            navAppearance.titleTextAttributes = [.foregroundColor: UIColor(themeManager.currentTheme.onSurface)]
            navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(themeManager.currentTheme.onSurface)]

            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().compactAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = UIColor(themeManager.currentTheme.surface)
            UITabBar.appearance().standardAppearance = tabAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }
        
        // Progress Views - Global styling
        UIProgressView.appearance().tintColor = primaryColor
        UIProgressView.appearance().trackTintColor = UIColor(themeManager.currentTheme.surfaceVariant)
        
        // Activity Indicators
        UIActivityIndicatorView.appearance().color = primaryColor
        
        // Switches (Toggles)  
        UISwitch.appearance().onTintColor = primaryColor
        UISwitch.appearance().thumbTintColor = UIColor(themeManager.currentTheme.surface)
        
        // Sliders
        UISlider.appearance().tintColor = primaryColor
        UISlider.appearance().thumbTintColor = primaryColor
        
        // Segmented Controls (Pickers)
        UISegmentedControl.appearance().selectedSegmentTintColor = primaryColor
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor(themeManager.currentTheme.onPrimary)
        ], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor(themeManager.currentTheme.onSurface)  
        ], for: .normal)
        
        // Steppers
        UIStepper.appearance().tintColor = primaryColor
        
        // Page Controls  
        UIPageControl.appearance().currentPageIndicatorTintColor = primaryColor
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(themeManager.currentTheme.surfaceVariant)
        
        // Search Bars
        UISearchBar.appearance().tintColor = primaryColor
        
        // Refresh Controls
        UIRefreshControl.appearance().tintColor = primaryColor
        
        print("🎨 [GLOBAL THEMING] Comprehensive theming applied to all UI components")
    }
}

//
//  OSRS_WikiApp.swift
//  OSRS Wiki
//
//  Created by Osamu Miyawaki on 7/29/25.
//
//  Root UI factory. The process entry point is osrsAppDelegate / osrsSceneDelegate
//  so resume can replace the scene's one UIWindow. SwiftUI scene hosts are not
//  used: iOS 26 can freeze that host's framebuffer after a real background.
//

import SwiftUI

@MainActor
enum osrsAppRoot {
    static let themeManager = osrsThemeManager()
    static let appState = AppState()

    static func start() {
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

        if #available(iOS 17.0, *) {
#if DEBUG
            if osrsTestEnvironment.isRunningHostedXCTest &&
                !osrsTestEnvironment.allowsProxyStartupDuringTests {
                print("🧪 App: Skipping proxy service startup for hosted XCTest")
            } else {
                Task { @MainActor in
                    print("🔧 App: Initializing proxy service for offline functionality...")
                    _ = ProxyInterceptorService.shared
                    print("✅ App: Proxy service initialized and ready")
                }
            }
#else
            Task { @MainActor in
                print("🔧 App: Initializing proxy service for offline functionality...")
                _ = ProxyInterceptorService.shared
                print("✅ App: Proxy service initialized and ready")
            }
#endif
        }
    }

    @ViewBuilder
    static var rootView: some View {
#if DEBUG
        if let exportRequest = osrsSettingsPreviewExportRequest.current {
            osrsSettingsPreviewTableExportView(request: exportRequest)
                .environmentObject(themeManager)
                .background(Color(exportRequest.theme.background))
                .tint(Color(exportRequest.theme.primary))
                .accentColor(Color(exportRequest.theme.primary))
                .onAppear {
                    applyGlobalTheming()
                }
        } else {
            mainView
        }
#else
        mainView
#endif
    }

    static var mainView: some View {
        CustomMainTabView()
            .environmentObject(themeManager)
            .environmentObject(appState)
            .background(Color(themeManager.currentTheme.background))
            .tint(Color(themeManager.currentTheme.primary))
            .accentColor(Color(themeManager.currentTheme.primary))
            .onChange(of: themeManager.currentTheme.primary) { _, _ in
                applyGlobalTheming()
            }
            .onAppear {
                themeManager.applyPersistedThemeToWindows()
                applyGlobalTheming()
#if DEBUG
                guard !osrsTestEnvironment.disablesStartupSideEffects else {
                    print("🧪 App: Skipping keyboard prewarming for deterministic test launch")
                    return
                }
#endif
                AppLaunchCoordinator.shared.performKeyboardPrewarmingWhenReady()
            }
    }

    static func applyGlobalTheming() {
        let primaryColor = UIColor(themeManager.currentTheme.primary)

        print("🎨 [GLOBAL THEMING] Applying comprehensive app-wide theming")
        print("🎨 [GLOBAL THEMING] Primary color: \(primaryColor)")

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

        UIProgressView.appearance().tintColor = primaryColor
        UIProgressView.appearance().trackTintColor = UIColor(themeManager.currentTheme.surfaceVariant)
        UIActivityIndicatorView.appearance().color = primaryColor
        UISwitch.appearance().onTintColor = primaryColor
        UISwitch.appearance().thumbTintColor = UIColor(themeManager.currentTheme.surface)
        UISlider.appearance().tintColor = primaryColor
        UISlider.appearance().thumbTintColor = primaryColor
        UISegmentedControl.appearance().selectedSegmentTintColor = primaryColor
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor(themeManager.currentTheme.onPrimary)
        ], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor(themeManager.currentTheme.onSurface)
        ], for: .normal)
        UIStepper.appearance().tintColor = primaryColor
        UIPageControl.appearance().currentPageIndicatorTintColor = primaryColor
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(themeManager.currentTheme.surfaceVariant)
        UISearchBar.appearance().tintColor = primaryColor
        UIRefreshControl.appearance().tintColor = primaryColor

        print("🎨 [GLOBAL THEMING] Comprehensive theming applied to all UI components")
    }
}

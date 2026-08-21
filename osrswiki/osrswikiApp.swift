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
        print("🎨 [GLOBAL THEMING] Applying live window and control theming")
        osrsLiveThemeApplier.apply(
            themeManager.currentTheme,
            colorScheme: themeManager.currentColorScheme
        )
        print("🎨 [GLOBAL THEMING] Live theming applied to connected windows")
    }
}

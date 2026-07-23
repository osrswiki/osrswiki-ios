//
//  MapView.swift
//  OSRS Wiki
//
//  MapLibre Native implementation for OSRS map
//

import SwiftUI

struct MapView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack(path: $appState.mapNavigationStack) {
            osrsMapLibreView()
                .accessibilityIdentifier("map_screen")
        }
    }
}

#Preview {
    MapView()
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
        .environment(\.osrsTheme, osrsLightTheme())
}

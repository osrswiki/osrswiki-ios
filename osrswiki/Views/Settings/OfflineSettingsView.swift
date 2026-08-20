//
//  OfflineSettingsView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI

struct OfflineSettingsView: View {
    @Environment(\.osrsTheme) var osrsTheme

    var body: some View {
        osrsDownloadSettingsView()
            .environment(\.osrsTheme, osrsTheme)
    }

    static func cacheSizeLimitMenu() -> some View {
        osrsCacheSizeLimitRow()
    }
}

private struct osrsCacheSizeLimitRow: View {
    @Environment(\.osrsTheme) private var osrsTheme
    @State private var selectedCacheSizeLimit = UserDefaults.standard.string(forKey: "offlineCacheSizeLimit") ?? "100"

    private let cacheSizeLimits = [
        ("50", "50 MB"),
        ("100", "100 MB"),
        ("200", "200 MB"),
        ("500", "500 MB"),
        ("1000", "1 GB"),
        ("2000", "2 GB")
    ]

    var body: some View {
        HStack {
            Label("Cache size limit", systemImage: "externaldrive.fill")
            Spacer()
            Menu {
                ForEach(cacheSizeLimits, id: \.0) { value, label in
                    Button(action: {
                        selectedCacheSizeLimit = value
                        UserDefaults.standard.set(value, forKey: "offlineCacheSizeLimit")
                    }) {
                        HStack {
                            Text(label)
                            if selectedCacheSizeLimit == value {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(cacheSizeLimits.first { $0.0 == selectedCacheSizeLimit }?.1 ?? "100 MB")
                        .foregroundStyle(.osrsSecondaryTextColor)
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.osrsSecondaryTextColor)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        OfflineSettingsView()
            .environmentObject(AppState())
            .environment(\.osrsTheme, osrsLightTheme())
    }
}

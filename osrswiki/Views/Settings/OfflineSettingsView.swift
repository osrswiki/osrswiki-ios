//
//  OfflineSettingsView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI

struct OfflineSettingsView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @State private var selectedCacheSizeLimit = "100"
    
    private let cacheSizeLimits = [
        ("50", "50 MB"),
        ("100", "100 MB"),
        ("200", "200 MB"),
        ("500", "500 MB"),
        ("1000", "1 GB"),
        ("2000", "2 GB")
    ]
    
    var body: some View {
        List {
            Section {
                cacheSizeLimitRow
            } header: {
                Text("Storage Settings")
            } footer: {
                Text("Controls how much space the app can use for cached content. Larger limits allow more content to be available offline.")
            }
            
            Section {
                clearCacheButton
                cacheStatusRow
            } header: {
                Text("Cache Management")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Offline Content")
        .navigationBarTitleDisplayMode(.large)
        .background(.osrsBackground)
        .onAppear {
            loadSettings()
        }
    }
    
    private var cacheSizeLimitRow: some View {
        HStack {
            Label("Cache Size Limit", systemImage: "externaldrive.fill")
                .foregroundColor(.blue)
            
            Spacer()
            
            Menu {
                ForEach(cacheSizeLimits, id: \.0) { value, label in
                    Button(action: {
                        selectedCacheSizeLimit = value
                        saveCacheSizeLimit(value)
                    }) {
                        HStack {
                            Text(label)
                            if selectedCacheSizeLimit == value {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
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
    
    private var clearCacheButton: some View {
        Button(action: {
            clearCache()
        }) {
            Label("Clear Cache", systemImage: "trash.fill")
                .foregroundColor(.red)
        }
    }
    
    private var cacheStatusRow: some View {
        HStack {
            Label("Cache Usage", systemImage: "chart.pie.fill")
                .foregroundColor(.orange)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("45.2 MB")
                    .font(.body)
                    .foregroundStyle(.osrsPrimaryTextColor)
                Text("of \(cacheSizeLimits.first { $0.0 == selectedCacheSizeLimit }?.1 ?? "100 MB")")
                    .font(.caption)
                    .foregroundStyle(.osrsSecondaryTextColor)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func loadSettings() {
        // Load cache size limit from UserDefaults
        selectedCacheSizeLimit = UserDefaults.standard.string(forKey: "offlineCacheSizeLimit") ?? "100"
    }
    
    private func saveCacheSizeLimit(_ value: String) {
        UserDefaults.standard.set(value, forKey: "offlineCacheSizeLimit")
    }
    
    private func clearCache() {
        // TODO: Implement cache clearing logic
        // This would clear cached content and update the cache usage display
    }
}

#Preview {
    NavigationView {
        OfflineSettingsView()
            .environmentObject(AppState())
    }
}
//
//  StorageView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI

struct StorageView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @StateObject private var viewModel = StorageViewModel()
    @State private var showingClearConfirmation = false
    @State private var selectedStorageType: StorageType?
    
    var body: some View {
        List {
            storageOverviewSection
            storageBreakdownSection
            managementActionsSection
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.large)
        .background(.osrsBackground)
        .onAppear {
            viewModel.loadStorageInfo()
        }
        .alert("Clear Data", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                if let storageType = selectedStorageType {
                    viewModel.clearStorage(type: storageType)
                }
                selectedStorageType = nil
            }
        } message: {
            if let storageType = selectedStorageType {
                Text("This will permanently delete all \(storageType.description.lowercased()). This action cannot be undone.")
            }
        }
    }
    
    private var storageOverviewSection: some View {
        Section {
            VStack(spacing: 16) {
                // Total storage usage
                VStack(spacing: 8) {
                    Text("Total App Storage")
                        .font(.headline)
                        .foregroundStyle(.osrsPrimaryTextColor)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(viewModel.totalStorageUsed)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        
                        Text("MB")
                            .font(.title3)
                            .foregroundStyle(.osrsSecondaryTextColor)
                            .padding(.bottom, 4)
                    }
                }
                
                // Storage progress bar
                VStack(spacing: 4) {
                    HStack {
                        Text("Available Device Storage")
                            .font(.caption)
                            .foregroundStyle(.osrsSecondaryTextColor)
                        
                        Spacer()
                        
                        Text("\(viewModel.availableStorage) GB free")
                            .font(.caption)
                            .foregroundStyle(.osrsSecondaryTextColor)
                    }
                    
                    ProgressView(value: viewModel.storageUsagePercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: viewModel.storageColor))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var storageBreakdownSection: some View {
        Section("Storage Breakdown") {
            ForEach(viewModel.storageItems) { item in
                StorageItemRow(item: item) {
                    selectedStorageType = item.type
                    showingClearConfirmation = true
                }
            }
        }
    }
    
    private var managementActionsSection: some View {
        Section("Management") {
            Button(action: {
                viewModel.optimizeStorage()
            }) {
                Label("Optimize Storage", systemImage: "wand.and.rays")
                    .foregroundStyle(.osrsPrimary)
            }
            
            Button(action: {
                viewModel.analyzeStorageUsage()
            }) {
                Label("Analyze Storage Usage", systemImage: "chart.bar.fill")
                    .foregroundStyle(.osrsAccent)
            }
            
            NavigationLink(destination: AdvancedStorageView()) {
                Label("Advanced Settings", systemImage: "gearshape.fill")
                    .foregroundStyle(.osrsSecondaryTextColor)
            }
        }
    }
}

struct StorageItemRow: View {
    let item: StorageItem
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.iconName)
                .foregroundColor(item.type.color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.type.description)
                    .font(.body)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text(item.details)
                    .font(.caption)
                    .foregroundStyle(.osrsSecondaryTextColor)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.size) MB")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                if item.canClear {
                    Button("Clear") {
                        onClear()
                    }
                    .font(.caption)
                    .foregroundStyle(.osrsError)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AdvancedStorageView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        List {
            Section("Automatic Cleanup") {
                Toggle("Auto-clear cache weekly", isOn: .constant(true))
                Toggle("Remove old downloads", isOn: .constant(false))
            }
            
            Section("Cache Limits") {
                VStack(alignment: .leading) {
                    Text("Image Cache Limit")
                    Slider(value: .constant(50), in: 10...200)
                    Text("50 MB")
                        .font(.caption)
                        .foregroundStyle(.osrsSecondaryTextColor)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Advanced Storage")
        .navigationBarTitleDisplayMode(.inline)
        .background(.osrsBackground)
    }
}

// MARK: - Storage Models
enum StorageType: String, CaseIterable {
    case cache = "cache"
    case offlineContent = "offline"
    case images = "images"
    case userData = "user_data"
    case app = "app"
    
    var description: String {
        switch self {
        case .cache: return "Cache Files"
        case .offlineContent: return "Offline Content"
        case .images: return "Downloaded Images"
        case .userData: return "User Data"
        case .app: return "App Data"
        }
    }
    
    var iconName: String {
        switch self {
        case .cache: return "externaldrive.fill"
        case .offlineContent: return "arrow.down.circle.fill"
        case .images: return "photo.fill"
        case .userData: return "person.crop.circle.fill"
        case .app: return "app.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .cache: return .orange
        case .offlineContent: return .green
        case .images: return .blue
        case .userData: return .purple
        case .app: return .gray
        }
    }
}

struct StorageItem: Identifiable {
    let id = UUID()
    let type: StorageType
    let size: Int // in MB
    let details: String
    let canClear: Bool
}

// MARK: - StorageViewModel
class StorageViewModel: ObservableObject {
    @Published var storageItems: [StorageItem] = []
    @Published var totalStorageUsed: String = "0"
    @Published var availableStorage: String = "0"
    @Published var storageUsagePercentage: Double = 0.0
    
    var storageColor: Color {
        if storageUsagePercentage > 0.8 {
            return .red
        } else if storageUsagePercentage > 0.6 {
            return .orange
        } else {
            return .green
        }
    }
    
    func loadStorageInfo() {
        // TODO: Implement actual storage calculation from device
        // For now, use sample data
        DispatchQueue.main.async {
            self.storageItems = [
                StorageItem(type: .cache, size: 45, details: "Temporary files and web cache", canClear: true),
                StorageItem(type: .offlineContent, size: 128, details: "Downloaded pages for offline reading", canClear: true),
                StorageItem(type: .images, size: 67, details: "Cached images and thumbnails", canClear: true),
                StorageItem(type: .userData, size: 12, details: "Settings and preferences", canClear: false),
                StorageItem(type: .app, size: 23, details: "Application files", canClear: false)
            ]
            
            let totalMB = self.storageItems.reduce(0) { $0 + $1.size }
            self.totalStorageUsed = String(totalMB)
            self.availableStorage = "15.2"
            self.storageUsagePercentage = Double(totalMB) / 1000.0 // Simulate percentage
        }
    }
    
    func clearStorage(type: StorageType) {
        if let index = storageItems.firstIndex(where: { $0.type == type }) {
            storageItems[index] = StorageItem(
                type: type,
                size: 0,
                details: storageItems[index].details + " (cleared)",
                canClear: storageItems[index].canClear
            )
            
            // Recalculate total
            let totalMB = storageItems.reduce(0) { $0 + $1.size }
            totalStorageUsed = String(totalMB)
            storageUsagePercentage = Double(totalMB) / 1000.0
        }
        
        // TODO: Implement actual storage clearing
    }
    
    func optimizeStorage() {
        // TODO: Implement storage optimization
        // This could remove duplicate files, compress images, etc.
    }
    
    func analyzeStorageUsage() {
        // TODO: Implement detailed storage analysis
        // This could show which pages/content use the most space
    }
}

#Preview {
    NavigationView {
        StorageView()
            .environmentObject(AppState())
    }
}
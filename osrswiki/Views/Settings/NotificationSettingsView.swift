//
//  NotificationSettingsView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @StateObject private var notificationManager = NotificationManager()
    
    var body: some View {
        List {
            permissionSection
            
            if notificationManager.permissionStatus == .authorized {
                newsNotificationsSection
                updateNotificationsSection
                quietHoursSection
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .background(.osrsBackground)
        .onAppear {
            notificationManager.checkPermissionStatus()
        }
    }
    
    private var permissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: notificationManager.permissionStatus.iconName)
                        .foregroundColor(notificationManager.permissionStatus.color)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notification Permission")
                            .font(.headline)
                            .foregroundStyle(.osrsPrimaryTextColor)
                        
                        Text(notificationManager.permissionStatus.description)
                            .font(.caption)
                            .foregroundStyle(.osrsSecondaryTextColor)
                    }
                    
                    Spacer()
                    
                    if notificationManager.permissionStatus == .notDetermined {
                        Button("Enable") {
                            notificationManager.requestPermission()
                        }
                        .foregroundStyle(.osrsPrimary)
                    }
                }
                
                if notificationManager.permissionStatus == .denied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To receive notifications, please enable them in Settings:")
                            .font(.caption)
                            .foregroundStyle(.osrsSecondaryTextColor)
                        
                        Button("Open Settings") {
                            notificationManager.openSettings()
                        }
                        .font(.caption)
                        .foregroundStyle(.osrsPrimary)
                    }
                    .padding(.top, 8)
                }
            }
        } header: {
            Text("Permission")
        }
    }
    
    private var newsNotificationsSection: some View {
        Section {
            Toggle("News Updates", isOn: $notificationManager.newsNotificationsEnabled)
            
            if notificationManager.newsNotificationsEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frequency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("News Frequency", selection: $notificationManager.newsFrequency) {
                        ForEach(NotificationFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.top, 8)
            }
        } header: {
            Text("Game News")
        } footer: {
            Text("Get notified about Old School RuneScape news, updates, and events.")
        }
    }
    
    private var updateNotificationsSection: some View {
        Section {
            Toggle("App Updates", isOn: $notificationManager.appUpdatesEnabled)
            Toggle("Feature Announcements", isOn: $notificationManager.featureAnnouncementsEnabled)
            Toggle("Wiki Content Updates", isOn: $notificationManager.wikiUpdatesEnabled)
        } header: {
            Text("App & Content")
        } footer: {
            Text("Stay informed about app improvements and wiki content changes.")
        }
    }
    
    private var quietHoursSection: some View {
        Section {
            Toggle("Quiet Hours", isOn: $notificationManager.quietHoursEnabled)
            
            if notificationManager.quietHoursEnabled {
                VStack(spacing: 12) {
                    HStack {
                        Text("Start Time")
                            .foregroundStyle(.osrsPrimaryTextColor)
                        Spacer()
                        DatePicker("", selection: $notificationManager.quietHoursStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("End Time")
                            .foregroundStyle(.osrsPrimaryTextColor)
                        Spacer()
                        DatePicker("", selection: $notificationManager.quietHoursEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                .padding(.top, 8)
            }
        } header: {
            Text("Do Not Disturb")
        } footer: {
            if notificationManager.quietHoursEnabled {
                Text("Notifications will be silenced during these hours: \(notificationManager.quietHoursDescription)")
            } else {
                Text("Set specific hours when you don't want to receive notifications.")
            }
        }
    }
}

// MARK: - NotificationManager
class NotificationManager: ObservableObject {
    @Published var permissionStatus: NotificationPermissionStatus = .notDetermined
    @Published var newsNotificationsEnabled = true
    @Published var newsFrequency: NotificationFrequency = .daily
    @Published var appUpdatesEnabled = true
    @Published var featureAnnouncementsEnabled = true
    @Published var wikiUpdatesEnabled = false
    @Published var quietHoursEnabled = false
    @Published var quietHoursStart = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @Published var quietHoursEnd = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    var quietHoursDescription: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: quietHoursStart)) - \(formatter.string(from: quietHoursEnd))"
    }
    
    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.permissionStatus = .notDetermined
                case .denied:
                    self.permissionStatus = .denied
                case .authorized, .provisional:
                    self.permissionStatus = .authorized
                case .ephemeral:
                    self.permissionStatus = .authorized
                @unknown default:
                    self.permissionStatus = .denied
                }
            }
        }
    }
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.permissionStatus = granted ? .authorized : .denied
                if granted {
                    self.scheduleNotifications()
                }
            }
        }
    }
    
    func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func loadSettings() {
        newsNotificationsEnabled = userDefaults.bool(forKey: "newsNotificationsEnabled")
        appUpdatesEnabled = userDefaults.bool(forKey: "appUpdatesEnabled")
        featureAnnouncementsEnabled = userDefaults.bool(forKey: "featureAnnouncementsEnabled")
        wikiUpdatesEnabled = userDefaults.bool(forKey: "wikiUpdatesEnabled")
        quietHoursEnabled = userDefaults.bool(forKey: "quietHoursEnabled")
        
        if let frequency = NotificationFrequency(rawValue: userDefaults.string(forKey: "newsFrequency") ?? "") {
            newsFrequency = frequency
        }
        
        if let startTime = userDefaults.object(forKey: "quietHoursStart") as? Date {
            quietHoursStart = startTime
        }
        
        if let endTime = userDefaults.object(forKey: "quietHoursEnd") as? Date {
            quietHoursEnd = endTime
        }
    }
    
    private func saveSettings() {
        userDefaults.set(newsNotificationsEnabled, forKey: "newsNotificationsEnabled")
        userDefaults.set(appUpdatesEnabled, forKey: "appUpdatesEnabled")
        userDefaults.set(featureAnnouncementsEnabled, forKey: "featureAnnouncementsEnabled")
        userDefaults.set(wikiUpdatesEnabled, forKey: "wikiUpdatesEnabled")
        userDefaults.set(quietHoursEnabled, forKey: "quietHoursEnabled")
        userDefaults.set(newsFrequency.rawValue, forKey: "newsFrequency")
        userDefaults.set(quietHoursStart, forKey: "quietHoursStart")
        userDefaults.set(quietHoursEnd, forKey: "quietHoursEnd")
        
        scheduleNotifications()
    }
    
    private func scheduleNotifications() {
        // TODO: Implement notification scheduling based on user preferences
        // This would create and schedule local notifications for news updates, etc.
    }
}

// MARK: - Supporting Types
enum NotificationPermissionStatus {
    case notDetermined, denied, authorized
    
    var iconName: String {
        switch self {
        case .notDetermined: return "bell.badge.circle"
        case .denied: return "bell.slash.circle.fill"
        case .authorized: return "bell.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .notDetermined: return .orange
        case .denied: return .red  
        case .authorized: return .green
        }
    }
    
    var description: String {
        switch self {
        case .notDetermined: return "Tap to enable notifications"
        case .denied: return "Notifications are disabled"
        case .authorized: return "Notifications are enabled"
        }
    }
}

enum NotificationFrequency: String, CaseIterable {
    case immediate = "immediate"
    case daily = "daily"
    case weekly = "weekly"
    
    var displayName: String {
        switch self {
        case .immediate: return "Immediate"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

#Preview {
    NavigationView {
        NotificationSettingsView()
            .environment(\.osrsTheme, osrsLightTheme())
    }
}
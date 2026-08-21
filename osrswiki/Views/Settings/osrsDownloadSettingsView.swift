import SwiftUI

struct osrsDownloadSettingsView: View {
    @EnvironmentObject private var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) private var osrsTheme
    @State private var settings = osrsDownloadSettings.load()

    var body: some View {
        List {
            Section {
                Picker("Update saved pages", selection: updatePolicyBinding) {
                    ForEach(osrsSavedPageUpdatePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .accessibilityIdentifier("downloads_update_policy_picker")
            } header: {
                Text("Saved pages")
                    .foregroundStyle(Color(osrsTheme.secondaryTextColor))
            } footer: {
                Text(settings.updatePolicy.summary)
                    .foregroundStyle(Color(osrsTheme.secondaryTextColor))
            }
            .listRowBackground(Color(osrsTheme.surfaceVariant))

            Section {
                Picker("Download over", selection: downloadNetworkBinding) {
                    ForEach(osrsSavedPageDownloadNetwork.allCases) { network in
                        Text(network.title).tag(network)
                    }
                }
                .accessibilityIdentifier("downloads_network_picker")
            } footer: {
                Text(settings.downloadNetwork.summary)
                    .foregroundStyle(Color(osrsTheme.secondaryTextColor))
            }
            .listRowBackground(Color(osrsTheme.surfaceVariant))

            Section {
                cacheSizeLimitRow
            } header: {
                Text("Cache")
                    .foregroundStyle(Color(osrsTheme.secondaryTextColor))
            } footer: {
                Text("Limits space used for ordinary article cache, separate from explicitly saved pages.")
                    .foregroundStyle(Color(osrsTheme.secondaryTextColor))
            }
            .listRowBackground(Color(osrsTheme.surfaceVariant))
        }
        .osrsSettingsPage(title: "Downloads")
        .overlay(alignment: .topLeading) {
            osrsAccessibilityMarker(identifier: "downloads_screen", label: "Downloads settings")
        }
        .onAppear {
            settings = osrsDownloadSettings.load()
        }
    }

    private var updatePolicyBinding: Binding<osrsSavedPageUpdatePolicy> {
        Binding(
            get: { settings.updatePolicy },
            set: { policy in
                settings.updatePolicy = policy
                settings.save()
            }
        )
    }

    private var downloadNetworkBinding: Binding<osrsSavedPageDownloadNetwork> {
        Binding(
            get: { settings.downloadNetwork },
            set: { network in
                settings.downloadNetwork = network
                settings.save()
            }
        )
    }

    private var cacheSizeLimitRow: some View {
        OfflineSettingsView.cacheSizeLimitMenu()
    }
}

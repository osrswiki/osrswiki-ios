import Foundation

enum osrsSavedPageUpdatePolicy: String, CaseIterable, Identifiable {
    case automatic
    case onAccess
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .onAccess: return "When opened"
        case .manual: return "Manual only"
        }
    }

    var summary: String {
        switch self {
        case .automatic:
            return "Check for a newer wiki revision in the background, then refresh the saved snapshot"
        case .onAccess:
            return "Show the saved snapshot immediately, then refresh it if the wiki revision changed"
        case .manual:
            return "Keep the saved snapshot until you choose Update"
        }
    }
}

enum osrsSavedPageDownloadNetwork: String, CaseIterable, Identifiable {
    case wifiOnly
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifiOnly: return "Wi-Fi only"
        case .any: return "Any connection"
        }
    }

    var summary: String {
        switch self {
        case .wifiOnly:
            return "Saved-page updates wait for Wi-Fi or Ethernet"
        case .any:
            return "Saved-page updates may use cellular data"
        }
    }
}

enum osrsSavedPageUpdateTrigger: Equatable {
    case automaticScan
    case access
    case manual
}

struct osrsDownloadSettings: Equatable {
    static let updatePolicyKey = "osrs.savedPage.updatePolicy"
    static let downloadNetworkKey = "osrs.savedPage.downloadNetwork"

    var updatePolicy: osrsSavedPageUpdatePolicy
    var downloadNetwork: osrsSavedPageDownloadNetwork

    static func load(defaults: UserDefaults = .standard) -> osrsDownloadSettings {
        let policy = osrsSavedPageUpdatePolicy(
            rawValue: defaults.string(forKey: updatePolicyKey) ?? ""
        ) ?? .onAccess
        let network = osrsSavedPageDownloadNetwork(
            rawValue: defaults.string(forKey: downloadNetworkKey) ?? ""
        ) ?? .wifiOnly
        return osrsDownloadSettings(updatePolicy: policy, downloadNetwork: network)
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(updatePolicy.rawValue, forKey: Self.updatePolicyKey)
        defaults.set(downloadNetwork.rawValue, forKey: Self.downloadNetworkKey)
    }

    private static let pendingManualUpdateKey = "osrs.savedPage.pendingManualUpdateIds"

    static func markPendingManualUpdate(id: String, defaults: UserDefaults = .standard) {
        var pending = Set(defaults.stringArray(forKey: pendingManualUpdateKey) ?? [])
        pending.insert(id)
        defaults.set(Array(pending), forKey: pendingManualUpdateKey)
    }

    static func consumePendingManualUpdate(id: String, defaults: UserDefaults = .standard) -> Bool {
        var pending = Set(defaults.stringArray(forKey: pendingManualUpdateKey) ?? [])
        let contained = pending.remove(id) != nil
        defaults.set(Array(pending), forKey: pendingManualUpdateKey)
        return contained
    }

    func allowsNetwork(isOnline: Bool, isUnmetered: Bool) -> Bool {
        guard isOnline else { return false }
        switch downloadNetwork {
        case .any:
            return true
        case .wifiOnly:
            return isUnmetered
        }
    }

    func shouldRefreshSnapshot(
        trigger: osrsSavedPageUpdateTrigger,
        isOnline: Bool,
        isUnmetered: Bool
    ) -> Bool {
        switch trigger {
        case .manual:
            return allowsNetwork(isOnline: isOnline, isUnmetered: isUnmetered)
        case .access:
            guard updatePolicy != .manual else { return false }
            return allowsNetwork(isOnline: isOnline, isUnmetered: isUnmetered)
        case .automaticScan:
            guard updatePolicy == .automatic else { return false }
            return allowsNetwork(isOnline: isOnline, isUnmetered: isUnmetered)
        }
    }
}

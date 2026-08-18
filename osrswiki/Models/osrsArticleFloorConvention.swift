import Foundation

enum osrsArticleFloorNumberingMode: String, CaseIterable, Identifiable {
    case auto
    case gb
    case us

    static let persistenceKey = "osrs_floor_numbering"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto detect"
        case .gb: return "UK"
        case .us: return "US"
        }
    }

    var summary: String {
        switch self {
        case .auto: return "Match this device’s locale"
        case .gb: return "UK (ground floor is the entrance)"
        case .us: return "US (1st floor is the entrance)"
        }
    }

    func convention(locale: Locale = .current) -> osrsArticleFloorConvention {
        switch self {
        case .auto: return osrsArticleFloorConvention.from(locale: locale)
        case .gb: return .gb
        case .us: return .us
        }
    }

    static func fromPersisted(_ value: String?) -> osrsArticleFloorNumberingMode {
        osrsArticleFloorNumberingMode(rawValue: value ?? "") ?? .auto
    }

    static func resolved(userDefaults: UserDefaults = .standard) -> osrsArticleFloorNumberingMode {
        fromPersisted(userDefaults.string(forKey: persistenceKey))
    }
}

/// Wiki floor-number markup always contains both GB and US variants. Choose the
/// dialect from the device locale or an explicit Appearance override: regions
/// that number the entrance level as the 1st floor use the US labels; everyone
/// else uses the wiki's UK default.
enum osrsArticleFloorConvention: String {
    case gb
    case us

    var bodyClass: String {
        switch self {
        case .gb: return "floornumber-setting-gb"
        case .us: return "floornumber-setting-us"
        }
    }

    var hiddenDialectSelector: String {
        switch self {
        case .gb: return ".floornumber-us, .floornumber-help"
        case .us: return ".floornumber-gb, .floornumber-help"
        }
    }

    var hiddenDialectClass: String {
        switch self {
        case .gb: return "floornumber-us"
        case .us: return "floornumber-gb"
        }
    }

    private static let usEntranceIsFirstFloor: Set<String> = [
        "US", "AS", "GU", "MP", "PR", "VI", "UM",
        "CA", "MX", "BR",
        "JP", "KR", "CN", "TW", "PH", "RU"
    ]

    static func from(locale: Locale = .current) -> osrsArticleFloorConvention {
        let region = locale.region?.identifier.uppercased()
            ?? locale.regionCode?.uppercased()
            ?? ""
        return usEntranceIsFirstFloor.contains(region) ? .us : .gb
    }

    static func current(
        mode: osrsArticleFloorNumberingMode = .resolved(),
        locale: Locale = .current
    ) -> osrsArticleFloorConvention {
        mode.convention(locale: locale)
    }
}

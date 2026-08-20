import Foundation

struct osrsCalculatorCatalogEntry: Equatable {
    let title: String
    let pageid: Int?
    let url: String
}

struct osrsCalculatorCatalogSnapshot {
    let fetchedAt: String?
    let calculators: [osrsCalculatorCatalogEntry]
    let excludedCount: Int
}

enum osrsCalculatorCatalog {
    static let assetPath = "manifests/osrs-wiki-calculators.json"
    static let liveAPI = URL(string: "https://oldschool.runescape.wiki/api.php?action=query&list=allpages&apnamespace=116&aplimit=500&format=json")!

    static func loadSnapshot(json: Data) throws -> osrsCalculatorCatalogSnapshot {
        let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]
        let rawItems = root["calculators"] as? [[String: Any]] ?? []
        let calculators = rawItems.compactMap { item -> osrsCalculatorCatalogEntry? in
            guard let title = item["title"] as? String,
                  osrsWikiWebViewUrl.isUserFacingCalculator(title) else {
                return nil
            }
            return osrsCalculatorCatalogEntry(
                title: title,
                pageid: item["pageid"] as? Int,
                url: item["url"] as? String ?? ""
            )
        }
        return osrsCalculatorCatalogSnapshot(
            fetchedAt: root["fetched_at"] as? String,
            calculators: calculators,
            excludedCount: root["excluded_count"] as? Int ?? 0
        )
    }

    static func loadBundled() throws -> osrsCalculatorCatalogSnapshot {
        let url = Bundle.main.url(forResource: "osrs-wiki-calculators", withExtension: "json")
            ?? Bundle.main.url(forResource: "osrs-wiki-calculators", withExtension: "json", subdirectory: "Assets/manifests")
            ?? Bundle.main.url(forResource: "osrs-wiki-calculators", withExtension: "json", subdirectory: "manifests")
        guard let url else {
            throw NSError(domain: "osrsCalculatorCatalog", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bundled calculator catalog missing"])
        }
        return try loadSnapshot(json: Data(contentsOf: url))
    }

    static func mergeLivePages(snapshot: osrsCalculatorCatalogSnapshot, livePages: [[String: Any]]) -> [osrsCalculatorCatalogEntry] {
        var byTitle: [String: osrsCalculatorCatalogEntry] = [:]
        snapshot.calculators.forEach { byTitle[$0.title] = $0 }
        for page in livePages {
            guard let title = page["title"] as? String,
                  osrsWikiWebViewUrl.isUserFacingCalculator(title) else {
                continue
            }
            byTitle[title] = osrsCalculatorCatalogEntry(
                title: title,
                pageid: page["pageid"] as? Int,
                url: "https://oldschool.runescape.wiki/w/" + title.replacingOccurrences(of: " ", with: "_")
            )
        }
        return byTitle.values.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }
}

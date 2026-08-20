import Foundation

enum osrsLiveArticleAssetPlan {
    static let firstScreenLimit = 24

    struct Partition: Equatable, Sendable {
        let high: [URL]
        let low: [URL]
    }

    static func partition(
        required: [URL],
        infobox: [URL] = [],
        firstScreenLimit: Int = Self.firstScreenLimit
    ) -> Partition {
        var seenRequired: Set<URL> = []
        let uniqueRequired = required.filter { seenRequired.insert($0).inserted }
        let requiredSet = Set(uniqueRequired)
        var high: [URL] = []
        var highSet: Set<URL> = []
        for url in infobox where requiredSet.contains(url) && highSet.insert(url).inserted {
            high.append(url)
        }
        for url in uniqueRequired.prefix(max(firstScreenLimit, 0)) where highSet.insert(url).inserted {
            high.append(url)
        }
        let low = uniqueRequired.filter { !highSet.contains($0) }
        return Partition(high: high, low: low)
    }
}

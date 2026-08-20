import Foundation

enum osrsLiveArticleAssetPlan {
    static let firstViewCap = 48

    struct Partition: Equatable, Sendable {
        let high: [URL]
        let low: [URL]
    }

    static func partition(
        required: [URL],
        firstView: [URL] = [],
        firstViewCap: Int = Self.firstViewCap
    ) -> Partition {
        var seenRequired: Set<URL> = []
        let uniqueRequired = required.filter { seenRequired.insert($0).inserted }
        let requiredSet = Set(uniqueRequired)
        var high: [URL] = []
        var highSet: Set<URL> = []
        let cap = max(firstViewCap, 0)
        var seenFirstView: Set<URL> = []
        for url in firstView where seenFirstView.insert(url).inserted {
            if high.count >= cap {
                break
            }
            guard requiredSet.contains(url), highSet.insert(url).inserted else {
                continue
            }
            high.append(url)
        }
        let low = uniqueRequired.filter { !highSet.contains($0) }
        return Partition(high: high, low: low)
    }
}

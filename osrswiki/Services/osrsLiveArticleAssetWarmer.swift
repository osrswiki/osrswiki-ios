import Foundation

final class osrsLiveArticleAssetWarmer: @unchecked Sendable {
    let queue = osrsLiveArticleAssetQueue()
    private let isCached: (URL) async -> Bool
    private let fetch: (URL) async -> Void
    private let highConcurrency: Int
    private let lowConcurrency: Int
    private let pageId: String

    init(
        pageId: String,
        isCached: @escaping (URL) async -> Bool,
        fetch: @escaping (URL) async -> Void,
        highConcurrency: Int = 4,
        lowConcurrency: Int = 2
    ) {
        self.pageId = pageId
        self.isCached = isCached
        self.fetch = fetch
        self.highConcurrency = max(highConcurrency, 0)
        self.lowConcurrency = max(lowConcurrency, 0)
    }

    func promote(_ urls: [URL]) {
        queue.promote(urls)
    }

    func cancel() {
        queue.cancel()
    }

    func warm(html: String) async {
        guard !html.isEmpty else { return }
        let required = osrsOfflineArticleResourceSettlement.requiredImageURLsInDocumentOrder(from: html)
        let infobox = osrsOfflineArticleResourceSettlement.infoboxImageURLs(from: html)
        let plan = osrsLiveArticleAssetPlan.partition(required: required, infobox: infobox)
        queue.load(high: plan.high, low: plan.low)
        NSLog(
            "osrsLiveAssetWarm: start page=%@ required=%d high=%d low=%d",
            pageId,
            required.count,
            plan.high.count,
            plan.low.count
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<highConcurrency {
                group.addTask { await self.drain(preferHigh: true) }
            }
            for _ in 0..<lowConcurrency {
                group.addTask { await self.drain(preferHigh: false) }
            }
        }
        NSLog("osrsLiveAssetWarm: done page=%@", pageId)
    }

    private func drain(preferHigh: Bool) async {
        while !Task.isCancelled {
            let url: URL?
            if preferHigh {
                url = queue.takeHigh() ?? queue.takeLow()
            } else {
                url = queue.takeLow()
            }
            guard let url else {
                if queue.isIdle {
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            defer { queue.complete(url) }
            if await isCached(url) {
                continue
            }
            guard !Task.isCancelled else { return }
            await fetch(url)
        }
    }
}

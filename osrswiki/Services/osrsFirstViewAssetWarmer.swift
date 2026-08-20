import Foundation

final class osrsFirstViewAssetWarmer: @unchecked Sendable {
    let queue = osrsLiveArticleAssetQueue()
    private let isCached: (URL) async -> Bool
    private let fetch: (URL) async -> Void
    private let concurrency: Int
    private let pageId: String

    init(
        pageId: String,
        isCached: @escaping (URL) async -> Bool,
        fetch: @escaping (URL) async -> Void,
        concurrency: Int = 4
    ) {
        self.pageId = pageId
        self.isCached = isCached
        self.fetch = fetch
        self.concurrency = max(concurrency, 0)
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
        let firstView = osrsOfflineArticleResourceSettlement.firstViewSlotURLs(from: html)
        let plan = osrsLiveArticleAssetPlan.partition(required: required, firstView: firstView)
        queue.load(high: plan.high, low: [])
        NSLog("osrsFirstViewWarm: start page=%@ count=%d", pageId, plan.high.count)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                group.addTask { await self.drain() }
            }
        }
        NSLog("osrsFirstViewWarm: done page=%@ count=%d", pageId, plan.high.count)
    }

    private func drain() async {
        while !Task.isCancelled {
            let url = queue.takeHigh()
            if url == nil {
                if queue.isIdle {
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            guard let url else { continue }
            if await isCached(url) {
                queue.complete(url)
                continue
            }
            await fetch(url)
            queue.complete(url)
        }
    }
}

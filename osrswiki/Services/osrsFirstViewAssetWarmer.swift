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
        let firstView = osrsOfflineArticleResourceSettlement.firstViewSlotURLs(
            from: html,
            eagerOnly: osrsLoadPerformancePrefs.lazyOffscreenArticleImages
        )
        let high: [URL]
        if osrsLoadPerformancePrefs.narrowFirstViewportPaintedSet {
            // Slice 1: slot extract only. Do not walk the full document URL list
            // on the early path; remainder warm still does that after reveal.
            high = Array(firstView.prefix(osrsLiveArticleAssetPlan.firstViewCap))
        } else {
            let required = osrsOfflineArticleResourceSettlement.requiredImageURLsInDocumentOrder(from: html)
            high = osrsLiveArticleAssetPlan.partition(required: required, firstView: firstView).high
        }
        queue.load(high: high, low: [])
        NSLog(
            "osrsFirstViewWarm: start page=%@ count=%d eagerOnly=%d",
            pageId,
            high.count,
            osrsLoadPerformancePrefs.lazyOffscreenArticleImages ? 1 : 0
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                group.addTask { await self.drain() }
            }
        }
        NSLog("osrsFirstViewWarm: done page=%@ count=%d", pageId, high.count)
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

import Foundation

final class osrsFirstViewPrewarmStore: @unchecked Sendable {
    static let shared = osrsFirstViewPrewarmStore()

    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]
    private var warmers: [String: osrsFirstViewAssetWarmer] = [:]
    private var pinned: Set<String> = []

    func start(identity: String, pageURL: URL, html: String) {
        if ProcessInfo.processInfo.arguments.contains("-osrsDisableFirstViewPrewarm") {
            return
        }
        lock.lock()
        if warmers[identity] != nil {
            lock.unlock()
            return
        }
        let pageId = ArticleViewModel.generatePageIdFromURL(pageURL)
        let warmer = osrsFirstViewAssetWarmer(
            pageId: pageId,
            isCached: { url in
                await ProxyInterceptorService.shared.hasPersistedResponseAsync(pageId: pageId, url: url)
            },
            fetch: { url in
                await Self.fetchAndPersist(pageId: pageId, url: url)
            }
        )
        warmers[identity] = warmer
        let task = Task.detached(priority: .utility) {
            await warmer.warm(html: html)
        }
        tasks[identity] = task
        lock.unlock()
    }

    func promote(identity: String, urls: [URL]) {
        lock.lock()
        let warmer = warmers[identity]
        lock.unlock()
        warmer?.promote(urls)
    }

    func pin(identity: String) {
        lock.lock()
        pinned.insert(identity)
        lock.unlock()
    }

    func cancel(identity: String, force: Bool = false) {
        lock.lock()
        if !force && pinned.contains(identity) {
            lock.unlock()
            return
        }
        let task = tasks.removeValue(forKey: identity)
        let warmer = warmers.removeValue(forKey: identity)
        if force {
            pinned.remove(identity)
        }
        lock.unlock()
        task?.cancel()
        warmer?.cancel()
    }

    private static func fetchAndPersist(pageId: String, url: URL) async {
        do {
            let (data, response) = try await NetworkManager.shared.performDataRequest(
                url: url,
                retryCount: 0,
                bypassCache: false,
                routingPolicy: .configured
            )
            _ = await ProxyInterceptorService.shared.persistSpeculativeBrowsingResponse(
                pageId: pageId,
                url: url,
                data: data,
                response: response
            )
        } catch {
            return
        }
    }
}

import Foundation

final class osrsLiveArticleAssetQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var high: [URL] = []
    private var low: [URL] = []
    private var queued: Set<URL> = []
    private var inFlight: Set<URL> = []
    private var done: Set<URL> = []
    private let isCached: (URL) -> Bool

    init(isCached: @escaping (URL) -> Bool = { _ in false }) {
        self.isCached = isCached
    }

    func load(high highUrls: [URL], low lowUrls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        high = []
        low = []
        queued = []
        inFlight = []
        done = []
        highUrls.forEach { enqueue(toHigh: true, $0, front: false) }
        lowUrls.forEach { enqueue(toHigh: false, $0, front: false) }
    }

    func promote(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        for url in urls {
            if done.contains(url) || inFlight.contains(url) {
                continue
            }
            if let index = low.firstIndex(of: url) {
                low.remove(at: index)
                queued.remove(url)
                enqueue(toHigh: true, url, front: true)
                continue
            }
            if let index = high.firstIndex(of: url) {
                high.remove(at: index)
                queued.remove(url)
                enqueue(toHigh: true, url, front: true)
            }
        }
    }

    func takeHigh() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return take(fromHigh: true)
    }

    func takeLow() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return take(fromHigh: false)
    }

    func complete(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        inFlight.remove(url)
        done.insert(url)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        high = []
        low = []
        queued = []
        inFlight = []
    }

    var isIdle: Bool {
        lock.lock()
        defer { lock.unlock() }
        return high.isEmpty && low.isEmpty && inFlight.isEmpty
    }

    private func enqueue(toHigh: Bool, _ url: URL, front: Bool) {
        if queued.contains(url) || done.contains(url) || inFlight.contains(url) {
            return
        }
        queued.insert(url)
        if toHigh {
            if front {
                high.insert(url, at: 0)
            } else {
                high.append(url)
            }
        } else if front {
            low.insert(url, at: 0)
        } else {
            low.append(url)
        }
    }

    private func take(fromHigh: Bool) -> URL? {
        if fromHigh {
            while !high.isEmpty {
                let url = high.removeFirst()
                queued.remove(url)
                if let taken = accept(url) {
                    return taken
                }
            }
            return nil
        }
        while !low.isEmpty {
            let url = low.removeFirst()
            queued.remove(url)
            if let taken = accept(url) {
                return taken
            }
        }
        return nil
    }

    private func accept(_ url: URL) -> URL? {
        if done.contains(url) || inFlight.contains(url) {
            return nil
        }
        if isCached(url) {
            done.insert(url)
            return nil
        }
        inFlight.insert(url)
        return url
    }
}

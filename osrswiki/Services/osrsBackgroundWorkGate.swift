import Foundation

/// Yields post-load prefetch/preload while the user is actively interacting.
/// Save still completes once idle; first-view warming stays on the high path.
final class osrsBackgroundWorkGate: @unchecked Sendable {
    static let shared = osrsBackgroundWorkGate()

    private let lock = NSLock()
    private var pausedUntil: TimeInterval = 0

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince1970 < pausedUntil
    }

    func noteUserInteraction(holdFor seconds: TimeInterval = 0.75) {
        lock.lock()
        pausedUntil = max(pausedUntil, Date().timeIntervalSince1970 + seconds)
        lock.unlock()
    }

    func waitWhilePaused() async {
        while isPaused {
            if Task.isCancelled {
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }
}

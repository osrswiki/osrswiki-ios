import Foundation
import QuartzCore
import UIKit

/// Records main-thread pan-frame intervals for interactive article swipe.
/// Enabled with `-osrsSwipeFPSProbe`. Simulator refresh is often 60 Hz;
/// the probe still distinguishes a stuttering swipe from a display-locked one.
enum osrsInteractiveSwipeFrameProbe {
    static let launchArgument = "-osrsSwipeFPSProbe"

    static var isSyntheticPanEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-osrsSwipeFPSSyntheticPan")
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static let accessibilityIdentifier = "swipe_fps_probe"
    private static let hostTag = 719_355
    private static let lock = NSLock()
    private static var intervals: [CFTimeInterval] = []
    private static var lastTimestamp: CFTimeInterval = 0
    private static var publishedToken = ""

    static func beginSequence() {
        guard isEnabled else { return }
        lock.lock()
        intervals.removeAll(keepingCapacity: true)
        lastTimestamp = 0
        publishedToken = summaryToken(samples: [])
        lock.unlock()
        publishHost()
    }

    static func recordPanFrame() {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        lock.lock()
        if lastTimestamp > 0 {
            intervals.append(now - lastTimestamp)
        }
        lastTimestamp = now
        publishedToken = summaryToken(samples: intervals)
        lock.unlock()
        publishHost()
    }

    static func finishSequence() {
        guard isEnabled else { return }
        lock.lock()
        let snapshot = intervals
        let token = summaryToken(samples: snapshot)
        publishedToken = token
        lock.unlock()
        NSLog("osrsInteractiveSwipeFrameProbe %@", token)
        publishHost()
    }

    static func accessibilityToken() -> String? {
        guard isEnabled else { return nil }
        lock.lock()
        let token = publishedToken
        lock.unlock()
        return token.isEmpty ? nil : token
    }

    static func summary(samples: [CFTimeInterval]) -> (
        count: Int,
        medianMs: Double,
        minHz: Double,
        medianHz: Double,
        displayHz: Int
    ) {
        let displayHz = max(UIScreen.main.maximumFramesPerSecond, 1)
        guard !samples.isEmpty else {
            return (0, 0, 0, 0, displayHz)
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let maxInterval = sorted.last ?? median
        let medianHz = median > 0 ? 1.0 / median : 0
        let minHz = maxInterval > 0 ? 1.0 / maxInterval : 0
        return (sorted.count, median * 1000, minHz, medianHz, displayHz)
    }

    /// Window-hosted AX probe so UITests can read FPS after the article pops.
    static func publishHost() {
        guard isEnabled, Thread.isMainThread else { return }
        let token = accessibilityToken() ?? ""
        guard let window = osrsInteractiveArticleSwipe.keyWindow() else { return }
        let label: UILabel
        if let existing = window.viewWithTag(hostTag) as? UILabel {
            label = existing
        } else {
            let created = UILabel(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
            created.tag = hostTag
            created.accessibilityIdentifier = accessibilityIdentifier
            created.isAccessibilityElement = true
            created.backgroundColor = .clear
            created.textColor = .clear
            created.font = .systemFont(ofSize: 1)
            window.addSubview(created)
            label = created
        }
        label.text = token
        label.accessibilityLabel = token
        label.accessibilityValue = token
    }

    private static func summaryToken(samples: [CFTimeInterval]) -> String {
        let stats = summary(samples: samples)
        return String(
            format: "swipe_fps_samples=%d;swipe_fps_median_ms=%.2f;swipe_fps_median_hz=%.1f;swipe_fps_min_hz=%.1f;swipe_fps_display_hz=%d",
            stats.count,
            stats.medianMs,
            stats.medianHz,
            stats.minHz,
            stats.displayHz
        )
    }
}

import UIKit

/// Same-second dump for Find / article-search / Name. Logging only. Do not
/// change compositor, WK, or layer.contents. Ships in Release so TF-class
/// overlays rewrite `osrs-scene-dump.txt` after overlay depth already ≥1.
@MainActor
enum osrsBlankViewFirstResponderDump {
    private static var lastReason: String = ""
    private static var lastStamp: TimeInterval = 0
    private static var periodicTimer: Timer?

    /// Release-safe harness trigger: `-osrsPeriodicSceneDump` rewrites the
    /// scene dump every 5 s so a drive that never presents keyboard/Find
    /// (never-opened-Find control) still produces a census.
    static func installPeriodicDumpIfRequested() {
        guard periodicTimer == nil,
              ProcessInfo.processInfo.arguments.contains("-osrsPeriodicSceneDump") else {
            return
        }
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                emit(reason: "periodic")
            }
        }
    }

    static func capture(reason: String) {
        emit(reason: reason + "+0")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            emit(reason: reason + "+80ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            emit(reason: reason + "+250ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            emit(reason: reason + "+2s")
        }
    }

    private static func emit(reason: String) {
        let now = Date().timeIntervalSince1970
        if reason == lastReason, now - lastStamp < 0.03 {
            return
        }
        lastReason = reason
        lastStamp = now

        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let targets = windows.filter { $0.isKeyWindow || $0 is osrsResumeCoverWindow }
        // keyboardDidShow/keyboardDidHide +0/+80/+250 stay JS-first and skip
        // CARender so the +2s rewrite can land btnCount before MARK copies
        // the file (and hide dumps stay cheap outside the harness).
        let fullCensus = reason.hasSuffix("+2s")
            || !(reason.contains("keyboardDidShow") || reason.contains("keyboardDidHide"))
        if targets.isEmpty, let first = windows.first {
            osrsSceneCompositor.dumpWindow(
                first,
                reason: reason,
                includeLayerCensus: fullCensus
            )
            return
        }
        for window in targets {
            osrsSceneCompositor.dumpWindow(
                window,
                reason: reason,
                includeLayerCensus: fullCensus
            )
        }
    }
}

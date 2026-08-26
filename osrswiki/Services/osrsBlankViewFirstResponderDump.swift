import UIKit

/// Same-second dump for Find / article-search / Name. Logging only. Do not
/// change compositor, WK, or layer.contents. Ships in Release so TF-class
/// overlays rewrite `osrs-scene-dump.txt` after overlay depth already ≥1.
@MainActor
enum osrsBlankViewFirstResponderDump {
    private static var lastReason: String = ""
    private static var lastStamp: TimeInterval = 0

    static func capture(reason: String) {
        emit(reason: reason + "+0")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            emit(reason: reason + "+80ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            emit(reason: reason + "+250ms")
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
        if targets.isEmpty, let first = windows.first {
            osrsSceneCompositor.dumpWindow(first, reason: reason)
            return
        }
        for window in targets {
            osrsSceneCompositor.dumpWindow(window, reason: reason)
        }
    }
}

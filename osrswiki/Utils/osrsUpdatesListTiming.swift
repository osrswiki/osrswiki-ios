import Foundation
import os.log

/// Tap clock for Home "View more" → first usable updates-list row.
/// Grep: LOAD-MINMAX first_updates_list_visible
enum osrsUpdatesListTiming {
    private static let log = Logger(subsystem: "osrswiki", category: "UpdatesList")
    private static var openAt: CFAbsoluteTime?
    private static var firstVisibleLogged = false

    static func markOpen(restart: Bool = true) {
        if !restart, openAt != nil { return }
        openAt = CFAbsoluteTimeGetCurrent()
        firstVisibleLogged = false
        log.info("LOAD-MINMAX updates_list_open")
    }

    static func markFirstVisible(rowCount: Int) {
        guard let openAt, !firstVisibleLogged else { return }
        firstVisibleLogged = true
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - openAt) * 1000)
        log.info("LOAD-MINMAX first_updates_list_visible elapsedMs=\(elapsedMs, privacy: .public) rowCount=\(rowCount, privacy: .public)")
    }
}

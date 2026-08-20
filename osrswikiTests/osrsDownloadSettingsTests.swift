import XCTest
@testable import osrswiki

final class osrsDownloadSettingsTests: XCTestCase {
    func testOnAccessRefreshesOverWifiAndSkipsManualOnly() {
        let settings = osrsDownloadSettings(
            updatePolicy: .onAccess,
            downloadNetwork: .wifiOnly
        )
        XCTAssertTrue(settings.shouldRefreshSnapshot(trigger: .access, isOnline: true, isUnmetered: true))
        XCTAssertFalse(settings.shouldRefreshSnapshot(trigger: .access, isOnline: true, isUnmetered: false))
        XCTAssertFalse(settings.shouldRefreshSnapshot(trigger: .automaticScan, isOnline: true, isUnmetered: true))
    }

    func testAutomaticAllowsBackgroundScanAndAccessRefresh() {
        let settings = osrsDownloadSettings(
            updatePolicy: .automatic,
            downloadNetwork: .any
        )
        XCTAssertTrue(settings.shouldRefreshSnapshot(trigger: .automaticScan, isOnline: true, isUnmetered: false))
        XCTAssertTrue(settings.shouldRefreshSnapshot(trigger: .access, isOnline: true, isUnmetered: false))
        XCTAssertFalse(settings.shouldRefreshSnapshot(trigger: .automaticScan, isOnline: false, isUnmetered: true))
    }

    func testManualOnlyRefreshesWhenTheUserAsks() {
        let settings = osrsDownloadSettings(
            updatePolicy: .manual,
            downloadNetwork: .wifiOnly
        )
        XCTAssertTrue(settings.shouldRefreshSnapshot(trigger: .manual, isOnline: true, isUnmetered: true))
        XCTAssertFalse(settings.shouldRefreshSnapshot(trigger: .access, isOnline: true, isUnmetered: true))
        XCTAssertFalse(settings.shouldRefreshSnapshot(trigger: .manual, isOnline: true, isUnmetered: false))
    }
}

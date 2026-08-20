import XCTest
@testable import osrswiki

final class osrsSavedPageRevisionProbeTests: XCTestCase {
    func testQueryURLAsksOnlyForRevisionIds() throws {
        let url = osrsSavedPageRevisionProbe.queryURL(forPageTitle: "Abyssal whip")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(items["action"], "query")
        XCTAssertEqual(items["prop"], "revisions")
        XCTAssertEqual(items["rvprop"], "ids")
        XCTAssertEqual(items["titles"], "Abyssal whip")
        XCTAssertNil(items["text"])
    }

    func testRemoteRevisionReadsMediawikiQueryPayload() throws {
        let json = """
        {"query":{"pages":[{"title":"Varrock","revisions":[{"revid":12345}]}]}}
        """.data(using: .utf8)!
        let remote = try XCTUnwrap(
            osrsSavedPageRevisionProbe.remoteRevision(in: json, requestedTitle: "Varrock")
        )
        XCTAssertEqual(remote.pageTitle, "Varrock")
        XCTAssertEqual(remote.revisionId, 12345)
    }

    func testSnapshotNeedsRefreshWhenLocalRevisionIsUnknownOrStale() {
        XCTAssertTrue(osrsSavedPageRevisionProbe.snapshotNeedsRefresh(localRevisionId: nil, remoteRevisionId: 10))
        XCTAssertTrue(osrsSavedPageRevisionProbe.snapshotNeedsRefresh(localRevisionId: 0, remoteRevisionId: 10))
        XCTAssertTrue(osrsSavedPageRevisionProbe.snapshotNeedsRefresh(localRevisionId: 9, remoteRevisionId: 10))
        XCTAssertFalse(osrsSavedPageRevisionProbe.snapshotNeedsRefresh(localRevisionId: 10, remoteRevisionId: 10))
    }
}

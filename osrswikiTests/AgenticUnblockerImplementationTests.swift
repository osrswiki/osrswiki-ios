//
//  AgenticUnblockerImplementationTests.swift
//  osrswikiTests
//
//  Durable simulator-only coverage for the June 16 iOS QA unblockers.
//

import XCTest
import SwiftUI
@testable import osrswiki

@MainActor
final class AgenticUnblockerImplementationTests: XCTestCase {
    override func tearDown() async throws {
        NetworkManager.shared.setForcedOfflineForTests(false)
        NetworkManager.shared.setNetworkConditionForTests(.none)
        NetworkManager.shared.configureProxyRouting(enabled: false)
        try await super.tearDown()
    }

    func testForcedOfflineMakesRawNetworkRequestsReturnNoConnection() async throws {
        NetworkManager.shared.setForcedOfflineForTests(true)

        XCTAssertFalse(NetworkManager.shared.isConnected)
        XCTAssertTrue(NetworkManager.shared.isForcedOfflineForTests)

        do {
            _ = try await NetworkManager.shared.performDataRequest(
                url: URL(string: "https://oldschool.runescape.wiki/api.php")!,
                retryCount: 0
            )
            XCTFail("Forced-offline raw requests should fail before touching the network")
        } catch let error as NetworkError {
            guard case .noConnection = error else {
                XCTFail("Expected noConnection, got \(error)")
                return
            }
        }
    }

    func testForcedOfflineMakesCodableNetworkRequestsReturnNoConnection() async throws {
        struct EmptyResponse: Codable {}

        NetworkManager.shared.setForcedOfflineForTests(true)

        do {
            _ = try await NetworkManager.shared.performRequest(
                url: URL(string: "https://oldschool.runescape.wiki/api.php")!,
                responseType: EmptyResponse.self,
                retryCount: 0
            )
            XCTFail("Forced-offline Codable requests should fail before touching the network")
        } catch let error as NetworkError {
            guard case .noConnection = error else {
                XCTFail("Expected noConnection, got \(error)")
                return
            }
        }
    }

    func testReachabilitySnapshotIsAdvisoryForARequestThatCanSucceed() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("osrs-advisory-reachability-\(UUID().uuidString).txt")
        try Data("reachable-despite-stale-monitor".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        NetworkManager.shared.isConnected = false

        let (data, _) = try await NetworkManager.shared.performDataRequest(
            url: fileURL,
            retryCount: 0
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "reachable-despite-stale-monitor")
    }

    func testDeadPassiveProxyFallsBackToDirectRequest() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("osrs-dead-proxy-fallback-\(UUID().uuidString).txt")
        try Data("direct-fallback-ok".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        NetworkManager.shared.configureProxyRouting(enabled: true, port: 1)

        let (data, _) = try await NetworkManager.shared.performDataRequest(
            url: fileURL,
            retryCount: 0
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "direct-fallback-ok")
    }

    func testDegradedNetworkConditionCanDelaySuccessfulRawRequest() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("osrs-network-condition-\(UUID().uuidString).txt")
        try Data("degraded-ok".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        NetworkManager.shared.setNetworkConditionForTests(.latency(seconds: 0.15))

        let start = Date()
        let (data, _) = try await NetworkManager.shared.performDataRequest(url: fileURL, retryCount: 0)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(String(data: data, encoding: .utf8), "degraded-ok")
        XCTAssertGreaterThanOrEqual(elapsed, 0.14)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testDegradedNetworkConditionCanInjectTimeoutConnectionLossAndCaptivePortal() async throws {
        struct EmptyResponse: Codable {}
        let url = URL(string: "https://oldschool.runescape.wiki/api.php")!

        NetworkManager.shared.setNetworkConditionForTests(.timeout(after: 0.01))
        do {
            _ = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 0)
            XCTFail("Timeout condition should fail before touching the network")
        } catch let error as NetworkError {
            guard case .timeout = error else {
                XCTFail("Expected timeout, got \(error)")
                return
            }
        }

        NetworkManager.shared.setNetworkConditionForTests(.connectionLost(after: 0.01))
        do {
            _ = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 0)
            XCTFail("Connection-lost condition should fail before touching the network")
        } catch let error as NetworkError {
            guard case .connectionLost = error else {
                XCTFail("Expected connectionLost, got \(error)")
                return
            }
        }

        NetworkManager.shared.setNetworkConditionForTests(.captivePortal(after: 0.01))
        do {
            _ = try await NetworkManager.shared.performRequest(url: url, responseType: EmptyResponse.self, retryCount: 0)
            XCTFail("Captive-portal condition should return non-JSON data and fail decoding")
        } catch let error as NetworkError {
            guard case .invalidData = error else {
                XCTFail("Expected invalidData, got \(error)")
                return
            }
        }
    }

    func testExportReadingListTextContainsSeededPageTitleAndURL() {
        let savedPage = SavedPage(
            id: "ui-test-varrock",
            title: "Varrock",
            description: "Seeded saved page for UI navigation testing",
            url: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            thumbnailUrl: nil,
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: true,
            offlineDownloadDate: Date(timeIntervalSince1970: 1_735_732_800),
            offlineStatus: .available,
            offlineFileSize: 2_048,
            offlineLocalPath: "ui-test-varrock-snapshot",
            durableSettlementVersion: SavedPage.currentDurableSettlementVersion
        )

        let exportText = SavedPagesViewModel.exportReadingListText(from: [savedPage])

        XCTAssertTrue(exportText.contains("Varrock"))
        XCTAssertTrue(exportText.contains("https://oldschool.runescape.wiki/w/Varrock"))
        XCTAssertTrue(exportText.contains("Seeded saved page for UI navigation testing"))
    }

    func testSharePageTextContainsTitleAndURLForSystemCopy() {
        let shareText = SavedPagesViewModel.sharePageText(
            title: "Varrock",
            url: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!
        )

        XCTAssertEqual(shareText, "Varrock\nhttps://oldschool.runescape.wiki/w/Varrock")
    }

    func testTabSelectionUpdatesImmediatelyForResponsiveNavigation() {
        let appState = AppState()
        appState.selectedTab = .news

        appState.setSelectedTab(.saved)

        XCTAssertEqual(
            appState.selectedTab,
            .saved,
            "Bottom tab selection should update synchronously so the visible screen changes within the local UI budget"
        )
    }

    func testArticleDynamicTypeScaleIncreasesForAccessibilityReading() {
        XCTAssertEqual(osrsArticleDynamicTypeScaling.scale(for: .large), 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(
            osrsArticleDynamicTypeScaling.scale(for: .accessibility5),
            1.5,
            "Article reading content should visibly scale at the largest accessibility content size"
        )
    }
}

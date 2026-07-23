//
//  IOS06TrustBoundaryTests.swift
//  osrswikiTests
//
//  Regression coverage for donation and feedback trust boundaries.
//

import XCTest
@testable import osrswiki

final class IOS06TrustBoundaryTests: XCTestCase {
    func testWikiDonationDestinationUsesCurrentPatreonPage() throws {
        let url = osrsDonationDestinations.wikiSupportURL

        XCTAssertEqual(url.absoluteString, "https://www.patreon.com/runescapewiki")
        XCTAssertNotEqual(url.host, "oldschool.runescape.wiki")
        XCTAssertFalse(url.path.contains("RuneScape:Donate"))
    }

    func testFeedbackPayloadOmitsDeviceBlockWhenSystemInfoIsExcluded() throws {
        let service = osrsFeedbackService(
            session: URLSession(configuration: .ephemeral),
            systemInfoProvider: {
                osrsFeedbackSystemInfo(
                    appVersion: "9.9.9",
                    buildNumber: "999",
                    systemVersion: "26.0",
                    deviceModel: "iPhone",
                    systemName: "iOS"
                )
            }
        )

        let request = try service.makeIssueRequest(
            title: "Search issue",
            description: "Search stopped responding.",
            label: "bug",
            includeSystemInfo: false
        )

        XCTAssertEqual(request.body, "Search stopped responding.")
        XCTAssertFalse(request.body.contains("Device Information"))
        XCTAssertFalse(request.body.contains("App Version"))
        XCTAssertFalse(request.body.contains("iOS Version"))
        XCTAssertFalse(request.body.contains("Device Name"))
    }

    func testFeedbackPayloadIncludesOnlyDisclosedSystemInfoWhenIncluded() throws {
        let service = osrsFeedbackService(
            session: URLSession(configuration: .ephemeral),
            systemInfoProvider: {
                osrsFeedbackSystemInfo(
                    appVersion: "9.9.9",
                    buildNumber: "999",
                    systemVersion: "26.0",
                    deviceModel: "iPhone",
                    systemName: "iOS"
                )
            }
        )

        let request = try service.makeIssueRequest(
            title: "Map issue",
            description: "The map floor selector is stuck.",
            label: "bug",
            includeSystemInfo: true
        )

        XCTAssertTrue(request.body.contains("The map floor selector is stuck."))
        XCTAssertTrue(request.body.contains("Device Information"))
        XCTAssertTrue(request.body.contains("App Version: 9.9.9 (999)"))
        XCTAssertTrue(request.body.contains("iOS Version: 26.0"))
        XCTAssertTrue(request.body.contains("Device: iPhone"))
        XCTAssertTrue(request.body.contains("System Name: iOS"))
        XCTAssertFalse(request.body.contains("Device Name"))
    }

    @MainActor
    func testDonationManagerDoesNotStartPaymentWhenProviderIsUnavailable() {
        let gateway = osrsFakeDonationGateway(
            availability: .unavailable("Donations are unavailable in this build.")
        )
        let manager = DonationManager(paymentGateway: gateway)

        manager.loadProducts()
        XCTAssertEqual(
            manager.donationState,
            .productsUnavailable("Donations are unavailable in this build.")
        )

        let completionExpectation = expectation(description: "Donation completion")
        manager.processDonation(amount: 5) { success in
            XCTAssertFalse(success)
            completionExpectation.fulfill()
        }
        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(gateway.startedAmounts, [])
        XCTAssertEqual(
            manager.donationState,
            .productsUnavailable("Donations are unavailable in this build.")
        )
    }
}

private final class osrsFakeDonationGateway: osrsDonationPaymentGateway {
    let availability: osrsDonationPaymentAvailability
    private(set) var startedAmounts: [Decimal] = []

    init(availability: osrsDonationPaymentAvailability) {
        self.availability = availability
    }

    func startDonation(
        amount: Decimal,
        completion: @escaping (osrsDonationPurchaseResult) -> Void
    ) {
        startedAmounts.append(amount)
        completion(.success)
    }
}

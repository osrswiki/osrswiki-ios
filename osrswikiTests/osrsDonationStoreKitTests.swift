//
//  osrsDonationStoreKitTests.swift
//  osrswikiTests
//
//  StoreKit 2 donation gateway: product IDs, manager, cancel/pending/error,
//  custom-amount handoff, and local StoreKit Configuration.
//
//  Device sandbox (not this XCTest): Settings > App Store > Sandbox Account
//  as contact.omiyawaki@gmail.com, then More > Donate on a store build.
//

import XCTest
#if canImport(StoreKitTest)
import StoreKitTest
#endif
@testable import osrswiki

@MainActor
final class osrsDonationStoreKitTests: XCTestCase {
    func testDonationProductIdsMatchPlayBillingSkus() {
        XCTAssertEqual(osrsDonationProductIds.donate1, "donate_1_usd")
        XCTAssertEqual(osrsDonationProductIds.donate5, "donate_5_usd")
        XCTAssertEqual(osrsDonationProductIds.donate10, "donate_10_usd")
        XCTAssertEqual(osrsDonationProductIds.donate25, "donate_25_usd")
        XCTAssertEqual(
            osrsDonationProductIds.all,
            ["donate_1_usd", "donate_5_usd", "donate_10_usd", "donate_25_usd"]
        )
        XCTAssertEqual(DonationAmount.one.productId, "donate_1_usd")
        XCTAssertNil(DonationAmount.custom.productId)
        XCTAssertNil(DonationAmount.fromPresetValue(7))
    }

    func testDefaultGatewayFactorySelectsStoreKit() {
        let gateway = osrsDonationGatewayFactory.makeDefault(arguments: [])
        XCTAssertTrue(gateway is osrsStoreKitDonationGateway)
        XCTAssertFalse(gateway is osrsUnavailableDonationGateway)
    }

    func testLaunchArgumentsSelectUnavailableAndFakeGateways() {
        XCTAssertTrue(
            osrsDonationGatewayFactory.makeDefault(
                arguments: [osrsDonationGatewayLaunchArgument.unavailable]
            ) is osrsUnavailableDonationGateway
        )
        XCTAssertTrue(
            osrsDonationGatewayFactory.makeDefault(
                arguments: [osrsDonationGatewayLaunchArgument.fake]
            ) is osrsFakeDonationGateway
        )
    }

    func testManagerLoadsStoreDisplayPricesFromGateway() async {
        let gateway = osrsFakeDonationGateway.previewLoaded()
        let manager = DonationManager(paymentGateway: gateway)

        await manager.loadProductsAsync()

        XCTAssertEqual(manager.displayPrice(for: .one), "$0.99")
        XCTAssertEqual(manager.displayPrice(for: .five), "$4.99")
        XCTAssertEqual(manager.displayPrice(for: .ten), "$9.99")
        XCTAssertEqual(manager.displayPrice(for: .twentyFive), "$24.99")
        XCTAssertTrue(manager.canStartDonation)
        XCTAssertNil(manager.donationUnavailableMessage)
        XCTAssertEqual(Set(manager.products.map(\.id)), Set(osrsDonationProductIds.all))
    }

    func testManagerFallsBackToPresetLabelsWhenPricesMissing() async {
        let gateway = osrsFakeDonationGateway(
            products: [
                osrsDonationProduct(id: osrsDonationProductIds.donate5, displayName: "Five", amount: 5, displayPrice: "")
            ]
        )
        let manager = DonationManager(paymentGateway: gateway)
        await manager.loadProductsAsync()

        XCTAssertEqual(manager.displayPrice(for: .one), "$1")
        XCTAssertEqual(manager.displayPrice(for: .five), "$5")
    }

    func testManagerPurchasesRealProductIdNotSyntheticApplePayId() async {
        let gateway = osrsFakeDonationGateway.previewLoaded()
        let manager = DonationManager(paymentGateway: gateway)
        await manager.loadProductsAsync()

        let completion = expectation(description: "purchase")
        manager.processDonation(amount: 5) { success in
            XCTAssertTrue(success)
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(gateway.purchasedProductIds, [osrsDonationProductIds.donate5])
        XCTAssertEqual(manager.donationState, .succeeded)
        XCTAssertFalse(gateway.purchasedProductIds.contains { $0.hasPrefix("apple-pay-donation") })
    }

    func testCustomAmountDoesNotStartStoreKitPurchase() async {
        let gateway = osrsFakeDonationGateway.previewLoaded()
        let manager = DonationManager(paymentGateway: gateway)
        await manager.loadProductsAsync()

        let completion = expectation(description: "custom")
        manager.processDonation(amount: .custom) { success in
            XCTAssertFalse(success)
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(gateway.purchasedProductIds, [])
        XCTAssertEqual(
            manager.donationState,
            .failed(DonationManager.customAmountUnsupportedMessage)
        )
    }

    func testPurchaseCancelPendingAndError() async {
        let gateway = osrsFakeDonationGateway.previewLoaded()
        gateway.purchaseResult = .cancelled
        let manager = DonationManager(paymentGateway: gateway)
        await manager.loadProductsAsync()

        let cancelled = expectation(description: "cancelled")
        manager.processDonation(productId: osrsDonationProductIds.donate1) { success in
            XCTAssertFalse(success)
            cancelled.fulfill()
        }
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(manager.donationState, .cancelled)

        gateway.purchaseResult = .pending
        let pending = expectation(description: "pending")
        manager.processDonation(productId: osrsDonationProductIds.donate1) { success in
            XCTAssertFalse(success)
            pending.fulfill()
        }
        await fulfillment(of: [pending], timeout: 1)
        XCTAssertEqual(manager.donationState, .pending)

        gateway.purchaseResult = .failed("store declined")
        let failed = expectation(description: "failed")
        manager.processDonation(productId: osrsDonationProductIds.donate1) { success in
            XCTAssertFalse(success)
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(manager.donationState, .failed("store declined"))
    }

    func testEmptyProductLoadKeepsDonateDisabled() async {
        let gateway = osrsFakeDonationGateway(products: [])
        let manager = DonationManager(paymentGateway: gateway)
        await manager.loadProductsAsync()

        XCTAssertFalse(manager.canStartDonation)
        XCTAssertEqual(
            manager.donationState,
            .productsUnavailable("No donation products are currently available.")
        )
        XCTAssertEqual(manager.displayPrice(for: .ten), "$10")
    }

#if canImport(StoreKitTest)
    func testStoreKitConfigurationLoadsFourConsumables() async throws {
        let url = try storeKitConfigurationURL()
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        addTeardownBlock {
            session.clearTransactions()
        }

        let gateway = osrsStoreKitDonationGateway()
        let result = await gateway.loadDonationProducts()
        guard case .loaded(let products) = result else {
            throw XCTSkip("StoreKit Configuration did not load products in this environment: \(result)")
        }

        XCTAssertEqual(Set(products.map(\.id)), Set(osrsDonationProductIds.all))
        XCTAssertTrue(products.allSatisfy { !$0.displayPrice.isEmpty })

        let purchase = await gateway.purchaseDonation(productId: osrsDonationProductIds.donate1)
        XCTAssertTrue(
            purchase == .success || purchase == .pending,
            "Local StoreKit purchase should succeed or pend, got \(purchase)"
        )
    }

    private func storeKitConfigurationURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            let candidate = url.appendingPathComponent("platforms/ios/osrswiki/StoreKit/osrsDonations.storekit")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("osrsDonations.storekit not found from \(#filePath)")
    }
#endif
}

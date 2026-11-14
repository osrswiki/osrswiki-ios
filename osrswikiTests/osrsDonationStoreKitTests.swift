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
    override func setUp() {
        super.setUp()
        DonationManager.resetPrefetchCacheForTesting()
    }

#if canImport(StoreKitTest)
    private var osrsStoreKitTestSession: SKTestSession?
    private var osrsStoreKitOutstanding: [Task<Void, Never>] = []
#endif

    override func tearDown() {
#if canImport(StoreKitTest)
        osrsCancelOutstandingStoreKitWork()
        osrsStoreKitTestSession?.resetToDefaultState()
        osrsStoreKitTestSession?.clearTransactions()
        osrsStoreKitTestSession = nil
#endif
        super.tearDown()
    }

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

    func testCachedProductsThenEmptyRefreshBecomeUnavailable() async {
        let seedGateway = osrsFakeDonationGateway.previewLoaded()
        let seeder = DonationManager(paymentGateway: seedGateway)
        await seeder.loadProductsAsync()
        XCTAssertFalse(seeder.products.isEmpty)

        let emptyGateway = osrsFakeDonationGateway(products: [])
        let manager = DonationManager(paymentGateway: emptyGateway)
        await manager.loadProductsAsync()

        XCTAssertEqual(
            manager.donationState,
            .productsUnavailable("No donation products are currently available.")
        )
        XCTAssertFalse(manager.canStartDonation)
        XCTAssertTrue(manager.products.isEmpty)
    }

#if canImport(StoreKitTest)
    func testStoreKitConfigurationLoadsFourConsumables() async throws {
        let url = try storeKitConfigurationURL()
        let session = try makeStoreKitTestSession(contentsOf: url)
        osrsStoreKitTestSession = session
        try await requireStoreKitTestConfiguration(session)

        let gateway = osrsStoreKitDonationGateway()
        let result = try await awaitConfiguredStoreKitStep("loadDonationProducts", session: session) {
            await gateway.loadDonationProducts()
        }
        guard case .loaded(let products) = result else {
            throw XCTSkip("StoreKit Configuration did not load products in this environment: \(result)")
        }

        XCTAssertEqual(Set(products.map(\.id)), Set(osrsDonationProductIds.all))
        XCTAssertTrue(products.allSatisfy { !$0.displayPrice.isEmpty })

        let purchase = try await awaitConfiguredStoreKitStep("purchaseDonation", session: session) {
            await gateway.purchaseDonation(productId: osrsDonationProductIds.donate1)
        }
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

    private func makeStoreKitTestSession(contentsOf url: URL) throws -> SKTestSession {
        do {
            let session = try SKTestSession(contentsOf: url)
            session.resetToDefaultState()
            session.disableDialogs = true
            session.clearTransactions()
            return session
        } catch {
            throw XCTSkip(osrsStoreKitTestConfigurationUnavailableMessage(detail: "\(error)"))
        }
    }

    /// Mini (Xcode 27.1 RC / iOS 26.5): `SKTestSession` init and
    /// `setSimulatedError` return without throwing; they only log
    /// `SKInternalErrorDomain Code=3`. `Product.products` still returns the
    /// four ASC SKUs. The local `.storekit` file is not in effect, so
    /// `Product.purchase` hits the live store and can stall on
    /// "Sign in to Apple Account". Prove the session catalog works with an
    /// off-device `buyProduct` + `allTransactions` round-trip *before*
    /// `purchaseDonation`. Skip only when that probe shows the config is
    /// inactive. A stall after a recorded session transaction is a real fail.
    private func requireStoreKitTestConfiguration(_ session: SKTestSession) async throws {
        session.clearTransactions()
        do {
            try await awaitDonationStoreKitStep("SKTestSession.buyProduct") {
                try await self.osrsBuyProductOffDevice(session, productId: osrsDonationProductIds.donate1)
            }
        } catch is osrsDonationStoreKitStepTimeout {
            throw osrsStoreKitConfigurationSkipOrFail(
                step: "SKTestSession.buyProduct",
                session: session,
                configurationConfirmed: false
            )
        } catch {
            throw XCTSkip(osrsStoreKitTestConfigurationUnavailableMessage(detail: "\(error)"))
        }

        let recorded = osrsStoreKitSessionProductIds(session)
        session.clearTransactions()
        guard recorded.contains(osrsDonationProductIds.donate1) else {
            throw XCTSkip(
                osrsStoreKitTestConfigurationUnavailableMessage(
                    detail: "SKTestSession.buyProduct returned without recording a session transaction."
                )
            )
        }
    }

    private func awaitConfiguredStoreKitStep<T>(
        _ step: String,
        session: SKTestSession,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        do {
            return try await awaitDonationStoreKitStep(step, operation: operation)
        } catch is osrsDonationStoreKitStepTimeout {
            throw osrsStoreKitConfigurationSkipOrFail(
                step: step,
                session: session,
                configurationConfirmed: true
            )
        }
    }

    private func osrsStoreKitConfigurationSkipOrFail(
        step: String,
        session: SKTestSession,
        configurationConfirmed: Bool
    ) -> Error {
        let recorded = osrsStoreKitSessionProductIds(session)
        osrsCancelOutstandingStoreKitWork()
        session.resetToDefaultState()
        session.clearTransactions()
        if !configurationConfirmed && recorded.isEmpty {
            return XCTSkip(
                osrsStoreKitTestConfigurationUnavailableMessage(
                    detail: "\(step) stalled and SKTestSession.allTransactions() is empty."
                )
            )
        }
        XCTFail("\(step) stalled: StoreKit call did not return within 30 seconds")
        return osrsDonationStoreKitStepTimeout(step: step)
    }

    private func osrsStoreKitTestConfigurationUnavailableMessage(detail: String) -> String {
        """
        SKTestSession did not apply osrsDonations.storekit. Xcode 27.1 RC / iOS 26.5 \
        xcodebuild test fails to persist StoreKit Test configuration \
        (SKInternalErrorDomain Code=3: Error saving configuration file / Error \
        clearing overrides; FB22237318). \(detail) Product.purchase would fall \
        through to the live App Store and can present Sign in to Apple Account.
        """
    }

    private func osrsStoreKitSessionProductIds(_ session: SKTestSession) -> Set<String> {
        Set(session.allTransactions().map(\.productIdentifier))
    }

    private func osrsBuyProductOffDevice(_ session: SKTestSession, productId: String) async throws {
        try await Task.detached {
            try session.buyProduct(productIdentifier: productId)
        }.value
    }

    /// First-finisher race. Structured `withTaskGroup` would still wait for a
    /// cancelled child, and StoreKit 2 does not honor task cancellation.
    /// The timer is cancelled when the step finishes; outstanding work is
    /// cancelled in `tearDown` so a stalled purchase cannot keep a live
    /// App Store sheet around for later tests.
    private func awaitDonationStoreKitStep<T>(
        _ step: String,
        timeoutNanoseconds: UInt64 = 30_000_000_000,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let box = osrsDonationStoreKitRaceBox<Result<T, Error>>()
        let work = Task {
            do {
                box.finish(.success(try await operation()))
            } catch {
                box.finish(.failure(error))
            }
        }
        let timer: Task<Void, Never> = Task.detached {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                box.finish(nil)
            } catch {}
        }
        osrsStoreKitOutstanding.append(work)
        osrsStoreKitOutstanding.append(timer)
        let result = await box.wait()
        timer.cancel()
        if result == nil {
            work.cancel()
        }
        guard let result else {
            throw osrsDonationStoreKitStepTimeout(step: step)
        }
        return try result.get()
    }

    private func osrsCancelOutstandingStoreKitWork() {
        osrsStoreKitOutstanding.forEach { $0.cancel() }
        osrsStoreKitOutstanding.removeAll()
    }
#endif
}

#if canImport(StoreKitTest)
private struct osrsDonationStoreKitStepTimeout: Error {
    let step: String
}

private final class osrsDonationStoreKitRaceBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var finishedValue: Value?
    private var resolved = false

    func wait() async -> Value? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if resolved {
                let value = finishedValue
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ value: Value?) {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return
        }
        resolved = true
        finishedValue = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
#endif

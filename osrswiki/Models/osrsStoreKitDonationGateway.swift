//
//  osrsStoreKitDonationGateway.swift
//  osrswiki
//
//  StoreKit 2 gateway for the four ASC consumable donation products.
//
//  Sandbox (physical device / TestFlight):
//  1. Settings > App Store > Sandbox Account, signed in as
//     contact.omiyawaki@gmail.com (or another Sandbox Apple ID on that account).
//  2. Install a build that talks to App Store Connect, not a scheme that
//     injects `-osrsDonationGatewayFake` / `-osrsDonationGatewayUnavailable`.
//  3. More > Donate, wait for store prices, buy a preset. Cancel, Ask to Buy
//     pending, and failures should return to Donate without crashing.
//  Simulator XCTest uses `osrsDonations.storekit` plus StoreKitTest. That does
//  not prove ASC sandbox. An unsigned Paid Apps Agreement blocks production
//  sales and can make Product.products return nothing on device; it does not
//  block this wiring.
//

import Foundation
import StoreKit

@MainActor
final class osrsStoreKitDonationGateway: osrsDonationPaymentGateway {
    private var storeProducts: [String: Product] = [:]
    private var transactionListener: Task<Void, Never>?

    var availability: osrsDonationPaymentAvailability {
        if AppStore.canMakePayments {
            return .available
        }
        return .unavailable("This Apple ID is not allowed to make payments on this device.")
    }

    init() {
        transactionListener = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.drainUnfinishedDonationTransactions()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadDonationProducts() async -> osrsDonationProductLoadResult {
        if let reason = availability.unavailableReason {
            return .unavailable(reason)
        }

        do {
            let products = try await Product.products(for: Set(osrsDonationProductIds.all))
            storeProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            let mapped = osrsDonationProductIds.all.compactMap { id -> osrsDonationProduct? in
                guard let product = storeProducts[id] else {
                    return nil
                }
                return osrsDonationProduct(
                    id: product.id,
                    displayName: product.displayName,
                    amount: osrsDonationProductIds.decimalValue(for: product.id) ?? 0,
                    displayPrice: product.displayPrice
                )
            }
            if mapped.isEmpty {
                return .unavailable(
                    "Donation products could not be loaded from the App Store. Try again later, or use Donate to Wiki."
                )
            }
            return .loaded(mapped)
        } catch {
            return .failed("Could not load donation products: \(error.localizedDescription)")
        }
    }

    func purchaseDonation(productId: String) async -> osrsDonationPurchaseResult {
        guard osrsDonationProductIds.amount(for: productId) != nil else {
            return .failed(DonationManager.customAmountUnsupportedMessage)
        }
        guard let product = storeProducts[productId] else {
            return .failed("That donation amount is not available right now.")
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                return await finishVerified(verification)
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Purchase returned an unexpected result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func finishVerified(
        _ verification: VerificationResult<Transaction>
    ) async -> osrsDonationPurchaseResult {
        switch verification {
        case .verified(let transaction):
            await transaction.finish()
            return .success
        case .unverified(_, let error):
            return .failed("Could not verify the purchase: \(error.localizedDescription)")
        }
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            await finishDonationTransaction(update)
        }
    }

    private func drainUnfinishedDonationTransactions() async {
        for await update in Transaction.unfinished {
            await finishDonationTransaction(update)
        }
    }

    private func finishDonationTransaction(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            return
        }
        guard osrsDonationProductIds.all.contains(transaction.productID) else {
            return
        }
        await transaction.finish()
    }
}

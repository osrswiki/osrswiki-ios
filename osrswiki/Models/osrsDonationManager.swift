//
//  osrsDonationManager.swift
//  osrswiki
//
//  Observable donation coordinator. Default gateway is StoreKit 2.
//

import Foundation

@MainActor
final class DonationManager: ObservableObject {
    static let defaultUnavailableMessage = "Donations are not available in this build because no payment provider is configured."
    static let customAmountUnsupportedMessage = "In-app donations are $1, $5, $10, or $25. For another amount, use Donate to Wiki."

    @Published private(set) var products: [osrsDonationProduct] = []
    @Published var donationState: osrsDonationState = .idle
    @Published var canMakePayments: Bool
    @Published var isApplePayAvailable: Bool

    private let paymentGateway: osrsDonationPaymentGateway

    /// Process-wide StoreKit product cache so Donate does not blank→populate
    /// on first open. Prefetch from More (or app warm); Donate hydrates from cache.
    private static var prefetchedProducts: [osrsDonationProduct] = []
    private static var prefetchTask: Task<Void, Never>?

    static func prefetchProductsIfNeeded() {
        guard prefetchTask == nil else { return }
        prefetchTask = Task { @MainActor in
            let manager = DonationManager()
            await manager.loadProductsAsync(forceNetwork: true)
            if !manager.products.isEmpty {
                prefetchedProducts = manager.products
            }
        }
    }

    init(paymentGateway: osrsDonationPaymentGateway? = nil) {
        let gateway = paymentGateway ?? osrsDonationGatewayFactory.makeDefault()
        self.paymentGateway = gateway
        self.canMakePayments = gateway.availability.isAvailable
        self.isApplePayAvailable = gateway.availability.isAvailable
        if let reason = gateway.availability.unavailableReason {
            donationState = .productsUnavailable(reason)
        }
    }

    var canStartDonation: Bool {
        guard paymentGateway.availability.isAvailable, !products.isEmpty else {
            return false
        }
        switch donationState {
        case .loadingProducts, .purchasing, .productsUnavailable:
            return false
        default:
            return true
        }
    }

    var donationUnavailableMessage: String? {
        if let reason = paymentGateway.availability.unavailableReason {
            return reason
        }
        if case .productsUnavailable(let reason) = donationState {
            return reason
        }
        if case .failed(let message) = donationState, products.isEmpty {
            return message
        }
        return nil
    }

    func displayPrice(for amount: DonationAmount) -> String {
        guard let productId = amount.productId,
              let product = products.first(where: { $0.id == productId }),
              !product.displayPrice.isEmpty else {
            return amount.displayValue
        }
        return product.displayPrice
    }

    func loadProducts() {
        Task {
            await loadProductsAsync()
        }
    }

    func loadProductsAsync(forceNetwork: Bool = false) async {
        canMakePayments = paymentGateway.availability.isAvailable
        isApplePayAvailable = paymentGateway.availability.isAvailable

        if !forceNetwork, products.isEmpty, !Self.prefetchedProducts.isEmpty {
            products = Self.prefetchedProducts
            donationState = .idle
            let result = await paymentGateway.loadDonationProducts()
            if case .loaded(let loaded) = result {
                products = loaded
                Self.prefetchedProducts = loaded
            }
            return
        }

        if let reason = paymentGateway.availability.unavailableReason {
            products = []
            donationState = osrsDonationStateReducer.reduceProductLoad(.unavailable(reason))
            return
        }

        donationState = osrsDonationStateReducer.loadingProducts()
        let result = await paymentGateway.loadDonationProducts()
        switch result {
        case .loaded(let loaded):
            products = loaded
            Self.prefetchedProducts = loaded
        case .unavailable, .failed:
            products = []
        }
        donationState = osrsDonationStateReducer.reduceProductLoad(result)
    }

    func processDonation(amount: DonationAmount, completion: @escaping (Bool) -> Void) {
        guard let productId = amount.productId else {
            donationState = osrsDonationStateReducer.reducePurchase(
                .failed(Self.customAmountUnsupportedMessage)
            )
            completion(false)
            return
        }
        processDonation(productId: productId, completion: completion)
    }

    func processDonation(amount: Double, completion: @escaping (Bool) -> Void) {
        guard let preset = DonationAmount.fromPresetValue(amount) else {
            donationState = osrsDonationStateReducer.reducePurchase(
                .failed(Self.customAmountUnsupportedMessage)
            )
            completion(false)
            return
        }
        processDonation(amount: preset, completion: completion)
    }

    func processDonation(productId: String, completion: @escaping (Bool) -> Void) {
        if let reason = paymentGateway.availability.unavailableReason {
            donationState = osrsDonationStateReducer.reduceProductLoad(.unavailable(reason))
            completion(false)
            return
        }

        guard canStartDonation else {
            donationState = osrsDonationStateReducer.reduceProductLoad(
                .unavailable("Donation products are not ready yet.")
            )
            completion(false)
            return
        }

        guard osrsDonationProductIds.amount(for: productId) != nil else {
            donationState = osrsDonationStateReducer.reducePurchase(
                .failed(Self.customAmountUnsupportedMessage)
            )
            completion(false)
            return
        }

        let product = products.first(where: { $0.id == productId }) ?? osrsDonationProduct(
            id: productId,
            displayName: osrsDonationProductIds.amount(for: productId)?.displayValue ?? productId,
            amount: osrsDonationProductIds.decimalValue(for: productId) ?? 0
        )
        donationState = osrsDonationStateReducer.beginPurchase(product: product)

        Task {
            let result = await paymentGateway.purchaseDonation(productId: productId)
            donationState = osrsDonationStateReducer.reducePurchase(result)
            completion(result == .success)
        }
    }
}

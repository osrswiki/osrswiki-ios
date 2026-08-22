//
//  osrsDonationPaymentGateway.swift
//  osrswiki
//
//  Payment seam for Donate. Production default is StoreKit 2. The unavailable
//  stub remains for tests and an explicit launch argument.
//

import Foundation

enum osrsDonationPaymentAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var unavailableReason: String? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}

@MainActor
protocol osrsDonationPaymentGateway: AnyObject {
    var availability: osrsDonationPaymentAvailability { get }
    func loadDonationProducts() async -> osrsDonationProductLoadResult
    func purchaseDonation(productId: String) async -> osrsDonationPurchaseResult
}

enum osrsDonationGatewayLaunchArgument {
    static let unavailable = "-osrsDonationGatewayUnavailable"
    static let fake = "-osrsDonationGatewayFake"
}

@MainActor
enum osrsDonationGatewayFactory {
    static func makeDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> osrsDonationPaymentGateway {
        if arguments.contains(osrsDonationGatewayLaunchArgument.unavailable) {
            return osrsUnavailableDonationGateway()
        }
        if arguments.contains(osrsDonationGatewayLaunchArgument.fake) {
            return osrsFakeDonationGateway.previewLoaded()
        }
        return osrsStoreKitDonationGateway()
    }
}

@MainActor
final class osrsUnavailableDonationGateway: osrsDonationPaymentGateway {
    let availability: osrsDonationPaymentAvailability

    init(reason: String = DonationManager.defaultUnavailableMessage) {
        self.availability = .unavailable(reason)
    }

    func loadDonationProducts() async -> osrsDonationProductLoadResult {
        .unavailable(availability.unavailableReason ?? DonationManager.defaultUnavailableMessage)
    }

    func purchaseDonation(productId: String) async -> osrsDonationPurchaseResult {
        _ = productId
        return .failed(availability.unavailableReason ?? DonationManager.defaultUnavailableMessage)
    }
}

@MainActor
final class osrsFakeDonationGateway: osrsDonationPaymentGateway {
    var availability: osrsDonationPaymentAvailability
    var products: [osrsDonationProduct]
    var purchaseResult: osrsDonationPurchaseResult
    private(set) var purchasedProductIds: [String] = []
    private(set) var loadCallCount = 0

    init(
        availability: osrsDonationPaymentAvailability = .available,
        products: [osrsDonationProduct] = osrsDonationProductIds.previewProducts,
        purchaseResult: osrsDonationPurchaseResult = .success
    ) {
        self.availability = availability
        self.products = products
        self.purchaseResult = purchaseResult
    }

    static func previewLoaded() -> osrsFakeDonationGateway {
        osrsFakeDonationGateway()
    }

    func loadDonationProducts() async -> osrsDonationProductLoadResult {
        loadCallCount += 1
        if let reason = availability.unavailableReason {
            return .unavailable(reason)
        }
        return .loaded(products)
    }

    func purchaseDonation(productId: String) async -> osrsDonationPurchaseResult {
        purchasedProductIds.append(productId)
        if osrsDonationProductIds.amount(for: productId) == nil {
            return .failed("Unknown donation product.")
        }
        return purchaseResult
    }
}

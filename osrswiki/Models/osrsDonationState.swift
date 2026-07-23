//
//  osrsDonationState.swift
//  osrswiki
//
//  Deterministic donation state model used by tests and UI diagnostics.
//

import Foundation

struct osrsDonationProduct: Equatable {
    let id: String
    let displayName: String
    let amount: Decimal
}

enum osrsDonationProductLoadResult: Equatable {
    case loaded([osrsDonationProduct])
    case unavailable(String)
    case failed(String)
}

enum osrsDonationPurchaseResult: Equatable {
    case cancelled
    case pending
    case success
    case failed(String)
}

enum osrsDonationState: Equatable {
    case idle
    case loadingProducts
    case productsAvailable([osrsDonationProduct])
    case productsUnavailable(String)
    case purchasing(osrsDonationProduct)
    case cancelled
    case pending
    case succeeded
    case failed(String)
}

struct osrsDonationStateReducer {
    static func loadingProducts() -> osrsDonationState {
        .loadingProducts
    }

    static func reduceProductLoad(_ result: osrsDonationProductLoadResult) -> osrsDonationState {
        switch result {
        case .loaded(let products) where !products.isEmpty:
            return .productsAvailable(products)
        case .loaded:
            return .productsUnavailable("No donation products are currently available.")
        case .unavailable(let reason):
            return .productsUnavailable(reason)
        case .failed(let message):
            return .failed(message)
        }
    }

    static func beginPurchase(product: osrsDonationProduct) -> osrsDonationState {
        .purchasing(product)
    }

    static func reducePurchase(_ result: osrsDonationPurchaseResult) -> osrsDonationState {
        switch result {
        case .cancelled:
            return .cancelled
        case .pending:
            return .pending
        case .success:
            return .succeeded
        case .failed(let message):
            return .failed(message)
        }
    }
}

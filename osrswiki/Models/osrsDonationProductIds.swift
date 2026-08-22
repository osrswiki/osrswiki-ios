//
//  osrsDonationProductIds.swift
//  osrswiki
//
//  App Store / Play Billing donation product IDs. Same strings on both
//  platforms. These are fixed-price consumables; there is no dynamic-price IAP.
//

import Foundation

enum osrsDonationProductIds {
    static let donate1 = "donate_1_usd"
    static let donate5 = "donate_5_usd"
    static let donate10 = "donate_10_usd"
    static let donate25 = "donate_25_usd"

    static let all: [String] = [donate1, donate5, donate10, donate25]

    static func productId(for amount: DonationAmount) -> String? {
        switch amount {
        case .one: return donate1
        case .five: return donate5
        case .ten: return donate10
        case .twentyFive: return donate25
        case .custom: return nil
        }
    }

    static func amount(for productId: String) -> DonationAmount? {
        switch productId {
        case donate1: return .one
        case donate5: return .five
        case donate10: return .ten
        case donate25: return .twentyFive
        default: return nil
        }
    }

    static func decimalValue(for productId: String) -> Decimal? {
        amount(for: productId)?.value
    }

    /// Preview / UITest stand-ins that match ASC list prices (~$0.99/$4.99/$9.99/$24.99).
    static var previewProducts: [osrsDonationProduct] {
        [
            osrsDonationProduct(id: donate1, displayName: "Donate $1", amount: 1, displayPrice: "$0.99"),
            osrsDonationProduct(id: donate5, displayName: "Donate $5", amount: 5, displayPrice: "$4.99"),
            osrsDonationProduct(id: donate10, displayName: "Donate $10", amount: 10, displayPrice: "$9.99"),
            osrsDonationProduct(id: donate25, displayName: "Donate $25", amount: 25, displayPrice: "$24.99")
        ]
    }
}

enum DonationAmount: CaseIterable, Hashable {
    case one, five, ten, twentyFive, custom

    static var presets: [DonationAmount] { [.one, .five, .ten, .twentyFive] }

    var displayValue: String {
        switch self {
        case .one: return "$1"
        case .five: return "$5"
        case .ten: return "$10"
        case .twentyFive: return "$25"
        case .custom: return "Custom"
        }
    }

    var value: Decimal {
        switch self {
        case .one: return 1
        case .five: return 5
        case .ten: return 10
        case .twentyFive: return 25
        case .custom: return 0
        }
    }

    var productId: String? {
        osrsDonationProductIds.productId(for: self)
    }

    static func fromPresetValue(_ amount: Double) -> DonationAmount? {
        switch amount {
        case 1: return .one
        case 5: return .five
        case 10: return .ten
        case 25: return .twentyFive
        default: return nil
        }
    }
}

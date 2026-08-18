//
//  DonateView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI
import StoreKit

enum osrsDonationDestinations {
    static let wikiSupportURL = URL(string: "https://www.patreon.com/runescapewiki")!
}

struct DonateView: View {
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var donationManager = DonationManager()
    @State private var selectedAmount: DonationAmount?
    @State private var customAmount: String = ""
    @State private var showingCustomInput = false
    @State private var showingProcessing = false
    @FocusState private var isCustomAmountFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: isCompactVerticalLayout ? 12 : 24) {
                headerSection
                amountSelectionSection
                
                if showingCustomInput {
                    customAmountSection
                }
                
                donateButtonSection
                
                if showingProcessing {
                    processingSection
                }
                
                wikiSupportSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, isCompactVerticalLayout ? 8 : 16)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 64)
        }
        .accessibilityIdentifier("donate_screen")
        .navigationTitle("Donate")
        .navigationBarTitleDisplayMode(.inline)
        .background(.osrsBackground)
        .onAppear {
            updateNavigationBarAppearance()
            donationManager.loadProducts()
        }
        .onChange(of: themeManager.selectedTheme) { oldValue, newValue in
            updateNavigationBarAppearance()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: isCompactVerticalLayout ? 8 : 16) {
            if !isCompactVerticalLayout {
                Image(systemName: "heart.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.osrsError)
            }

            Text("Support OSRS Wiki")
                .font(isCompactVerticalLayout ? .headline : .title)
                .fontWeight(.bold)
                .foregroundStyle(.osrsPrimaryTextColor)

            if !isCompactVerticalLayout {
                Text("If you get value of this app, please consider donating! Your support helps us pay for the $99 developer fee that allows us to make the app available on the App Store. It also allows us to continue improving the app for the OSRS community.")
                    .font(.body)
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
        }
    }
    
    private var amountSelectionSection: some View {
        VStack(spacing: isCompactVerticalLayout ? 8 : 12) {
            Text("Choose an amount")
                .font(isCompactVerticalLayout ? .subheadline : .headline)
                .foregroundStyle(.osrsPrimaryTextColor)
            
            Picker("Preset amount", selection: presetAmountSelection) {
                ForEach(DonationAmount.allCases.filter { $0 != .custom }, id: \.self) { amount in
                    Text(amount.displayValue)
                        .tag(Optional(amount))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("donation_preset_amounts")
            
            DonationAmountButton(
                amount: .custom,
                isSelected: showingCustomInput
            ) {
                showingCustomInput = true
                selectedAmount = .custom
            }
        }
    }

    private var presetAmountSelection: Binding<DonationAmount?> {
        Binding(
            get: {
                selectedAmount == .custom ? nil : selectedAmount
            },
            set: { newAmount in
                guard let newAmount else {
                    return
                }
                selectedAmount = newAmount
                showingCustomInput = false
                customAmount = ""
            }
        )
    }
    
    private var customAmountSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.osrsAccent)
                
                TextField("Enter amount", text: $customAmount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityIdentifier("donate_custom_amount")
                    .accessibilityLabel("Enter amount")
                    .focused($isCustomAmountFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isCustomAmountFocused = false
                            }
                        }
                    }
            }

            if let validationMessage = customAmountValidationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.osrsError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("donate_custom_amount_error")
            }
            
            Text("Minimum: $1.00, Maximum: $99.99")
                .font(.caption)
                .foregroundStyle(.osrsSecondaryTextColor)
        }
        .padding()
        .background(.osrsSearchBoxBackgroundColor)
        .cornerRadius(12)
    }
    
    private var donateButtonSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                processDonation()
            }) {
                HStack {
                    Image(systemName: "heart.fill")
                    Text(donateButtonText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .foregroundStyle(isDonateButtonEnabled ? Color(osrsTheme.onPrimary) : Color(osrsTheme.primaryTextColor))
            .padding()
            .background(isDonateButtonEnabled ? Color(osrsTheme.primary) : Color(osrsTheme.surfaceVariant))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                .stroke(Color(osrsTheme.outline), lineWidth: isDonateButtonEnabled ? 0 : 1)
            )
            .buttonStyle(osrsDonationButtonStyle())
            .disabled(!isDonateButtonEnabled)

            if let unavailableMessage = donationManager.donationUnavailableMessage {
                Text(unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.osrsSecondaryTextColor)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("donation_unavailable_message")
            }
        }
    }
    
    private var processingSection: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())                .tint(.osrsPrimaryColor)
                .scaleEffect(1.2)
            
            Text("Processing payment...")
                .font(.body)
                .foregroundStyle(.osrsSecondaryTextColor)
        }
        .padding()
        .background(.osrsSearchBoxBackgroundColor)
        .cornerRadius(12)
    }
    
    private var wikiSupportSection: some View {
        VStack(spacing: 16) {
            Divider()
            
            VStack(spacing: 12) {
                Text("Support the Wiki Too!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.osrsPrimaryTextColor)
                
                Text("The Old School RuneScape Wiki is maintained by volunteers. Consider supporting them too!")
                    .font(.body)
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    openWikiDonation()
                }) {
                    HStack {
                        Text("Donate to Wiki")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.osrsPrimary)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.osrsOutline, lineWidth: 2)
                    )
                }
            }
        }
    }
    
    private var isDonateButtonEnabled: Bool {
        if showingCustomInput {
            guard let amount = customDonationAmount,
                  amount >= 1.00,
                  amount <= 99.99 else {
                return false
            }
        }
        return selectedAmount != nil && !showingProcessing && donationManager.canStartDonation
    }
    
    private var donateButtonText: String {
        if donationManager.donationUnavailableMessage != nil {
            return "Donations Unavailable"
        }

        if let selectedAmount = selectedAmount {
            switch selectedAmount {
            case .custom:
                if let amount = customDonationAmount, amount >= 1.00, amount <= 99.99 {
                    return String(format: "Donate $%.2f", amount)
                } else {
                    return "Enter Amount"
                }
            default:
                return "Donate \(selectedAmount.displayValue)"
            }
        }
        return "Select Amount"
    }

    private var trimmedCustomAmount: String {
        customAmount.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customDonationAmount: Double? {
        guard !trimmedCustomAmount.isEmpty else {
            return nil
        }
        return Double(trimmedCustomAmount)
    }

    private var isCompactVerticalLayout: Bool {
        verticalSizeClass == .compact
    }

    private var customAmountValidationMessage: String? {
        guard showingCustomInput, !trimmedCustomAmount.isEmpty else {
            return nil
        }

        guard let amount = customDonationAmount else {
            return "Use numbers only."
        }

        if amount < 1.00 {
            return "Enter at least $1.00."
        }

        if amount > 99.99 {
            return "Enter $99.99 or less."
        }

        return nil
    }
    
    private func processDonation() {
        showingProcessing = true
        
        let amount: Double
        if selectedAmount == .custom {
            guard let validCustomAmount = customDonationAmount,
                  validCustomAmount >= 1.00,
                  validCustomAmount <= 99.99 else {
                showingProcessing = false
                return
            }
            amount = validCustomAmount
        } else {
            amount = selectedAmount?.value ?? 0
        }
        
        donationManager.processDonation(amount: amount) { success in
            DispatchQueue.main.async {
                showingProcessing = false
                if success {
                    // Show success message
                    selectedAmount = nil
                    customAmount = ""
                    showingCustomInput = false
                }
            }
        }
    }
    
    private func openWikiDonation() {
        UIApplication.shared.open(osrsDonationDestinations.wikiSupportURL)
    }
    
    /// Direct UIKit navigation bar theming to match AppearanceSettingsView
    private func updateNavigationBarAppearance() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let navigationController = findNavigationController(in: window.rootViewController) else {
                return
            }

            let currentTheme = themeManager.currentTheme
            if #available(iOS 26.0, *) {
                navigationController.navigationBar.tintColor = UIColor(currentTheme.primary)
                navigationController.overrideUserInterfaceStyle = themeManager.currentColorScheme == .dark ? .dark : .light
                return
            }
            
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            
            // Apply theme colors directly (matching AppearanceSettingsView)
            appearance.backgroundColor = UIColor(currentTheme.surface)
            appearance.titleTextAttributes = [.foregroundColor: UIColor(currentTheme.onSurface)]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(currentTheme.onSurface)]
            
            // Apply to navigation bar
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.compactAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
            
            // Set tint color for back buttons and navigation items
            navigationController.navigationBar.tintColor = UIColor(currentTheme.primary)
            
            // Update color scheme for status bar and buttons
            navigationController.overrideUserInterfaceStyle = themeManager.currentColorScheme == .dark ? .dark : .light
            
            print("📱 Applied UIKit navigation bar theming to DonateView: \(themeManager.selectedTheme)")
        }
    }
    
    /// Helper to find the navigation controller in the view hierarchy
    private func findNavigationController(in viewController: UIViewController?) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        
        for child in viewController?.children ?? [] {
            if let found = findNavigationController(in: child) {
                return found
            }
        }
        
        return nil
    }
}

struct DonationAmountButton: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let amount: DonationAmount
    let isSelected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .headline) private var regularMinButtonHeight: CGFloat = 52
    
    var body: some View {
        Button(action: action) {
            Text(amount.displayValue)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: minButtonHeight)
                .padding(.horizontal, 16)
                .padding(.vertical, verticalSizeClass == .compact ? 4 : 8)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(isSelected ? .osrsOnPrimary : .osrsPrimaryTextColor)
        .background(isSelected ? .osrsPrimary : .osrsSearchBoxBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(osrsTheme.outline) : Color.clear, lineWidth: 2)
        )
        .buttonStyle(osrsDonationButtonStyle())
    }

    private var minButtonHeight: CGFloat {
        verticalSizeClass == .compact ? 36 : regularMinButtonHeight
    }
}

private struct osrsDonationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
    }
}

// MARK: - DonationAmount Enum
enum DonationAmount: CaseIterable {
    case one, five, ten, twentyFive, custom
    
    var displayValue: String {
        switch self {
        case .one: return "$1"
        case .five: return "$5"
        case .ten: return "$10"
        case .twentyFive: return "$25"
        case .custom: return "Custom"
        }
    }
    
    var value: Double {
        switch self {
        case .one: return 1.0
        case .five: return 5.0
        case .ten: return 10.0
        case .twentyFive: return 25.0
        case .custom: return 0.0
        }
    }
}

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

protocol osrsDonationPaymentGateway: AnyObject {
    var availability: osrsDonationPaymentAvailability { get }
    func startDonation(
        amount: Decimal,
        completion: @escaping (osrsDonationPurchaseResult) -> Void
    )
}

final class osrsUnavailableDonationGateway: osrsDonationPaymentGateway {
    let availability: osrsDonationPaymentAvailability

    init(reason: String = DonationManager.defaultUnavailableMessage) {
        self.availability = .unavailable(reason)
    }

    func startDonation(
        amount: Decimal,
        completion: @escaping (osrsDonationPurchaseResult) -> Void
    ) {
        completion(.failed(availability.unavailableReason ?? DonationManager.defaultUnavailableMessage))
    }
}

// MARK: - DonationManager
class DonationManager: NSObject, ObservableObject {
    static let defaultUnavailableMessage = "Donations are not available in this build because no payment provider is configured."

    @Published var products: [SKProduct] = [] // Legacy StoreKit for compatibility
    @Published var donationState: osrsDonationState = .productsUnavailable(DonationManager.defaultUnavailableMessage)
    @Published var canMakePayments: Bool = {
        if #available(iOS 18.0, *) {
            return true // AppStore.canMakePayments would go here when using modern StoreKit
        } else {
            return SKPaymentQueue.canMakePayments()
        }
    }()
    @Published var isApplePayAvailable: Bool

    private let paymentGateway: osrsDonationPaymentGateway

    init(paymentGateway: osrsDonationPaymentGateway = osrsUnavailableDonationGateway()) {
        self.paymentGateway = paymentGateway
        self.isApplePayAvailable = paymentGateway.availability.isAvailable
        super.init()
        if let reason = paymentGateway.availability.unavailableReason {
            donationState = .productsUnavailable(reason)
        }
    }

    var canStartDonation: Bool {
        guard paymentGateway.availability.isAvailable else {
            return false
        }
        if case .productsAvailable = donationState {
            return true
        }
        return false
    }

    var donationUnavailableMessage: String? {
        if let reason = paymentGateway.availability.unavailableReason {
            return reason
        }
        if case .productsUnavailable(let reason) = donationState {
            return reason
        }
        return nil
    }

    func loadProducts() {
        if let reason = paymentGateway.availability.unavailableReason {
            donationState = osrsDonationStateReducer.reduceProductLoad(.unavailable(reason))
            return
        }

        donationState = osrsDonationStateReducer.reduceProductLoad(
            .unavailable("In-app donation products are not configured for this build.")
        )
    }
    
    func processDonation(amount: Double, completion: @escaping (Bool) -> Void) {
        guard amount > 0 else {
            donationState = osrsDonationStateReducer.reducePurchase(.failed("Donation amount must be greater than zero."))
            completion(false)
            return
        }

        if let reason = paymentGateway.availability.unavailableReason {
            donationState = osrsDonationStateReducer.reduceProductLoad(.unavailable(reason))
            completion(false)
            return
        }

        guard canStartDonation else {
            donationState = osrsDonationStateReducer.reduceProductLoad(
                .unavailable("In-app donation products are not configured for this build.")
            )
            completion(false)
            return
        }

        let decimalAmount = Decimal(amount)
        donationState = osrsDonationStateReducer.beginPurchase(
            product: osrsDonationProduct(
                id: "apple-pay-donation-\(amount)",
                displayName: String(format: "$%.2f Donation", amount),
                amount: decimalAmount
            )
        )

        paymentGateway.startDonation(amount: decimalAmount) { [weak self] result in
            DispatchQueue.main.async {
                self?.donationState = osrsDonationStateReducer.reducePurchase(result)
                completion(result == .success)
            }
        }
    }
}

#Preview {
    NavigationView {
        DonateView()
            .environmentObject(osrsThemeManager.preview)
            .environment(\.osrsTheme, osrsLightTheme())
    }
}

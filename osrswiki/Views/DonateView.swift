//
//  DonateView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session
//

import SwiftUI

enum osrsDonationDestinations {
    static let wikiSupportURL = URL(string: "https://www.patreon.com/runescapewiki")!
}

struct DonateView: View {
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var donationManager: DonationManager
    @State private var selectedAmount: DonationAmount?
    @State private var showingCustomInput = false

    @MainActor
    init() {
        _donationManager = StateObject(wrappedValue: DonationManager())
    }

    @MainActor
    init(donationManager: DonationManager) {
        _donationManager = StateObject(wrappedValue: donationManager)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: isCompactVerticalLayout ? 12 : 24) {
                headerSection
                amountSelectionSection

                if showingCustomInput {
                    customAmountSection
                }

                donateButtonSection
                statusSection
                wikiSupportSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, isCompactVerticalLayout ? 8 : 16)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 64)
        }
        .accessibilityIdentifier("donate_screen")
        .background(.osrsBackground)
        .osrsMoreDestinationChrome(title: "Donate")
        .task {
            await donationManager.loadProductsAsync()
        }
    }

    private var headerSection: some View {
        VStack(spacing: isCompactVerticalLayout ? 8 : 16) {
            Text("Support OSRS Wiki")
                .font(isCompactVerticalLayout ? .headline : .title2)
                .foregroundStyle(.osrsPrimaryTextColor)
                .multilineTextAlignment(.center)

            Text("This app is free. Nothing is locked behind a donation.")
                .font(.body)
                .foregroundStyle(.osrsPrimaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            Text("If you want to help, it goes to fees I pay to put this app in the App Store and the time it takes to keep the app working.")
                .font(.body)
                .foregroundStyle(.osrsPrimaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
        }
    }

    private var amountSelectionSection: some View {
        VStack(spacing: isCompactVerticalLayout ? 8 : 12) {
            Text("Choose an amount")
                .font(isCompactVerticalLayout ? .subheadline : .headline)
                .foregroundStyle(.osrsPrimaryTextColor)

            Picker("Preset amount", selection: presetAmountSelection) {
                ForEach(DonationAmount.presets, id: \.self) { amount in
                    Text(donationManager.displayPrice(for: amount))
                        .tag(Optional(amount))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("donation_preset_amounts")
            .disabled(!donationManager.canStartDonation && donationManager.donationUnavailableMessage != nil)

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
            }
        )
    }

    private var customAmountSection: some View {
        Text(DonationManager.customAmountUnsupportedMessage)
            .font(.caption)
            .foregroundStyle(.osrsSecondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("donate_custom_amount_handoff")
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
            .accessibilityIdentifier("donate_submit")

            if let unavailableMessage = donationManager.donationUnavailableMessage {
                Text(unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.osrsSecondaryTextColor)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("donation_unavailable_message")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch donationManager.donationState {
        case .loadingProducts:
            processingRow(text: "Loading donation amounts...")
        case .purchasing:
            processingRow(text: "Processing payment...")
        case .succeeded:
            statusText("Thank you for supporting the app.", identifier: "donate_status_success")
        case .cancelled:
            statusText("Purchase cancelled.", identifier: "donate_status_cancelled")
        case .pending:
            statusText("This purchase is pending approval.", identifier: "donate_status_pending")
        case .failed(let message):
            statusText(message, identifier: "donate_status_failed", isError: true)
        default:
            EmptyView()
        }
    }

    private func processingRow(text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .tint(.osrsPrimaryColor)
                .scaleEffect(1.2)

            Text(text)
                .font(.body)
                .foregroundStyle(.osrsSecondaryTextColor)
        }
        .padding()
        .background(.osrsSearchBoxBackgroundColor)
        .cornerRadius(12)
        .accessibilityIdentifier("donate_processing")
    }

    private func statusText(_ text: String, identifier: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(isError ? .osrsError : .osrsSecondaryTextColor)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier(identifier)
            .padding()
            .background(.osrsSearchBoxBackgroundColor)
            .cornerRadius(12)
    }

    private var wikiSupportSection: some View {
        VStack(spacing: 16) {
            Divider()

            VStack(spacing: 12) {
                Text("The Old School RuneScape Wiki is run by volunteers. Support them too if you can.")
                    .font(.body)
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .multilineTextAlignment(.center)

                osrsOutboundLinkRow(title: "Donate to Wiki", action: openWikiDonation)
            }
        }
    }

    private var isPurchasing: Bool {
        if case .purchasing = donationManager.donationState {
            return true
        }
        return false
    }

    private var isDonateButtonEnabled: Bool {
        guard let selectedAmount, selectedAmount != .custom else {
            return false
        }
        return !isPurchasing && donationManager.canStartDonation
    }

    private var donateButtonText: String {
        if case .loadingProducts = donationManager.donationState {
            return "Loading..."
        }
        if donationManager.donationUnavailableMessage != nil {
            return "Donations Unavailable"
        }
        if selectedAmount == .custom {
            return "Use Donate to Wiki"
        }
        if let selectedAmount {
            return "Donate \(donationManager.displayPrice(for: selectedAmount))"
        }
        return "Select Amount"
    }

    private var isCompactVerticalLayout: Bool {
        verticalSizeClass == .compact
    }

    private func processDonation() {
        guard let selectedAmount, selectedAmount != .custom else {
            return
        }

        donationManager.processDonation(amount: selectedAmount) { success in
            if success {
                self.selectedAmount = nil
                showingCustomInput = false
            }
        }
    }

    private func openWikiDonation() {
        UIApplication.shared.open(osrsDonationDestinations.wikiSupportURL)
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
        .accessibilityIdentifier("donate_amount_\(amount.displayValue)")
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

#Preview {
    NavigationView {
        DonateView(donationManager: DonationManager(paymentGateway: osrsFakeDonationGateway.previewLoaded()))
            .environmentObject(osrsThemeManager.preview)
            .environment(\.osrsTheme, osrsLightTheme())
    }
}

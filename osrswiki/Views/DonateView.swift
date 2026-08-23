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
            VStack(spacing: osrsMorePageMetrics.pageStackSpacing) {
                headerSection
                amountSelectionSection
                donateButtonSection
                statusSection
                wikiSupportSection
            }
            .padding(.horizontal, osrsMorePageMetrics.horizontalPadding)
            .padding(.vertical, isCompactVerticalLayout ? 8 : osrsMorePageMetrics.verticalPadding)
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
        VStack(spacing: osrsMorePageMetrics.sectionSpacing) {
            Text("Support the OSRS Wiki App")
                .font(isCompactVerticalLayout ? .headline : .title2)
                .foregroundStyle(.osrsPrimaryTextColor)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("donate_header")

            Text("This app is free. Nothing is locked behind a donation. If you want to help, it goes to fees I pay to put this app in the App Store and the time it takes to keep the app working.")
                .font(.body)
                .foregroundStyle(.osrsPrimaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
        }
    }

    private var amountSelectionSection: some View {
        VStack(spacing: osrsMorePageMetrics.sectionSpacing) {
            Text("Choose an amount")
                .font(isCompactVerticalLayout ? .subheadline : .headline)
                .foregroundStyle(.osrsPrimaryTextColor)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(DonationAmount.presets, id: \.self) { amount in
                    DonationAmountButton(
                        title: donationManager.displayPrice(for: amount),
                        amount: amount,
                        isSelected: selectedAmount == amount,
                        isEnabled: donationManager.canStartDonation || donationManager.donationUnavailableMessage == nil
                    ) {
                        selectedAmount = amount
                    }
                }
            }
            .accessibilityIdentifier("donation_preset_amounts")
        }
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
                .padding(.horizontal, 32)
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
            .frame(maxWidth: .infinity)

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
        case .loadingProducts where donationManager.products.isEmpty:
            processingRow(text: "Loading donation amounts...")
        case .purchasing:
            processingRow(text: "Processing donation...")
        case .succeeded:
            statusText("Thank you for supporting the app.", identifier: "donate_status_success")
        case .cancelled:
            statusText("Donation cancelled", identifier: "donate_status_cancelled")
        case .pending:
            statusText("This donation is pending approval.", identifier: "donate_status_pending")
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
            .foregroundStyle(isError ? .osrsError : .osrsPrimaryTextColor)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier(identifier)
            .padding()
            .background(.osrsSearchBoxBackgroundColor)
            .cornerRadius(12)
    }

    private var wikiSupportSection: some View {
        VStack(spacing: osrsMorePageMetrics.sectionSpacing) {
            Divider()
                .padding(.top, osrsMorePageMetrics.donateWikiBlockSpacing - osrsMorePageMetrics.sectionSpacing)

            VStack(spacing: osrsMorePageMetrics.sectionSpacing) {
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
        guard selectedAmount != nil else {
            return false
        }
        return !isPurchasing && donationManager.canStartDonation
    }

    private var donateButtonText: String {
        if case .loadingProducts = donationManager.donationState, donationManager.products.isEmpty {
            return "Loading..."
        }
        if donationManager.donationUnavailableMessage != nil {
            return "Donations Unavailable"
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
        guard let selectedAmount else {
            return
        }

        donationManager.processDonation(amount: selectedAmount) { success in
            if success {
                self.selectedAmount = nil
            }
            // Keep selection after cancel so amount chips stay readable.
        }
    }

    private func openWikiDonation() {
        UIApplication.shared.open(osrsDonationDestinations.wikiSupportURL)
    }
}

struct DonationAmountButton: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let title: String
    let amount: DonationAmount
    let isSelected: Bool
    var isEnabled: Bool = true
    let action: () -> Void
    @ScaledMetric(relativeTo: .headline) private var regularMinButtonHeight: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: minButtonHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, verticalSizeClass == .compact ? 4 : 6)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(isSelected ? Color(osrsTheme.onPrimary) : Color(osrsTheme.primaryTextColor))
        .background(isSelected ? Color(osrsTheme.secondary) : Color(osrsTheme.surfaceVariant))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color(osrsTheme.primary) : Color(osrsTheme.outline),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .opacity(isEnabled ? 1 : 0.55)
        .disabled(!isEnabled)
        .buttonStyle(osrsDonationButtonStyle())
        .accessibilityIdentifier("donate_amount_\(amount.displayValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var minButtonHeight: CGFloat {
        verticalSizeClass == .compact ? 32 : regularMinButtonHeight
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

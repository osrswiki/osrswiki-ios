//
//  FeedbackView.swift
//  OSRS Wiki
//
//  Created on iOS feature parity session - Updated for design and functional parity with Android
//

import SwiftUI
import MessageUI
import StoreKit

struct FeedbackView: View {
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) var osrsTheme
    @State private var showingBugReportForm = false
    @State private var showingFeatureRequestForm = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var alertMessage = ""
    @State private var isSubmitting = false
    
    // App Store availability flag - set to true when app is live on App Store
    private let isAppOnAppStore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: osrsMorePageMetrics.pageStackSpacing) {
                if isAppOnAppStore {
                    rateAppCard
                }
                reportIssueCard
                requestFeatureCard
            }
            .padding(.horizontal, osrsMorePageMetrics.horizontalPadding)
            .padding(.vertical, osrsMorePageMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 64)
        }
        .accessibilityIdentifier("feedback_screen")
        .background(.osrsBackground)
        .osrsMoreDestinationChrome(title: "Send Feedback")
        .sheet(isPresented: $showingBugReportForm) {
            osrsFeedbackFormView(
                feedbackType: .bug,
                isPresented: $showingBugReportForm,
                onSuccess: { message in
                    alertMessage = message
                    showingSuccessAlert = true
                },
                onError: { error in
                    alertMessage = error
                    showingErrorAlert = true
                }
            )
        }
        .sheet(isPresented: $showingFeatureRequestForm) {
            osrsFeedbackFormView(
                feedbackType: .feature,
                isPresented: $showingFeatureRequestForm,
                onSuccess: { message in
                    alertMessage = message
                    showingSuccessAlert = true
                },
                onError: { error in
                    alertMessage = error
                    showingErrorAlert = true
                }
            )
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Feedback rows (link is the affordance)

    private var rateAppCard: some View {
        osrsFeedbackCardView(
            title: "Rate This App",
            description: "Love our app? Rate it on the App Store to help others discover it!",
            buttonText: "Rate App",
            buttonIcon: "arrow.up.right",
            action: {
                openAppStore()
            }
        )
    }

    private var reportIssueCard: some View {
        osrsFeedbackCardView(
            title: "Report an Issue",
            description: "Found a bug or something not working correctly? Let us know!",
            buttonText: "Report Issue",
            buttonIcon: "ant.fill",
            action: {
                showingBugReportForm = true
            }
        )
    }

    private var requestFeatureCard: some View {
        osrsFeedbackCardView(
            title: "Request a Feature",
            description: "Have an idea for a new feature or improvement? Share it with us!",
            buttonText: "Request Feature",
            buttonIcon: "lightbulb.fill",
            action: {
                showingFeatureRequestForm = true
            }
        )
    }

    // MARK: - Actions

    private func openAppStore() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            alertMessage = "App rating is not available right now."
            showingErrorAlert = true
            return
        }

        AppStore.requestReview(in: windowScene)
    }
}

// MARK: - Reusable Card Component (Android Design Parity)

struct osrsFeedbackCardView: View {
    let title: String
    let description: String
    let buttonText: String
    let buttonIcon: String
    let action: () -> Void

    var body: some View {
        // Match About: plain text + outbound text link (no elevated card chrome).
        VStack(alignment: .leading, spacing: osrsMorePageMetrics.creditBlockSpacing) {
            VStack(alignment: .leading, spacing: osrsMorePageMetrics.headingBodySpacing) {
                Text(title)
                    .font(.osrsTitle)
                    .foregroundStyle(.osrsOnSurface)

                Text(description)
                    .font(.osrsBody)
                    .foregroundStyle(.osrsPrimaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            osrsOutboundLinkRow(
                title: buttonText,
                systemImage: buttonIcon,
                alignment: .leading,
                action: action
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Feedback Form Component

struct osrsFeedbackFormView: View {
    let feedbackType: osrsFeedbackType
    @Binding var isPresented: Bool
    let onSuccess: (String) -> Void
    let onError: (String) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var useCase = "" // Only for feature requests
    @State private var includeSystemInfo = true
    @State private var isSubmitting = false

    @Environment(\.osrsTheme) var osrsTheme
    @EnvironmentObject var themeManager: osrsThemeManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    titleSection
                    descriptionSection
                    if feedbackType == .feature {
                        useCaseSection
                    }
                    systemInfoSection
                    submitButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .navigationTitle(feedbackType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.osrsPrimary)
                }
            }
            .background(.osrsBackground)
            .modifier(osrsLegacyFeedbackNavigationSurface())
            .toolbarColorScheme(themeManager.currentColorScheme, for: .navigationBar)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: feedbackType.iconName)
                .font(.system(size: 48))
                .foregroundStyle(feedbackType.color)

            Text(feedbackType.description)
                .font(.body)
                .foregroundStyle(.osrsSecondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.top, -8)
        .padding(.bottom, 4)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(feedbackType == .feature ? "Feature Summary" : "Title")
                .font(.headline)
                .foregroundStyle(.osrsPrimaryTextColor)

            TextField(
                feedbackType == .feature ?
                "Brief description of the feature you'd like to see" :
                "Brief description of the \(feedbackType.displayName.lowercased())",
                text: $title
            )
                .padding()
                .background(.osrsSurfaceVariant)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.osrsOutline, lineWidth: 1)
                )
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(feedbackType == .feature ? "Detailed Description" : "Description")
                .font(.headline)
                .foregroundStyle(.osrsPrimaryTextColor)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.osrsSurfaceVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.osrsOutline, lineWidth: 1)
                    )

                TextEditor(text: $description)
                    .padding(8)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.osrsPrimaryTextColor)
            }
            .frame(minHeight: 120)

            Text(feedbackType == .bug ?
                 "Please include steps to reproduce the issue." :
                 feedbackType == .feature ?
                 "Describe exactly what the feature should do and how it should work" :
                 "Describe your idea in as much detail as possible.")
                .font(.caption)
                .foregroundStyle(.osrsSecondaryTextColor)
        }
    }

    private var useCaseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use Case (Optional)")
                .font(.headline)
                .foregroundStyle(.osrsPrimaryTextColor)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.osrsSurfaceVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.osrsOutline, lineWidth: 1)
                    )

                TextEditor(text: $useCase)
                    .padding(8)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.osrsPrimaryTextColor)
            }
            .frame(minHeight: 80)

            Text("Explain why this feature would be valuable and how you'd use it")
                .font(.caption)
                .foregroundStyle(.osrsSecondaryTextColor)
        }
    }

    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Include system information", isOn: $includeSystemInfo)
                .font(.headline)

            if includeSystemInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Information:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.osrsSecondaryTextColor)

                    Text(systemInfoText)
                        .font(.caption)
                        .foregroundStyle(.osrsSecondaryTextColor)
                        .padding(8)
                        .background(.osrsSurfaceVariant)
                        .cornerRadius(6)
                }
            }

            Text("This helps us understand and fix device-specific issues.")
                .font(.caption)
                .foregroundStyle(.osrsSecondaryTextColor)
        }
    }

    private var submitButton: some View {
        Button(action: {
            submitFeedback()
        }) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.osrsOnPrimaryColor))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSubmitting ? "Submitting..." : "Submit \(feedbackType.displayName)")
            }
            .font(.headline)
            .foregroundStyle(.osrsOnPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.osrsPrimary)
            .opacity(isSubmitEnabled ? 1.0 : 0.4)
            .cornerRadius(12)
        }
        .disabled(!isSubmitEnabled || isSubmitting)
    }

    private var isSubmitEnabled: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var systemInfoText: String {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return """
        App Version: \(appVersion) (\(buildNumber))
        iOS Version: \(device.systemVersion)
        Device: \(device.model)
        Theme: \(themeManager.selectedTheme.rawValue)
        """
    }

    private func submitFeedback() {
        isSubmitting = true

        Task {
            let result: Result<String, Error>

            switch feedbackType {
            case .bug:
                result = await osrsFeedbackService.shared.reportIssue(
                    title: title,
                    description: description,
                    includeSystemInfo: includeSystemInfo
                )
            case .feature:
                // Combine description and use case if provided (matching Android logic)
                let fullDescription = if !useCase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    "\(description)\n\n**Use Case:**\n\(useCase)"
                } else {
                    description
                }
                result = await osrsFeedbackService.shared.requestFeature(
                    title: title,
                    description: fullDescription,
                    includeSystemInfo: includeSystemInfo
                )
            }

            await MainActor.run {
                isSubmitting = false

                switch result {
                case .success(let message):
                    onSuccess(message)
                    isPresented = false
                case .failure(let error):
                    if let feedbackError = error as? osrsFeedbackError {
                        print("Feedback submission failed: \(feedbackError)")
                        onError("Feedback could not be sent. Please try again.")
                    } else {
                        print("Unexpected feedback failure: \(error)")
                        onError("Feedback could not be sent. Please try again.")
                    }
                }
            }
        }
    }
}

private struct osrsLegacyFeedbackNavigationSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.osrsSurface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Feedback Type Enum
enum osrsFeedbackType {
    case bug, feature

    var displayName: String {
        switch self {
        case .bug: return "Bug Report"
        case .feature: return "Feature Request"
        }
    }

    var description: String {
        switch self {
        case .bug: return "Report something that's not working correctly"
        case .feature: return "Suggest a new feature or improvement"
        }
    }

    var iconName: String {
        switch self {
        case .bug: return "ant.fill"
        case .feature: return "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .bug: return Color.osrsErrorColor
        case .feature: return Color.osrsAccentColor
        }
    }
}

#Preview {
    NavigationView {
        FeedbackView()
            .environmentObject(AppState())
            .environmentObject(osrsThemeManager.preview)
            .environment(\.osrsTheme, osrsLightTheme())
    }
}

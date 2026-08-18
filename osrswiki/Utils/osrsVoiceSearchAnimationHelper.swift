//
//  osrsVoiceSearchAnimationHelper.swift
//  osrswiki
//
//  Created on voice search implementation session
//

import SwiftUI
import UIKit

@MainActor
class osrsVoiceSearchAnimationHelper: ObservableObject {
    
    @Published var currentIcon: String = "mic"
    @Published var isAnimating: Bool = false
    @Published var iconColor: Color = .primary
    @Published var pulseScale: CGFloat = 1.0
    
    private var animationTimer: Timer?
    
    func setIdleState() {
        stopCurrentAnimation()
        currentIcon = "mic"
        iconColor = .primary
        isAnimating = false
        pulseScale = 1.0
    }
    
    func setListeningState() {
        stopCurrentAnimation()
        currentIcon = "mic.fill"
        iconColor = .red
        isAnimating = true
        startPulseAnimation()
    }
    
    func setProcessingState() {
        stopCurrentAnimation()
        currentIcon = "mic.fill"
        iconColor = .red
        isAnimating = false
        pulseScale = 1.0
    }
    
    func setErrorState() {
        stopCurrentAnimation()
        currentIcon = "mic"
        iconColor = .primary
        isAnimating = false
        pulseScale = 1.0
    }
    
    private func startPulseAnimation() {
        // Use a repeating animation for the pulsing effect
        withAnimation(
            Animation.easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.3
        }
    }
    
    private func stopCurrentAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        // Stop the pulse animation by resetting the scale
        withAnimation(.easeOut(duration: 0.2)) {
            pulseScale = 1.0
        }
    }
    
    func cleanup() {
        stopCurrentAnimation()
    }
    
    deinit {
        // Can't call async cleanup from deinit, but that's okay
        // The animation will be cleaned up automatically when the object is deallocated
    }
}

// MARK: - Voice Search Button View
struct osrsVoiceSearchButton: View {
    @StateObject private var animationHelper = osrsVoiceSearchAnimationHelper()
    @Environment(\.osrsTheme) var osrsTheme
    
    let action: () -> Void
    let state: osrsSpeechRecognitionManager.SpeechState
    let accessibilityIdentifier: String

    init(
        action: @escaping () -> Void,
        state: osrsSpeechRecognitionManager.SpeechState,
        accessibilityIdentifier: String = "voice_search_button"
    ) {
        self.action = action
        self.state = state
        self.accessibilityIdentifier = accessibilityIdentifier
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: animationHelper.currentIcon)
                .foregroundStyle(animationHelper.iconColor == .primary ? 
                               Color(osrsTheme.placeholderColor) : animationHelper.iconColor)
                .font(.system(size: 16, weight: .medium))
                .scaleEffect(animationHelper.pulseScale)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onChange(of: state) { _, newState in
            updateAnimationForState(newState)
        }
        .onAppear {
            updateAnimationForState(state)
        }
        .onDisappear {
            animationHelper.cleanup()
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle, .error:
            return "Voice search"
        case .listening:
            return "Stop voice search"
        case .processing:
            return "Processing voice search"
        }
    }
    
    private func updateAnimationForState(_ state: osrsSpeechRecognitionManager.SpeechState) {
        switch state {
        case .idle:
            animationHelper.setIdleState()
        case .listening:
            animationHelper.setListeningState()
        case .processing:
            animationHelper.setProcessingState()
        case .error:
            animationHelper.setErrorState()
        }
    }
}

// MARK: - Shared Tab Search Chrome

/// Compact themed heading used by the root Home, Saved, and Search History tabs.
/// Keeping the title metrics here prevents those roots from drifting independently.
struct osrsThemedTabHeader<Trailing: View>: View {
    @Environment(\.osrsTheme) private var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var titleFontSize: CGFloat = 28

    let title: String
    let accessibilityIdentifier: String
    let trailing: () -> Trailing

    init(
        _ title: String,
        accessibilityIdentifier: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(Color(osrsTheme.primaryTextColor))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(accessibilityIdentifier)

            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private var titleFont: Font {
        for name in ["Alegreya-Bold", "alegreya_bold", "Alegreya Bold"] where UIFont(name: name, size: titleFontSize) != nil {
            return .custom(name, size: titleFontSize)
        }
        return .system(size: titleFontSize, weight: .bold, design: .serif)
    }
}

extension View {
    /// One spacing contract for the Home, Saved, History, and Search History launchers.
    func osrsTabSearchLauncherLayout(compact: Bool = false) -> some View {
        padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 0)
    }
}

/// Search launcher plus one trailing glass control. The control sits in the leftover
/// space between the field and the trailing screen edge rather than hugging that edge.
struct osrsTabSearchWithTrailingControl<Trailing: View>: View {
    let search: osrsSearchLauncher
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            search
            trailing()
                .frame(width: 80, alignment: .center)
        }
        .padding(.leading, 16)
        .padding(.top, 0)
        .padding(.bottom, 0)
    }
}

struct osrsGlassOverflowMenu<Content: View>: View {
    @Environment(\.osrsTheme) private var osrsTheme
    let accessibilityIdentifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(osrsTheme.primaryTextColor))
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(90))
        }
        .osrsFloatingGlass(in: Circle(), fallback: Color(osrsTheme.surfaceVariant))
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("More")
    }
}

extension osrsThemedTabHeader where Trailing == EmptyView {
    init(_ title: String, accessibilityIdentifier: String) {
        self.init(title, accessibilityIdentifier: accessibilityIdentifier) {
            EmptyView()
        }
    }
}

/// One bounded geometry contract for the launcher and active editor. Normal content
/// stays compact; accessibility categories get one deliberate, predictable expansion.
enum osrsSearchControlGeometry {
    static let compactHeight: CGFloat = 48
    static let accessibilityHeight: CGFloat = 64

    static func height(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? accessibilityHeight : compactHeight
    }

    /// Circular stadium: each end is a semicircle (radius = height/2).
    /// Continuous/squircle rounded rects read as a rectangle with tight corners.
    static func pillShape(height: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: height / 2, style: .circular)
    }

    static func pillShape(for dynamicTypeSize: DynamicTypeSize) -> RoundedRectangle {
        pillShape(height: height(for: dynamicTypeSize))
    }
}

/// A launcher with independent search and microphone actions. The old launcher
/// wrapped the whole capsule in one Button, which made adding a functional mic
/// impossible without nesting buttons.
struct osrsSearchLauncher: View {
    @Environment(\.osrsTheme) private var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let placeholder: String
    let accessibilityIdentifier: String
    let voiceAccessibilityIdentifier: String
    let speechState: osrsSpeechRecognitionManager.SpeechState
    let onSearchTap: () -> Void
    let onVoiceTap: () -> Void

    private var controlHeight: CGFloat {
        osrsSearchControlGeometry.height(for: dynamicTypeSize)
    }

    var body: some View {
        HStack(spacing: 0) {
            osrsUIKitSearchLauncherButton(
                title: placeholder,
                accessibilityIdentifier: accessibilityIdentifier,
                foregroundColor: UIColor(osrsTheme.placeholderColor),
                allowsTwoLines: dynamicTypeSize.isAccessibilitySize,
                controlHeight: controlHeight,
                action: onSearchTap
            )
            .frame(maxWidth: .infinity)
            .frame(height: controlHeight)

            osrsVoiceSearchButton(
                action: onVoiceTap,
                state: speechState,
                accessibilityIdentifier: voiceAccessibilityIdentifier
            )
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.trailing, 2)
        .frame(height: controlHeight)
        .osrsFloatingGlass(in: osrsSearchControlGeometry.pillShape(height: controlHeight), fallback: Color(osrsTheme.surfaceVariant))
    }
}

struct osrsGlassIconButton: View {
    @Environment(\.osrsTheme) private var osrsTheme
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(osrsTheme.primaryTextColor))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .osrsFloatingGlass(in: Circle(), fallback: Color(osrsTheme.surfaceVariant))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Shared chrome metrics. Tab search uses one paired gap above and below the
/// bar. Article floating chrome uses the home tab-bar-to-screen-edge distance
/// so every surface sits the same distance from the nearest physical edge.
enum osrsOverlayChromeMetrics {
    private static let cacheLock = NSLock()
    private static var cachedTopInset: CGFloat = 59
    private static var cachedBottomInset: CGFloat = 34

    private static func liveWindowSafeArea() -> UIEdgeInsets? {
        guard Thread.isMainThread else { return nil }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.keyWindow ?? scene?.windows.first
        return window?.safeAreaInsets
    }

    static var topInset: CGFloat {
        if let insets = liveWindowSafeArea() {
            cacheLock.lock()
            cachedTopInset = insets.top
            cacheLock.unlock()
            return insets.top
        }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedTopInset
    }

    /// Paired gap: Dynamic Island → search bar, and search bar → first content.
    static let pairedEdgeGap: CGFloat = 8

    static var bottomInset: CGFloat {
        if let insets = liveWindowSafeArea() {
            cacheLock.lock()
            cachedBottomInset = insets.bottom
            cacheLock.unlock()
            return insets.bottom
        }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedBottomInset
    }

    static func tabContentClearance(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        osrsSearchControlGeometry.height(for: dynamicTypeSize) + pairedEdgeGap
    }

    /// Home tab bar sits partly in the home-indicator zone. On a 34pt
    /// indicator the measured glass-to-screen gap is ~22pt (0.65 × inset).
    static var screenEdgeGap: CGFloat {
        let inset = bottomInset
        if inset <= 0 { return pairedEdgeGap }
        return max(pairedEdgeGap, (inset * 0.65).rounded())
    }

    /// Native iOS 26 floating tab bar (icons + labels). Article chrome uses
    /// the same height so its capsule stays concentric with the device corners.
    static let floatingBarHeight: CGFloat = 62
}

extension View {
    /// Place overlay chrome using the *remaining* safe area only.
    /// `GeometryReader.safeAreaInsets` reports the window inset even when the
    /// overlay is already laid out below it, so adding that value double-counts
    /// and pushes bars away from the edges.
    func osrsPairedEdgeChrome<Chrome: View>(
        edge: VerticalEdge,
        @ViewBuilder chrome: @escaping () -> Chrome
    ) -> some View {
        // Pin the overlay to the physical screen edge first. NavigationStack
        // still reports a leftover safe-area, so `.safeAreaPadding` double-counts
        // and sits the article bar ~12pt below the home search bar.
        overlay(alignment: edge == .top ? .top : .bottom) {
            chrome()
                .padding(
                    .top,
                    edge == .top ? osrsOverlayChromeMetrics.topInset : 0
                )
                .padding(
                    .bottom,
                    edge == .bottom ? osrsOverlayChromeMetrics.screenEdgeGap : 0
                )
        }
        .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
    }
}

private struct osrsTabGlassAccessoryBarModifier<Accessory: View>: ViewModifier {
    @ViewBuilder let accessory: () -> Accessory

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .safeAreaInset(edge: .top, spacing: osrsOverlayChromeMetrics.pairedEdgeGap) {
                    accessory()
                }
        } else {
            VStack(spacing: 0) {
                accessory()
                    .padding(.bottom, 4)
                content
            }
        }
    }
}

extension View {
    func osrsTabGlassAccessoryBar<Accessory: View>(
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(osrsTabGlassAccessoryBarModifier(accessory: accessory))
    }

    @ViewBuilder
    func osrsFloatingGlass(in shape: Capsule, fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .containerShape(shape)
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
        } else {
            self
                .background(fallback, in: shape)
                .clipShape(shape)
        }
    }

    @ViewBuilder
    func osrsFloatingGlass(in shape: RoundedRectangle, fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .containerShape(shape)
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
        } else {
            self
                .background(fallback, in: shape)
                .clipShape(shape)
        }
    }

    @ViewBuilder
    func osrsFloatingGlass<S: Shape>(in shape: S, fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
        } else {
            self
                .background(fallback, in: shape)
                .clipShape(shape)
        }
    }
}

/// Shared active-search chrome for Search and Saved. Reserving the clear-button slot keeps
/// the editable field within two points of its launch/typing/clear geometry at every state.
struct osrsActiveSearchToolbar: View {
    @Environment(\.osrsTheme) private var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let backAccessibilityLabel: String
    let backAccessibilityIdentifier: String
    let inputAccessibilityIdentifier: String
    let clearAccessibilityIdentifier: String
    let voiceAccessibilityIdentifier: String
    let speechState: osrsSpeechRecognitionManager.SpeechState
    let onBack: () -> Void
    let onClear: () -> Void
    let onVoiceTap: () -> Void
    let onSubmit: () -> Void

    private var controlHeight: CGFloat {
        osrsSearchControlGeometry.height(for: dynamicTypeSize)
    }

    var body: some View {
        // Horizontally flipped inactive launcher: 80pt leading control slot,
        // flexible glass field, 16pt trailing inset. Extra horizontal padding
        // here (or via osrsTabSearchLauncherLayout) insets the bar off the
        // screen edge and breaks the shared width contract.
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(osrsTheme.primaryTextColor))
            .osrsFloatingGlass(in: Circle(), fallback: Color(osrsTheme.surfaceVariant))
            .frame(width: 80, alignment: .center)
            .accessibilityLabel(backAccessibilityLabel)
            .accessibilityIdentifier(backAccessibilityIdentifier)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(osrsTheme.placeholderColor))
                    .accessibilityHidden(true)

                osrsUIKitSearchTextField(
                    text: $text,
                    shouldFocus: isFocused,
                    onFocusChange: { isFocused = $0 },
                    placeholder: placeholder,
                    accessibilityIdentifier: inputAccessibilityIdentifier,
                    textColor: UIColor(osrsTheme.primaryTextColor),
                    placeholderColor: UIColor(osrsTheme.placeholderColor),
                    tintColor: UIColor(osrsTheme.primary),
                    controlHeight: controlHeight,
                    onSubmit: onSubmit
                )
                .frame(height: controlHeight)
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)

                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Color(osrsTheme.secondaryTextColor))
                .opacity(text.isEmpty ? 0 : 1)
                .allowsHitTesting(!text.isEmpty)
                .accessibilityHidden(text.isEmpty)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier(clearAccessibilityIdentifier)

                osrsVoiceSearchButton(
                    action: onVoiceTap,
                    state: speechState,
                    accessibilityIdentifier: voiceAccessibilityIdentifier
                )
            }
            .padding(.leading, 12)
            .padding(.trailing, 2)
            .frame(height: controlHeight)
            .frame(maxWidth: .infinity)
            .osrsFloatingGlass(
                in: osrsSearchControlGeometry.pillShape(height: controlHeight),
                fallback: Color(osrsTheme.surfaceVariant)
            )
        }
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
    }
}

/// UIKit supplies one leaf accessibility node for the search action. SwiftUI's composed Button
/// can expose its visual Text as a second font-tight StaticText even when the label visibly fits.
private struct osrsUIKitSearchLauncherButton: UIViewRepresentable {
    let title: String
    let accessibilityIdentifier: String
    let foregroundColor: UIColor
    let allowsTwoLines: Bool
    let controlHeight: CGFloat
    let action: () -> Void

    final class Coordinator: NSObject {
        var parent: osrsUIKitSearchLauncherButton

        init(parent: osrsUIKitSearchLauncherButton) {
            self.parent = parent
        }

        @objc func activate() {
            parent.action()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(context.coordinator, action: #selector(Coordinator.activate), for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
        button.isAccessibilityElement = true
        button.titleLabel?.isAccessibilityElement = false
        button.imageView?.isAccessibilityElement = false
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configure(button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIButton,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: controlHeight
        )
    }

    private func configure(_ button: UIButton) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: "magnifyingglass")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.baseForegroundColor = foregroundColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        configuration.titleLineBreakMode = allowsTwoLines ? .byWordWrapping : .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .callout)
            attributes.foregroundColor = foregroundColor
            return attributes
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = allowsTwoLines ? 2 : 1
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = title
    }
}

/// A real UITextField keeps its editable accessibility node equal to the 44pt host instead of
/// exposing only SwiftUI's font-tight glyph frame. FocusState remains the source of truth.
struct osrsUIKitSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let shouldFocus: Bool
    let onFocusChange: (Bool) -> Void
    let placeholder: String
    let accessibilityIdentifier: String
    let textColor: UIColor
    let placeholderColor: UIColor
    let tintColor: UIColor
    var controlHeight: CGFloat = osrsSearchControlGeometry.compactHeight
    let onSubmit: () -> Void

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: osrsUIKitSearchTextField
        private var pendingTextUpdate: DispatchWorkItem?
        private(set) var lastDeliveredText: String
        private var focusSynchronizationGeneration = 0

        init(parent: osrsUIKitSearchTextField) {
            self.parent = parent
            lastDeliveredText = parent.text
        }

        @objc func textChanged(_ textField: UITextField) {
            scheduleTextDelivery(textField.text ?? "")
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            deliverTextImmediately(textField.text ?? "")
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            deliverTextImmediately(textField.text ?? "")
            parent.onSubmit()
            return true
        }

        func scheduleTextDelivery(_ value: String) {
            pendingTextUpdate?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastDeliveredText = value
                self.parent.text = value
            }
            pendingTextUpdate = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
        }

        func deliverTextImmediately(_ value: String) {
            pendingTextUpdate?.cancel()
            pendingTextUpdate = nil
            lastDeliveredText = value
            parent.text = value
        }

        func synchronizeExternalText(_ value: String, in textField: UITextField) {
            guard value != lastDeliveredText else { return }
            pendingTextUpdate?.cancel()
            pendingTextUpdate = nil
            lastDeliveredText = value
            if textField.text != value {
                textField.text = value
            }
        }

        /// A FocusState change can build the representable before UIKit has attached its view
        /// to a window. Synchronize once on the next main turn, then let didMoveToWindow issue a
        /// fresh generation when attachment actually happens. This remains bounded and makes a
        /// stale focus request unable to override a newer dismiss/back transition.
        func requestFocusSynchronization(in textField: UITextField) {
            focusSynchronizationGeneration &+= 1
            let requestedGeneration = focusSynchronizationGeneration
            synchronizeFocus(
                in: textField,
                generation: requestedGeneration,
                attemptsRemaining: 3,
                delay: 0
            )
        }

        func cancelFocusSynchronization() {
            focusSynchronizationGeneration &+= 1
        }

        private func synchronizeFocus(
            in textField: UITextField,
            generation: Int,
            attemptsRemaining: Int,
            delay: TimeInterval
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak textField] in
                guard let self,
                      let textField,
                      generation == self.focusSynchronizationGeneration else { return }

                guard textField.window != nil else {
                    // didMoveToWindow will issue a new generation when attachment completes.
                    return
                }

                if self.parent.shouldFocus {
                    if !textField.isFirstResponder {
                        textField.becomeFirstResponder()
                    }
                    if !textField.isFirstResponder, attemptsRemaining > 0 {
                        // NavigationStack/system-tab transitions can briefly reject first
                        // responder status even after window attachment. Retry a fixed number of
                        // times; a newer focus/back request invalidates this generation.
                        self.synchronizeFocus(
                            in: textField,
                            generation: generation,
                            attemptsRemaining: attemptsRemaining - 1,
                            delay: 0.10
                        )
                    }
                } else if textField.isFirstResponder {
                    textField.resignFirstResponder()
                }
            }
        }
    }

    final class SearchTextField: UITextField {
        weak var focusCoordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            focusCoordinator?.requestFocusSynchronization(in: self)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = SearchTextField(frame: .zero)
        textField.focusCoordinator = context.coordinator
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = UIFont.preferredFont(forTextStyle: .callout)
        textField.adjustsFontForContentSizeCategory = true
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        configure(textField)
        context.coordinator.requestFocusSynchronization(in: textField)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        configureAppearance(textField)
        context.coordinator.synchronizeExternalText(text, in: textField)
        context.coordinator.requestFocusSynchronization(in: textField)
    }

    static func dismantleUIView(_ textField: UITextField, coordinator: Coordinator) {
        coordinator.cancelFocusSynchronization()
        coordinator.deliverTextImmediately(textField.text ?? "")
        textField.resignFirstResponder()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: controlHeight
        )
    }

    private func configure(_ textField: UITextField) {
        textField.text = text
        configureAppearance(textField)
        textField.accessibilityIdentifier = accessibilityIdentifier
    }

    private func configureAppearance(_ textField: UITextField) {
        textField.textColor = textColor
        textField.tintColor = tintColor
        let hasAttributedPlaceholder = (textField.attributedPlaceholder?.length ?? 0) > 0
        let existingPlaceholderColor = hasAttributedPlaceholder
            ? textField.attributedPlaceholder?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            : nil
        if textField.attributedPlaceholder?.string != placeholder ||
            existingPlaceholderColor != placeholderColor {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: placeholderColor]
            )
        }
        textField.accessibilityIdentifier = accessibilityIdentifier
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        osrsVoiceSearchButton(
            action: {},
            state: .idle
        )
        
        osrsVoiceSearchButton(
            action: {},
            state: .listening
        )
        
        osrsVoiceSearchButton(
            action: {},
            state: .processing
        )
    }
    .padding()
    .environment(\.osrsTheme, osrsLightTheme())
}

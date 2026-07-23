//
//  osrsThemeTransition.swift
//  OSRS Wiki
//
//  Created for iOS theme transition animations
//  Smooth transitions between OSRS light and dark themes
//

import SwiftUI

// MARK: - Theme Transition Manager

/// Manager for handling smooth theme transitions with animations
@MainActor
class osrsThemeTransitionManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Whether a theme transition is currently in progress
    @Published var isTransitioning = false
    
    /// The transition progress (0.0 to 1.0)
    @Published var transitionProgress: Double = 0.0
    
    // MARK: - Animation Configuration
    
    /// Duration of theme transition animations
    static let transitionDuration: Double = 0.6
    
    /// Animation curve for theme transitions
    static let transitionCurve = Animation.easeInOut(duration: transitionDuration)
    
    /// Delay for staggered animations
    static let staggerDelay: Double = 0.05
    
    // MARK: - Transition Methods
    
    /// Perform an animated theme transition
    /// - Parameter action: The theme change action to perform
    func animateThemeTransition(_ action: @escaping () -> Void) {
        guard !isTransitioning else { return }
        
        withAnimation(Self.transitionCurve) {
            isTransitioning = true
            transitionProgress = 0.0
        }
        
        // Perform the theme change after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            action()
            
            withAnimation(Self.transitionCurve) {
                self.transitionProgress = 1.0
            }
            
            // Reset transition state
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionDuration) {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.isTransitioning = false
                    self.transitionProgress = 0.0
                }
            }
        }
    }
    
    /// Create a staggered animation for multiple elements
    /// - Parameter index: The index of the element for staggering
    /// - Returns: An animation with appropriate delay
    static func staggeredAnimation(for index: Int) -> Animation {
        return transitionCurve.delay(Double(index) * staggerDelay)
    }
}

// MARK: - Transition View Modifier

/// View modifier for applying theme transition effects
struct osrsThemeTransitionModifier: ViewModifier {
    let transitionManager: osrsThemeTransitionManager
    let animationIndex: Int
    
    func body(content: Content) -> some View {
        content
            .opacity(transitionManager.isTransitioning ? 0.8 : 1.0)
            .scaleEffect(transitionManager.isTransitioning ? 0.98 : 1.0)
            .animation(
                osrsThemeTransitionManager.staggeredAnimation(for: animationIndex),
                value: transitionManager.isTransitioning
            )
    }
}

extension View {
    /// Apply OSRS theme transition effects
    /// - Parameters:
    ///   - transitionManager: The transition manager to use
    ///   - animationIndex: Index for staggered animations (default: 0)
    func osrsThemeTransition(
        _ transitionManager: osrsThemeTransitionManager,
        animationIndex: Int = 0
    ) -> some View {
        modifier(osrsThemeTransitionModifier(
            transitionManager: transitionManager,
            animationIndex: animationIndex
        ))
    }
}

// MARK: - Transition Effects

/// Container for various transition effects
struct osrsThemeTransitionEffects {
    
    /// Fade transition for backgrounds
    static func fadeBackground(isTransitioning: Bool) -> some View {
        Rectangle()
            .fill(.osrsBackground)
            .opacity(isTransitioning ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.8), value: isTransitioning)
    }
    
    /// Scale transition for buttons and interactive elements
    static func scaleTransition(isTransitioning: Bool, content: some View) -> some View {
        content
            .scaleEffect(isTransitioning ? 0.95 : 1.0)
            .opacity(isTransitioning ? 0.7 : 1.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isTransitioning)
    }
    
    /// Slide transition for navigation elements
    static func slideTransition(
        isTransitioning: Bool,
        offset: CGFloat = 10,
        content: some View
    ) -> some View {
        content
            .offset(y: isTransitioning ? offset : 0)
            .opacity(isTransitioning ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.5), value: isTransitioning)
    }
    
    /// Color transition for text and icons
    static func colorTransition(isTransitioning: Bool, content: some View) -> some View {
        content
            .opacity(isTransitioning ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.4), value: isTransitioning)
    }
}

// MARK: - Enhanced AppearanceSettingsView Integration

extension AppearanceSettingsView {
    /// Enhanced theme selection with animations
    func animatedThemeSelection(
        for themeSelection: osrsThemeSelection,
        transitionManager: osrsThemeTransitionManager
    ) -> some View {
        Button(action: {
            transitionManager.animateThemeTransition {
                themeManager.setTheme(themeSelection)
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(themeSelection.displayName)
                        .font(.body)
                        .foregroundStyle(.osrsOnSurface)
                    
                    Text(themeSelection.description)
                        .font(.caption)
                        .foregroundStyle(.osrsOnSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if themeManager.selectedTheme == themeSelection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.osrsPrimary)
                        .font(.body.weight(.semibold))
                        .scaleEffect(transitionManager.isTransitioning ? 1.2 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), 
                                 value: transitionManager.isTransitioning)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .osrsThemeTransition(transitionManager, animationIndex: themeSelection.hashValue)
    }
}

// MARK: - Transition Indicators

/// Visual indicator for theme transitions
struct osrsThemeTransitionIndicator: View {
    let isTransitioning: Bool
    
    var body: some View {
        if isTransitioning {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.osrsPrimaryColor)
                
                Text("Switching theme...")
                    .font(.caption)
                    .foregroundStyle(.osrsOnSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.osrsSurfaceVariant)
            .cornerRadius(20)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Transition Presets

/// Pre-configured transition animations for common UI elements
enum osrsTransitionPreset {
    case navigation
    case content
    case button
    case card
    case modal
    
    var animation: Animation {
        switch self {
        case .navigation:
            return .easeInOut(duration: 0.4)
        case .content:
            return .easeInOut(duration: 0.6)
        case .button:
            return .spring(response: 0.4, dampingFraction: 0.7)
        case .card:
            return .easeInOut(duration: 0.5)
        case .modal:
            return .spring(response: 0.6, dampingFraction: 0.8)
        }
    }
    
    var delay: Double {
        switch self {
        case .navigation:
            return 0.0
        case .content:
            return 0.1
        case .button:
            return 0.05
        case .card:
            return 0.15
        case .modal:
            return 0.0
        }
    }
}

extension View {
    /// Apply a pre-configured transition preset
    /// - Parameter preset: The transition preset to apply
    func osrsTransition(_ preset: osrsTransitionPreset, isActive: Bool) -> some View {
        self
            .opacity(isActive ? 0.8 : 1.0)
            .scaleEffect(isActive ? 0.98 : 1.0)
            .animation(preset.animation.delay(preset.delay), value: isActive)
    }
}

// MARK: - Debug and Preview Support

#if DEBUG
struct osrsThemeTransitionPreview: View {
    @StateObject private var transitionManager = osrsThemeTransitionManager()
    @StateObject private var themeManager = osrsThemeManager.preview
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Theme Transition Demo")
                .osrsHeadlineStyle()
                .foregroundStyle(.osrsOnSurface)
                .osrsThemeTransition(transitionManager)
            
            VStack(spacing: 12) {
                ForEach(osrsThemeSelection.allCases, id: \.self) { selection in
                    Button(selection.displayName) {
                        transitionManager.animateThemeTransition {
                            themeManager.setTheme(selection)
                        }
                    }
                    .font(.osrsBody)
                    .foregroundStyle(.osrsOnPrimary)
                    .padding()
                    .background(.osrsPrimary)
                    .cornerRadius(8)
                    .osrsThemeTransition(transitionManager, animationIndex: selection.hashValue)
                }
            }
            
            osrsThemeTransitionIndicator(isTransitioning: transitionManager.isTransitioning)
            
            Spacer()
        }
        .padding()
        .background(.osrsBackground)
        .environmentObject(themeManager)
        .environment(\.osrsTheme, themeManager.currentTheme)
    }
}

#Preview {
    osrsThemeTransitionPreview()
}
#endif
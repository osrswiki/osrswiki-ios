//
//  osrsVoiceSearchAnimationHelper.swift
//  osrswiki
//
//  Created on voice search implementation session
//

import SwiftUI

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
        .accessibilityLabel("Microphone")
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

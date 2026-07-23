//
//  AppLaunchCoordinator.swift
//  OSRS Wiki
//
//  Coordinates app launch operations to ensure proper sequencing
//

import SwiftUI
import UIKit

/// Coordinates app launch operations to prevent UI animations during keyboard prewarming
@MainActor
class AppLaunchCoordinator: ObservableObject {
    static let shared = AppLaunchCoordinator()
    
    // Track various UI readiness states
    @Published private(set) var isMainViewAppeared = false
    @Published private(set) var isTabBarRendered = false
    @Published private(set) var isThemeApplied = false
    @Published private(set) var isKeyboardPrewarmed = false
    
    // Callbacks for when UI is ready
    private var uiReadyCallbacks: [() -> Void] = []
    
    private init() {}
    
    /// Mark that the main view has appeared
    func markMainViewAppeared() {
        guard !isMainViewAppeared else { return }
        isMainViewAppeared = true
        checkAndTriggerIfReady()
    }
    
    /// Mark that the tab bar has been rendered
    func markTabBarRendered() {
        guard !isTabBarRendered else { return }
        isTabBarRendered = true
        checkAndTriggerIfReady()
    }
    
    /// Mark that the theme has been applied
    func markThemeApplied() {
        guard !isThemeApplied else { return }
        isThemeApplied = true
        checkAndTriggerIfReady()
    }
    
    /// Check if all UI components are ready
    var isUIReady: Bool {
        isMainViewAppeared && isTabBarRendered && isThemeApplied
    }
    
    /// Register a callback to be called when UI is ready
    func onUIReady(_ callback: @escaping () -> Void) {
        if isUIReady {
            // UI is already ready, call immediately
            callback()
        } else {
            // Store for later
            uiReadyCallbacks.append(callback)
        }
    }
    
    /// Check if ready and trigger callbacks
    private func checkAndTriggerIfReady() {
        guard isUIReady else { return }
        
        // Execute all pending callbacks
        let callbacks = uiReadyCallbacks
        uiReadyCallbacks.removeAll()
        
        for callback in callbacks {
            callback()
        }
    }
    
    /// Perform keyboard prewarming when UI is ready
    func performKeyboardPrewarmingWhenReady() {
        onUIReady { [weak self] in
            guard let self = self else { return }
            guard !self.isKeyboardPrewarmed else { return }
            
            // Disable animations during keyboard prewarming
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            
            KeyboardPrewarmer.shared.prewarmKeyboard { [weak self] in
                // Keyboard prewarming complete
                self?.isKeyboardPrewarmed = true
                
                // Re-enable animations
                CATransaction.commit()
            }
        }
    }
}
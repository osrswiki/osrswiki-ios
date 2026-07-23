//
//  KeyboardPrewarmer.swift
//  OSRS Wiki
//
//  Pre-warms the keyboard to eliminate first-show latency
//

import SwiftUI
import UIKit

class KeyboardPrewarmer {
    static let shared = KeyboardPrewarmer()
    private var hiddenTextField: UITextField?
    private var hasPrewarmed = false
    
    private init() {}
    
    /// Pre-warm the keyboard on app launch to eliminate first-show delay
    func prewarmKeyboard(completion: (() -> Void)? = nil) {
        guard !hasPrewarmed else {
            completion?()
            return
        }
        hasPrewarmed = true
        
        DispatchQueue.main.async { [weak self] in
            // Disable all animations during keyboard prewarming
            UIView.performWithoutAnimation {
                // Create a hidden text field
                let textField = UITextField()
                textField.frame = CGRect(x: -100, y: -100, width: 1, height: 1)
                textField.alpha = 0
                textField.isUserInteractionEnabled = false // Prevent any interaction
                
                // Add to the window
                if let window = UIApplication.shared.windows.first {
                    // Add the text field without animation
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    
                    window.addSubview(textField)
                    
                    // Show keyboard briefly without animation
                    textField.becomeFirstResponder()
                    
                    CATransaction.commit()
                    
                    // Hide it after a minimal delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        UIView.performWithoutAnimation {
                            CATransaction.begin()
                            CATransaction.setDisableActions(true)
                            
                            textField.resignFirstResponder()
                            textField.removeFromSuperview()
                            self?.hiddenTextField = nil
                            
                            CATransaction.commit()
                            
                            // Call completion after everything is done
                            completion?()
                        }
                    }
                    
                    self?.hiddenTextField = textField
                } else {
                    // No window available, call completion
                    completion?()
                }
            }
        }
    }
}

// View modifier to pre-warm keyboard
struct PrewarmKeyboard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                KeyboardPrewarmer.shared.prewarmKeyboard()
            }
    }
}

extension View {
    func prewarmKeyboard() -> some View {
        modifier(PrewarmKeyboard())
    }
}
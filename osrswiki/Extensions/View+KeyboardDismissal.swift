//
//  View+KeyboardDismissal.swift
//  OSRS Wiki
//
//  Extension to handle keyboard dismissal properly
//

import SwiftUI
import UIKit

extension View {
    /// Dismisses the keyboard by ending editing on all text fields
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// Force dismisses the keyboard using the window's endEditing method
    func forceKeyboardDismissal() {
        UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.endEditing(true)
    }
    
    /// Dismisses keyboard and ensures proper view layout update
    func dismissKeyboardWithLayoutUpdate() {
        // First, dismiss the keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Force end editing on the key window
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            keyWindow.endEditing(true)
        }
        
        // Trigger layout update
        DispatchQueue.main.async {
            UIApplication.shared.windows.forEach { window in
                window.setNeedsLayout()
                window.layoutIfNeeded()
            }
        }
    }
}

/// A modifier to automatically dismiss keyboard when the view disappears
struct DismissKeyboardOnDisappear: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onDisappear {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                
                // Also force end editing to ensure keyboard is fully dismissed
                if let keyWindow = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) {
                    keyWindow.endEditing(true)
                }
            }
    }
}

extension View {
    /// Automatically dismisses keyboard when view disappears
    func dismissKeyboardOnDisappear() -> some View {
        self.modifier(DismissKeyboardOnDisappear())
    }
}
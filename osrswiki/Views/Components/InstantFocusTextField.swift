//
//  InstantFocusTextField.swift
//  OSRS Wiki
//
//  Created on search focus optimization session
//  Provides immediate keyboard focus without animation delays
//

import SwiftUI
import UIKit

/// A UIViewRepresentable TextField that provides instant focus and keyboard appearance
/// This bypasses SwiftUI's focus animation delays for immediate response
struct InstantFocusTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFirstResponder: Bool
    let onSubmit: () -> Void
    let textColor: UIColor
    let tintColor: UIColor
    
    init(
        text: Binding<String>,
        placeholder: String,
        isFirstResponder: Bool,
        textColor: UIColor = .label,
        tintColor: UIColor = .systemBlue,
        onSubmit: @escaping () -> Void = {}
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isFirstResponder = isFirstResponder
        self.textColor = textColor
        self.tintColor = tintColor
        self.onSubmit = onSubmit
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.text = text
        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.font = .preferredFont(forTextStyle: .body)
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        
        // Set up instant focus if needed
        if isFirstResponder {
            // Use a small delay to ensure view is in hierarchy
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
            }
        }
        
        // Add target for text changes
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange),
            for: .editingChanged
        )
        
        return textField
    }
    
    func updateUIView(_ textField: UITextField, context: Context) {
        // Update text if different
        if textField.text != text {
            textField.text = text
        }
        
        // Update focus state
        DispatchQueue.main.async {
            if isFirstResponder && !textField.isFirstResponder {
                textField.becomeFirstResponder()
            } else if !isFirstResponder && textField.isFirstResponder {
                textField.resignFirstResponder()
            }
        }
        
        // Update colors in case of theme change
        textField.textColor = textColor
        textField.tintColor = tintColor
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: InstantFocusTextField
        
        init(_ parent: InstantFocusTextField) {
            self.parent = parent
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
        
        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            parent.text = ""
            return true
        }
    }
}

/// Helper view modifier to preload keyboard on view appearance
struct KeyboardPreloader: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Subscribe to keyboard notifications to detect when keyboard appears
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillShowNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
    }
}

extension View {
    /// Preloads the keyboard for faster appearance
    func preloadKeyboard() -> some View {
        self.modifier(KeyboardPreloader())
    }
}

/// Optimized search text field that provides instant focus
struct OptimizedSearchField: View {
    @Binding var text: String
    @FocusState var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        InstantFocusTextField(
            text: $text,
            placeholder: placeholder,
            isFirstResponder: isFocused,
            textColor: UIColor(osrsTheme.primaryTextColor),
            tintColor: UIColor(osrsTheme.primary),
            onSubmit: onSubmit
        )
    }
}
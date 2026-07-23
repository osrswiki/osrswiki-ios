//
//  FocusHelper.swift
//  OSRS Wiki
//
//  Helper for managing text field focus without delays
//

import SwiftUI

/// View modifier that immediately focuses a text field when a condition is met
struct ImmediateFocus: ViewModifier {
    @FocusState private var isFocused: Bool
    let shouldFocus: Bool
    
    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: shouldFocus) { _, newValue in
                if newValue {
                    isFocused = true
                }
            }
            .onAppear {
                if shouldFocus {
                    isFocused = true
                }
            }
    }
}

/// View modifier that auto-focuses on appear
struct AutoFocus: ViewModifier {
    @FocusState private var isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
    }
}

extension View {
    /// Immediately focuses when condition is true
    func immediateFocus(when condition: Bool) -> some View {
        modifier(ImmediateFocus(shouldFocus: condition))
    }
    
    /// Auto-focuses the field on appear
    func autoFocus() -> some View {
        modifier(AutoFocus())
    }
}

/// Environment key for keyboard preloading
struct KeyboardPreloadKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var preloadKeyboard: Bool {
        get { self[KeyboardPreloadKey.self] }
        set { self[KeyboardPreloadKey.self] = newValue }
    }
}

/// View that preloads the keyboard for faster appearance
struct KeyboardPreloaderView: View {
    @State private var dummyText = ""
    @FocusState private var dummyFocus: Bool
    
    var body: some View {
        TextField("", text: $dummyText)
            .focused($dummyFocus)
            .frame(width: 0, height: 0)
            .opacity(0)
            .onAppear {
                // Briefly focus to load keyboard, then unfocus
                dummyFocus = true
                DispatchQueue.main.async {
                    dummyFocus = false
                }
            }
    }
}
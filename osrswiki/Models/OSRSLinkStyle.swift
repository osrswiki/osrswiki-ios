//
//  OSRSLinkStyle.swift
//  osrswiki
//
//  Created by Claude for iOS-Android link font weight consistency
//

import SwiftUI

/// Custom ViewModifier that makes text appear as a "link" with heavier font weight
struct OSRSLinkTextModifier: ViewModifier {
    let fontSize: CGFloat
    
    init(fontSize: CGFloat = 17) {
        self.fontSize = fontSize
    }
    
    func body(content: Content) -> some View {
        content.font(.body.weight(.medium))
    }
}

/// Custom ButtonStyle that makes button text appear as a "link" with heavier font weight
struct OSRSLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold) // Make button link text heavier
            .opacity(configuration.isPressed ? 0.7 : 1.0) // Pressed state feedback
    }
}

/// Extensions for applying link styling to specific elements
extension View {
    /// Applies heavier font weight to Text elements that act as links
    /// Use this for individual Text views that should appear as links
    func osrsLinkText(fontSize: CGFloat = 17) -> some View {
        self.modifier(OSRSLinkTextModifier(fontSize: fontSize))
    }
    
    /// Applies heavier font weight to Button elements that act as links
    /// Use this for Button views that should appear as clickable links
    func osrsLinkButton() -> some View {
        self.buttonStyle(OSRSLinkButtonStyle())
    }
}
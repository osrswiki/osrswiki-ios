//
//  osrsContentsReveal.swift
//  osrswiki
//
//  Hit-testing rules for the article table-of-contents overlay.
//

import CoreGraphics
import SwiftUI

enum osrsContentsReveal {
    static func isVisuallyOpen(isPresented: Bool, interactiveProgress: CGFloat) -> Bool {
        isPresented || interactiveProgress > 0.02
    }

    static func allowsOverlayHitTesting(isPresented: Bool, interactiveProgress: CGFloat) -> Bool {
        isVisuallyOpen(isPresented: isPresented, interactiveProgress: interactiveProgress)
    }

    /// Finger-follow uses a disabled transaction. After lift, this spring is
    /// sampled every display frame; interpolatingSpring plus glass snapshots
    /// dropped ProMotion after the finger left the screen.
    static var settleAnimation: Animation {
        .interactiveSpring(response: 0.30, dampingFraction: 0.92, blendDuration: 0)
    }
}

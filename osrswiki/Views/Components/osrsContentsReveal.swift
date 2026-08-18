//
//  osrsContentsReveal.swift
//  osrswiki
//
//  Hit-testing rules for the article table-of-contents overlay.
//

import CoreGraphics

enum osrsContentsReveal {
    static func isVisuallyOpen(isPresented: Bool, interactiveProgress: CGFloat) -> Bool {
        isPresented || interactiveProgress > 0.02
    }

    static func allowsOverlayHitTesting(isPresented: Bool, interactiveProgress: CGFloat) -> Bool {
        isVisuallyOpen(isPresented: isPresented, interactiveProgress: interactiveProgress)
    }
}

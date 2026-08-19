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

    /// Finger-follow uses a disabled transaction. After lift, continue with the
    /// same velocity-matched interpolating spring used by the article swipe so
    /// the coast is not a second animation from rest.
    static func settleAnimation(
        from: CGFloat,
        to: CGFloat,
        velocity: CGFloat
    ) -> Animation {
        osrsInteractiveArticleSwipe.settleAnimation(
            from: from,
            to: to,
            velocity: velocity,
            distance: osrsInteractiveArticleSwipe.contentsDrawerWidth
        )
    }
}

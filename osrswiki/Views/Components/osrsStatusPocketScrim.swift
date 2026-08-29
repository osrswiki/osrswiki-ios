//
//  osrsStatusPocketScrim.swift
//  OSRS Wiki
//
//  Theme-gradient scrim for the status pocket. iOS 26 roots hide the nav bar,
//  so scrolled content (Home cards, Search rows, Saved list, Map tiles, More
//  root, Article) otherwise collides with the clock/battery cluster.
//
//  Physical-top overlay. Do not move into the topInset-padded chrome helpers
//  (paired-edge chrome / tab glass accessory bar) — they lay out below the
//  status pocket and would paint the search-pill band instead.
//

import SwiftUI

struct osrsStatusPocketScrim: View {
    @Environment(\.osrsTheme) private var osrsTheme

    var body: some View {
        LinearGradient(
            colors: [osrsTheme.background, osrsTheme.background.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: osrsOverlayChromeMetrics.topInset + 20)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

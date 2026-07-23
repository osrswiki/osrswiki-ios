//
//  osrsAccessibilityMarker.swift
//  OSRS Wiki
//
//  Invisible DEBUG-only accessibility anchors for UI conformance tests.
//

import SwiftUI

struct osrsAccessibilityMarker: View {
    let identifier: String
    let label: String

    var body: some View {
#if DEBUG
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
#else
        EmptyView()
#endif
    }
}

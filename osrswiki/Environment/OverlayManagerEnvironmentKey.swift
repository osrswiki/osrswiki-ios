//
//  OverlayManagerEnvironmentKey.swift
//  osrswiki
//
//  Environment key for GlobalOverlayManager to handle optional access
//

import SwiftUI

struct OverlayManagerEnvironmentKey: EnvironmentKey {
    static let defaultValue: GlobalOverlayManager? = nil
}

extension EnvironmentValues {
    var overlayManager: GlobalOverlayManager? {
        get { self[OverlayManagerEnvironmentKey.self] }
        set { self[OverlayManagerEnvironmentKey.self] = newValue }
    }
}

extension View {
    func overlayManager(_ manager: GlobalOverlayManager?) -> some View {
        environment(\.overlayManager, manager)
    }
}
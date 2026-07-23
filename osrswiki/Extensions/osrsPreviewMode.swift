//
//  osrsPreviewMode.swift
//  OSRS Wiki
//
//  Environment key for enabling preview mode in components to avoid AsyncImage issues in testing
//

import SwiftUI

/// Environment key for enabling preview rendering mode
struct osrsPreviewModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var osrsPreviewMode: Bool {
        get { self[osrsPreviewModeKey.self] }
        set { self[osrsPreviewModeKey.self] = newValue }
    }
}
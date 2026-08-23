//
//  osrsLoadPerformancePrefs.swift
//  osrswiki
//
//  Process-local load performance flags (parity with Android Prefs @Volatile load flags).
//

import Foundation

enum osrsLoadPerformancePrefs {
    /// Live article HTML inlines first-paint CSS (parity with saved `inlineFirstPaintCss: true`).
    /// Set `false` for one-commit rollback of Phase B Task 7.
    static var inlineLiveFirstPaintCss: Bool = true

    /// When true, HTML uses one minified critical bundle instead of ten sheets.
    /// Default false until Task 9 accepts the bundle (Phase B Task 7b).
    static var useCriticalArticleBundle: Bool = false
}

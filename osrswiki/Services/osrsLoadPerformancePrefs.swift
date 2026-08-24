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
    /// Default true: production uses the Task 7b bundle on the Task 7 live inline path
    /// (`inlineLiveFirstPaintCss`). Flip to false for one-commit rollback to per-file
    /// critical sheets. Body reveal stays FirstViewPainted; settled is stopwatch-only.
    static var useCriticalArticleBundle: Bool = true

    /// When true, live opens extract first-viewport slot image URLs from HTML and
    /// fetch them before `loadHTMLString`. Decode → FirstViewPainted is unchanged;
    /// this only requests slot URLs sooner. Flip to false to roll back Task 10.
    static var warmFirstViewportImagesEarly: Bool = true

    /// When true, FirstViewPainted waits only on intersecting media plus the
    /// authored-default switcher pane (not the full switcher pool / every srcset
    /// candidate), and the early first-view warmer extracts the slot only — not
    /// the full document URL list. Flip to false to roll back the post-Task-10
    /// painted-set cut. Reveal stays FirstViewPainted.
    static var narrowFirstViewportPaintedSet: Bool = true

    /// When true, live HTML inlines the critical bundle (+ platform aesthetics)
    /// and restores `wiki-integration.css` / `navbox_styles.css` to the existing
    /// `media=print` onload deferred-link path. Saved/offline stays fully inlined.
    /// Flip to false to roll back thousand-cuts slice 2.
    static var deferLiveWikiFidelityCss: Bool = true
}

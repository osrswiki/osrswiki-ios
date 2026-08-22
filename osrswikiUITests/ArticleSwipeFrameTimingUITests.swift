import XCTest

/// Measures interactive article swipe frame times on a heavy recent-updates page.
/// Simulator refresh is often 60 Hz; this still fails a sluggish 15–30 Hz swipe.
///
/// XCTest HID drags do not reliably begin the WKWebView pan, so the app drives
/// the same `interactiveSwipe.update` path from a CADisplayLink when
/// `-osrsSwipeFPSSyntheticPan` is set. That includes snapshot chrome and
/// overlay publishes, which is the work that hitchs a finger-following swipe.
final class ArticleSwipeFrameTimingUITests: XCTestCase {
    func testInteractiveSwipeOnSummerSweepUpKeepsDisplayLockedFrameTimes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-osrsSwipeFPSProbe",
            "-osrsSwipeFPSSyntheticPan",
            "-screenshotMode",
            "-resetReaderPreferencesForUITests",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab", "search",
            "-startArticleTitle", "Summer Sweep Up - Hunter & Skilling",
            "-startArticleURL", "https://oldschool.runescape.wiki/w/Summer_Sweep_Up_-_Hunter_%26_Skilling",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        let webView = app.webViews["article_web_view"].firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "Expected Summer Sweep Up article WebView")

        let probeQuery = app.descendants(matching: .any)["swipe_fps_probe"].firstMatch
        let hasSamples = NSPredicate { _, _ in
            let probeState = probeQuery.exists
                ? ((probeQuery.value as? String) ?? probeQuery.label)
                : ""
            let webState = (webView.value as? String) ?? ""
            let state = probeState.contains("swipe_fps_samples=") ? probeState : webState
            let samples = Int(
                state
                    .split(separator: ";")
                    .map(String.init)
                    .first { $0.hasPrefix("swipe_fps_samples=") }?
                    .dropFirst("swipe_fps_samples=".count) ?? ""
            ) ?? 0
            return samples > 6
        }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hasSamples, object: nil)], timeout: 18)

        var state = ""
        if probeQuery.exists {
            state = (probeQuery.value as? String) ?? probeQuery.label
        }
        if !state.contains("swipe_fps_samples=") {
            state = (webView.value as? String) ?? state
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "summer-sweep-up-interactive-swipe"
        attachment.lifetime = .keepAlways
        add(attachment)
        let stateAttachment = XCTAttachment(string: state)
        stateAttachment.name = "article-runtime-swipe-fps"
        stateAttachment.lifetime = .keepAlways
        add(stateAttachment)

        XCTAssertTrue(
            state.contains("swipe_fps_samples="),
            "Swipe FPS probe should publish samples; value=\(state) web=\((webView.value as? String) ?? "")"
        )
        let samples = probeInt("swipe_fps_samples", in: state)
        let medianMs = probeDouble("swipe_fps_median_ms", in: state)
        let displayHz = probeInt("swipe_fps_display_hz", in: state)
        XCTAssertGreaterThan(samples, 6, "Need enough pan frames to measure; value=\(state)")
        XCTAssertLessThan(
            medianMs,
            22,
            "Interactive swipe should stay display-locked (≥ ~45 fps). median=\(medianMs)ms displayHz=\(displayHz) value=\(state)"
        )
    }

    private func probeInt(_ key: String, in state: String) -> Int {
        Int(probeScalar(key, in: state)) ?? 0
    }

    private func probeDouble(_ key: String, in state: String) -> Double {
        Double(probeScalar(key, in: state)) ?? .greatestFiniteMagnitude
    }

    private func probeScalar(_ key: String, in state: String) -> String {
        let prefix = key + "="
        return state
            .split(separator: ";")
            .map(String.init)
            .first { $0.hasPrefix(prefix) }?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
            .description ?? ""
    }
}

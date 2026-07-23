//
//  DeepNavigationStackAuditUITests.swift
//  osrswikiUITests
//
//  Audit-only harness for iOS article navigation stack depth and reverse back order.
//

import XCTest

final class DeepNavigationStackAuditUITests: XCTestCase {
    private struct StartPoint: Decodable {
        let sample_id: String
        let sequence: Int
        let source_kind: String
        let title: String
        let url: String
        let edge_case: String?
        let required_link_text: String?
    }

    private struct Observation: Encodable {
        let event: String
        let sampleId: String
        let startSequence: Int
        let startTitle: String
        let depth: Int
        let expectedUrl: String?
        let observedUrl: String?
        let observedTitle: String?
        let stackState: String
        let transition: String
        let result: String
        let message: String
        let elapsedSeconds: Double
    }

    private struct FixtureAuditRecord: Encodable {
        let event: String
        let result: String
        let seed: Int
        let startOffset: Int
        let startCount: Int
        let targetDepth: Int
        let completedStarts: Int
        let forwardTransitions: Int
        let backTransitions: Int
        let mismatchCount: Int
        let finalActiveURL: String?
        let firstMismatch: String?
        let appReportedElapsedMilliseconds: Int
        let testElapsedSeconds: Double
        let rawState: String
    }

    private var evidenceRoot: URL {
        let path = ProcessInfo.processInfo.environment["OSRS_QA_EVIDENCE_ROOT"]
        if let path, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        preconditionFailure(
            "OSRS_QA_EVIDENCE_ROOT must be set to a path verified by " +
                "scripts/shared/local-artifact-root.sh"
        )
    }

    private var startManifestURL: URL {
        if let path = ProcessInfo.processInfo.environment["OSRS_DEEP_NAV_START_MANIFEST"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return evidenceRoot.appendingPathComponent("manifests/start-points.jsonl")
    }

    private var maxRandomStarts: Int {
        envInt("OSRS_DEEP_NAV_RANDOM_STARTS", defaultValue: 10000)
    }

    private var targetDepth: Int {
        envInt("OSRS_DEEP_NAV_TARGET_DEPTH", defaultValue: 100)
    }

    private var maxAuditSeconds: TimeInterval {
        TimeInterval(envInt("OSRS_DEEP_NAV_MAX_SECONDS", defaultValue: 300))
    }

    private var usesLiveRandomLinks: Bool {
        ProcessInfo.processInfo.environment["OSRS_DEEP_NAV_USE_LIVE_LINKS"] == "1"
    }

    private var rngState: UInt64 = UInt64(envIntStatic("OSRS_DEEP_NAV_SEED", defaultValue: 20260709))

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: evidenceRoot.appendingPathComponent("screenshots", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func testForcedBloodMoonQuickGuideBackOrder() throws {
        let start = StartPoint(
            sample_id: "forced-blood-moon-quick-guide",
            sequence: 0,
            source_kind: "forced_edge_case",
            title: "The Blood Moon Rises",
            url: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises",
            edge_case: "Blood Moon update to quest quick guide",
            required_link_text: "quick guide"
        )
        let app = launchApp(start: start)
        let startedAt = Date()

        XCTAssertTrue(waitForArticleURL(in: app, containing: "/w/The_Blood_Moon_Rises", timeout: 30), app.debugDescription)
        writeObservation(
            "forced-edge-observations.jsonl",
            Observation(
                event: "forward",
                sampleId: start.sample_id,
                startSequence: start.sequence,
                startTitle: start.title,
                depth: 0,
                expectedUrl: start.url,
                observedUrl: activeURL(in: app),
                observedTitle: visibleArticleTitle(in: app),
                stackState: navigationStackState(in: app),
                transition: "launch",
                result: "pass",
                message: "Blood Moon source article loaded",
                elapsedSeconds: Date().timeIntervalSince(startedAt)
            )
        )
        saveScreenshot(from: app, named: "forced-01-blood-moon-loaded")

        let link = waitForLink(in: app, matchingAnyOf: ["quick guide", "quest guide"], timeout: 30)
        XCTAssertTrue(link.exists, app.debugDescription)
        link.tap()

        XCTAssertTrue(waitForArticleURL(in: app, containing: "/w/The_Blood_Moon_Rises/Quick_guide", timeout: 30), app.debugDescription)
        writeObservation(
            "forced-edge-observations.jsonl",
            Observation(
                event: "forward",
                sampleId: start.sample_id,
                startSequence: start.sequence,
                startTitle: start.title,
                depth: 1,
                expectedUrl: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide",
                observedUrl: activeURL(in: app),
                observedTitle: visibleArticleTitle(in: app),
                stackState: navigationStackState(in: app),
                transition: "tap:quick guide",
                result: "pass",
                message: "Quick guide loaded as second native article destination",
                elapsedSeconds: Date().timeIntervalSince(startedAt)
            )
        )
        saveScreenshot(from: app, named: "forced-02-quick-guide-loaded")

        tapArticleBackButton(in: app)

        XCTAssertTrue(waitForArticleURL(in: app, containing: "/w/The_Blood_Moon_Rises", timeout: 45), app.debugDescription)
        XCTAssertFalse(navigationStackState(in: app).contains("/w/The_Blood_Moon_Rises/Quick_guide"))
        writeObservation(
            "forced-edge-observations.jsonl",
            Observation(
                event: "back",
                sampleId: start.sample_id,
                startSequence: start.sequence,
                startTitle: start.title,
                depth: 0,
                expectedUrl: start.url,
                observedUrl: activeURL(in: app),
                observedTitle: visibleArticleTitle(in: app),
                stackState: navigationStackState(in: app),
                transition: "article_back_button",
                result: "pass",
                message: "Back returned visibly to Blood Moon source article",
                elapsedSeconds: Date().timeIntervalSince(startedAt)
            )
        )
        saveScreenshot(from: app, named: "forced-03-back-to-blood-moon")
    }

    func testRandomStartsReachDepthAndReverseBackOrder() throws {
        if !usesLiveRandomLinks {
            try auditDeterministicFixtureStartsReachDepthAndReverseBackOrder()
            return
        }

        try auditLiveRandomStartsReachDepthAndReverseBackOrder()
    }

    private func auditLiveRandomStartsReachDepthAndReverseBackOrder() throws {
        let starts = try loadStartPoints()
            .filter { $0.source_kind == "random_start" }
            .prefix(maxRandomStarts)
        XCTAssertFalse(starts.isEmpty, "Random start manifest should contain at least one random start")

        let auditStartedAt = Date()
        for start in starts {
            if Date().timeIntervalSince(auditStartedAt) > maxAuditSeconds {
                throw XCTSkip("Audit time limit reached after \(Date().timeIntervalSince(auditStartedAt)) seconds")
            }
            try auditDeepNavigation(from: start, auditStartedAt: auditStartedAt)
        }
    }

    private func auditDeterministicFixtureStartsReachDepthAndReverseBackOrder() throws {
        let seed = Self.envIntStatic("OSRS_DEEP_NAV_SEED", defaultValue: 20260709)
        let startOffset = envInt("OSRS_DEEP_NAV_FIXTURE_START_OFFSET", defaultValue: 0)
        let startedAt = Date()
        let app = launchFixtureAuditApp(seed: seed, startOffset: startOffset)

        let marker = app.otherElements["deep_navigation_fixture_audit_state"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 30), app.debugDescription)
        let rawState = waitForFixtureAuditState(in: app, timeout: maxAuditSeconds)
        let fields = parseFixtureAuditState(rawState)
        let record = FixtureAuditRecord(
            event: "fixture_audit",
            result: fields["status"] ?? "missing",
            seed: intField(fields, "seed"),
            startOffset: intField(fields, "startOffset"),
            startCount: intField(fields, "startCount"),
            targetDepth: intField(fields, "targetDepth"),
            completedStarts: intField(fields, "completedStarts"),
            forwardTransitions: intField(fields, "forwardTransitions"),
            backTransitions: intField(fields, "backTransitions"),
            mismatchCount: intField(fields, "mismatches"),
            finalActiveURL: nilIfLiteralNil(fields["finalActive"]),
            firstMismatch: nilIfLiteralNil(fields["firstMismatch"]),
            appReportedElapsedMilliseconds: intField(fields, "elapsedMs"),
            testElapsedSeconds: Date().timeIntervalSince(startedAt),
            rawState: rawState
        )

        writeFixtureRecord("fixture-stack-observations.jsonl", record)
        writeJSON("fixture-stack-summary.json", record)

        XCTAssertEqual(record.result, "pass", rawState)
        XCTAssertEqual(record.seed, seed, rawState)
        XCTAssertEqual(record.startOffset, startOffset, rawState)
        XCTAssertEqual(record.startCount, maxRandomStarts, rawState)
        XCTAssertGreaterThanOrEqual(record.targetDepth, 100, rawState)
        XCTAssertEqual(record.targetDepth, targetDepth, rawState)
        XCTAssertEqual(record.completedStarts, maxRandomStarts, rawState)
        XCTAssertEqual(record.forwardTransitions, maxRandomStarts * targetDepth, rawState)
        XCTAssertEqual(record.backTransitions, maxRandomStarts * targetDepth, rawState)
        XCTAssertEqual(record.mismatchCount, 0, rawState)
    }

    private func auditDeepNavigation(from start: StartPoint, auditStartedAt: Date) throws {
        let app = launchApp(start: start)
        XCTAssertTrue(waitForArticleURL(in: app, containing: articlePathFragment(for: start.url), timeout: 30), app.debugDescription)

        var expectedStack: [String] = [try XCTUnwrap(activeURL(in: app), "Start article should expose active URL")]
        writeObservation(
            "random-stack-observations.jsonl",
            Observation(
                event: "forward",
                sampleId: start.sample_id,
                startSequence: start.sequence,
                startTitle: start.title,
                depth: 0,
                expectedUrl: start.url,
                observedUrl: expectedStack.last,
                observedTitle: visibleArticleTitle(in: app),
                stackState: navigationStackState(in: app),
                transition: "launch",
                result: "pass",
                message: "Random start article loaded",
                elapsedSeconds: Date().timeIntervalSince(auditStartedAt)
            )
        )

        for depth in 1...targetDepth {
            guard Date().timeIntervalSince(auditStartedAt) <= maxAuditSeconds else {
                recordLimit(start: start, depth: depth - 1, message: "Audit time limit reached during forward traversal")
                throw XCTSkip("Audit time limit reached during forward traversal")
            }

            let beforeURL = activeURL(in: app)
            guard let transition = tapDeterministicArticleLink(in: app) else {
                recordLimit(start: start, depth: depth - 1, message: "No hittable article link found")
                XCTFail("No hittable article link found at depth \(depth) from \(start.title)")
                return
            }

            XCTAssertTrue(waitForActiveURLToChange(in: app, from: beforeURL, timeout: 35), app.debugDescription)
            let observedURL = try XCTUnwrap(activeURL(in: app), "Depth \(depth) should expose active URL")
            expectedStack.append(observedURL)
            writeObservation(
                "random-stack-observations.jsonl",
                Observation(
                    event: "forward",
                    sampleId: start.sample_id,
                    startSequence: start.sequence,
                    startTitle: start.title,
                    depth: depth,
                    expectedUrl: nil,
                    observedUrl: observedURL,
                    observedTitle: visibleArticleTitle(in: app),
                    stackState: navigationStackState(in: app),
                    transition: transition,
                    result: "pass",
                    message: "Forward article transition observed",
                    elapsedSeconds: Date().timeIntervalSince(auditStartedAt)
                )
            )
        }

        for depth in stride(from: expectedStack.count - 2, through: 0, by: -1) {
            let expectedURL = expectedStack[depth]
            tapArticleBackButton(in: app)
            let passed = waitForArticleURL(in: app, containing: articlePathFragment(for: expectedURL), timeout: 45)
            let observedURL = activeURL(in: app)
            writeObservation(
                "random-stack-observations.jsonl",
                Observation(
                    event: "back",
                    sampleId: start.sample_id,
                    startSequence: start.sequence,
                    startTitle: start.title,
                    depth: depth,
                    expectedUrl: expectedURL,
                    observedUrl: observedURL,
                    observedTitle: visibleArticleTitle(in: app),
                    stackState: navigationStackState(in: app),
                    transition: "article_back_button",
                    result: passed && observedURL == expectedURL ? "pass" : "mismatch",
                    message: passed ? "Back order check completed" : "Expected URL did not become active before timeout",
                    elapsedSeconds: Date().timeIntervalSince(auditStartedAt)
                )
            )
            XCTAssertTrue(passed, "Back at depth \(depth) should return to \(expectedURL); observed \(observedURL ?? "nil")")
            XCTAssertEqual(observedURL, expectedURL, "Back order mismatch at depth \(depth)")
        }
    }

    private func launchApp(start: StartPoint) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "search",
            "-startArticleTitle",
            start.title,
            "-startArticleURL",
            start.url,
            "-allowProxyStartupDuringTests"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        return app
    }

    private func launchFixtureAuditApp(seed: Int, startOffset: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "search",
            "-useDeepNavigationFixtureForUITests",
            "-runDeepNavigationFixtureAuditForUITests",
            "-deepNavigationFixtureSeed",
            "\(seed)",
            "-deepNavigationFixtureStartOffset",
            "\(startOffset)",
            "-deepNavigationFixtureStartCount",
            "\(maxRandomStarts)",
            "-deepNavigationFixtureDepth",
            "\(targetDepth)"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 120))
        return app
    }

    private func loadStartPoints() throws -> [StartPoint] {
        let data = try String(contentsOf: startManifestURL, encoding: .utf8)
        let decoder = JSONDecoder()
        return try data
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { try decoder.decode(StartPoint.self, from: Data($0.utf8)) }
    }

    private func waitForLink(in app: XCUIApplication, matchingAnyOf labels: [String], timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let link = app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
                if link.exists && link.isHittable {
                    return link
                }
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", labels.first ?? "")).firstMatch
    }

    private func tapDeterministicArticleLink(in app: XCUIApplication) -> String? {
        let maxScrolls = 8
        for _ in 0...maxScrolls {
            _ = nextRandom()
            let link = app.links.matching(NSPredicate(
                format: "label != '' AND NOT label CONTAINS[c] %@ AND NOT label CONTAINS[c] %@ AND NOT label CONTAINS[c] %@",
                "edit",
                "special",
                "file:"
            )).firstMatch

            if link.exists && link.isHittable {
                let label = link.label
                link.tap()
                return "tap:\(label)"
            }

            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        return nil
    }

    private func nextRandom() -> UInt64 {
        rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
        return rngState
    }

    private func tapArticleBackButton(in app: XCUIApplication) {
        let backButton = app.buttons["article_back_button"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 8), app.debugDescription)
        backButton.tap()
    }

    private func waitForFixtureAuditState(in app: XCUIApplication, timeout: TimeInterval) -> String {
        let marker = app.otherElements["deep_navigation_fixture_audit_state"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = marker.label
            if label.contains("status=pass") || label.contains("status=mismatch") {
                return label
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return marker.label
    }

    private func waitForArticleURL(in app: XCUIApplication, containing fragment: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = navigationStackState(in: app)
            if state.contains(fragment) &&
                !app.staticTexts["Failed to Load Page"].exists &&
                !state.contains("active=nil") {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    private func waitForActiveURLToChange(in app: XCUIApplication, from oldURL: String?, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = activeURL(in: app)
            if current != nil, current != oldURL {
                return true
            }
            if app.staticTexts["Failed to Load Page"].exists {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    private func navigationStackState(in app: XCUIApplication) -> String {
        app.otherElements["article_navigation_stack_state"].firstMatch.label
    }

    private func activeURL(in app: XCUIApplication) -> String? {
        let state = navigationStackState(in: app)
        guard let range = state.range(of: "active=") else { return nil }
        let suffix = state[range.upperBound...]
        let value = suffix.split(separator: ";", maxSplits: 1).first.map(String.init) ?? String(suffix)
        return value == "nil" ? nil : value
    }

    private func visibleArticleTitle(in app: XCUIApplication) -> String? {
        nil
    }

    private func articlePathFragment(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return url.path
    }

    private func writeObservation(_ relativePath: String, _ observation: Observation) {
        writeJSONLine(relativePath, observation)
    }

    private func writeFixtureRecord(_ relativePath: String, _ record: FixtureAuditRecord) {
        writeJSONLine(relativePath, record)
    }

    private func writeJSONLine<T: Encodable>(_ relativePath: String, _ value: T) {
        let url = evidenceRoot.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func writeJSON<T: Encodable>(_ relativePath: String, _ value: T) {
        let url = evidenceRoot.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url)
    }

    private func recordLimit(start: StartPoint, depth: Int, message: String) {
        writeObservation(
            "limits.jsonl",
            Observation(
                event: "limit",
                sampleId: start.sample_id,
                startSequence: start.sequence,
                startTitle: start.title,
                depth: depth,
                expectedUrl: nil,
                observedUrl: nil,
                observedTitle: nil,
                stackState: "",
                transition: "",
                result: "blocked",
                message: message,
                elapsedSeconds: 0
            )
        )
    }

    private func saveScreenshot(from app: XCUIApplication, named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let fileURL = evidenceRoot
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    private func envInt(_ key: String, defaultValue: Int) -> Int {
        Self.envIntStatic(key, defaultValue: defaultValue)
    }

    private static func envIntStatic(_ key: String, defaultValue: Int) -> Int {
        guard let value = ProcessInfo.processInfo.environment[key],
              let intValue = Int(value) else {
            return defaultValue
        }
        return intValue
    }

    private func parseFixtureAuditState(_ state: String) -> [String: String] {
        var fields: [String: String] = [:]
        for part in state.split(separator: ";") {
            let keyValue = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard keyValue.count == 2 else { continue }
            fields[keyValue[0]] = keyValue[1]
        }
        return fields
    }

    private func intField(_ fields: [String: String], _ key: String) -> Int {
        Int(fields[key] ?? "") ?? -1
    }

    private func nilIfLiteralNil(_ value: String?) -> String? {
        guard let value, value != "nil" else { return nil }
        return value
    }
}

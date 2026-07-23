import XCTest

final class HomeBlankBelowNewsRegressionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var evidenceDirectory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        if let path = ProcessInfo.processInfo.environment["OSRS_HOME_BLANK_EVIDENCE_DIR"], !path.isEmpty {
            evidenceDirectory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: evidenceDirectory!, withIntermediateDirectories: true)
        }
    }

    func testHomeSectionsBelowUpdatesRenderInCleanLaunch() throws {
        app.launch()
        try captureHomeBelowUpdatesEvidence(prefix: "clean")
    }

    func testHomeSectionsBelowUpdatesRenderAfterRelaunchWithCache() throws {
        app.launch()
        try captureHomeBelowUpdatesEvidence(prefix: "cached-initial")

        app.terminate()
        app.launch()
        try captureHomeBelowUpdatesEvidence(prefix: "cached-relaunch")
    }

    private func captureHomeBelowUpdatesEvidence(prefix: String) throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch to the foreground")

        let searchField = app.staticTexts["Search OSRS Wiki"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 20), "Home search field should be visible")

        saveScreenshot(named: "\(prefix)-top")
        saveDebugDescription(named: "\(prefix)-top-tree")

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "Home should expose a scroll view")

        let announcements = app.staticTexts["Announcements"].firstMatch
        let onThisDay = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'On this day'")).firstMatch
        let popularPages = app.staticTexts["Popular pages"].firstMatch

        for index in 0..<5 where !popularPages.isHittable {
            scrollView.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            saveScreenshot(named: "\(prefix)-scroll-\(index + 1)")
        }

        saveDebugDescription(named: "\(prefix)-below-updates-tree")

        XCTAssertTrue(announcements.exists, "Announcements should be present below Updates")
        XCTAssertTrue(onThisDay.exists, "On this day should be present below Updates")
        XCTAssertTrue(popularPages.exists, "Popular pages should be present below Updates")
    }

    private func saveScreenshot(named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let evidenceDirectory else { return }
        let url = evidenceDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    private func saveDebugDescription(named name: String) {
        let description = app.debugDescription
        let attachment = XCTAttachment(string: description)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let evidenceDirectory else { return }
        let url = evidenceDirectory.appendingPathComponent("\(name).txt")
        try? description.write(to: url, atomically: true, encoding: .utf8)
    }
}

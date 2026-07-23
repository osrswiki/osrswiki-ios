//
//  InternalWikiLinkRoutingUITests.swift
//  osrswikiUITests
//

import XCTest

final class InternalWikiLinkRoutingUITests: XCTestCase {
    private var evidenceRoot: URL? {
        guard let path = ProcessInfo.processInfo.environment["OSRS_QA_EVIDENCE_ROOT"],
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func testBloodMoonQuickGuideLinkRoutesThroughArticleViewer() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "search",
            "-startArticleTitle",
            "The Blood Moon Rises",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(app.staticTexts["The Blood Moon Rises"].waitForExistence(timeout: 20))

        let webView = app.webViews["article_web_view"].firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25))

        let quickGuideLink = app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "quick guide")).firstMatch
        XCTAssertTrue(quickGuideLink.waitForExistence(timeout: 20), app.debugDescription)

        quickGuideLink.tap()

        XCTAssertTrue(app.staticTexts["The Blood Moon Rises/Quick guide"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews["article_web_view"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Blood Moon quick guide routed in article viewer"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBloodMoonQuickGuideBackReturnsToBloodMoonArticle() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "search",
            "-startArticleTitle",
            "The Blood Moon Rises",
            "-startArticleURL",
            "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises",
            "-allowProxyStartupDuringTests"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        XCTAssertTrue(
            waitForVisibleText(in: app, containing: "The Blood Moon Rises", timeout: 25),
            app.debugDescription
        )
        saveScreenshot(from: app, named: "01-blood-moon-page-loaded")

        let questGuideLink = waitForLink(
            in: app,
            matchingAnyOf: ["quest guide", "quick guide"],
            timeout: 25
        )
        XCTAssertTrue(questGuideLink.exists, app.debugDescription)
        questGuideLink.tap()

        XCTAssertTrue(
            waitForVisibleText(in: app, containing: "The Blood Moon Rises/Quick guide", timeout: 25),
            app.debugDescription
        )
        XCTAssertTrue(
            waitForNavigationStackState(
                in: app,
                containing: [
                    "selected=search",
                    "search=2",
                    "active=https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"
                ],
                timeout: 10
            ),
            "Quick guide should create a second native Search article destination before Back. State: \(navigationStackState(in: app))"
        )
        saveScreenshot(from: app, named: "02-quick-guide-loaded")

        tapArticleBackButton(in: app)

        XCTAssertTrue(
            waitForVisibleTextToDisappear(in: app, containing: "The Blood Moon Rises/Quick guide", timeout: 40),
            "Back navigation should not leave the quick guide article visible"
        )
        XCTAssertTrue(
            waitForVisibleTextToDisappear(in: app, containing: "Refreshing page", timeout: 40),
            "Back navigation should finish refreshing the previous article"
        )
        XCTAssertTrue(
            waitForVisibleTextToDisappear(in: app, containing: "Rendering page", timeout: 40),
            "Back navigation should finish rendering the previous article"
        )
        XCTAssertTrue(
            waitForVisibleText(in: app, containing: "The Blood Moon Rises", timeout: 25),
            app.debugDescription
        )
        XCTAssertTrue(
            waitForVisibleText(in: app, containing: "This quest has a", timeout: 25),
            app.debugDescription
        )
        XCTAssertTrue(
            waitForLink(in: app, matchingAnyOf: ["quick guide"], timeout: 3).exists,
            app.debugDescription
        )
        XCTAssertFalse(
            app.otherElements["search_screen"].exists,
            "Back should return to the source article, not the Search root"
        )
        saveScreenshot(from: app, named: "03-after-back-blood-moon-page")
    }

    private func waitForLink(in app: XCUIApplication, matchingAnyOf labels: [String], timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            for label in labels {
                let predicate = NSPredicate(format: "label CONTAINS[c] %@", label)
                let link = app.links.matching(predicate).firstMatch
                if link.exists && link.isHittable {
                    return link
                }
            }

            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        return app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", labels.first ?? "")).firstMatch
    }

    private func waitForVisibleText(in app: XCUIApplication, containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let element = app.staticTexts.matching(predicate).firstMatch
        return element.waitForExistence(timeout: timeout)
    }

    private func waitForVisibleTextToDisappear(in app: XCUIApplication, containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let element = app.staticTexts.matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        return !element.exists
    }

    private func tapArticleBackButton(in app: XCUIApplication) {
        let backButton = app.buttons["article_back_button"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), app.debugDescription)
        backButton.tap()
    }

    private func waitForNavigationStackState(in app: XCUIApplication, containing fragments: [String], timeout: TimeInterval) -> Bool {
        let marker = app.otherElements["article_navigation_stack_state"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let label = marker.label
            if fragments.allSatisfy({ label.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return false
    }

    private func navigationStackState(in app: XCUIApplication) -> String {
        app.otherElements["article_navigation_stack_state"].firstMatch.label
    }

    private func saveScreenshot(from app: XCUIApplication, named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let evidenceRoot else { return }
        let screenshotsDirectory = evidenceRoot.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        let fileURL = screenshotsDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }
}

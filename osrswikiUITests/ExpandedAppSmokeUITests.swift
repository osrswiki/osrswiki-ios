//
//  ExpandedAppSmokeUITests.swift
//  osrswikiUITests
//
//  Stable UI smoke lane for the expanded iOS RC gate.
//

import XCTest

final class ExpandedAppSmokeUITests: XCTestCase {
    private let tabLaunchBudget: TimeInterval = 10.0
    private let baseLaunchArguments = [
        "-screenshotMode",
        "-disableBackgroundPreloading",
        "-resetSavedPagesForUITests",
        "-seedSavedPagesForUITests"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDirectLaunchTabsExposeStableRootControls() throws {
        for tab in ["news", "map", "search", "saved", "more"] {
            let app = makeApp(startTab: tab)
            let start = Date()
            app.launch()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: tabLaunchBudget), "\(tab) tab launch should foreground the app")
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, tabLaunchBudget, "\(tab) tab should foreground within the smoke budget")

            assertTabBarExists(in: app)
            attachScreenshot(from: app, name: "expanded-smoke-\(tab)")
            app.terminate()
        }
    }

    func testSeededSavedPageLaunchesIntoSavedTab() throws {
        let app = makeApp(startTab: "saved")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: tabLaunchBudget))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 5), "Seeded saved page should be visible")
        attachScreenshot(from: app, name: "expanded-smoke-saved-seeded")
    }

    func testDirectDonateRouteLaunchesWithoutPaymentSheet() throws {
        let app = makeApp(startTab: "more", extraArguments: ["-startMoreDestination", "donate"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: tabLaunchBudget))
        XCTAssertTrue(app.staticTexts["Support OSRS Wiki"].waitForExistence(timeout: 8), "Donate route should render")
        XCTAssertTrue(app.buttons["Donations Unavailable"].waitForExistence(timeout: 5), "Donate action should clearly show unavailable state")
        XCTAssertFalse(app.buttons["Donations Unavailable"].isEnabled, "Unavailable donate action should not be tappable")
        XCTAssertTrue(app.staticTexts["donation_unavailable_message"].waitForExistence(timeout: 5), "Donate route should explain why app donations are unavailable")
        XCTAssertTrue(
            app.staticTexts["donation_unavailable_message"].label.contains("no payment provider is configured"),
            "Unavailable copy should avoid implying a payment can succeed"
        )
        XCTAssertFalse(app.sheets.firstMatch.exists, "Smoke launch should not present an Apple Pay sheet")
        attachScreenshot(from: app, name: "expanded-smoke-donate-route")
    }

    private func makeApp(startTab: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseLaunchArguments + ["-startTab", startTab] + extraArguments
        return app
    }

    private func assertTabBarExists(in app: XCUIApplication) {
        for identifier in ["news_tab", "map_tab", "search_tab", "saved_tab", "more_tab"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5), "Expected tab button \(identifier)")
        }
    }

    private func attachScreenshot(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

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
        let app = makeApp(
            startTab: "more",
            extraArguments: [
                "-startMoreDestination",
                "donate",
                "-osrsDonationGatewayFake"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: tabLaunchBudget))
        XCTAssertTrue(app.staticTexts["Support OSRS Wiki"].waitForExistence(timeout: 8), "Donate route should render")
        XCTAssertTrue(app.segmentedControls["donation_preset_amounts"].waitForExistence(timeout: 5), "Preset donation amounts should be visible")
        let priceSegment = app.segmentedControls["donation_preset_amounts"].buttons["$0.99"]
        XCTAssertTrue(
            priceSegment.waitForExistence(timeout: 5),
            "Store displayPrice should replace the $1 fallback when products load"
        )
        XCTAssertFalse(app.buttons["Donations Unavailable"].exists, "Fake-loaded StoreKit products should not keep the unavailable stub")
        XCTAssertFalse(app.sheets.firstMatch.exists, "Smoke launch should not present a payment sheet")
        attachScreenshot(from: app, name: "expanded-smoke-donate-route")
    }

    private func makeApp(startTab: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseLaunchArguments + ["-startTab", startTab] + extraArguments
        return app
    }

    private func assertTabBarExists(in app: XCUIApplication) {
        for identifier in ["home_tab", "map_tab", "search_tab", "saved_tab", "more_tab"] {
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

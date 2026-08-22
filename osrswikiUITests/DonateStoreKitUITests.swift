//
//  DonateStoreKitUITests.swift
//  osrswikiUITests
//
//  Donate presets, StoreKit display prices, and custom-amount wiki handoff.
//  Simulator does not complete App Store sandbox IAP. Device sandbox:
//  contact.omiyawaki@gmail.com.
//

import XCTest

final class DonateStoreKitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPresetPricesAndCustomAmountHandoff() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "more",
            "-startMoreDestination",
            "donate",
            "-osrsDonationGatewayFake"
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["donate_screen"].waitForExistence(timeout: 10) || app.descendants(matching: .any)["donate_screen"].waitForExistence(timeout: 2))

        let presets = app.segmentedControls["donation_preset_amounts"]
        XCTAssertTrue(presets.waitForExistence(timeout: 5))
        XCTAssertTrue(presets.buttons["$0.99"].waitForExistence(timeout: 5))
        XCTAssertTrue(presets.buttons["$4.99"].exists)
        XCTAssertTrue(presets.buttons["$9.99"].exists)
        XCTAssertTrue(presets.buttons["$24.99"].exists)

        presets.buttons["$4.99"].tap()
        XCTAssertTrue(app.buttons["Donate $4.99"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Donate $4.99"].isEnabled)
        XCTAssertFalse(app.sheets.firstMatch.exists)

        app.buttons["Custom"].tap()
        XCTAssertTrue(app.staticTexts["donate_custom_amount_handoff"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["donate_custom_amount_handoff"].label.contains("Donate to Wiki"),
            "Custom amount should hand off to wiki/Patreon instead of inventing a dynamic IAP"
        )
        XCTAssertFalse(app.textFields["donate_custom_amount"].exists)
        XCTAssertFalse(app.buttons["Donate $4.99"].exists)
        XCTAssertTrue(app.buttons["Use Donate to Wiki"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Use Donate to Wiki"].isEnabled)
        XCTAssertFalse(app.sheets.firstMatch.exists)

        XCTAssertTrue(
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "Donate to Wiki"))
                .firstMatch
                .exists
        )
    }

    func testUnavailableLaunchArgumentStillBlocksPurchase() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "more",
            "-startMoreDestination",
            "donate",
            "-osrsDonationGatewayUnavailable"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Donations Unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Donations Unavailable"].isEnabled)
        XCTAssertTrue(app.staticTexts["donation_unavailable_message"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }
}

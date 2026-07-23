//
//  DonateExternalHandoffUITests.swift
//  osrswikiUITests
//
//  Regression coverage for the Donate to Wiki external handoff.
//

import XCTest

final class DonateExternalHandoffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDonateToWikiOpensPatreonDestinationInSafari() throws {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()

        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "more",
            "-startMoreDestination",
            "donate"
        ]
        app.launch()

        XCTAssertTrue(element(in: app, identifier: "donate_screen").waitForExistence(timeout: 10))

        let wikiDonateButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Donate to Wiki"))
            .firstMatch
        XCTAssertTrue(wikiDonateButton.waitForExistence(timeout: 5))
        for _ in 0..<4 where !wikiDonateButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(wikiDonateButton.isHittable)

        wikiDonateButton.tap()

        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        dismissSafariFirstRunPrompts(in: safari)

        let addressField = safariAddressField(in: safari)
        XCTAssertTrue(addressField.waitForExistence(timeout: 15), safari.debugDescription)
        addressField.tap()

        let addressValue = String(describing: addressField.value ?? "")
        XCTAssertTrue(
            addressValue.lowercased().contains("patreon.com/runescapewiki"),
            "Safari address should contain the current wiki Patreon destination, got: \(addressValue)"
        )
    }

    private func dismissSafariFirstRunPrompts(in safari: XCUIApplication) {
        for label in ["Continue", "Not Now"] {
            let button = safari.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
            }
        }
    }

    private func safariAddressField(in safari: XCUIApplication) -> XCUIElement {
        let fullURLPredicate = NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", "patreon.com", "patreon.com")
        let fullURLField = safari.descendants(matching: .any).matching(fullURLPredicate).firstMatch
        if fullURLField.exists {
            return fullURLField
        }

        let addressPredicate = NSPredicate(format: "label CONTAINS[c] %@ OR placeholderValue CONTAINS[c] %@", "Address", "Search or enter website name")
        let addressField = safari.descendants(matching: .any).matching(addressPredicate).firstMatch
        if addressField.exists {
            return addressField
        }

        return safari.textFields.firstMatch
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let any = app.descendants(matching: .any)[identifier]
        if any.exists {
            return any
        }
        return app.otherElements[identifier]
    }
}

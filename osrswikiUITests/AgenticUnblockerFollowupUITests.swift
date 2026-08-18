//
//  AgenticUnblockerFollowupUITests.swift
//  osrswikiUITests
//
//  Simulator-only regression coverage promoted from the June 16 QA unblocker work.
//

import XCTest
import UIKit

final class AgenticUnblockerFollowupUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 12
    private let loadTimeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOfflineCachedSavedArticleUsesCacheOnlyMode() throws {
        let app = makeApp(
            startTab: "saved",
            extraArguments: [
                "-seedSavedPagesForUITests",
                "-seedOfflineSavedPageForUITests",
                "-forceNetworkOfflineForUITests",
                "-allowProxyStartupDuringTests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        openSeededSavedPage(in: app)

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout), "Cached saved article should open in-app")
        XCTAssertTrue(app.staticTexts["Available offline"].waitForExistence(timeout: 5), "Cached forced-offline page should clearly indicate cached/offline content")
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].waitForExistence(timeout: 3), "Cached forced-offline page should not show failed-load overlay")
        XCTAssertFalse(app.buttons["Retry"].exists, "Cached forced-offline page should not expose Retry")
        attachDebugDescription(from: app, name: "offline-cached-saved-article")
    }

    func testOfflineUncachedSavedArticleShowsErrorAndRetry() throws {
        let app = makeApp(
            startTab: "saved",
            extraArguments: [
                "-seedRetryableSavedPageForUITests",
                "-forceNetworkOfflineForUITests",
                "-allowProxyStartupDuringTests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        openSeededSavedPage(in: app)

        XCTAssertTrue(app.staticTexts["Failed to Load Page"].waitForExistence(timeout: loadTimeout))
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 3))
        attachDebugDescription(from: app, name: "offline-uncached-saved-article")
    }

    func testRetryableSavedArticleTransfersRoutePublishesAndRefreshesSavedRoot() throws {
        let app = makeApp(
            startTab: "saved",
            extraArguments: [
                "-seedRetryableSavedPageForUITests",
                "-allowProxyStartupDuringTests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        let initialMetadata = app.staticTexts["saved_row_metadata"]
        XCTAssertTrue(initialMetadata.waitForExistence(timeout: 8))
        XCTAssertTrue(initialMetadata.label.hasPrefix("RETRY"))
        openSeededSavedPage(in: app)

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))
        let retry = app.buttons["Retry"]
        XCTAssertTrue(
            retry.waitForExistence(timeout: 8),
            "An outdated/failed Saved article should expose its in-place Retry action"
        )
        retry.tap()

        let saving = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Saving...'" )
        ).firstMatch
        XCTAssertTrue(saving.waitForExistence(timeout: 8), "Retry must enter its explicit settlement before Back")
        let back = try articleBackButton(in: app)
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 10))

        let refreshedMetadata = app.staticTexts["saved_row_metadata"]
        XCTAssertTrue(refreshedMetadata.waitForExistence(timeout: 10))
        let savedPredicate = NSPredicate(format: "label BEGINSWITH 'SAVED'")
        expectation(
            for: savedPredicate,
            evaluatedWith: refreshedMetadata,
            handler: nil
        )
        waitForExpectations(timeout: 120)

        openSeededSavedPage(in: app)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))
        XCTAssertTrue(
            app.buttons["Saved"].waitForExistence(timeout: 8),
            "Reopening the same row must bind the newly published snapshot rather than the retired route"
        )
        attachScreenshot(from: app, name: "saved-retry-published-and-reopened")
        attachDebugDescription(from: app, name: "saved-retry-published-and-reopened")

        app.buttons["Saved"].tap()
        let secondBack = try articleBackButton(in: app)
        secondBack.tap()
        XCTAssertTrue(element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["No Saved Pages"].waitForExistence(timeout: 10),
            "An unsave mutation from ArticleView must remove the retained Saved row after Back"
        )
    }

    func testForcedOfflineSearchShowsSearchErrorWithoutHostDnsBlackhole() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-forceNetworkOfflineForUITests",
                "-disableSearchAutofocusForUITests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "search_screen").waitForExistence(timeout: 8))

        let searchField = app.textFields["search_input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        app.typeText("Varrock")

        XCTAssertTrue(
            app.alerts["Search Error"].waitForExistence(timeout: 10),
            "Forced-offline Search should surface a Search Error without relying on host DNS blackhole"
        )
        XCTAssertFalse(
            app.cells.containing(.staticText, identifier: "Varrock").firstMatch.exists,
            "Forced-offline Search should not show a stale online Varrock result"
        )
        attachDebugDescription(from: app, name: "forced-offline-search-error")
    }

    func testOnlineSearchOpensArticleWithoutFalseOfflineError() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: ["-disableSearchAutofocusForUITests"]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "search_screen").waitForExistence(timeout: 8))

        let searchField = app.textFields["search_input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        app.typeText("Lumbridge")

        let result = app.staticTexts["Lumbridge"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: loadTimeout), "Live Search should return Lumbridge")
        XCTAssertFalse(app.alerts["Search Error"].exists, "Reachable Search must not surface a false offline error")
        result.tap()

        XCTAssertTrue(element(in: app, identifier: "article_web_view").waitForExistence(timeout: loadTimeout))
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists, "Selected live Search result should load its article")
        attachScreenshot(from: app, name: "online-search-article-loaded")
        attachDebugDescription(from: app, name: "online-search-article-loaded")
    }

    func testDegradedNetworkSearchTimeoutShowsErrorAndKeepsTabsReachable() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-networkConditionForUITests",
                "timeout:0.01",
                "-disableSearchAutofocusForUITests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "search_screen").waitForExistence(timeout: 8))

        let searchField = app.textFields["search_input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        app.typeText("Varrock")

        let alert = app.alerts["Search Error"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 10),
            "Degraded timeout Search should surface a Search Error"
        )
        XCTAssertTrue(alert.staticTexts["Search request timed out"].exists)
        alert.buttons["OK"].tap()

        let moreTab = app.buttons["more_tab"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        XCTAssertTrue(moreTab.isHittable)
        moreTab.tap()
        XCTAssertTrue(element(in: app, identifier: "more_screen").waitForExistence(timeout: 8))
        attachDebugDescription(from: app, name: "degraded-network-search-timeout")
    }

    func testSeededSavedShareRecordsShareRequest() throws {
        let app = makeApp(
            startTab: "saved",
            extraArguments: ["-seedSavedPagesForUITests", "-stubShareSheetsForUITests"]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        let row = seededSavedRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.swipeRight()

        let shareButton = app.buttons["Share"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        shareButton.tap()

        let marker = app.staticTexts["saved_share_request_recorded"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertTrue(marker.label.contains("Varrock"))
        XCTAssertTrue(marker.label.contains("https://oldschool.runescape.wiki/w/Varrock"))
    }

    func testSeededSavedExportRecordsExportedReadingList() throws {
        let app = makeApp(
            startTab: "saved",
            extraArguments: ["-seedSavedPagesForUITests", "-stubShareSheetsForUITests"]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))

        let menu = app.buttons["saved_header_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let exportButton = app.buttons["Export Reading List"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let marker = app.staticTexts["saved_export_request_recorded"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertTrue(marker.label.contains("Varrock"))
        XCTAssertTrue(marker.label.contains("https://oldschool.runescape.wiki/w/Varrock"))
    }

    func testSeededSavedShareAndExportCompleteThroughTestReceiverActivity() throws {
        let app = makeApp(
            startTab: "saved",
            extraArguments: [
                "-seedSavedPagesForUITests",
                "-useTestShareReceiverActivityForUITests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        let row = seededSavedRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.swipeRight()

        let shareButton = app.buttons["Share"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        shareButton.tap()
        tapTestShareReceiverActivity(in: app)
        assertTestShareReceiverPayload(
            in: app,
            contains: [
                "osrs_test_share_receiver_completed",
                "Varrock",
                "https://oldschool.runescape.wiki/w/Varrock"
            ]
        )
        completeTestShareReceiverActivity(in: app)

        let menu = app.buttons["saved_header_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let exportButton = app.buttons["Export Reading List"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        tapTestShareReceiverActivity(in: app)
        assertTestShareReceiverPayload(
            in: app,
            contains: [
                "osrs_test_share_receiver_completed",
                "OSRS Wiki Reading List",
                "Varrock"
            ]
        )
        completeTestShareReceiverActivity(in: app)
    }

    func testSavedFilterFocusesWhenOpenedFromSavedSearchBar() throws {
        let app = makeApp(startTab: "saved", extraArguments: ["-seedSavedPagesForUITests"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(seededSavedRow(in: app).waitForExistence(timeout: 8))

        let searchEntry = app.buttons["saved_search"]
        XCTAssertTrue(searchEntry.waitForExistence(timeout: 5))
        searchEntry.tap()

        let filterField = app.textFields["saved_search_input"]
        XCTAssertTrue(filterField.waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["saved_search_back_button"].exists)
        XCTAssertTrue(app.buttons["saved_search_voice_search"].exists)

        app.typeText("Var")

        let value = filterField.value as? String ?? ""
        XCTAssertTrue(
            value.localizedCaseInsensitiveContains("Var"),
            "Saved search should focus the destination field when opened; value was '\(value)'"
        )
        XCTAssertTrue(seededSavedRow(in: app).waitForExistence(timeout: 3))

        let clear = app.buttons["saved_search_clear_button"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertFalse(
            (filterField.value as? String ?? "").localizedCaseInsensitiveContains("Var"),
            "Clearing Saved search must remove the typed query without replacing the editor."
        )
        attachDebugDescription(from: app, name: "saved-filter-focused")
    }

    func testSavedLauncherEditorGeometryRowsAndThemedCanvasInLightAndDark() throws {
        var canvasLuminanceByTheme: [String: Double] = [:]

        for theme in ["osrs_light", "osrs_dark"] {
            let app = makeApp(
                startTab: "saved",
                extraArguments: [
                    "-seedSavedPagesForUITests",
                    "-forceThemeForUITests", theme
                ]
            )
            app.launch()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
            let rowTitle = app.staticTexts["Varrock"]
            let preview = app.staticTexts["saved_row_preview"]
            let metadata = app.staticTexts["saved_row_metadata"]
            XCTAssertTrue(rowTitle.waitForExistence(timeout: 8))
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertTrue(metadata.waitForExistence(timeout: 5))
            XCTAssertEqual(preview.label, "Seeded saved page for UI navigation testing")
            XCTAssertLessThan(preview.frame.height, 30, "Normal-size Saved preview must remain exactly one visual line")
            XCTAssertTrue(metadata.label.hasPrefix("SAVED •"), "Saved metadata must remain below the one-line preview")
            XCTAssertTrue(metadata.label.contains("2025"), "Saved metadata must retain the compact localized date")
            XCTAssertFalse(metadata.label.localizedCaseInsensitiveContains("Last updated:"), "The visual metadata should keep the date without a verbose prefix")

            let launcher = app.buttons["saved_search"]
            XCTAssertTrue(launcher.waitForExistence(timeout: 5))
            XCTAssertEqual(preview.frame.minX, rowTitle.frame.minX, accuracy: 2, "Saved preview must share the title alignment in \(theme)")
            XCTAssertEqual(metadata.frame.minX, rowTitle.frame.minX, accuracy: 2, "Saved metadata must share the title alignment in \(theme)")
            XCTAssertEqual(rowTitle.frame.minX, 16, accuracy: 2, "Saved rows keep the 16pt leading inset in \(theme)")
            XCTAssertLessThan(metadata.frame.height, 30, "Normal-size Saved metadata must remain one line in \(theme)")

            let downloadStatusImages = app.images.matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "download",
                "offline"
            ))
            XCTAssertEqual(downloadStatusImages.count, 0, "Saved rows must not expose a green download/offline status arrow")

            let rowAttachment = XCTAttachment(screenshot: app.screenshot())
            rowAttachment.name = "saved-row-title-preview-metadata-\(theme)"
            rowAttachment.lifetime = .keepAlways
            add(rowAttachment)

            let launchHeight = launcher.frame.height
            launcher.tap()
            XCTAssertTrue(element(in: app, identifier: "saved_search_screen").waitForExistence(timeout: 5))

            let input = app.textFields["saved_search_input"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            let emptyFrame = input.frame
            app.typeText("Var")
            let typedFrame = input.frame

            let clear = app.buttons["saved_search_clear_button"]
            XCTAssertTrue(clear.waitForExistence(timeout: 3))
            clear.tap()
            let clearedFrame = input.frame

            XCTAssertEqual(emptyFrame.height, launchHeight, accuracy: 2)
            XCTAssertEqual(typedFrame.height, emptyFrame.height, accuracy: 2)
            XCTAssertEqual(clearedFrame.height, emptyFrame.height, accuracy: 2)
            XCTAssertEqual(typedFrame.minY, emptyFrame.minY, accuracy: 2)
            XCTAssertEqual(clearedFrame.minY, emptyFrame.minY, accuracy: 2)

            app.typeText("no-matching-saved-page")
            let screenshot = app.screenshot()
            canvasLuminanceByTheme[theme] = try averageLuminance(
                in: screenshot,
                normalizedRects: [
                    CGRect(x: 0.02, y: 0.30, width: 0.08, height: 0.45),
                    CGRect(x: 0.45, y: 0.55, width: 0.10, height: 0.12),
                    CGRect(x: 0.90, y: 0.30, width: 0.08, height: 0.45)
                ]
            )

            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "saved-search-geometry-themed-canvas-\(theme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            attachDebugDescription(from: app, name: "saved-search-geometry-themed-canvas-\(theme)")
            app.terminate()
        }

        let lightLuminance = try XCTUnwrap(canvasLuminanceByTheme["osrs_light"])
        let darkLuminance = try XCTUnwrap(canvasLuminanceByTheme["osrs_dark"])
        XCTAssertGreaterThan(
            lightLuminance - darkLuminance,
            60,
            "Saved active-search gaps/canvas must follow the selected light/dark OSRS theme; light=\(lightLuminance), dark=\(darkLuminance)"
        )
    }

    func testEmptySavedMenuDisablesExportAndClearAll() throws {
        let app = makeApp(startTab: "saved")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["No Saved Pages"].waitForExistence(timeout: 8))

        let menu = app.buttons["saved_header_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let exportButton = app.buttons["Export Reading List"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertFalse(exportButton.isEnabled, "Empty Saved export should be disabled instead of silently doing nothing")

        let clearButton = app.buttons["Clear All Saved Pages"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        XCTAssertFalse(clearButton.isEnabled, "Empty Saved clear-all should be disabled instead of silently doing nothing")
        attachDebugDescription(from: app, name: "empty-saved-menu-disabled-actions")
    }

    func testRealArticleSaveAppearsAsCleanSavedRow() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-startArticleTitle",
                "Varrock",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Varrock",
                "-allowProxyStartupDuringTests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Article Save action should be visible before saving")
        saveButton.tap()

        let savedButton = app.buttons["Saved"].firstMatch
        XCTAssertTrue(savedButton.waitForExistence(timeout: loadTimeout), "Article Save action should complete and show Saved")

        let backButton = try articleBackButton(in: app)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Article back button should be available after saving")
        backButton.tap()

        let savedTab = tabButton(in: app, identifier: "saved_tab", label: "Saved tab")
        XCTAssertTrue(savedTab.waitForExistence(timeout: 8), "Global Saved tab should return after leaving the article")
        XCTAssertTrue(savedTab.isHittable, "Global Saved tab should be hittable after leaving the saved article")
        savedTab.tap()

        XCTAssertTrue(element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 8))
        let row = seededSavedRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "The real-saved Varrock article should appear as a clean Saved row")
        XCTAssertFalse(app.webViews.firstMatch.exists, "Saved root should not still expose article WebView content")

        let menu = app.buttons["saved_header_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isHittable)
        menu.tap()

        let exportButton = app.buttons["Export Reading List"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertTrue(exportButton.isEnabled, "A non-empty real Saved list should enable Export Reading List")
        let clearButton = app.buttons["Clear All Saved Pages"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        XCTAssertTrue(clearButton.isEnabled, "A non-empty real Saved list should enable Clear All Saved Pages")

        attachScreenshot(from: app, name: "real-article-saved-row-clean")
        attachDebugDescription(from: app, name: "real-article-saved-row-clean")
    }

    func testMoreDonateAndFeedbackRoutesRecoverAcrossSameSessionStates() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-startArticleTitle",
                "Varrock",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Varrock",
                "-allowProxyStartupDuringTests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))

        let backButton = try articleBackButton(in: app)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        XCTAssertTrue(app.buttons["more_tab"].waitForExistence(timeout: 8))
        try assertMoreRoutes(in: app, context: "after article back")

        try assertTabSwitch(in: app, tabIdentifier: "search_tab", expectedScreenIdentifier: "search_screen")
        let searchField = app.textFields["search_input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search input should be visible before typing")
        searchField.tap()
        app.typeText("Var")
        try assertMoreRoutes(in: app, context: "after Search keyboard input")

        try assertTabSwitch(in: app, tabIdentifier: "saved_tab", expectedScreenIdentifier: "saved_pages_screen")
        try assertMoreRoutes(in: app, context: "after Saved")

        try assertTabSwitch(in: app, tabIdentifier: "map_tab", expectedScreenIdentifier: "map_screen")
        try assertMoreRoutes(in: app, context: "after Map")

        attachScreenshot(from: app, name: "same-session-more-routes")
        attachDebugDescription(from: app, name: "same-session-more-routes")
    }

    func testDonateCustomAmountValidatesInvalidInputAndKeepsValidAmountStable() throws {
        let app = makeApp(startTab: "more", extraArguments: ["-startMoreDestination", "donate"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "donate_screen").waitForExistence(timeout: 8))

        let customButton = app.buttons["Custom"]
        XCTAssertTrue(customButton.waitForExistence(timeout: 5))
        customButton.tap()

        let amountField = app.textFields["Enter amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))

        replaceText(in: amountField, with: "0", app: app)
        XCTAssertFalse(app.buttons["Enter Amount"].isEnabled)
        let validation = app.staticTexts["donate_custom_amount_error"]
        XCTAssertTrue(validation.waitForExistence(timeout: 3))
        XCTAssertTrue(validation.label.contains("$1.00"))

        replaceText(in: amountField, with: "abc", app: app)
        XCTAssertFalse(app.buttons["Enter Amount"].isEnabled)
        XCTAssertTrue(validation.waitForExistence(timeout: 3))
        XCTAssertTrue(validation.label.localizedCaseInsensitiveContains("number"))

        replaceText(in: amountField, with: "5", app: app)
        XCTAssertFalse(validation.exists)
        XCTAssertTrue(app.buttons["Donate $5.00"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Donate $5.00"].isEnabled)

        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 1) {
            doneButton.tap()
        }

        let value = amountField.value as? String ?? ""
        XCTAssertEqual(value, "5")
        XCTAssertTrue(app.buttons["Donate $5.00"].exists)
        attachDebugDescription(from: app, name: "donate-custom-amount-validation")
    }

    func testDonatePresetAmountPickerUpdatesDonateCta() throws {
        let app = makeApp(startTab: "more", extraArguments: ["-startMoreDestination", "donate"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "donate_screen").waitForExistence(timeout: 8))

        let fiveDollars = app.buttons["$5"]
        XCTAssertTrue(fiveDollars.waitForExistence(timeout: 5))
        fiveDollars.tap()

        let donateFive = app.buttons["Donate $5"]
        XCTAssertTrue(donateFive.waitForExistence(timeout: 3))
        XCTAssertTrue(donateFive.isEnabled)

        let customButton = app.buttons["Custom"]
        XCTAssertTrue(customButton.waitForExistence(timeout: 3))
        customButton.tap()

        XCTAssertTrue(app.textFields["Enter amount"].waitForExistence(timeout: 3))
        let enterAmount = app.buttons["Enter Amount"]
        XCTAssertTrue(enterAmount.waitForExistence(timeout: 3))
        XCTAssertFalse(enterAmount.isEnabled)

        let tenDollars = app.buttons["$10"]
        XCTAssertTrue(tenDollars.waitForExistence(timeout: 3))
        tenDollars.tap()

        XCTAssertFalse(app.textFields["Enter amount"].exists)
        let donateTen = app.buttons["Donate $10"]
        XCTAssertTrue(donateTen.waitForExistence(timeout: 3))
        XCTAssertTrue(donateTen.isEnabled)
        attachDebugDescription(from: app, name: "donate-preset-picker-selection")
    }

    func testRateAppDeclineDoesNotShowSuccessAlert() throws {
        let app = makeApp(startTab: "more", extraArguments: ["-startMoreDestination", "feedback"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "feedback_screen").waitForExistence(timeout: 8))

        let rateAppButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Rate App"))
            .firstMatch
        XCTAssertTrue(rateAppButton.waitForExistence(timeout: 5))
        rateAppButton.tap()

        let notNowButton = app.buttons["Not Now"]
        if notNowButton.waitForExistence(timeout: 3) {
            notNowButton.tap()
        }

        XCTAssertFalse(
            app.alerts["Success"].waitForExistence(timeout: 3),
            "Declining or dismissing the rating prompt should not show a success alert"
        )
        attachDebugDescription(from: app, name: "rate-app-no-success-alert")
    }

    func testArticleOverflowRefreshFailureShowsRetryAndRetryDismissesError() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-startArticleTitle",
                "Varrock",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Varrock",
                "-forceArticleRefreshFailureForUITests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))

        openArticleOverflowMenu(in: app)
        let refresh = app.buttons["Refresh Page"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()

        XCTAssertTrue(app.staticTexts["Failed to Load Page"].waitForExistence(timeout: 8))
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        attachDebugDescription(from: app, name: "article-refresh-forced-failure")

        retry.tap()
        XCTAssertTrue(
            app.staticTexts["Failed to Load Page"].waitForNonExistence(timeout: 10),
            "Retry should dismiss the failed-load overlay after the article reloads"
        )
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        attachDebugDescription(from: app, name: "article-refresh-retry-dismissed-error")
    }

    func testActiveArticleReloadShowsRetryWhenForcedNetworkFailure() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-startArticleTitle",
                "Varrock",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Varrock",
                "-forceArticleReloadNetworkFailureAfterFirstSuccessForUITests",
                "-allowProxyStartupDuringTests"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))

        openArticleOverflowMenu(in: app)
        let refresh = app.buttons["Refresh Page"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()

        XCTAssertTrue(app.staticTexts["Failed to Load Page"].waitForExistence(timeout: 8))
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        attachDebugDescription(from: app, name: "active-article-reload-forced-network-failure")

        retry.tap()
        XCTAssertTrue(
            app.staticTexts["Failed to Load Page"].waitForNonExistence(timeout: 10),
            "Retry should dismiss the failed-load overlay after the active article reloads"
        )
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        attachDebugDescription(from: app, name: "active-article-reload-retry-dismissed-error")
    }

    func testCleanLaunchBottomTabsSwitchVisibleScreens() throws {
        let app = makeApp(startTab: "news", extraArguments: ["-seedSavedPagesForUITests"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "home_screen").waitForExistence(timeout: 10))

        try assertTabSwitch(in: app, tabIdentifier: "saved_tab", expectedScreenIdentifier: "saved_pages_screen")
        try assertTabSwitch(in: app, tabIdentifier: "search_tab", expectedScreenIdentifier: "search_screen")
        try assertTabSwitch(in: app, tabIdentifier: "map_tab", expectedScreenIdentifier: "map_screen")
        try assertTabSwitch(in: app, tabIdentifier: "more_tab", expectedScreenIdentifier: "more_screen")
        try assertTabSwitch(in: app, tabIdentifier: "home_tab", expectedScreenIdentifier: "home_screen")

        attachDebugDescription(from: app, name: "clean-launch-bottom-tabs-visible-screens")
    }

    func testCleanLaunchMapTabOpensUsableMapSurface() throws {
        let app = makeApp(startTab: "news")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "home_screen").waitForExistence(timeout: 10))

        let mapTab = app.buttons["map_tab"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 8), "Map tab should exist from a clean launch")
        XCTAssertTrue(mapTab.isHittable, "Map tab should be hittable from a clean launch")
        mapTab.tap()

        let mapScreen = app.otherElements["map_screen"].firstMatch
        XCTAssertTrue(mapScreen.waitForExistence(timeout: 10), "Tapping Map from clean launch should show the Map screen")

        let mapView = app.descendants(matching: .any)["map_view"]
        XCTAssertTrue(mapView.waitForExistence(timeout: 12), "Map screen should expose the native MapLibre surface")

        mapView.swipeLeft()
        mapView.swipeRight()
        mapView.pinch(withScale: 1.2, velocity: 1.0)

        let floorUp = app.buttons["Increase map floor"]
        XCTAssertTrue(floorUp.waitForExistence(timeout: 8), "Clean-launch Map should expose the floor-up control")
        XCTAssertTrue(floorUp.isHittable, "Clean-launch Map floor-up control should be hittable")
        floorUp.tap()

        let floorDown = app.buttons["Decrease map floor"]
        XCTAssertTrue(floorDown.waitForExistence(timeout: 8), "Clean-launch Map should expose the floor-down control after moving up")
        XCTAssertTrue(floorDown.isHittable, "Clean-launch Map floor-down control should be hittable after moving up")
        floorDown.tap()

        XCTAssertTrue(element(in: app, identifier: "map_screen").waitForExistence(timeout: 5))
        XCTAssertFalse(element(in: app, identifier: "article_web_view").exists, "Clean-launch Map interactions should not open article content")
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists, "Clean-launch Map interactions should not open an article error state")

        attachScreenshot(from: app, name: "clean-launch-map-usable-surface")
        attachDebugDescription(from: app, name: "clean-launch-map-usable-surface")
    }

    func testSavedArticleModeDoesNotExposeGlobalTabs() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-seedSavedPagesForUITests",
                "-startArticleTitle",
                "Varrock",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Varrock"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: loadTimeout))

        assertGlobalTabsAreNotHittable(in: app)
        XCTAssertFalse(
            element(in: app, identifier: "saved_pages_screen").exists,
            "A saved article should remain in article mode instead of exposing the Saved root under article chrome"
        )
        attachDebugDescription(from: app, name: "saved-article-global-tabs-hidden")
    }

    func testArticleAppliesAccessibilityDynamicTypeScaleToWebView() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-startArticleTitle",
                "Varrock",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Varrock"
            ]
        )
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 8))

        let articleWebView = element(in: app, identifier: "article_web_view")
        XCTAssertTrue(articleWebView.waitForExistence(timeout: loadTimeout))

        let value = articleWebView.value as? String ?? ""
        XCTAssertTrue(
            value.contains("article_dynamic_type_scale=2.00"),
            "Article WebView should apply accessibility Dynamic Type scale; value was '\(value)'"
        )
        attachDebugDescription(from: app, name: "article-accessibility-dynamic-type-scale")
    }

    func testAppearanceReaderPreferencesPersistAndReachArticleRuntime() throws {
        let settingsApp = makeApp(
            startTab: "more",
            extraArguments: [
                "-startMoreDestination", "appearance",
                "-resetReaderPreferencesForUITests"
            ]
        )
        settingsApp.launch()
        XCTAssertTrue(settingsApp.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: settingsApp, identifier: "appearance_screen").waitForExistence(timeout: 10))

        let collapse = settingsApp.switches["appearance_collapse_tables_toggle"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        XCTAssertEqual(collapse.value as? String, "1")
        setSwitch(collapse, enabled: false, in: settingsApp)

        let slider = settingsApp.sliders["appearance_article_text_scale"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.75)
        let selectedScale = try XCTUnwrap(slider.value as? String)
        XCTAssertNotEqual(selectedScale, "100%")

        let swipeRight = settingsApp.switches["appearance_swipe_right_back_toggle"]
        let swipeLeft = settingsApp.switches["appearance_swipe_left_contents_toggle"]
        for _ in 0..<3 where !swipeLeft.isHittable {
            settingsApp.swipeUp()
        }
        XCTAssertTrue(swipeRight.isHittable)
        XCTAssertTrue(swipeLeft.isHittable)
        setSwitch(swipeRight, enabled: false, in: settingsApp)
        setSwitch(swipeLeft, enabled: false, in: settingsApp)

        let changedAttachment = XCTAttachment(screenshot: settingsApp.screenshot())
        changedAttachment.name = "appearance-reader-preferences-changed"
        changedAttachment.lifetime = .keepAlways
        add(changedAttachment)
        settingsApp.terminate()

        let relaunchedApp = makeApp(
            startTab: "more",
            extraArguments: ["-startMoreDestination", "appearance"]
        )
        relaunchedApp.launch()
        XCTAssertTrue(relaunchedApp.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: relaunchedApp, identifier: "appearance_screen").waitForExistence(timeout: 10))

        let persistedCollapse = relaunchedApp.switches["appearance_collapse_tables_toggle"]
        let persistedSlider = relaunchedApp.sliders["appearance_article_text_scale"]
        XCTAssertEqual(persistedCollapse.value as? String, "0")
        XCTAssertEqual(persistedSlider.value as? String, selectedScale)
        let persistedSwipeRight = relaunchedApp.switches["appearance_swipe_right_back_toggle"]
        let persistedSwipeLeft = relaunchedApp.switches["appearance_swipe_left_contents_toggle"]
        for _ in 0..<3 where !persistedSwipeLeft.isHittable {
            relaunchedApp.swipeUp()
        }
        XCTAssertEqual(persistedSwipeRight.value as? String, "0")
        XCTAssertEqual(persistedSwipeLeft.value as? String, "0")
        relaunchedApp.terminate()

        let articleApp = makeApp(
            startTab: "search",
            extraArguments: [
                "-startArticleTitle", "Varrock",
                "-startArticleURL", "https://oldschool.runescape.wiki/w/Varrock"
            ]
        )
        articleApp.launch()
        XCTAssertTrue(articleApp.wait(for: .runningForeground, timeout: launchTimeout))
        let webView = element(in: articleApp, identifier: "article_web_view")
        XCTAssertTrue(webView.waitForExistence(timeout: loadTimeout))
        let runtimeState = try XCTUnwrap(webView.value as? String)
        XCTAssertTrue(runtimeState.contains("article_user_text_scale="), runtimeState)
        XCTAssertFalse(runtimeState.contains("article_user_text_scale=1.00"), runtimeState)
        XCTAssertTrue(runtimeState.contains("article_collapse_tables=0"), runtimeState)
        XCTAssertTrue(runtimeState.contains("article_swipe_right_back=0"), runtimeState)
        XCTAssertTrue(runtimeState.contains("article_swipe_left_contents=0"), runtimeState)
        attachDebugDescription(from: articleApp, name: "appearance-reader-preferences-article-runtime")
    }

    func testDarkArticlePaintsTheTopSafeAreaWithTheActiveTheme() throws {
        let app = makeApp(
            startTab: "search",
            extraArguments: [
                "-forceThemeForUITests",
                "osrs_dark",
                "-startArticleTitle",
                "Lumbridge",
                "-startArticleURL",
                "https://oldschool.runescape.wiki/w/Lumbridge"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "article_web_view").waitForExistence(timeout: loadTimeout))

        let screenshot = app.screenshot()
        let topSafeAreaLuminance = try averageLuminance(
            in: screenshot,
            normalizedRects: [
                CGRect(x: 0.02, y: 0.0, width: 0.30, height: 0.055),
                CGRect(x: 0.68, y: 0.0, width: 0.30, height: 0.055)
            ]
        )
        XCTAssertLessThan(
            topSafeAreaLuminance,
            110,
            "Dark article chrome should paint behind the Dynamic Island/status bar; luminance was \(topSafeAreaLuminance)"
        )

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "dark-article-top-safe-area"
        attachment.lifetime = .keepAlways
        add(attachment)
        attachDebugDescription(from: app, name: "dark-article-top-safe-area")
    }

    func testDynamicTypeDirectRoutesAtCurrentContentSize() throws {
        try assertDirectRoute(startTab: "news", expectedIdentifier: "home_screen")
        try assertDirectRoute(startTab: "saved", expectedIdentifier: "saved_pages_screen", seedSaved: true)
        try assertDirectRoute(startTab: "search", expectedIdentifier: "search_screen")
        try assertDirectRoute(startTab: "map", expectedIdentifier: "map_screen")
        try assertDirectRoute(startTab: "more", expectedIdentifier: "more_screen")
        try assertDirectRoute(startTab: "more", expectedIdentifier: "appearance_screen", extraArguments: ["-startMoreDestination", "appearance"])
        try assertDirectRoute(startTab: "more", expectedIdentifier: "donate_screen", extraArguments: ["-startMoreDestination", "donate"])
        try assertDirectRoute(startTab: "more", expectedIdentifier: "feedback_screen", extraArguments: ["-startMoreDestination", "feedback"])
    }

    func testSavedAccessibilityXXXLKeepsEmptyStateReadableAndTabsReachable() throws {
        let app = makeApp(startTab: "saved")
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 8))

        let search = app.buttons["saved_search"]
        let menu = app.buttons["saved_header_menu"]
        let emptyTitle = app.staticTexts["No Saved Pages"]
        let emptyMessage = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "personal reading list"))
            .firstMatch
        let mapTab = app.buttons["map_tab"]

        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(mapTab.waitForExistence(timeout: 5))

        let contentFrame = readableContentFrame(in: app)
        assertFrame(search.frame, of: "Saved search entry", isInside: contentFrame)
        assertFrame(menu.frame, of: "Saved menu", isInside: contentFrame)
        assertFrame(emptyTitle.frame, of: "Saved empty-state title", isInside: contentFrame)
        assertFrame(emptyMessage.frame, of: "Saved empty-state message", isInside: contentFrame)

        XCTAssertTrue(search.isHittable, "Saved search should remain hittable at accessibility XXXL")
        XCTAssertTrue(menu.isHittable, "Saved menu should remain hittable at accessibility XXXL")
        XCTAssertTrue(mapTab.isHittable, "Bottom Map tab should remain hittable at accessibility XXXL")
        attachScreenshot(from: app, name: "saved-accessibility-xxxl-readable")
        attachDebugDescription(from: app, name: "saved-accessibility-xxxl-readable")
    }

    func testDynamicTypeMapLabelDoesNotResolveToOffscreenInteractiveElement() throws {
        let app = makeApp(startTab: "news")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        let mapCandidates = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Map' OR identifier == 'map_tab'"))

        for index in 0..<mapCandidates.count {
            let candidate = mapCandidates.element(boundBy: index)
            guard candidate.exists, candidate.isHittable else { continue }
            XCTAssertGreaterThanOrEqual(candidate.frame.minX, 0, "Hittable Map candidate should not be offscreen: \(candidate)")
            XCTAssertGreaterThanOrEqual(candidate.frame.minY, 0, "Hittable Map candidate should not be offscreen: \(candidate)")
        }
    }

    func testIpadAfterMapDonateFreshFlow() throws {
        let app = makeApp(startTab: "map")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "map_screen").waitForExistence(timeout: 8))

        XCTAssertTrue(app.buttons["more_tab"].waitForExistence(timeout: 8))
        app.buttons["more_tab"].tap()
        XCTAssertTrue(app.buttons["more_donate"].waitForExistence(timeout: 8))
        app.buttons["more_donate"].tap()

        XCTAssertTrue(element(in: app, identifier: "donate_screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Support OSRS Wiki"].exists)
    }

    func testIpadAfterMapFeedbackFreshFlow() throws {
        let app = makeApp(startTab: "map")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "map_screen").waitForExistence(timeout: 8))

        XCTAssertTrue(app.buttons["more_tab"].waitForExistence(timeout: 8))
        app.buttons["more_tab"].tap()
        XCTAssertTrue(app.buttons["more_feedback"].waitForExistence(timeout: 8))
        app.buttons["more_feedback"].tap()

        XCTAssertTrue(element(in: app, identifier: "feedback_screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Send Feedback"].exists || app.navigationBars["Send Feedback"].exists)
    }

    func testIpadMapControlsKeepMoreDonateFeedbackRoutesOnTargetSurfaces() throws {
        let app = makeApp(startTab: "map")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        let mapSurface = app.otherElements["map_screen"].firstMatch
        XCTAssertTrue(mapSurface.waitForExistence(timeout: 8))

        mapSurface.swipeLeft()
        mapSurface.swipeRight()
        mapSurface.pinch(withScale: 1.2, velocity: 1.0)

        let floorUp = app.buttons["Increase map floor"]
        XCTAssertTrue(floorUp.waitForExistence(timeout: 8), "Map floor-up control should be visible")
        XCTAssertTrue(floorUp.isHittable, "Map floor-up control should be hittable")
        floorUp.tap()

        let floorDown = app.buttons["Decrease map floor"]
        XCTAssertTrue(floorDown.waitForExistence(timeout: 8), "Map floor-down control should be visible after moving up")
        XCTAssertTrue(floorDown.isHittable, "Map floor-down control should be hittable after moving up")
        floorDown.tap()

        XCTAssertTrue(element(in: app, identifier: "map_screen").waitForExistence(timeout: 5))
        XCTAssertFalse(element(in: app, identifier: "article_web_view").exists, "Map controls should not open article content")
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists, "Map controls should not open an article error state")

        try assertMoreRoutes(in: app, context: "after iPad map controls")
        attachScreenshot(from: app, name: "ipad-map-controls-more-routes")
        attachDebugDescription(from: app, name: "ipad-map-controls-more-routes")
    }

    func testSeededSavedSwipeDelete() throws {
        let app = makeApp(startTab: "saved", extraArguments: ["-seedSavedPagesForUITests"])
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        let row = seededSavedRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.swipeLeft()

        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        XCTAssertTrue(app.staticTexts["No Saved Pages"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Varrock"].exists)
    }

    func testSeededSavedPagePersistsAcrossRelaunchWithoutReseed() throws {
        let seededApp = makeApp(startTab: "saved", extraArguments: ["-seedSavedPagesForUITests"])
        seededApp.launch()

        XCTAssertTrue(seededApp.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(seededSavedRow(in: seededApp).waitForExistence(timeout: 8))
        seededApp.terminate()

        let restoredApp = makeApp(startTab: "saved", resetSavedPages: false)
        restoredApp.launch()

        XCTAssertTrue(restoredApp.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(seededSavedRow(in: restoredApp).waitForExistence(timeout: 8))
        attachDebugDescription(from: restoredApp, name: "saved-page-relaunch-persistence")
    }

    private func assertDirectRoute(
        startTab: String,
        expectedIdentifier: String,
        seedSaved: Bool = false,
        extraArguments: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var launchArguments = extraArguments
        if seedSaved {
            launchArguments.append("-seedSavedPagesForUITests")
        }
        let app = makeApp(startTab: startTab, extraArguments: launchArguments)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout), file: file, line: line)
        XCTAssertTrue(element(in: app, identifier: expectedIdentifier).waitForExistence(timeout: 10), "Missing \(expectedIdentifier)", file: file, line: line)
        attachDebugDescription(from: app, name: "dynamic-direct-\(expectedIdentifier)")
        app.terminate()
    }

    private func assertTabSwitch(
        in app: XCUIApplication,
        tabIdentifier: String,
        expectedScreenIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let label = [
            "home_tab": "Home tab",
            "saved_tab": "Saved tab",
            "search_tab": "Search tab",
            "map_tab": "Map tab",
            "more_tab": "More tab"
        ][tabIdentifier] ?? tabIdentifier
        let tab = tabButton(in: app, identifier: tabIdentifier, label: label)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing \(tabIdentifier)", file: file, line: line)
        XCTAssertTrue(tab.isHittable, "\(tabIdentifier) should be hittable", file: file, line: line)

        tab.tap()

        XCTAssertTrue(
            element(in: app, identifier: expectedScreenIdentifier).waitForExistence(timeout: 5),
            "Tapping \(tabIdentifier) should show \(expectedScreenIdentifier)",
            file: file,
            line: line
        )
    }

    private func tabButton(
        in app: XCUIApplication,
        identifier: String,
        label: String
    ) -> XCUIElement {
        let identified = app.buttons[identifier]
        if identified.exists {
            return identified
        }

        let labeled = app.buttons[label]
        if labeled.exists {
            return labeled
        }

        return app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", identifier, label)
        ).firstMatch
    }

    private func assertGlobalTabsAreNotHittable(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tabs = [
            (identifier: "home_tab", label: "Home tab"),
            (identifier: "saved_tab", label: "Saved tab"),
            (identifier: "search_tab", label: "Search tab"),
            (identifier: "map_tab", label: "Map tab"),
            (identifier: "more_tab", label: "More tab")
        ]
        for candidate in tabs {
            let tab = tabButton(in: app, identifier: candidate.identifier, label: candidate.label)
            XCTAssertFalse(
                tab.exists && tab.isHittable,
                "\(candidate.identifier) should not be hittable while article chrome owns the bottom bar",
                file: file,
                line: line
            )
        }
    }

    private func makeApp(
        startTab: String,
        extraArguments: [String] = [],
        resetSavedPages: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            startTab
        ]
        if resetSavedPages {
            launchArguments.insert("-resetSavedPagesForUITests", at: 2)
        }
        app.launchArguments = launchArguments + extraArguments
        return app
    }

    private func openSeededSavedPage(in app: XCUIApplication) {
        let title = app.staticTexts["Varrock"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Seeded saved page should be visible")
        title.tap()
    }

    private func openArticleOverflowMenu(in app: XCUIApplication) {
        let ellipsis = app.buttons["ellipsis"].firstMatch
        if ellipsis.waitForExistence(timeout: 5) {
            ellipsis.tap()
            return
        }

        let more = app.buttons["More"].firstMatch
        if more.waitForExistence(timeout: 5) {
            more.tap()
            return
        }

        XCTFail("Article overflow menu button should exist")
    }

    private func tapTestShareReceiverActivity(in app: XCUIApplication) {
        let receiver = app.descendants(matching: .any)["OSRS Test Receiver"].firstMatch
        XCTAssertTrue(receiver.waitForExistence(timeout: 8), "Test receiver activity should appear in the share sheet")
        receiver.tap()
    }

    private func assertTestShareReceiverPayload(
        in app: XCUIApplication,
        contains expectedFragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completionMarker = app.staticTexts["osrs_test_share_receiver_completed"]
        XCTAssertTrue(
            completionMarker.waitForExistence(timeout: 8),
            "Test receiver should show a completion marker",
            file: file,
            line: line
        )

        let payload = app.staticTexts["osrs_test_share_receiver_payload"]
        XCTAssertTrue(
            payload.waitForExistence(timeout: 5),
            "Test receiver should show the received payload",
            file: file,
            line: line
        )

        for fragment in expectedFragments {
            XCTAssertTrue(
                payload.label.contains(fragment),
                "Expected share payload to contain \(fragment), got: \(payload.label)",
                file: file,
                line: line
            )
        }
    }

    private func completeTestShareReceiverActivity(in app: XCUIApplication) {
        let completeButton = app.buttons["osrs_test_share_receiver_complete"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5), "Test receiver should expose completion")
        completeButton.tap()
    }

    private func articleBackButton(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let chevronButton = app.buttons["chevron.left"].firstMatch
        if chevronButton.waitForExistence(timeout: 1) {
            return chevronButton
        }

        let windowFrame = app.windows.firstMatch.frame
        let topLeadingButtons = app.buttons.allElementsBoundByIndex.filter { button in
            guard button.exists else { return false }
            return button.frame.minX <= windowFrame.minX + 80 &&
                button.frame.minY <= windowFrame.minY + 140
        }

        let backButton = topLeadingButtons.min { lhs, rhs in
            if lhs.frame.minY == rhs.frame.minY {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }

        return try XCTUnwrap(backButton, "Article back button should be the top-leading button", file: file, line: line)
    }

    private func assertMoreRoutes(
        in app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let moreTab = app.buttons["more_tab"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 8), "\(context): More tab should exist", file: file, line: line)
        XCTAssertTrue(moreTab.isHittable, "\(context): More tab should be hittable", file: file, line: line)
        moreTab.tap()

        XCTAssertTrue(
            element(in: app, identifier: "more_screen").waitForExistence(timeout: 8),
            "\(context): More screen should be visible",
            file: file,
            line: line
        )

        let donate = app.buttons["more_donate"]
        XCTAssertTrue(donate.waitForExistence(timeout: 5), "\(context): Donate row should exist", file: file, line: line)
        XCTAssertTrue(donate.isHittable, "\(context): Donate row should be hittable", file: file, line: line)
        donate.tap()
        XCTAssertTrue(
            element(in: app, identifier: "donate_screen").waitForExistence(timeout: 8),
            "\(context): Donate screen should open from More",
            file: file,
            line: line
        )
        XCTAssertTrue(app.staticTexts["Support OSRS Wiki"].exists, "\(context): Donate content should be visible", file: file, line: line)
        try navigateBackToMore(in: app, context: context, file: file, line: line)

        let feedback = app.buttons["more_feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), "\(context): Feedback row should exist", file: file, line: line)
        XCTAssertTrue(feedback.isHittable, "\(context): Feedback row should be hittable", file: file, line: line)
        feedback.tap()
        XCTAssertTrue(
            element(in: app, identifier: "feedback_screen").waitForExistence(timeout: 8),
            "\(context): Feedback screen should open from More",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts["Send Feedback"].exists || app.navigationBars["Send Feedback"].exists,
            "\(context): Feedback content should be visible",
            file: file,
            line: line
        )
        try navigateBackToMore(in: app, context: context, file: file, line: line)
    }

    private func navigateBackToMore(
        in app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let labeledBack = app.navigationBars.buttons["More"].firstMatch
        if labeledBack.waitForExistence(timeout: 2) {
            labeledBack.tap()
        } else {
            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 3), "\(context): More destination should expose a back button", file: file, line: line)
            backButton.tap()
        }

        XCTAssertTrue(
            element(in: app, identifier: "more_screen").waitForExistence(timeout: 8),
            "\(context): Back navigation should return to More",
            file: file,
            line: line
        )
    }

    private func seededSavedRow(in app: XCUIApplication) -> XCUIElement {
        let cell = app.cells.containing(.staticText, identifier: "Varrock").firstMatch
        if cell.exists {
            return cell
        }
        return app.staticTexts["Varrock"]
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        let isKeyboardFocused = NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
        if !isKeyboardFocused {
            field.tap()
        }
        if let value = field.value as? String, value != "Enter amount" {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        app.typeText(text)
    }

    private func setSwitch(
        _ control: XCUIElement,
        enabled: Bool,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedValue = enabled ? "1" : "0"
        XCTAssertTrue(control.exists, "Switch must exist", file: file, line: line)
        XCTAssertTrue(control.isHittable, "Switch must be hittable", file: file, line: line)
        guard (control.value as? String) != expectedValue else { return }

        // SwiftUI exposes the whole labeled row as the Switch AX frame on iOS 26. Tapping the
        // element midpoint lands on the label, so exercise the visible native switch affordance.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: control
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [changed], timeout: 3),
            .completed,
            "Switch binding did not persist target value \(expectedValue)",
            file: file,
            line: line
        )
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let any = app.descendants(matching: .any)[identifier]
        if any.exists {
            return any
        }
        return app.otherElements[identifier]
    }

    private func averageLuminance(
        in screenshot: XCUIScreenshot,
        normalizedRects: [CGRect]
    ) throws -> Double {
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation)?.cgImage)
        var luminanceTotal = 0.0
        var pixelTotal = 0

        for normalizedRect in normalizedRects {
            let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let cropRect = CGRect(
                x: Double(image.width) * normalizedRect.minX,
                y: Double(image.height) * normalizedRect.minY,
                width: Double(image.width) * normalizedRect.width,
                height: Double(image.height) * normalizedRect.height
            ).integral.intersection(imageBounds)
            let cropped = try XCTUnwrap(image.cropping(to: cropRect))
            var pixels = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &pixels,
                width: cropped.width,
                height: cropped.height,
                bitsPerComponent: 8,
                bytesPerRow: cropped.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))

            for offset in stride(from: 0, to: pixels.count, by: 4) {
                luminanceTotal += 0.2126 * Double(pixels[offset])
                    + 0.7152 * Double(pixels[offset + 1])
                    + 0.0722 * Double(pixels[offset + 2])
                pixelTotal += 1
            }
        }

        return luminanceTotal / Double(pixelTotal)
    }

    private func readableContentFrame(in app: XCUIApplication) -> CGRect {
        let windowFrame = app.windows.firstMatch.frame
        let tabTop = ["home_tab", "saved_tab", "search_tab", "map_tab", "more_tab"]
            .compactMap { identifier -> CGFloat? in
                let tab = app.buttons[identifier]
                return tab.exists ? tab.frame.minY : nil
            }
            .min() ?? windowFrame.maxY
        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.minY,
            width: windowFrame.width,
            height: max(0, tabTop - windowFrame.minY)
        )
    }

    private func savedHeaderTitle(
        in app: XCUIApplication,
        above searchEntry: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let identifiedTitle = app.staticTexts["saved_header"]
        if identifiedTitle.exists {
            return identifiedTitle
        }

        let candidates = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Saved"))
            .allElementsBoundByIndex
            .filter { $0.exists && $0.frame.maxY <= searchEntry.frame.minY }

        let title = candidates.max { lhs, rhs in
            lhs.frame.height < rhs.frame.height
        }
        return try XCTUnwrap(title, "Saved screen title should be visible above the search entry", file: file, line: line)
    }

    private func assertFrame(
        _ frame: CGRect,
        of elementName: String,
        isInside container: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(frame.minX, container.minX, "\(elementName) should not render off the leading edge; frame=\(frame), container=\(container)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, container.minY, "\(elementName) should not render above the viewport; frame=\(frame), container=\(container)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, container.maxX, "\(elementName) should not render off the trailing edge; frame=\(frame), container=\(container)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, container.maxY, "\(elementName) should not render under the bottom tabs; frame=\(frame), container=\(container)", file: file, line: line)
    }

    private func attachScreenshot(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachDebugDescription(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

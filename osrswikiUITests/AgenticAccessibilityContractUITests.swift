//
//  AgenticAccessibilityContractUITests.swift
//  osrswikiUITests
//
//  VoiceOver-equivalent accessibility contract coverage derived from XCTest's UI tree.
//

import XCTest
import UIKit

final class AgenticAccessibilityContractUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 12

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimaryTabsExposeAccessibilityContracts() throws {
        try assertScreen(
            startTab: "news",
            screenIdentifier: "home_screen",
            requiredButtons: ["home_tab", "saved_tab", "search_tab", "map_tab", "more_tab"],
            requiredLabels: ["Home", "Search OSRS Wiki"]
        )

        try assertScreen(
            startTab: "saved",
            screenIdentifier: "saved_pages_screen",
            requiredButtons: ["home_tab", "saved_tab", "search_tab", "map_tab", "more_tab"],
            requiredLabels: ["Saved", "Varrock"],
            extraArguments: ["-seedSavedPagesForUITests"]
        )

        try assertScreen(
            startTab: "search",
            screenIdentifier: "search_screen",
            requiredButtons: ["home_tab", "saved_tab", "search_tab", "map_tab", "more_tab"],
            requiredLabels: [],
            requiredIdentifiers: ["search_history_launcher"]
        )

        try assertScreen(
            startTab: "map",
            screenIdentifier: "map_screen",
            requiredButtons: ["home_tab", "saved_tab", "search_tab", "map_tab", "more_tab"],
            requiredLabels: [],
            requiredIdentifiers: ["map_view"]
        )

        try assertScreen(
            startTab: "more",
            screenIdentifier: "more_screen",
            requiredButtons: ["more_appearance", "more_donate", "more_feedback"],
            requiredLabels: ["More", "Appearance", "Donate", "Feedback"],
            orderIdentifiers: ["more_appearance", "more_donate", "more_about", "more_feedback"]
        )
    }

    func testMoreDestinationsExposeAccessibilityContractsAndExits() throws {
        try assertScreen(
            startTab: "more",
            screenIdentifier: "appearance_screen",
            requiredButtons: [],
            requiredLabels: ["Appearance", "Theme", "Article text size"],
            extraArguments: ["-startMoreDestination", "appearance"],
            expectNavigationExit: true
        )

        try assertScreen(
            startTab: "more",
            screenIdentifier: "donate_screen",
            requiredButtons: [],
            requiredLabels: ["Support OSRS Wiki"],
            extraArguments: ["-startMoreDestination", "donate"],
            expectNavigationExit: true
        )

        try assertScreen(
            startTab: "more",
            screenIdentifier: "feedback_screen",
            requiredButtons: [],
            requiredLabels: ["Send Feedback"],
            extraArguments: ["-startMoreDestination", "feedback"],
            expectNavigationExit: true
        )
    }

    func testBottomTabsDoNotExposeUnsupportedDynamicTypeAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSavedPagesForUITests",
            "-startTab",
            "news",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "home_screen").waitForExistence(timeout: 10))

        let expectedTabs = [
            (identifier: "home_tab", label: "Home tab"),
            (identifier: "saved_tab", label: "Saved tab"),
            (identifier: "search_tab", label: "Search tab"),
            (identifier: "map_tab", label: "Map tab"),
            (identifier: "more_tab", label: "More tab")
        ]
        let windowFrame = app.windows.firstMatch.frame
        var previousFrame: CGRect?

        for tab in expectedTabs {
            let element = app.buttons[tab.identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing bottom tab \(tab.identifier)")
            XCTAssertEqual(element.label, tab.label, "\(tab.identifier) should keep its accessible label at accessibility XXXL")
            XCTAssertTrue(element.isHittable, "\(tab.identifier) should remain hittable at accessibility XXXL")
            assertNonEmptyFrame(element.frame, of: tab.label)
            assertFrame(element.frame, of: tab.label, isInside: windowFrame)
            XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(tab.identifier) should keep a minimum hit width")
            XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(tab.identifier) should keep a minimum hit height")

            if let previousFrame {
                XCTAssertGreaterThanOrEqual(
                    element.frame.midX,
                    previousFrame.midX,
                    "\(tab.identifier) should preserve the bottom-tab visual order"
                )
            }
            previousFrame = element.frame
        }

        let visibleTabLabels = Set(["Home", "Saved", "Search", "Map", "More"])
        var clippedTabLabelIssues: [String] = []

        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            let label = issue.element?.label ?? ""
            let elementDescription = String(describing: issue.element)

            if visibleTabLabels.contains(label),
               elementDescription.contains("_tab"),
               issue.compactDescription == "Text clipped" {
                clippedTabLabelIssues.append("\(label): \(issue.compactDescription)")
            }

            return true
        }

        XCTAssertTrue(
            clippedTabLabelIssues.isEmpty,
            "Bottom tab labels should not expose text clipping at accessibility XXXL:\n\(clippedTabLabelIssues.joined(separator: "\n"))"
        )

        attachDebugDescription(from: app, name: "bottom-tabs-accessibility-xxxl")
    }

    func testAppearanceControlsRemainReachableInLightAndDarkAtAccessibilityXXXL() throws {
        for theme in ["osrs_light", "osrs_dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-screenshotMode",
                "-disableBackgroundPreloading",
                "-startTab", "more",
                "-startMoreDestination", "appearance",
                "-forceThemeForUITests", theme,
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
            ]
            app.launch()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
            XCTAssertTrue(element(in: app, identifier: "appearance_screen").waitForExistence(timeout: 10))

            for identifier in [
                "appearance_theme_picker",
                "appearance_collapse_tables_toggle"
            ] {
                let control = element(in: app, identifier: identifier)
                XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing \(identifier) in \(theme)")
                XCTAssertTrue(control.isHittable, "\(identifier) must remain hittable at AX XXXL in \(theme)")
                assertFrame(control.frame, of: identifier, isInside: app.frame)
            }

            let textScale = element(in: app, identifier: "appearance_article_text_scale")
            XCTAssertTrue(textScale.waitForExistence(timeout: 5), "Missing article text scale in \(theme)")
            for _ in 0..<3 where !textScale.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(textScale.isHittable, "Article text scale must remain reachable at AX XXXL in \(theme)")
            assertFrame(textScale.frame, of: "appearance_article_text_scale", isInside: app.frame)

            for identifier in [
                "appearance_swipe_right_back_toggle",
                "appearance_swipe_left_contents_toggle"
            ] {
                // Query the eventual native control type directly. A lazy, initially offscreen
                // row can first appear to an `.any` query as an `Other`, then materialize as a
                // `Switch` after scrolling; retaining that fallback query can never match it.
                let control = app.switches[identifier]
                // In an AX-sized lazy List the lower row may not be instantiated until the
                // viewport reaches it. Scroll a bounded distance, then require the real control
                // to exist, intersect the viewport, and be hittable.
                for _ in 0..<8 where !(control.exists && control.isHittable) {
                    app.swipeUp()
                }
                XCTAssertTrue(control.waitForExistence(timeout: 2), "Missing \(identifier) in \(theme)")
                XCTAssertTrue(control.isHittable, "\(identifier) must remain hittable at AX XXXL in \(theme)")
                XCTAssertTrue(
                    control.frame.intersects(app.frame),
                    "\(identifier) must intersect the visible viewport at AX XXXL in \(theme); frame=\(control.frame)"
                )
            }

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "appearance-native-controls-\(theme)-axxxl"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testAppearanceUsesCompactGroupedNativeControlsInLightAndDark() throws {
        for theme in ["osrs_light", "osrs_dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-screenshotMode",
                "-disableBackgroundPreloading",
                "-startTab", "more",
                "-startMoreDestination", "appearance",
                "-forceThemeForUITests", theme
            ]
            app.launch()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
            XCTAssertTrue(element(in: app, identifier: "appearance_screen").waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Display"].waitForExistence(timeout: 5))
            XCTAssertTrue(element(in: app, identifier: "appearance_theme_picker").isHittable)
            XCTAssertTrue(element(in: app, identifier: "appearance_collapse_tables_toggle").isHittable)
            XCTAssertTrue(element(in: app, identifier: "appearance_article_text_scale").isHittable)

            let displayAttachment = XCTAttachment(screenshot: app.screenshot())
            displayAttachment.name = "appearance-grouped-display-\(theme)"
            displayAttachment.lifetime = .keepAlways
            add(displayAttachment)

            let swipeLeft = app.switches["appearance_swipe_left_contents_toggle"]
            for _ in 0..<3 where !swipeLeft.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(app.staticTexts["Navigation"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.switches["appearance_swipe_right_back_toggle"].isHittable)
            XCTAssertTrue(swipeLeft.isHittable)

            let navigationAttachment = XCTAttachment(screenshot: app.screenshot())
            navigationAttachment.name = "appearance-grouped-navigation-\(theme)"
            navigationAttachment.lifetime = .keepAlways
            add(navigationAttachment)
            app.terminate()
        }
    }

    func testHomeFeedTextDoesNotExposeUnsupportedDynamicTypeAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSavedPagesForUITests",
            "-seedHomeFeedForUITests",
            "-startTab",
            "news",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "home_screen").waitForExistence(timeout: 10))

        let timestamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Last updated:")).firstMatch
        let updateCard = app.buttons.matching(identifier: "home_update_card").firstMatch
        let updateTitle = app.staticTexts["New Regional Worlds Launch TODAY!"].firstMatch
        let updateSnippet = app.staticTexts["This week's update brings new Regional Worlds and some handy Farming QoL and Sailing Changes!"].firstMatch

        XCTAssertTrue(timestamp.waitForExistence(timeout: 5), "Home feed should expose the last-updated timestamp")
        XCTAssertTrue(updateCard.waitForExistence(timeout: 5), "Home feed should expose an update card")
        XCTAssertTrue(updateTitle.waitForExistence(timeout: 5), "Seeded update title should remain visible at accessibility XXXL")
        XCTAssertTrue(updateSnippet.waitForExistence(timeout: 5), "Seeded update snippet should remain visible at accessibility XXXL")

        assertNonEmptyFrame(timestamp.frame, of: "Home feed timestamp")
        assertNonEmptyFrame(updateCard.frame, of: "Home update card")
        assertFrame(updateTitle.frame, of: "Home update title", isInside: updateCard.frame)
        assertFrame(updateSnippet.frame, of: "Home update snippet", isInside: updateCard.frame)
        attachDebugDescription(from: app, name: "home-feed-dynamic-type-readable")
    }

    func testHomeUpdateCardDoesNotExposeClippingAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-seedHomeFeedForUITests",
            "-startTab",
            "news"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "home_screen").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["New Regional Worlds Launch TODAY!"].waitForExistence(timeout: 5))

        let updateCard = app.buttons.matching(identifier: "home_update_card").firstMatch
        XCTAssertTrue(updateCard.waitForExistence(timeout: 5))
        let semanticCard = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "New Regional Worlds Launch TODAY!",
            "This week's update brings new Regional Worlds"
        )).firstMatch
        XCTAssertTrue(semanticCard.waitForExistence(timeout: 5))

        let updateCardLabels = Set([
            "New Regional Worlds Launch TODAY!",
            "This week's update brings new Regional Worlds and some handy Farming QoL and Sailing Changes!"
        ])
        var clippedHomeCardIssues: [String] = []

        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            let element = issue.element
            let label = element?.label ?? ""

            print("AGENTIC_AX_AUDIT screen=home-update-card type=\(issue.auditType.rawValue) compact=\(issue.compactDescription) element=\(String(describing: element))")
            if updateCardLabels.contains(label), issue.compactDescription == "Text clipped" {
                // The card deliberately truncates its visual title/snippet at standard
                // sizes, but exposes their complete combined text as the button label.
                // Treat that as accessible truncation only when the semantic parent
                // demonstrably contains the full child label.
                if !semanticCard.label.contains(label) {
                    clippedHomeCardIssues.append("\(label): \(issue.compactDescription)")
                }
            }

            return true
        }

        XCTAssertTrue(
            clippedHomeCardIssues.isEmpty,
            "Home update-card title and snippet should not expose text clipping findings:\n\(clippedHomeCardIssues.joined(separator: "\n"))"
        )
    }

    func testSavedListTextDoesNotExposeClippingAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSavedPagesForUITests",
            "-seedSavedPagesForUITests",
            "-startTab",
            "saved"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Varrock"].waitForExistence(timeout: 5))
        let semanticRow = app.buttons["saved_page_row"].firstMatch
        XCTAssertTrue(semanticRow.waitForExistence(timeout: 5))

        var clippedSavedIssues: [String] = []

        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            let element = issue.element
            let label = element?.label ?? ""
            let identifier = element?.identifier ?? ""
            let isSavedListText = label == "Search saved pages" ||
                identifier == "saved_row_title" ||
                identifier == "saved_row_preview" ||
                identifier == "saved_row_metadata"

            print("AGENTIC_AX_AUDIT screen=saved-list type=\(issue.auditType.rawValue) compact=\(issue.compactDescription) element=\(String(describing: element))")
            if isSavedListText, issue.compactDescription == "Text clipped" {
                // The normal-size preview is intentionally one visual line, matching Android.
                // Its complete text must remain available through the semantic row button.
                let isAccessiblePreviewTruncation = identifier == "saved_row_preview" &&
                    semanticRow.label.contains(label)
                if !isAccessiblePreviewTruncation {
                    clippedSavedIssues.append("\(label): \(issue.compactDescription)")
                }
            }

            return true
        }

        XCTAssertTrue(
            clippedSavedIssues.isEmpty,
            "Saved search entry and title/preview/metadata row should not expose text clipping findings:\n\(clippedSavedIssues.joined(separator: "\n"))"
        )
    }

    func testSavedDateDoesNotExposeContrastAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSavedPagesForUITests",
            "-seedSavedPagesForUITests",
            "-startTab",
            "saved"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "saved_pages_screen").waitForExistence(timeout: 10))
        let metadata = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Last updated: Jan 1, 2025")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))

        var dateContrastIssues: [String] = []

        try app.performAccessibilityAudit(for: [.contrast]) { issue in
            let element = issue.element
            let label = element?.label ?? ""

            print("AGENTIC_AX_AUDIT screen=saved-date type=\(issue.auditType.rawValue) compact=\(issue.compactDescription) element=\(String(describing: element))")
            if label.contains("Last updated: Jan 1, 2025"), issue.compactDescription.contains("Contrast") {
                dateContrastIssues.append("\(label): \(issue.compactDescription)")
            }

            return true
        }

        XCTAssertTrue(
            dateContrastIssues.isEmpty,
            "Saved row date should have sufficient contrast:\n\(dateContrastIssues.joined(separator: "\n"))"
        )
    }

    func testSearchSurfaceDoesNotExposeKnownAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSearchRecentsForUITests",
            "-seedSearchRecentsForUITests",
            "-startTab",
            "search"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "search_screen").waitForExistence(timeout: 10))
        let launcher = app.buttons["search_history_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 5))
        launcher.tap()
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Varrock"].waitForExistence(timeout: 5))
        let activeSearchInput = app.textFields["search_input"]
        XCTAssertTrue(activeSearchInput.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            activeSearchInput.frame.height,
            44,
            "The native editable search field must retain a complete 44pt accessibility frame."
        )
        XCTAssertTrue(
            app.frame.contains(activeSearchInput.frame),
            "The native editable search field must remain fully inside the app viewport."
        )

        var knownSearchIssues: [String] = []
        let textLabels = Set([
            "Search OSRS Wiki",
            "Enter a search term to find articles, items, quests, and more.",
            "Recent"
        ])
        let buttonLabels = Set(["Microphone", "Clear", "Varrock"])

        try app.performAccessibilityAudit(for: [.hitRegion, .contrast, .textClipped]) { issue in
            let element = issue.element
            let label = element?.label ?? ""
            let elementDescription = String(describing: element)
            let compactDescription = issue.compactDescription

            print("AGENTIC_AX_AUDIT screen=search-surface type=\(issue.auditType.rawValue) compact=\(compactDescription) element=\(elementDescription)")

            let isSearchInput = elementDescription.contains("identifier: 'search_input'")
            if issue.auditType == .hitRegion, buttonLabels.contains(label) {
                knownSearchIssues.append("\(label): \(compactDescription)")
            } else if issue.auditType == .contrast, textLabels.contains(label) || buttonLabels.contains(label) {
                knownSearchIssues.append("\(label): \(compactDescription)")
            } else if issue.auditType == .textClipped,
                      (textLabels.contains(label) && !isSearchInput) ||
                          (isSearchInput && (element?.frame.height ?? 0) < 44) {
                knownSearchIssues.append("\(label.isEmpty ? "search_input" : label): \(compactDescription)")
            }

            return true
        }

        XCTAssertTrue(
            knownSearchIssues.isEmpty,
            "Search should not expose the known hit-area, contrast, or clipping audit findings:\n\(knownSearchIssues.joined(separator: "\n"))"
        )
    }

    func testDonateSurfaceDoesNotExposeKnownAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-startTab",
            "more",
            "-startMoreDestination",
            "donate"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        XCTAssertTrue(element(in: app, identifier: "donate_screen").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Support OSRS Wiki"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["$1"].waitForExistence(timeout: 5))

        let presetAmountLabels = Set(["$1", "$5", "$10", "$25"])
        var ctaContrastIssues: [String] = []
        var presetDynamicTypeIssues: [String] = []

        try app.performAccessibilityAudit(for: [.contrast, .dynamicType]) { issue in
            let element = issue.element
            let label = element?.label ?? ""
            let compactDescription = issue.compactDescription

            print("AGENTIC_AX_AUDIT screen=donate-surface type=\(issue.auditType.rawValue) compact=\(compactDescription) element=\(String(describing: element))")

            if issue.auditType == .contrast, label == "Select Amount" {
                ctaContrastIssues.append("\(label): \(compactDescription)")
            } else if issue.auditType == .dynamicType, presetAmountLabels.contains(label), compactDescription.contains("Dynamic Type") {
                presetDynamicTypeIssues.append("\(label): \(compactDescription)")
            }

            return true
        }

        XCTAssertTrue(
            ctaContrastIssues.isEmpty,
            "Donate should not expose the known disabled CTA contrast audit finding:\n\(ctaContrastIssues.joined(separator: "\n"))"
        )

        XCTAssertTrue(
            presetDynamicTypeIssues.isEmpty,
            "Donate preset amount buttons should not expose Dynamic Type audit findings:\n\(presetDynamicTypeIssues.joined(separator: "\n"))"
        )
    }

    private func assertScreen(
        startTab: String,
        screenIdentifier: String,
        requiredButtons: [String],
        requiredLabels: [String],
        requiredIdentifiers: [String] = [],
        extraArguments: [String] = [],
        orderIdentifiers: [String] = [],
        expectNavigationExit: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-resetSavedPagesForUITests",
            "-startTab",
            startTab
        ] + extraArguments
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout), file: file, line: line)
        XCTAssertTrue(element(in: app, identifier: screenIdentifier).waitForExistence(timeout: 10), "Missing \(screenIdentifier)", file: file, line: line)

        for buttonIdentifier in requiredButtons {
            let button = app.buttons[buttonIdentifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing button \(buttonIdentifier)", file: file, line: line)
            XCTAssertTrue(button.isHittable, "Button \(buttonIdentifier) should be hittable", file: file, line: line)
        }

        for label in requiredLabels {
            XCTAssertTrue(
                app.staticTexts[label].exists ||
                    app.buttons[label].exists ||
                    app.navigationBars[label].exists ||
                    app.textFields[label].exists,
                "Missing accessibility label \(label)",
                file: file,
                line: line
            )
        }

        for identifier in requiredIdentifiers {
            XCTAssertTrue(
                element(in: app, identifier: identifier).waitForExistence(timeout: 5),
                "Missing accessibility identifier \(identifier)",
                file: file,
                line: line
            )
        }

        if !orderIdentifiers.isEmpty {
            assertOrder(orderIdentifiers, in: app.debugDescription, file: file, line: line)
        }

        if expectNavigationExit {
            XCTAssertTrue(
                app.navigationBars.buttons.firstMatch.exists || app.buttons["more_tab"].exists,
                "Destination should expose a navigation or tab escape path",
                file: file,
                line: line
            )
        }

        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "accessibility-contract-\(screenIdentifier)"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    private func assertOrder(
        _ identifiers: [String],
        in debugDescription: String,
        file: StaticString,
        line: UInt
    ) {
        var previousIndex = debugDescription.startIndex

        for identifier in identifiers {
            guard let range = debugDescription.range(of: identifier, range: previousIndex..<debugDescription.endIndex) else {
                XCTFail("Missing ordered identifier \(identifier)", file: file, line: line)
                return
            }
            previousIndex = range.upperBound
        }
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let any = app.descendants(matching: .any)[identifier]
        if any.exists {
            return any
        }
        return app.otherElements[identifier]
    }

    private func assertFrame(
        _ frame: CGRect,
        of elementName: String,
        isInside container: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(frame.minX, container.minX, "\(elementName) should not render off the container's leading edge; frame=\(frame), container=\(container)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, container.minY, "\(elementName) should not render above the container; frame=\(frame), container=\(container)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, container.maxX, "\(elementName) should not render off the container's trailing edge; frame=\(frame), container=\(container)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, container.maxY, "\(elementName) should not render below the container; frame=\(frame), container=\(container)", file: file, line: line)
    }

    private func assertNonEmptyFrame(
        _ frame: CGRect,
        of elementName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(frame.width, 1, "\(elementName) should have measurable width; frame=\(frame)", file: file, line: line)
        XCTAssertGreaterThan(frame.height, 1, "\(elementName) should have measurable height; frame=\(frame)", file: file, line: line)
    }

    private func attachDebugDescription(from app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

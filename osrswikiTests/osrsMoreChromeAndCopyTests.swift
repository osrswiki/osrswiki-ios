import XCTest
@testable import osrswiki

final class osrsMoreChromeAndCopyTests: XCTestCase {
    func testEveryPushedMoreDestinationUsesSharedTranslucentChrome() throws {
        let root = try repositoryRoot()
        let chrome = try source(root, "platforms/ios/osrswiki/Views/Components/osrsMoreDestinationChrome.swift")
        let settingsPage = try source(root, "platforms/ios/osrswiki/Views/Settings/osrsSettingsPage.swift")
        let appearance = try source(root, "platforms/ios/osrswiki/Views/Settings/AppearanceSettingsView.swift")
        let downloads = try source(root, "platforms/ios/osrswiki/Views/Settings/osrsDownloadSettingsView.swift")
        let donate = try source(root, "platforms/ios/osrswiki/Views/DonateView.swift")
        let about = try source(root, "platforms/ios/osrswiki/Views/AboutView.swift")
        let feedback = try source(root, "platforms/ios/osrswiki/Views/FeedbackView.swift")
        let app = try source(root, "platforms/ios/osrswiki/osrswikiApp.swift")
        let live = try source(root, "platforms/ios/osrswiki/Models/osrsLiveThemeApplier.swift")

        XCTAssertTrue(chrome.contains("osrsLiveThemeApplier.apply"))
        XCTAssertFalse(chrome.contains("toolbarBackground(Color(osrsTheme.background)"))
        XCTAssertTrue(chrome.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(settingsPage.contains("osrsMoreDestinationChrome"))
        XCTAssertTrue(settingsPage.contains(".tint(Color(osrsTheme.primary))"))
        XCTAssertTrue(settingsPage.contains(".accentColor(Color(osrsTheme.primary))"))
        for file in [appearance, downloads] {
            XCTAssertTrue(file.contains("osrsSettingsPage("))
            XCTAssertFalse(file.contains(".id(themeManager.selectedTheme)"))
        }
        for file in [donate, about, feedback] {
            XCTAssertTrue(file.contains("osrsMoreDestinationChrome"))
            XCTAssertFalse(file.contains(".id(themeManager.selectedTheme)"))
            XCTAssertFalse(file.contains("updateNavigationBarAppearance"))
        }
        XCTAssertTrue(appearance.contains("Text(\"Display\")"))
        XCTAssertTrue(appearance.contains("Text(\"Navigation\")"))
        XCTAssertTrue(app.contains("osrsLiveThemeApplier.apply"))
        XCTAssertTrue(live.contains("apply(theme, toView:"))
        XCTAssertTrue(live.contains("UISwitch"))
        XCTAssertTrue(live.contains("tintSwitchLike"))
        XCTAssertTrue(live.contains("localizedCaseInsensitiveContains(\"switch\")"))
        XCTAssertTrue(live.contains("scheduleFollowUp"))
        XCTAssertTrue(live.contains("UISlider"))
        XCTAssertTrue(live.contains("UISegmentedControl"))
        XCTAssertTrue(live.contains("if #available(iOS 26.0, *)"))
    }

    func testDonateAndFeedbackCopyAndOutboundRowsMatchTheSharedPolicy() throws {
        let root = try repositoryRoot()
        let donate = try source(root, "platforms/ios/osrswiki/Views/DonateView.swift")
        let feedback = try source(root, "platforms/ios/osrswiki/Views/FeedbackView.swift")
        let about = try source(root, "platforms/ios/osrswiki/Views/AboutView.swift")
        let outbound = try source(root, "platforms/ios/osrswiki/Views/Components/osrsOutboundLinkRow.swift")

        XCTAssertTrue(donate.contains("This app is free. Nothing is locked behind a donation."))
        XCTAssertTrue(donate.contains("App Store and the time it takes to keep the app working."))
        XCTAssertTrue(donate.contains("The Old School RuneScape Wiki is run by volunteers. Support them too if you can."))
        XCTAssertTrue(donate.contains("osrsOutboundLinkRow(title: \"Donate to Wiki\""))
        XCTAssertTrue(donate.contains("https://www.patreon.com/runescapewiki"))
        XCTAssertFalse(donate.contains("currency picker"))
        XCTAssertTrue(feedback.contains("osrsMoreDestinationChrome(title: \"Send Feedback\")"))
        XCTAssertFalse(feedback.contains("Help & Feedback"))
        XCTAssertTrue(feedback.contains("Rate This App"))
        XCTAssertTrue(feedback.contains("Report an Issue"))
        XCTAssertTrue(feedback.contains("Request a Feature"))
        XCTAssertTrue(feedback.contains("osrsOutboundLinkRow"))
        XCTAssertFalse(feedback.contains(".onTapGesture"))
        XCTAssertTrue(about.contains("osrsOutboundLinkRow"))
        XCTAssertTrue(outbound.contains("The link is the hit target"))
        XCTAssertTrue(outbound.contains(".accessibilityAddTraits(.isLink)"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("platforms/ios/osrswiki.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root from \(#filePath)")
    }

    private func source(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

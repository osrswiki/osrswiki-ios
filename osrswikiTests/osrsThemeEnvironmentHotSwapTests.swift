import SwiftUI
import UIKit
import XCTest
@testable import osrswiki

@MainActor
final class osrsThemeEnvironmentHotSwapTests: XCTestCase {
    func testEnvironmentThemeColorsUpdateWhenSelectionChangesWithoutRemounting() {
        let suiteName = "osrsThemeEnvironmentHotSwapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let themeManager = osrsThemeManager(userDefaults: defaults)
        themeManager.setTheme(.osrsDark)

        var observedTextHex: [String] = []
        let host = UIHostingController(rootView: osrsThemeEnvironmentHarness(
            themeManager: themeManager,
            probe: { osrsThemeEnvironmentProbe(onPrimaryTextHex: { observedTextHex.append($0) }) }
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(observedTextHex.isEmpty, "Probe should publish the initial dark theme text color")
        let darkHex = observedTextHex.last?.uppercased()
        XCTAssertEqual(darkHex, osrsDarkTheme().primaryTextColor.toHex().uppercased())

        themeManager.setTheme(.osrsLight)
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let lightHex = observedTextHex.last?.uppercased()
        XCTAssertNotEqual(
            lightHex,
            darkHex,
            "Environment osrsTheme must hot-swap text color when the selection changes without remounting the page"
        )
        XCTAssertEqual(lightHex, osrsLightTheme().primaryTextColor.toHex().uppercased())
    }

    func testAppearanceSettingsHostedLabelsAndSwitchesHotSwap() {
        let suiteName = "osrsThemeEnvironmentHotSwapTests.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let themeManager = osrsThemeManager(userDefaults: defaults)
        themeManager.setTheme(.osrsDark)
        themeManager.setSwipeRightToGoBackEnabled(true)

        let host = UIHostingController(rootView: osrsThemeEnvironmentHarness(
            themeManager: themeManager,
            probe: { AppearanceSettingsView() }
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        let darkSwitch = firstSwitchLike(in: host.view)
        XCTAssertNotNil(darkSwitch, "Appearance should mount a switch-like control\n\(describeViews(host.view))")
        let darkOnTint = tintColor(of: darkSwitch!)
        let darkThumb = thumbTint(of: darkSwitch!)

        themeManager.setTheme(.osrsLight)
        osrsLiveThemeApplier.apply(
            themeManager.currentTheme,
            to: window,
            colorScheme: .light,
            scheduleFollowUp: true
        )
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        let lightSwitch = firstSwitchLike(in: host.view)
        XCTAssertNotEqual(
            tintColor(of: lightSwitch),
            darkOnTint,
            "ON switches must retint immediately on dark→light"
        )
        if #available(iOS 26.0, *) {
            XCTAssertNil(thumbTint(of: lightSwitch))
        } else {
            XCTAssertEqual(thumbTint(of: lightSwitch), osrsLiveThemeApplier.switchThumbColor())
        }
        _ = darkThumb
    }
}

private struct osrsThemeEnvironmentHarness<Content: View>: View {
    @ObservedObject var themeManager: osrsThemeManager
    let probe: () -> Content

    var body: some View {
        NavigationStack {
            probe()
        }
        .environmentObject(themeManager)
        .environment(\.osrsTheme, themeManager.currentTheme)
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
        .tint(Color(themeManager.currentTheme.primary))
    }
}

private struct osrsThemeEnvironmentProbe: View {
    @Environment(\.osrsTheme) private var osrsTheme
    let onPrimaryTextHex: (String) -> Void

    var body: some View {
        let hex = osrsTheme.primaryTextColor.toHex()
        Color.clear
            .accessibilityIdentifier("osrs_theme_environment_probe")
            .task(id: hex) {
                onPrimaryTextHex(hex)
            }
    }
}

private func firstSwitchLike(in view: UIView?) -> UIView? {
    guard let view else { return nil }
    if view is UISwitch { return view }
    let typeName = String(describing: type(of: view))
    if typeName.localizedCaseInsensitiveContains("switch") {
        return view
    }
    for subview in view.subviews {
        if let match = firstSwitchLike(in: subview) {
            return match
        }
    }
    return nil
}

private func tintColor(of view: UIView?) -> UIColor? {
    guard let view else { return nil }
    if let toggle = view as? UISwitch {
        return toggle.onTintColor
    }
    return view.tintColor
}

private func thumbTint(of view: UIView?) -> UIColor? {
    (view as? UISwitch)?.thumbTintColor
}

private func describeViews(_ view: UIView, depth: Int = 0) -> String {
    let indent = String(repeating: "  ", count: depth)
    var lines = ["\(indent)\(type(of: view)) frame=\(view.frame)"]
    if let label = view as? UILabel {
        lines.append("\(indent)  text=\(label.text ?? "nil") color=\(String(describing: label.textColor))")
    }
    for subview in view.subviews.prefix(40) {
        lines.append(describeViews(subview, depth: depth + 1))
    }
    return lines.joined(separator: "\n")
}

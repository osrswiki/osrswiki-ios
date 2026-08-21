import XCTest
import UIKit
@testable import osrswiki

@MainActor
final class osrsLiveThemeApplierTests: XCTestCase {
    func testLiveWalkRetintsAlreadyMountedControlsWhenThemeChanges() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let toggle = UISwitch()
        let slider = UISlider()
        let segmented = UISegmentedControl(items: ["A", "B"])
        window.addSubview(toggle)
        window.addSubview(slider)
        window.addSubview(segmented)
        window.makeKeyAndVisible()

        osrsLiveThemeApplier.apply(osrsLightTheme(), to: window, colorScheme: .light)
        let lightOnTint = toggle.onTintColor
        let lightSlider = slider.minimumTrackTintColor
        let lightSegment = segmented.selectedSegmentTintColor
        XCTAssertNotNil(lightOnTint)
        XCTAssertNotNil(lightSlider)
        XCTAssertNotNil(lightSegment)

        osrsLiveThemeApplier.apply(osrsDarkTheme(), to: window, colorScheme: .dark)
        XCTAssertNotEqual(toggle.onTintColor, lightOnTint)
        XCTAssertNotEqual(slider.minimumTrackTintColor, lightSlider)
        XCTAssertNotEqual(segmented.selectedSegmentTintColor, lightSegment)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
    }

    func testAppearanceProxyAloneDoesNotRetintMountedSwitches() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let toggle = UISwitch()
        toggle.onTintColor = .red
        window.addSubview(toggle)
        window.makeKeyAndVisible()

        let previousAppearance = UISwitch.appearance().onTintColor
        UISwitch.appearance().onTintColor = .blue
        XCTAssertEqual(toggle.onTintColor, .red)

        osrsLiveThemeApplier.apply(osrsDarkTheme(), toView: toggle)
        XCTAssertNotEqual(toggle.onTintColor, .red)
        UISwitch.appearance().onTintColor = previousAppearance
    }

    func testSwitchThumbsUseHighContrastBrownInsteadOfParchment() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let toggle = UISwitch()
        window.addSubview(toggle)
        window.makeKeyAndVisible()

        osrsLiveThemeApplier.apply(osrsLightTheme(), to: window, colorScheme: .light)
        XCTAssertEqual(toggle.thumbTintColor, osrsLiveThemeApplier.switchThumbColor())
        XCTAssertNotEqual(toggle.thumbTintColor, UIColor(osrsLightTheme().surface))

        osrsLiveThemeApplier.apply(osrsDarkTheme(), to: window, colorScheme: .dark)
        XCTAssertEqual(toggle.thumbTintColor, osrsLiveThemeApplier.switchThumbColor())
    }
}

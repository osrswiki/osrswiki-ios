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

    func testLiveWalkRetintsMountedMenuButtonTitlesWhenThemeChanges() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let button = UIButton(type: .system)
        button.setTitle("Light", for: .normal)
        button.setTitleColor(.white, for: .normal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.title = "Light"
            config.baseForegroundColor = .white
            button.configuration = config
        }
        window.addSubview(button)
        window.makeKeyAndVisible()

        osrsLiveThemeApplier.apply(osrsLightTheme(), to: window, colorScheme: .light)
        let lightInk = UIColor(osrsLightTheme().primaryTextColor)
        XCTAssertNotEqual(button.titleColor(for: .normal), UIColor.white)
        XCTAssertEqual(
            button.titleColor(for: .normal)?.cgColor,
            lightInk.cgColor
        )
        if #available(iOS 15.0, *) {
            XCTAssertEqual(
                button.configuration?.baseForegroundColor?.cgColor,
                lightInk.cgColor
            )
        }
    }

    func testSwitchThumbsUseHighContrastBrownInsteadOfParchment() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let toggle = UISwitch()
        window.addSubview(toggle)
        window.makeKeyAndVisible()

        osrsLiveThemeApplier.apply(osrsLightTheme(), to: window, colorScheme: .light)
        if #available(iOS 26.0, *) {
            XCTAssertNil(
                toggle.thumbTintColor,
                "iOS 26 glass switches need the system thumb so ON is thumb-in-track, not a brown pill"
            )
            XCTAssertEqual(toggle.onTintColor, UIColor(osrsLightTheme().primary))
        } else {
            XCTAssertEqual(toggle.thumbTintColor, osrsLiveThemeApplier.switchThumbColor())
            XCTAssertNotEqual(toggle.thumbTintColor, UIColor(osrsLightTheme().surface))
        }

        osrsLiveThemeApplier.apply(osrsDarkTheme(), to: window, colorScheme: .dark)
        if #available(iOS 26.0, *) {
            XCTAssertNil(toggle.thumbTintColor)
            XCTAssertEqual(toggle.onTintColor, UIColor(osrsDarkTheme().primary))
        } else {
            XCTAssertEqual(toggle.thumbTintColor, osrsLiveThemeApplier.switchThumbColor())
        }
    }

    func testNestedSwitchesAreRetintedThroughTheViewWalk() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let host = UIView()
        let toggle = UISwitch()
        toggle.onTintColor = .red
        host.addSubview(toggle)
        window.addSubview(host)
        window.makeKeyAndVisible()

        osrsLiveThemeApplier.apply(osrsDarkTheme(), to: window, colorScheme: .dark, scheduleFollowUp: true)
        XCTAssertNotEqual(toggle.onTintColor, .red)
        if #available(iOS 26.0, *) {
            XCTAssertNil(toggle.thumbTintColor)
        } else {
            XCTAssertEqual(toggle.thumbTintColor, osrsLiveThemeApplier.switchThumbColor())
        }
        XCTAssertEqual(toggle.tintColor, UIColor(osrsDarkTheme().primary))
    }
}

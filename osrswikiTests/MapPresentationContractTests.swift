import SwiftUI
import UIKit
import XCTest
@testable import osrswiki

@MainActor
final class MapPresentationContractTests: XCTestCase {
    func testBlockingLoaderOnlyAppearsBeforeTheFirstReadyMap() {
        XCTAssertTrue(
            osrsShouldShowInitialMapLoader(
                hasPresentedInitialMap: false,
                errorMessage: nil
            )
        )
        XCTAssertFalse(
            osrsShouldShowInitialMapLoader(
                hasPresentedInitialMap: true,
                errorMessage: nil
            ),
            "Floor and realm switches should keep the already-rendered map visible"
        )
        XCTAssertFalse(
            osrsShouldShowInitialMapLoader(
                hasPresentedInitialMap: false,
                errorMessage: "Missing map asset"
            ),
            "An actionable error should replace, not overlap, the initial loader"
        )
    }

    func testMapControlsResolveToThemeSurfaceContrastPairs() {
        let light = osrsLightTheme()
        let dark = osrsDarkTheme()

        XCTAssertEqual(UIColor(light.mapControlBackgroundColor), UIColor(light.surface))
        XCTAssertEqual(UIColor(light.mapControlTextColor), UIColor(light.onSurface))
        XCTAssertEqual(UIColor(dark.mapControlBackgroundColor), UIColor(dark.surface))
        XCTAssertEqual(UIColor(dark.mapControlTextColor), UIColor(dark.onSurface))
    }
}

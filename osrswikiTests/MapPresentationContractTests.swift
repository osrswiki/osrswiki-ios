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

    func testMapPlaneLabelsStayWesternDigitsAndUseVerbatimText() throws {
        for plane in 0...3 {
            let label = osrsMapPlaneLabel(plane)
            XCTAssertEqual(label, String(plane))
            XCTAssertTrue(label.allSatisfy { $0 >= "0" && $0 <= "9" })
            XCTAssertFalse(
                label.contains { $0 >= "\u{0660}" && $0 <= "\u{0669}" },
                "Plane \(plane) leaked Eastern Arabic-Indic digits: \(label)"
            )
        }
        let mapSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "platforms/ios/osrswiki/Views/OSRSMapLibreView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(mapSource.contains("Text(verbatim: osrsMapPlaneLabel(store.activePlane))"))
        XCTAssertFalse(mapSource.contains("Text(\"\\(store.activePlane)\")"))
    }

    func testMapControlsResolveToThemeSurfaceContrastPairs() {
        let light = osrsLightTheme()
        let dark = osrsDarkTheme()

        XCTAssertEqual(UIColor(light.mapControlBackgroundColor), UIColor(light.surface))
        XCTAssertEqual(UIColor(light.mapControlTextColor), UIColor(light.onSurface))
        XCTAssertEqual(UIColor(dark.mapControlBackgroundColor), UIColor(dark.surface))
        XCTAssertEqual(UIColor(dark.mapControlTextColor), UIColor(dark.onSurface))
        XCTAssertGreaterThan(
            osrsOverlayChromeMetrics.mapFloatingControlBottomInset,
            osrsOverlayChromeMetrics.floatingBarHeight,
            "Floor chrome must clear the floating tab / article-map bar"
        )
    }

    func testLightMapTabBarUsesOpaqueParchmentFill() throws {
        let surface = UIColor(osrsLightTheme().surface)
        let mapLight = osrsReadableChromePolicy.tabBarOpaqueFill(
            selectedTab: .map,
            isLightTheme: true,
            surface: surface
        )
        XCTAssertNotNil(mapLight)
        XCTAssertEqual(mapLight, surface)
        XCTAssertNil(
            osrsReadableChromePolicy.tabBarOpaqueFill(
                selectedTab: .map,
                isLightTheme: false,
                surface: surface
            )
        )
        XCTAssertNil(
            osrsReadableChromePolicy.tabBarOpaqueFill(
                selectedTab: .news,
                isLightTheme: true,
                surface: surface
            )
        )
        let tabSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "platforms/ios/osrswiki/Views/CustomMainTabView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(tabSource.contains("toolbarBackground"))
        XCTAssertTrue(tabSource.contains("selectedTab == .map && themeManager.currentTheme is osrsLightTheme"))
        XCTAssertTrue(tabSource.contains("toolbarBackground(Color.clear, for: .tabBar)"))
        XCTAssertFalse(tabSource.contains("? .visible"))
        XCTAssertTrue(tabSource.contains("MapView().ignoresSafeArea(edges: .bottom)"))
        let mapSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "platforms/ios/osrswiki/Views/MapView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(mapSource.contains(".ignoresSafeArea(edges: .bottom)"))
        XCTAssertFalse(mapSource.contains("Color.black"))
        let tabBarSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "platforms/ios/osrswiki/Extensions/UITabBar+FastRestore.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(tabBarSource.contains("configureWithTransparentBackground()"))
        XCTAssertTrue(tabBarSource.contains("bar.isTranslucent = true"))
        XCTAssertFalse(tabBarSource.contains("configureWithOpaqueBackground()"))
        XCTAssertFalse(tabBarSource.contains("isTranslucent = opaqueFill == nil"))
    }

    private func repositoryRoot() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        while root.pathComponents.count > 1,
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path) {
            root.deleteLastPathComponent()
        }
        return root
    }
}

import UIKit
import XCTest
@testable import osrswiki

final class osrsWindowSceneGeometryTests: XCTestCase {
    func testKeyboardOverlapUsesContainerMaxYNotAssumedPhoneHeight() {
        let keyboard = CGRect(x: 0, y: 400, width: 700, height: 320)
        XCTAssertEqual(
            osrsWindowSceneGeometry.keyboardOverlap(
                keyboardFrame: keyboard,
                containerMaxY: 500
            ),
            100
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.keyboardOverlap(
                keyboardFrame: keyboard,
                containerMaxY: 390
            ),
            0
        )
    }

    func testContentSizeUsesIndependentHorizontalInsets() {
        let insets = UIEdgeInsets(top: 47, left: 62, bottom: 34, right: 8)
        XCTAssertNotEqual(insets.left, insets.right)
        let size = osrsWindowSceneGeometry.contentSize(
            windowSize: CGSize(width: 700, height: 800),
            safeAreaInsets: insets
        )
        XCTAssertEqual(size.width, 630)
        XCTAssertEqual(size.height, 719)
    }

    func testAccessibilityCardWidthUsesContainerNotHardcodedPhone() {
        XCTAssertEqual(
            osrsWindowSceneGeometry.accessibilityCardWidth(
                isAccessibilitySize: false,
                containerWidth: 700,
                standardWidth: 280
            ),
            280
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.accessibilityCardWidth(
                isAccessibilitySize: true,
                containerWidth: 700,
                standardWidth: 280
            ),
            398
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.accessibilityCardWidth(
                isAccessibilitySize: true,
                containerWidth: 320,
                standardWidth: 280
            ),
            288
        )
    }

    func testFallbackViewportPrefersLiveViewBounds() {
        XCTAssertEqual(
            osrsWindowSceneGeometry.fallbackViewport(
                viewSize: CGSize(width: 512, height: 300),
                fallback: CGSize(width: 390, height: 844)
            ),
            CGSize(width: 512, height: 300)
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.fallbackViewport(
                viewSize: .zero,
                fallback: CGSize(width: 512, height: 300)
            ),
            CGSize(width: 512, height: 300)
        )
    }

    func testLayoutSourcesDoNotUseUIScreenMainBounds() throws {
        let root = try repositoryRoot()
        let layoutFiles = [
            "platforms/ios/osrswiki/Views/CustomMainTabView.swift",
            "platforms/ios/osrswiki/Views/NewsView.swift",
            "platforms/ios/osrswiki/Views/ArticleWebView.swift",
            "platforms/ios/osrswiki/Views/OSRSMapLibreView.swift",
            "platforms/ios/osrswiki/Views/Components/osrsInteractiveArticleSwipe.swift",
            "platforms/ios/osrswiki/Utils/osrsArticleWebViewLayout.swift",
            "platforms/ios/osrswiki/Services/osrsPreparedArticleWebViewStore.swift",
            "platforms/ios/osrswiki/Services/osrsThemePreviewRenderer.swift",
            "platforms/ios/osrswiki/Services/osrsTablePreviewRenderer.swift",
            "platforms/ios/osrswiki/Views/Settings/osrsSettingsPreviewExportView.swift",
            "platforms/ios/osrswikiUITests/SearchToMapNavigationTest.swift",
            "platforms/ios/osrswikiUITests/NavigationAutomationTests.swift"
        ]
        for relative in layoutFiles {
            let source = try String(
                contentsOf: root.appendingPathComponent(relative),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains("UIScreen.main.bounds"),
                "\(relative) still sizes layout from UIScreen.main.bounds"
            )
        }

        let helper = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Utils/osrsWindowSceneGeometry.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(helper.contains("coordinateSpace.bounds"))
        XCTAssertTrue(helper.contains("traitCollection.displayScale"))
        XCTAssertTrue(helper.contains("fallbackPhonePortrait"))
    }

    func testProjectDoesNotBumpToIOS27SDK() throws {
        let root = try repositoryRoot()
        let pbxproj = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(pbxproj.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.5;"))
        XCTAssertTrue(pbxproj.contains("LastUpgradeCheck = 1640;"))
        XCTAssertTrue(pbxproj.contains("SWIFT_VERSION = 5.0;"))
        XCTAssertFalse(pbxproj.contains("IPHONEOS_DEPLOYMENT_TARGET = 27"))
        XCTAssertFalse(pbxproj.contains("LastUpgradeCheck = 2700"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return url
    }
}

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

    func testHomeUpdatesCarouselInsetsUnchangedWithoutHorizontalSideChrome() {
        let phonePortrait = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let ipadTypical = UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        let expected = UIEdgeInsets(
            top: 0,
            left: osrsWindowSceneGeometry.homeUpdatesCarouselBaseHorizontalPadding,
            bottom: 0,
            right: osrsWindowSceneGeometry.homeUpdatesCarouselBaseHorizontalPadding
        )
        XCTAssertEqual(expected.left, 16)
        XCTAssertEqual(expected.right, 16)
        XCTAssertEqual(
            osrsWindowSceneGeometry.homeUpdatesCarouselContentInsets(safeAreaInsets: phonePortrait),
            expected
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.homeUpdatesCarouselContentInsets(safeAreaInsets: ipadTypical),
            expected
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.homeUpdatesCarouselContentInsets(safeAreaInsets: .zero),
            expected
        )
    }

    func testHomeUpdatesCarouselInsetsAddIndependentHorizontalSafeArea() {
        let duoLike = UIEdgeInsets(top: 8, left: 62, bottom: 34, right: 8)
        XCTAssertNotEqual(duoLike.left, duoLike.right)
        let insets = osrsWindowSceneGeometry.homeUpdatesCarouselContentInsets(
            safeAreaInsets: duoLike
        )
        XCTAssertEqual(insets.left, 16 + 62)
        XCTAssertEqual(insets.right, 16 + 8)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.bottom, 0)
    }

    func testExtraHorizontalSafeAreaInsetsAreIndependentAndZeroOnPhonePortrait() {
        let phonePortrait = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        XCTAssertEqual(
            osrsWindowSceneGeometry.extraHorizontalSafeAreaInsets(phonePortrait),
            .zero
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.extraHorizontalSafeAreaInsets(.zero),
            .zero
        )

        let duoLike = UIEdgeInsets(top: 8, left: 62, bottom: 34, right: 8)
        let extra = osrsWindowSceneGeometry.extraHorizontalSafeAreaInsets(duoLike)
        XCTAssertEqual(extra.left, 62)
        XCTAssertEqual(extra.right, 8)
        XCTAssertEqual(extra.top, 0)
        XCTAssertEqual(extra.bottom, 0)
        XCTAssertNotEqual(extra.left, extra.right)
        XCTAssertNotEqual(extra.left, extra.left * 2)
    }

    func testOverlayChromeHorizontalInsetsKeepBaseWhenSideChromeIsAbsent() {
        let expected = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        XCTAssertEqual(
            osrsWindowSceneGeometry.overlayChromeHorizontalInsets(
                base: 16,
                safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            ),
            expected
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.homeUpdatesCarouselContentInsets(
                safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            ),
            osrsWindowSceneGeometry.overlayChromeHorizontalInsets(
                base: osrsWindowSceneGeometry.homeUpdatesCarouselBaseHorizontalPadding,
                safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            )
        )
    }

    func testNewsViewInsetsUpdatesCarouselOnlyAndLeavesSearchRandomHorizontal() throws {
        let root = try repositoryRoot()
        let news = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/NewsView.swift"),
            encoding: .utf8
        )
        let helper = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Utils/osrsWindowSceneGeometry.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            helper.contains("homeUpdatesCarouselContentInsets"),
            "Geometry helper must own Duo-gated carousel inset math"
        )
        XCTAssertTrue(
            news.contains("osrsHomeUpdatesCarouselSideChromeInset"),
            "Live Updates carousel must apply the side-chrome inset"
        )
        XCTAssertTrue(
            news.contains("osrsHorizontalSideChromeInset") || news.contains("safeAreaPadding(.horizontal)"),
            "Carousel must use system horizontal safe area, not a hard-coded Duo rail width"
        )
        XCTAssertTrue(
            news.contains("homeUpdatesCarouselBaseHorizontalPadding"),
            "Carousel base padding must come from the shared constant so non-Duo stays 16pt"
        )

        let accessoryRange = news.range(of: "private var homeGlassAccessory")
        XCTAssertNotNil(accessoryRange)
        let afterAccessory = news[accessoryRange!.upperBound...]
        let newsBodyRange = afterAccessory.range(of: "var body: some View")
        let feedRange = news.range(of: "struct WikiFeedContentView")
        XCTAssertNotNil(newsBodyRange)
        XCTAssertNotNil(feedRange)
        let feed = String(news[feedRange!.lowerBound...])
        let accessoryBody = String(news[accessoryRange!.lowerBound..<newsBodyRange!.lowerBound])

        XCTAssertTrue(accessoryBody.contains("osrsTabSearchWithTrailingControl"))
        XCTAssertTrue(accessoryBody.contains("home_search"))
        XCTAssertTrue(accessoryBody.contains("home_random_page"))
        XCTAssertFalse(
            accessoryBody.contains("osrsHomeUpdatesCarouselSideChromeInset"),
            "Search/Random must stay the existing horizontal glass accessory"
        )
        XCTAssertFalse(
            accessoryBody.contains("safeAreaPadding(.horizontal)"),
            "Search/Random must not pick up the Updates carousel inset"
        )

        let carouselMarker = "accessibilityIdentifier(\"home_updates_carousel\")"
        XCTAssertTrue(feed.contains(carouselMarker))
        if let carouselRange = feed.range(of: carouselMarker) {
            let prefix = String(feed[..<carouselRange.lowerBound])
            XCTAssertTrue(
                prefix.contains("osrsHomeUpdatesCarouselSideChromeInset"),
                "Side-chrome inset must wrap the Updates carousel, not the rest of Home"
            )
        }

        XCTAssertEqual(
            news.components(separatedBy: "osrsHomeUpdatesCarouselSideChromeInset").count - 1,
            2,
            "Inset helper should be defined once and applied only to the live Updates carousel"
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

    func testProjectLinksIOS271SDKWithoutRaisingDeploymentTarget() throws {
        let root = try repositoryRoot()
        let pbxproj = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(pbxproj.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.5;"))
        XCTAssertTrue(pbxproj.contains("LastUpgradeCheck = 2710;"))
        XCTAssertTrue(pbxproj.contains("LastSwiftUpdateCheck = 2710;"))
        XCTAssertTrue(pbxproj.contains("SDKROOT = iphoneos27.1;"))
        XCTAssertTrue(pbxproj.contains("SWIFT_VERSION = 5.0;"))
        XCTAssertFalse(pbxproj.contains("IPHONEOS_DEPLOYMENT_TARGET = 27"))
        XCTAssertFalse(pbxproj.contains("LastUpgradeCheck = 1640;"))
    }

    func testOverlayEdgeInsetsSkipInteriorFoldAndInactiveRegions() {
        let container = CGSize(width: 400, height: 800)
        XCTAssertEqual(
            osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
                containerSize: container,
                regions: []
            ),
            .zero,
            "No reserved regions: typical iPhone/iPad overlays stay put"
        )

        let inactiveFold = osrsWindowSceneGeometry.osrsReservedRegionSnapshot(
            frame: CGRect(x: 180, y: 0, width: 40, height: 800),
            margins: .zero,
            isActive: false
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
                containerSize: container,
                regions: [inactiveFold]
            ),
            .zero
        )

        let interiorFold = osrsWindowSceneGeometry.osrsReservedRegionSnapshot(
            frame: CGRect(x: 180, y: 0, width: 40, height: 800),
            margins: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
            isActive: true
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
                containerSize: container,
                regions: [interiorFold]
            ),
            .zero,
            "Center fold must not displace overlay chrome or article-like canvases"
        )

        let leadingRail = osrsWindowSceneGeometry.osrsReservedRegionSnapshot(
            frame: CGRect(x: 0, y: 0, width: 62, height: 800),
            margins: .zero,
            isActive: true
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
                containerSize: container,
                regions: [leadingRail]
            ).left,
            62
        )
        XCTAssertEqual(
            osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
                containerSize: container,
                regions: [leadingRail],
                alreadyAccounted: UIEdgeInsets(top: 0, left: 62, bottom: 0, right: 0)
            ),
            .zero,
            "Window safe-area rail must not double-inset overlay chrome"
        )

        let topCamera = osrsWindowSceneGeometry.osrsReservedRegionSnapshot(
            frame: CGRect(x: 160, y: 0, width: 80, height: 36),
            margins: UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 8),
            isActive: true
        )
        let cameraInsets = osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
            containerSize: container,
            regions: [topCamera]
        )
        XCTAssertEqual(cameraInsets.top, 44)
        XCTAssertEqual(cameraInsets.left, 0)
        XCTAssertEqual(cameraInsets.right, 0)
        XCTAssertEqual(cameraInsets.bottom, 0)
    }

    func testDuoSystemBarAPIAdoptionSites() throws {
        let root = try repositoryRoot()
        let bars = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Utils/osrsDuoSystemBars.swift"
            ),
            encoding: .utf8
        )
        let tabView = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/CustomMainTabView.swift"
            ),
            encoding: .utf8
        )
        let youtube = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/osrsInAppYouTubePlayer.swift"
            ),
            encoding: .utf8
        )
        let dedicated = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/DedicatedSearchView.swift"
            ),
            encoding: .utf8
        )
        let map = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/OSRSMapLibreView.swift"
            ),
            encoding: .utf8
        )
        let article = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/ArticleView.swift"
            ),
            encoding: .utf8
        )
        let articleWeb = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/ArticleWebView.swift"
            ),
            encoding: .utf8
        )
        let htmlBuilder = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Services/osrsPageHtmlBuilder.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(bars.contains("toolbarVerticalBehavior(.automatic)"))
        XCTAssertTrue(bars.contains("toolbarVerticalBehavior(.disabled)"))
        XCTAssertTrue(bars.contains(".axisBehavior(.horizontalOnly)"))
        XCTAssertTrue(bars.contains("toolbarVerticalEdge"))
        XCTAssertTrue(bars.contains("reservedRegions(kind: .division)"))
        XCTAssertTrue(bars.contains("reservedRegions(kind: .occlusion)"))
        XCTAssertTrue(bars.contains("#available(iOS 27.1, *)"))
        XCTAssertTrue(bars.contains("searchRandomStayHorizontalReason"))
        XCTAssertFalse(bars.contains("if isDuo"))

        XCTAssertTrue(tabView.contains("osrsSystemVerticalBarsEnabled()"))
        XCTAssertTrue(youtube.contains("osrsSystemVerticalBarsDisabled()"))
        XCTAssertTrue(youtube.contains("osrsHorizontalOnlyToolbarItem"))
        XCTAssertTrue(dedicated.contains("osrsHorizontalOnlyToolbarItem"))
        XCTAssertTrue(map.contains("osrsReservedRegionOverlayPadding"))
        XCTAssertTrue(article.contains("osrsSystemVerticalBarsDisabled()"))
        XCTAssertTrue(article.contains("osrsHorizontalOnlyToolbarItem"))

        XCTAssertFalse(
            articleWeb.contains("reservedRegions"),
            "Article WKWebView scroll must not be displaced for the fold"
        )
        XCTAssertFalse(htmlBuilder.contains("reservedRegions"))
        XCTAssertFalse(article.contains("reservedRegions"))
    }

    func testHorizontalCarouselsShareSideChromeInsetAndLeaveSearchRandomHorizontal() throws {
        let root = try repositoryRoot()
        let news = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/NewsView.swift"),
            encoding: .utf8
        )
        let dedicated = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/DedicatedSearchView.swift"
            ),
            encoding: .utf8
        )
        let chromeHelper = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(chromeHelper.contains("func osrsHorizontalSideChromeInset"))
        XCTAssertTrue(chromeHelper.contains("safeAreaPadding(.horizontal)"))
        XCTAssertFalse(chromeHelper.contains("osrsHorizontalOnlyToolbarItem"))
        XCTAssertFalse(chromeHelper.contains("if isDuo"))
        XCTAssertTrue(chromeHelper.contains("osrsTabSearchWithTrailingControl"))
        XCTAssertTrue(chromeHelper.contains("struct osrsActiveSearchToolbar"))
        XCTAssertTrue(chromeHelper.contains("osrsDuoSystemBars.searchRandomStayHorizontalReason"))

        XCTAssertGreaterThanOrEqual(
            news.components(separatedBy: "ScrollView(.horizontal").count - 1,
            2
        )
        XCTAssertTrue(
            dedicated.contains("osrsHorizontalSideChromeInset"),
            "Recent-search chip carousel has the same scroll-axis safe-area class as Updates"
        )

        let accessoryRange = news.range(of: "private var homeGlassAccessory")
        XCTAssertNotNil(accessoryRange)
        let afterAccessory = news[accessoryRange!.upperBound...]
        let newsBodyRange = afterAccessory.range(of: "var body: some View")
        XCTAssertNotNil(newsBodyRange)
        let accessoryBody = String(news[accessoryRange!.lowerBound..<newsBodyRange!.lowerBound])
        XCTAssertTrue(accessoryBody.contains("osrsTabSearchWithTrailingControl"))
        XCTAssertFalse(accessoryBody.contains("ToolbarItem"))
        XCTAssertFalse(accessoryBody.contains("axisBehavior"))
    }

    func testIgnoredSafeAreaChromeUsesIndependentHorizontalInsets() throws {
        let root = try repositoryRoot()
        let chromeHelper = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift"
            ),
            encoding: .utf8
        )
        let articleBar = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/Components/osrsArticleBottomBar.swift"
            ),
            encoding: .utf8
        )
        let map = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/OSRSMapLibreView.swift"
            ),
            encoding: .utf8
        )
        let drawer = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/Components/osrsContentsDrawerSimple.swift"
            ),
            encoding: .utf8
        )
        let tabView = try String(
            contentsOf: root.appendingPathComponent(
                "platforms/ios/osrswiki/Views/CustomMainTabView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(chromeHelper.contains("static var leftInset"))
        XCTAssertTrue(chromeHelper.contains("static var rightInset"))
        XCTAssertTrue(chromeHelper.contains("func osrsIgnoredSafeAreaSideChromePadding"))
        XCTAssertTrue(chromeHelper.contains("osrsIgnoredSafeAreaSideChromePadding()"))
        XCTAssertFalse(chromeHelper.contains("safeAreaInsets.left * 2"))
        XCTAssertFalse(chromeHelper.contains("if isDuo"))

        XCTAssertTrue(articleBar.contains("osrsOverlayChromeHorizontalPadding"))
        XCTAssertFalse(articleBar.contains("safeAreaInsets.left * 2"))

        XCTAssertTrue(map.contains("osrsOverlayChromeHorizontalPadding"))
        XCTAssertTrue(map.contains("osrsReservedRegionOverlayPadding"))
        XCTAssertTrue(drawer.contains("contentsDrawerTrailingPadding"))

        XCTAssertTrue(tabView.contains("TabView(selection: nativeTabSelection)"))
        XCTAssertTrue(tabView.contains("osrsSystemVerticalBarsEnabled()"))
        XCTAssertTrue(tabView.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(tabView.contains("CustomTabBar()"))
        let nativeRange = try XCTUnwrap(tabView.range(of: "private var nativeTabContent"))
        let native = String(tabView[nativeRange.lowerBound...])
        XCTAssertFalse(
            native.contains("CustomTabBar()"),
            "Duo / iOS 26+ must keep the system TabView so vertical bars can adopt it"
        )
    }

    func testProductionLayoutDoesNotGateOnDuoIdiomOrHardcodedHinge() throws {
        let root = try repositoryRoot()
        let files = [
            "platforms/ios/osrswiki/Utils/osrsWindowSceneGeometry.swift",
            "platforms/ios/osrswiki/Utils/osrsDuoSystemBars.swift",
            "platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift",
            "platforms/ios/osrswiki/Views/NewsView.swift",
            "platforms/ios/osrswiki/Views/ArticleView.swift",
            "platforms/ios/osrswiki/Views/OSRSMapLibreView.swift",
            "platforms/ios/osrswiki/Views/Components/osrsArticleBottomBar.swift",
            "platforms/ios/osrswiki/Views/Components/osrsContentsDrawerSimple.swift",
            "platforms/ios/osrswiki/Views/CustomMainTabView.swift"
        ]
        for relative in files {
            let source = try String(
                contentsOf: root.appendingPathComponent(relative),
                encoding: .utf8
            )
            XCTAssertFalse(source.contains("isDuo"), "\(relative) gates layout on a Duo idiom")
            XCTAssertFalse(source.contains("if isDuo"), "\(relative) uses if isDuo")
            XCTAssertFalse(source.contains("hingeWidth"), "\(relative) hard-codes hinge width")
            XCTAssertFalse(source.contains("safeAreaInsets.left * 2"), "\(relative) assumes symmetric insets")
        }
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

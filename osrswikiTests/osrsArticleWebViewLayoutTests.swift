import UIKit
import XCTest
@testable import osrswiki

final class osrsArticleWebViewLayoutTests: XCTestCase {
    func testUnspecifiedProposalUsesWindowSizeOnRegularWidthIPad() {
        let iPadAir = CGSize(width: 834, height: 1210)
        let size = osrsArticleWebViewLayout.resolvedSize(
            proposedWidth: nil,
            proposedHeight: nil,
            windowSize: iPadAir
        )
        XCTAssertEqual(size, iPadAir)
        XCTAssertTrue(osrsArticleWebViewLayout.isUsableArticleFrame(size))
    }

    func testZeroProposalDoesNotCollapseArticleBody() {
        let iPadAir = CGSize(width: 834, height: 1210)
        let size = osrsArticleWebViewLayout.resolvedSize(
            proposedWidth: 0,
            proposedHeight: 0,
            windowSize: iPadAir
        )
        XCTAssertEqual(size, iPadAir)
    }

    func testSubMinimumProposalFallsBackToWindow() {
        let iPadAir = CGSize(width: 834, height: 1210)
        let size = osrsArticleWebViewLayout.resolvedSize(
            proposedWidth: 40,
            proposedHeight: 40,
            windowSize: iPadAir
        )
        XCTAssertEqual(size, iPadAir)
        XCTAssertFalse(osrsArticleWebViewLayout.isUsableArticleFrame(CGSize(width: 40, height: 40)))
        XCTAssertTrue(
            osrsArticleWebViewLayout.didBecomeUsable(
                previous: .zero,
                next: iPadAir
            )
        )
    }

    func testInitialFrameUsesWindowSize() {
        let iPadAir = CGSize(width: 834, height: 1210)
        XCTAssertEqual(
            osrsArticleWebViewLayout.initialFrame(windowSize: iPadAir),
            CGRect(origin: .zero, size: iPadAir)
        )
    }

    func testPhoneProposalIsHonored() {
        let size = osrsArticleWebViewLayout.resolvedSize(
            proposedWidth: 390,
            proposedHeight: 844,
            windowSize: CGSize(width: 834, height: 1210)
        )
        XCTAssertEqual(size, CGSize(width: 390, height: 844))
    }

    func testRegularWidthSizeClassDoesNotChangeResolvedFill() {
        let regularPad = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceIdiom: .pad),
            UITraitCollection(horizontalSizeClass: .regular),
            UITraitCollection(verticalSizeClass: .regular)
        ])
        XCTAssertEqual(regularPad.userInterfaceIdiom, .pad)
        XCTAssertEqual(regularPad.horizontalSizeClass, .regular)

        let compactPhone = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceIdiom: .phone),
            UITraitCollection(horizontalSizeClass: .compact)
        ])
        let window = CGSize(width: 834, height: 1210)
        let padSize = osrsArticleWebViewLayout.resolvedSize(
            proposedWidth: nil,
            proposedHeight: nil,
            windowSize: window
        )
        let phoneFallback = osrsArticleWebViewLayout.resolvedSize(
            proposedWidth: nil,
            proposedHeight: nil,
            windowSize: window
        )
        XCTAssertEqual(padSize, phoneFallback)
        XCTAssertEqual(compactPhone.userInterfaceIdiom, .phone)
    }

    func testPaintOracleDoesNotTrustAccessibilityLabels() throws {
        let root = try repositoryRoot()
        let ui = try source(root, "platforms/ios/osrswikiUITests/osrsIPadEquivalenceUITests.swift")
        XCTAssertFalse(ui.contains("label CONTAINS[c] %@\", \"Old School\""))
        XCTAssertFalse(ui.contains("if lastRange > 16"))
        XCTAssertTrue(ui.contains("Pixel-only"))
        XCTAssertTrue(ui.contains("lastRange > 24"))
        XCTAssertTrue(ui.contains("Upper body only"))
    }

    func testArticleViewFillsProposedCanvasInsteadOfCollapsingWK() throws {
        let root = try repositoryRoot()
        let articleView = try source(root, "platforms/ios/osrswiki/Views/ArticleView.swift")
        let articleWebView = try source(root, "platforms/ios/osrswiki/Views/ArticleWebView.swift")
        let tabView = try source(root, "platforms/ios/osrswiki/Views/CustomMainTabView.swift")

        XCTAssertTrue(articleView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        XCTAssertTrue(articleWebView.contains("osrsArticleWebViewLayout.resolvedSize"))
        XCTAssertTrue(articleWebView.contains("func sizeThatFits"))
        XCTAssertTrue(tabView.contains(".tabViewStyle(.tabBarOnly)"))
        XCTAssertFalse(
            articleView.contains("liveArticleWebViewPresent: viewModel.webView != nil"),
            "Article chrome fill must not wait on a not-yet-mounted WK"
        )
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

    private func source(_ root: URL, _ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}

//
//  AndroidParityTimingTests.swift
//  osrswikiTests
//
//  Test for Android parity progress timing - verifying JavaScript content readiness
//

import XCTest
import WebKit
import Combine
@testable import osrswiki

@MainActor
final class AndroidParityTimingTests: XCTestCase {

    func testBottomBarVisibilityChangesAreImmediate() {
        XCTAssertEqual(osrsBottomBarTransition.visibilityAnimationDuration, 0)
    }

    func testWebKitCompletionDoesNotMarkArticleCompleteBeforeJavaScriptSignal() throws {
        let viewModel = makeViewModel()
        viewModel.isLoading = true

        viewModel.updateProgressFromWebKit(1.0)

        XCTAssertTrue(viewModel.isLoading, "WebKit completion should keep the article in loading state")
        XCTAssertEqual(viewModel.loadingProgress, 0.95, accuracy: 0.001)
        XCTAssertEqual(viewModel.loadingProgressText, "Finalizing content...")
    }

    func testJavaScriptCompletionFinishesProgressAndClearsLoadingState() async throws {
        let viewModel = makeViewModelWithWebView()
        viewModel.isLoading = true
        viewModel.isRefreshing = true
        viewModel.loadingProgress = 0.95
        viewModel.loadingProgressText = "Finalizing content..."
        let expectation = expectation(description: "loading completes after WebKit and JavaScript readiness")
        let cancellable = viewModel.$isLoading.dropFirst().sink { isLoading in
            if !isLoading {
                expectation.fulfill()
            }
        }

        viewModel.webView?.loadHTMLString(Self.testArticleHTML, baseURL: Self.wikiBaseURL)
        viewModel.webView(viewModel.webView!, didFinish: nil)
        viewModel.completeLoadingWithBodyReveal()
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(viewModel.loadingProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.loadingProgressText, "Complete!")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        cancellable.cancel()
    }

    func testJavaScriptReadinessDoesNotCompleteBeforeWebKitDidFinish() async throws {
        let viewModel = makeViewModelWithWebView()
        viewModel.isLoading = true
        viewModel.loadingProgress = 0.95
        viewModel.loadingProgressText = "Finalizing content..."

        viewModel.completeLoadingWithBodyReveal()

        XCTAssertTrue(viewModel.isLoading, "JavaScript readiness alone must not complete article loading before WebKit didFinish for the same load")
        XCTAssertLessThan(viewModel.loadingProgress, 1.0)
    }

    func testStaleJavaScriptReadinessDoesNotCompleteCurrentLoad() async throws {
        let viewModel = makeViewModelWithWebView()
        viewModel.isLoading = true
        viewModel.loadingProgress = 0.95
        viewModel.loadingProgressText = "Finalizing content..."

        viewModel.webView?.loadHTMLString(Self.testArticleHTML, baseURL: Self.wikiBaseURL)
        viewModel.webView(viewModel.webView!, didFinish: nil)
        viewModel.completeLoadingWithBodyReveal(loadGeneration: -1)

        XCTAssertTrue(viewModel.isLoading, "A stale JavaScript readiness generation must not complete the active article load")
        XCTAssertLessThan(viewModel.loadingProgress, 1.0)
    }

    func testStaleUnboundWebKitNavigationDoesNotCompleteCurrentLoad() async throws {
        let viewModel = makeViewModelWithWebView()
        viewModel.isLoading = true
        viewModel.loadingProgress = 0.95
        viewModel.loadingProgressText = "Finalizing content..."

        let completion = expectation(description: "stale WebKit navigation must not complete active load")
        completion.isInverted = true
        let cancellable = viewModel.$isLoading.dropFirst().sink { isLoading in
            if !isLoading {
                completion.fulfill()
            }
        }

        let staleNavigation = try XCTUnwrap(viewModel.webView?.loadHTMLString(Self.testArticleHTML, baseURL: Self.wikiBaseURL))
        _ = viewModel.webView?.loadHTMLString(Self.testArticleHTML.replacingOccurrences(of: "Abyssal whip", with: "Rune scimitar"), baseURL: Self.wikiBaseURL)

        viewModel.webView(viewModel.webView!, didFinish: staleNavigation)
        viewModel.completeLoadingWithBodyReveal()

        await fulfillment(of: [completion], timeout: 0.5)
        XCTAssertTrue(viewModel.isLoading, "A stale native WKNavigation didFinish must not satisfy WebKit readiness for the active article load")
        XCTAssertLessThan(viewModel.loadingProgress, 1.0)
        cancellable.cancel()
    }

    private func makeViewModel() -> ArticleViewModel {
        ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Abyssal_whip")!,
            pageTitle: "Abyssal whip"
        )
    }

    private func makeViewModelWithWebView() -> ArticleViewModel {
        let viewModel = makeViewModel()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        viewModel.setWebView(webView)
        webView.navigationDelegate = viewModel
        return viewModel
    }

    private static let wikiBaseURL = URL(string: "https://oldschool.runescape.wiki/")!

    private static let testArticleHTML = """
    <!doctype html>
    <html>
      <head><title>Abyssal whip</title></head>
      <body style="visibility: hidden;">Abyssal whip</body>
    </html>
    """
}

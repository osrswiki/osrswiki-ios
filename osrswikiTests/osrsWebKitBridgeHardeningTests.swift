//
//  osrsWebKitBridgeHardeningTests.swift
//  osrswikiTests
//

import WebKit
import XCTest
@testable import osrswiki

final class osrsWebKitBridgeHardeningTests: XCTestCase {
    @available(iOS 17.0, *)
    @MainActor
    func testWebViewProxyConfigurationDoesNotInstallFakeConnectProxy() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)

        let configured = ProxyInterceptorService.shared.configureWebViewForProxyInterception(webView)

        XCTAssertTrue(configured)
        XCTAssertTrue(webView.configuration.websiteDataStore.proxyConfigurations.isEmpty)
    }

    func testWikiHostValidationRejectsSubstringLookalikes() {
        XCTAssertTrue(osrsWebKitSecurityPolicy.isTrustedWikiHost("oldschool.runescape.wiki"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.isTrustedWikiHost("runescape.wiki"))

        XCTAssertFalse(osrsWebKitSecurityPolicy.isTrustedWikiHost("secure.runescape.wiki"))
        XCTAssertFalse(osrsWebKitSecurityPolicy.isTrustedWikiHost("oldschool.runescape.wiki.evil"))
        XCTAssertFalse(osrsWebKitSecurityPolicy.isTrustedWikiHost("eviloldschool.runescape.wiki"))
        XCTAssertFalse(osrsWebKitSecurityPolicy.isTrustedWikiHost("runescape.wiki.evil"))
    }

    func testAppAssetsWikiArticlePathRoutesToAppArticleURL() throws {
        let sourceURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Quest_guide"))

        let destinationURL = osrsArticleLinkRouter.appArticleURL(for: sourceURL)

        XCTAssertEqual(destinationURL?.absoluteString, "https://oldschool.runescape.wiki/w/Quest_guide")
    }

    func testAppAssetsBloodMoonQuickGuideRoutesToAppArticleURL() throws {
        let sourceURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/The_Blood_Moon_Rises/Quick_guide"))

        let destinationURL = osrsArticleLinkRouter.appArticleURL(for: sourceURL)

        XCTAssertEqual(destinationURL?.absoluteString, "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide")
    }

    func testInternalLinkBridgeCancelsAnchorClickBeforeAppNavigation() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleWebView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("createInternalLinkRoutingScript()"))
        XCTAssertTrue(source.contains("injectionTime: .atDocumentStart"))
        XCTAssertTrue(source.contains("rawTarget && rawTarget.nodeType === 3 ? rawTarget.parentElement : rawTarget"))
        XCTAssertTrue(source.contains("link.getAttribute('data-osrs-article-href') || link.href"))
        XCTAssertTrue(source.contains("event.preventDefault();"))
        XCTAssertTrue(source.contains("event.stopPropagation();"))
        XCTAssertTrue(source.contains("event.stopImmediatePropagation();"))
        XCTAssertTrue(source.contains("url.protocol === 'app-assets:' && url.hostname === 'localhost'"))
        XCTAssertTrue(source.contains("document.addEventListener('click', routeInternalArticleLink, true);"))
        XCTAssertFalse(source.contains("'touchstart', 'pointerdown', 'mousedown', 'touchend', 'pointerup', 'click'"))
        XCTAssertFalse(source.contains("window.__osrsLastInternalNavigationURL"))
        XCTAssertTrue(source.contains("window.webkit.messageHandlers.linkHandler.postMessage"))
    }

    func testWebViewDelegateCancelsInternalArticleNavigationBeforeNativePush() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        let helperRange = try XCTUnwrap(source.range(of: "private func handleArticleNavigationPolicy"))
        let appArticleCase = try XCTUnwrap(source.range(of: "case .appArticle(let articleURL):"))
        let externalCase = try XCTUnwrap(source.range(of: "case .external(let externalURL):", range: appArticleCase.upperBound..<source.endIndex))
        let legacyDelegate = try XCTUnwrap(source.range(of: "func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler:"))
        let modernDelegate = try XCTUnwrap(source.range(of: "func webView(\n        _ webView: WKWebView,\n        decidePolicyFor navigationAction: WKNavigationAction,\n        preferences: WKWebpagePreferences,"))
        let branch = String(source[appArticleCase.lowerBound..<externalCase.lowerBound])
        let stopLoadingRange = try XCTUnwrap(branch.range(of: "webView.stopLoading()"))
        let routeRange = try XCTUnwrap(branch.range(of: "navigateToInternalArticle?(articleURL)"))

        XCTAssertLessThan(helperRange.lowerBound, appArticleCase.lowerBound)
        XCTAssertLessThan(stopLoadingRange.lowerBound, routeRange.lowerBound)
        XCTAssertTrue(branch.contains("webView.stopLoading()"))
        XCTAssertTrue(branch.contains("DispatchQueue.main.async"))
        XCTAssertTrue(branch.contains("return .cancel"))
        XCTAssertLessThan(legacyDelegate.lowerBound, modernDelegate.lowerBound)
        XCTAssertTrue(source.contains("let policy = handleArticleNavigationPolicy(for: navigationAction, in: webView, timeString: timeString)"))
        XCTAssertTrue(source.contains("if policy == .cancel {\n            decisionHandler(.cancel)\n            return\n        }"))
        XCTAssertTrue(source.contains("if policy == .cancel {\n            decisionHandler(.cancel, preferences)\n            return\n        }"))
    }

    func testModernWebViewDelegatePolicyCallbackAlsoCancelsInternalArticleNavigation() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("WKWebpagePreferences"))
        XCTAssertTrue(source.contains("decisionHandler(.cancel, preferences)"))
        XCTAssertTrue(source.contains("handleArticleNavigationPolicy"))
    }

    func testUnboundWebViewArticleNavigationsArePromotedToNativeArticleStack() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("routeObservedUnboundArticleNavigationIfNeeded"))
        XCTAssertTrue(source.contains("routedObservedArticleNavigationURLs"))
        XCTAssertTrue(source.contains("navigateToInternalArticle?(articleURL)"))

        let didStartRange = try XCTUnwrap(source.range(of: "func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)"))
        let didFinishRange = try XCTUnwrap(source.range(of: "func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)"))
        let didStartBody = String(source[didStartRange.lowerBound..<didFinishRange.lowerBound])
        XCTAssertTrue(didStartBody.contains("routeObservedUnboundArticleNavigationIfNeeded(in: webView"))
    }

    func testRenderedSubpageIdentityProbePromotesWebViewContentMutationToNativeStack() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var renderedArticleIdentityProbe: Timer?"))
        XCTAssertTrue(source.contains("startRenderedArticleIdentityProbe(for: generation)"))
        XCTAssertTrue(source.contains("routeRenderedArticleNavigationIfNeeded(in: webView, context: \"renderedArticleIdentityProbe\")"))
        XCTAssertTrue(source.contains("document.querySelector('#firstHeading')"))
        XCTAssertTrue(source.contains("document.querySelector('h1.page-header')"))
        XCTAssertTrue(source.contains("renderedTitle.contains(\"/\")"))
        XCTAssertTrue(source.contains("Self.articleURL(forResolvedTitle: renderedTitle)"))
        XCTAssertTrue(source.contains("articleURL.absoluteString != self.pageUrl.absoluteString"))
        XCTAssertTrue(source.contains("self.routedObservedArticleNavigationURLs.insert(routeKey)"))
        XCTAssertTrue(source.contains("self.stopRenderedArticleIdentityProbe()"))
        XCTAssertTrue(source.contains("self.navigateToInternalArticle?(articleURL)"))
    }

    func testAppAssetArticleSchemeRequestsRouteThroughNativeArticleStack() throws {
        let root = try repositoryRoot()
        let webViewSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleWebView.swift"),
            encoding: .utf8
        )
        let articleViewSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(webViewSource.contains("osrsArticleLinkRouter.appArticleURL(for: url)"))
        XCTAssertTrue(webViewSource.contains("NotificationCenter.default.post("))
        XCTAssertTrue(webViewSource.contains("name: .osrsInternalArticleLinkRequested"))
        XCTAssertTrue(webViewSource.contains("code: NSURLErrorCancelled"))
        XCTAssertFalse(articleViewSource.contains(".onReceive(NotificationCenter.default.publisher(for: .osrsInternalArticleLinkRequested))"))
        XCTAssertTrue(webViewSource.contains("self.parent.appState.routeInternalArticleLink("))
        XCTAssertTrue(webViewSource.contains("sourceArticleURL: self.parent.viewModel.pageUrl"))
    }

    func testGeneratedArticleHtmlNormalizesInternalArticleAnchorsToAppOwnedDataHandoffURLs() {
        let html = osrsPageHtmlBuilder().buildFullHtmlDocument(
            title: "The Blood Moon Rises",
            bodyContent: """
            <p>
                <a href="/w/The_Blood_Moon_Rises/Quick_guide">quest guide</a>
                <a href="https://oldschool.runescape.wiki/w/Varrock#History">Varrock</a>
                <a href="/w/File:Blood_Moon.png">file page</a>
            </p>
            """,
            theme: osrsLightTheme()
        )

        XCTAssertTrue(html.contains("normalizeInternalArticleLinks"))
        XCTAssertTrue(html.contains("app-assets://localhost"))
        XCTAssertTrue(html.contains("href=\"/w/The_Blood_Moon_Rises/Quick_guide\" data-osrs-article-href=\"app-assets://localhost/w/The_Blood_Moon_Rises/Quick_guide\""))
        XCTAssertTrue(html.contains("href=\"https://oldschool.runescape.wiki/w/Varrock#History\" data-osrs-article-href=\"app-assets://localhost/w/Varrock#History\""))
        XCTAssertTrue(html.contains("href=\"/w/File:Blood_Moon.png\""))
        XCTAssertTrue(html.contains("oldschool.runescape.wiki"))
        XCTAssertTrue(html.contains("File:"))
        XCTAssertTrue(html.contains("MutationObserver"))
    }

    func testLocalLoadHTMLStringOriginCanUseMainFrameBridge() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsWebKitSecurityPolicy.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("originProtocol == \"applewebdata\""))
        XCTAssertTrue(source.contains("guard frameInfo.isMainFrame else { return false }"))
    }

    func testMainFrameLinkHandlerDoesNotDependOnOpaqueWebKitOrigin() throws {
        let root = try repositoryRoot()
        let policySource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsWebKitSecurityPolicy.swift"),
            encoding: .utf8
        )
        let webViewSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleWebView.swift"),
            encoding: .utf8
        )

        let mainFrameRange = try XCTUnwrap(policySource.range(of: "guard frameInfo.isMainFrame else { return false }"))
        let linkHandlerRange = try XCTUnwrap(policySource.range(of: "if name == \"linkHandler\""))
        let originRange = try XCTUnwrap(policySource.range(of: "guard isTrustedMessageOrigin(frameInfo.securityOrigin) else { return false }"))
        XCTAssertLessThan(mainFrameRange.lowerBound, linkHandlerRange.lowerBound)
        XCTAssertLessThan(linkHandlerRange.lowerBound, originRange.lowerBound)
        XCTAssertTrue(webViewSource.contains("guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) else { return }"))
    }

    func testInternalArticleLinkRequestsAreHandledByRootAppState() throws {
        let root = try repositoryRoot()
        let appStateSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/AppState.swift"),
            encoding: .utf8
        )
        let customRootSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/CustomMainTabView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appStateSource.contains("observeInternalArticleLinkRequests()"))
        XCTAssertTrue(appStateSource.contains("forName: .osrsInternalArticleLinkRequested"))
        XCTAssertTrue(appStateSource.contains("self?.routeInternalArticleLink(url, sourceArticleURL: sourceArticleURL)"))

        XCTAssertFalse(customRootSource.contains(".onReceive(NotificationCenter.default.publisher(for: .osrsInternalArticleLinkRequested))"))
    }

    func testAssetHandlerCancellationOwnsEveryTransportAndHasNoDirectCacheWritePath() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleWebView.swift"),
            encoding: .utf8
        )

        XCTAssertEqual(
            source.components(separatedBy: "launchTransport(for: urlSchemeTask)").count - 1,
            3,
            "Every external/image/MediaWiki transport must be tied to its WKURLSchemeTask lifecycle."
        )
        XCTAssertTrue(source.contains("transportHandle?.cancel()"))
        XCTAssertTrue(source.contains("transportHandles.forEach { $0.cancel() }"))
        XCTAssertFalse(source.contains("private func saveHttpResponse("))
        XCTAssertFalse(source.contains("ProxyInterceptorService.shared.cacheResponseForAsset("))
    }

    func testAssetTransportHandleCancelsAGatedLateResponse() async {
        let gate = osrsAssetTransportTestGate()
        let probe = osrsAssetTransportCancellationProbe()
        let started = expectation(description: "transport started")
        let handle = osrsAssetTransportCancellationHandle()
        let task = Task {
            started.fulfill()
            await gate.wait()
            await probe.record(Task.isCancelled)
        }
        handle.install(task)
        await fulfillment(of: [started], timeout: 1)

        handle.cancel()
        await gate.open()
        await task.value
        let observedCancellation = await probe.value

        XCTAssertTrue(observedCancellation, "Stopping the WK task must cancel a transport even when its upstream response arrives later.")
    }

    func testTrustedWikiArticleURLRoutesToAppArticleURL() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"))

        let destinationURL = osrsArticleLinkRouter.appArticleURL(for: sourceURL)

        XCTAssertEqual(destinationURL, sourceURL)
    }

    func testWikiFileAndSpecialPathsDoNotRouteToAppArticle() throws {
        let fileURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/File:Blood_Moon.png"))
        let specialURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Special:RandomRootpage/main"))

        XCTAssertNil(osrsArticleLinkRouter.appArticleURL(for: fileURL))
        XCTAssertNil(osrsArticleLinkRouter.appArticleURL(for: specialURL))
    }

    @MainActor
    func testFloorNumberingPreferenceLinksOpenTheAppearanceSetting() throws {
        let httpsURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Special:Preferences"))
        let appAssetURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Special:Preferences#mw-prefsection-rendering"))
        XCTAssertTrue(osrsArticleLinkRouter.isFloorNumberingSettingsURL(httpsURL))
        XCTAssertTrue(osrsArticleLinkRouter.isFloorNumberingSettingsURL(appAssetURL))
        XCTAssertEqual(
            ArticleViewModel.articleNavigationDecision(for: httpsURL),
            .floorNumberingSettings
        )
        XCTAssertEqual(
            ArticleViewModel.articleNavigationDecision(for: appAssetURL),
            .floorNumberingSettings
        )
    }

    @MainActor
    func testExternalEmbedNavigationsStayInWebViewUntilUserActivatesALink() {
        XCTAssertEqual(
            ArticleViewModel.osrsExternalNavigationAction(navigationType: .other, isMainFrame: false),
            .allowInWebView
        )
        XCTAssertEqual(
            ArticleViewModel.osrsExternalNavigationAction(navigationType: .linkActivated, isMainFrame: false),
            .allowInWebView
        )
        XCTAssertEqual(
            ArticleViewModel.osrsExternalNavigationAction(navigationType: .other, isMainFrame: true),
            .cancelSilently
        )
        XCTAssertEqual(
            ArticleViewModel.osrsExternalNavigationAction(navigationType: .linkActivated, isMainFrame: true),
            .openInBrowser
        )
    }

    func testAppAssetsNonArticleWikiNamespacesConvertToTrustedWikiURLForExternalHandling() throws {
        let cases: [(source: String, expected: String)] = [
            (
                "app-assets://localhost/w/File:Blood_Moon.png",
                "https://oldschool.runescape.wiki/w/File:Blood_Moon.png"
            ),
            (
                "app-assets://localhost/w/Media:Blood_Moon.png",
                "https://oldschool.runescape.wiki/w/Media:Blood_Moon.png"
            ),
            (
                "app-assets://localhost/w/Special:RandomRootpage/main",
                "https://oldschool.runescape.wiki/w/Special:RandomRootpage/main"
            )
        ]

        for testCase in cases {
            let sourceURL = try XCTUnwrap(URL(string: testCase.source))

            let externalURL = osrsArticleLinkRouter.externalWikiURLForNonArticleAppAssetURL(sourceURL)

            XCTAssertEqual(externalURL?.absoluteString, testCase.expected, testCase.source)
            XCTAssertNil(osrsArticleLinkRouter.appArticleURL(for: sourceURL), testCase.source)
        }
    }

    func testArticleViewerRoutesRemainArticleViewerRoutes() throws {
        let appAssetArticleURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Quest_guide"))
        let trustedHTTPArticleURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Quest_guide"))

        XCTAssertEqual(
            osrsArticleLinkRouter.appArticleURL(for: appAssetArticleURL)?.absoluteString,
            "https://oldschool.runescape.wiki/w/Quest_guide"
        )
        XCTAssertEqual(osrsArticleLinkRouter.appArticleURL(for: trustedHTTPArticleURL), trustedHTTPArticleURL)
        XCTAssertNil(osrsArticleLinkRouter.externalWikiURLForNonArticleAppAssetURL(appAssetArticleURL))
        XCTAssertNil(osrsArticleLinkRouter.externalWikiURLForNonArticleAppAssetURL(trustedHTTPArticleURL))
    }

    @MainActor
    func testWebViewDelegateDecisionCancelsAppAssetsNonArticleNamespacesWithTrustedWikiURL() throws {
        let cases: [(source: String, expected: String)] = [
            (
                "app-assets://localhost/w/File:Blood_Moon.png",
                "https://oldschool.runescape.wiki/w/File:Blood_Moon.png"
            ),
            (
                "app-assets://localhost/w/Media:Blood_Moon.png",
                "https://oldschool.runescape.wiki/w/Media:Blood_Moon.png"
            ),
            (
                "app-assets://localhost/w/Special:RandomRootpage/main",
                "https://oldschool.runescape.wiki/w/Special:RandomRootpage/main"
            )
        ]

        for testCase in cases {
            let sourceURL = try XCTUnwrap(URL(string: testCase.source))
            let expectedURL = try XCTUnwrap(URL(string: testCase.expected))

            XCTAssertEqual(
                ArticleViewModel.articleNavigationDecision(for: sourceURL),
                .external(expectedURL),
                testCase.source
            )
        }
    }

    @MainActor
    func testWebViewDelegateDecisionPreservesArticleAndAssetRouting() throws {
        let appAssetArticleURL = try XCTUnwrap(URL(string: "app-assets://localhost/w/Quest_guide"))
        let trustedHTTPArticleURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Quest_guide"))
        let appAssetResourceURL = try XCTUnwrap(URL(string: "app-assets://localhost/styles/wiki.css"))

        XCTAssertEqual(
            ArticleViewModel.articleNavigationDecision(for: appAssetArticleURL),
            .appArticle(try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Quest_guide")))
        )
        XCTAssertEqual(
            ArticleViewModel.articleNavigationDecision(for: trustedHTTPArticleURL),
            .appArticle(trustedHTTPArticleURL)
        )
        XCTAssertEqual(ArticleViewModel.articleNavigationDecision(for: appAssetResourceURL), .allow)
    }

    func testNonWikiExternalURLDoesNotRouteToAppArticle() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://secure.runescape.com/m=news"))

        XCTAssertNil(osrsArticleLinkRouter.appArticleURL(for: sourceURL))
    }

    func testRandomLinkRoutingAuditPriorEdgeCasesUseExpectedArticleRouterBranch() throws {
        let cases: [(name: String, url: String, routedURL: String?)] = [
            (
                "Home/news article path",
                "app-assets://localhost/w/Update:The_Blood_Moon_Rises",
                "https://oldschool.runescape.wiki/w/Update:The_Blood_Moon_Rises"
            ),
            (
                "The Blood Moon Rises",
                "app-assets://localhost/w/The_Blood_Moon_Rises",
                "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises"
            ),
            (
                "The Blood Moon Rises quick guide",
                "app-assets://localhost/w/The_Blood_Moon_Rises/Quick_guide",
                "https://oldschool.runescape.wiki/w/The_Blood_Moon_Rises/Quick_guide"
            ),
            (
                "app-assets relative /w link",
                "app-assets://localhost/w/Quest_guide",
                "https://oldschool.runescape.wiki/w/Quest_guide"
            ),
            (
                "oldschool absolute /w link",
                "https://oldschool.runescape.wiki/w/Varrock",
                "https://oldschool.runescape.wiki/w/Varrock"
            ),
            (
                "runescape.wiki alias",
                "https://runescape.wiki/w/Old_School_RuneScape",
                "https://runescape.wiki/w/Old_School_RuneScape"
            ),
            (
                "file page",
                "app-assets://localhost/w/File:Blood_Moon.png",
                nil
            ),
            (
                "media page",
                "app-assets://localhost/w/Media:Blood_Moon.png",
                nil
            ),
            (
                "special page",
                "app-assets://localhost/w/Special:RandomRootpage/main",
                nil
            ),
            (
                "fragment link",
                "app-assets://localhost/w/Quest_guide#Rewards",
                "https://oldschool.runescape.wiki/w/Quest_guide#Rewards"
            ),
            (
                "query link",
                "app-assets://localhost/w/Varrock?oldid=14443131",
                "https://oldschool.runescape.wiki/w/Varrock?oldid=14443131"
            ),
            (
                "redirect-like title",
                "app-assets://localhost/w/Strength_potion",
                "https://oldschool.runescape.wiki/w/Strength_potion"
            ),
            (
                "percent encoded title",
                "app-assets://localhost/w/Recipe_for_Disaster%2FFreeing_Evil_Dave",
                "https://oldschool.runescape.wiki/w/Recipe_for_Disaster/Freeing_Evil_Dave"
            ),
            (
                "non-wiki external",
                "https://secure.runescape.com/m=news",
                nil
            ),
            (
                "lookalike external",
                "https://oldschool.runescape.wiki.evil/w/Varrock",
                nil
            )
        ]

        for testCase in cases {
            let url = try XCTUnwrap(URL(string: testCase.url), testCase.name)
            XCTAssertEqual(
                osrsArticleLinkRouter.appArticleURL(for: url)?.absoluteString,
                testCase.routedURL,
                testCase.name
            )
        }
    }

    func testProductionBridgePolicyLimitsHandlersAndDebugSurfaces() {
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("clipboardBridge"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("mapBridge"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("linkHandler"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("renderTimeline"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("osrsYouTube"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("osrsCalculatorApi"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("osrsLiveAssetWarm"))
        XCTAssertTrue(osrsWebKitSecurityPolicy.productionHandlerNames.contains("osrsFirstViewComplete"))

        XCTAssertFalse(osrsWebKitSecurityPolicy.productionHandlerNames.contains("safariDebugger"))
        XCTAssertFalse(osrsWebKitSecurityPolicy.isWebViewInspectionEnabled)

        for script in osrsWebKitSecurityPolicy.productionUserScripts {
            XCTAssertTrue(script.isForMainFrameOnly, "\(script.name) must not be injected into subframes")
        }
    }

    func testYouTubeEmbedIDsParseWatchEmbedAndShortURLs() throws {
        XCTAssertEqual(
            osrsYouTubeEmbed.videoID(from: "https://www.youtube.com/embed/dQw4w9WgXcQ"),
            "dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            osrsYouTubeEmbed.videoID(from: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=4"),
            "dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            osrsYouTubeEmbed.videoID(from: "https://youtu.be/dQw4w9WgXcQ"),
            "dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            osrsYouTubeEmbed.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            "dQw4w9WgXcQ"
        )
        let player = try! XCTUnwrap(osrsYouTubeEmbed.playerURL(videoID: "dQw4w9WgXcQ"))
        XCTAssertEqual(player.host, "www.youtube.com")
        XCTAssertTrue(player.path.contains("/embed/dQw4w9WgXcQ"))
        XCTAssertTrue(player.query?.contains("origin=") == true)
        XCTAssertTrue(player.query?.contains("playsinline=1") == true)
        let request = osrsYouTubeEmbed.playerRequest(url: player)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Referer")?.contains("oldschool.runescape.wiki") == true)

        let js = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("shared/js/responsive_videos.js"),
            encoding: .utf8
        )
        XCTAssertTrue(js.contains("iframe.removeAttribute('src')"))
        XCTAssertTrue(js.contains("i.ytimg.com/vi/"))
        XCTAssertTrue(js.contains("data-osrs-youtube-id"))
    }

    func testArticleLifecyclePersistsScrollAndRecoversTerminatedWebContent() throws {
        let root = try repositoryRoot()
        let articleView = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        let appState = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/AppState.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(articleView.contains("osrsArticleSceneRestore"))
        XCTAssertTrue(articleView.contains("captureCurrentArticleScroll()"))
        XCTAssertTrue(articleView.contains("needsContentProcessRecovery"))
        XCTAssertTrue(articleView.contains("recommitCachedArticleAfterBackground(force:"))
        XCTAssertTrue(articleView.contains("noteApplicationDidEnterBackground()"))
        XCTAssertTrue(articleView.contains("shouldReloadArticleOnReappear"))
        XCTAssertTrue(articleView.contains("isArticleVisible = true"))
        XCTAssertTrue(articleView.contains("recoverBlankResume"))
        XCTAssertTrue(viewModel.contains("recoverBlankResume"))
        XCTAssertTrue(viewModel.contains("pendingArticleLoadIsReload = false"))
        XCTAssertFalse(viewModel.contains("pendingArticleLoadIsReload = true"))
        XCTAssertTrue(viewModel.contains("mustWriteDocument"))
        XCTAssertTrue(viewModel.contains("document.body.style.visibility = 'visible'"))
        XCTAssertTrue(articleView.contains("osrsYouTubePlayerSheet"))
        let youtubePlayer = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/osrsInAppYouTubePlayer.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(youtubePlayer.contains("osrsInAppYouTubePlayer"))
        XCTAssertTrue(youtubePlayer.contains("scenePhase"))
        XCTAssertTrue(youtubePlayer.contains("phase == .background"))
        XCTAssertTrue(youtubePlayer.contains("osrsYouTubeEmbed.playerRequest"))
        XCTAssertTrue(viewModel.contains("webViewWebContentProcessDidTerminate"))
        XCTAssertTrue(viewModel.contains("osrsWebViewThemePaint.noteWebContentProcessTerminated"))
        XCTAssertTrue(articleView.contains("osrsWebViewThemePaint.apply(to: webView, theme: osrsTheme)"))
        XCTAssertTrue(viewModel.contains("pendingYouTubeEmbedURL"))
        XCTAssertTrue(appState.contains("osrs.articleScrollOffsets"))
        XCTAssertTrue(appState.contains("persistArticleScrollOffsets"))
        XCTAssertTrue(appState.contains("articleForegroundEpoch"))
        XCTAssertTrue(appState.contains("noteApplicationDidBecomeActive"))
        XCTAssertFalse(appState.contains("osrsResumedSceneWindow.reconnectAfterBackground"))
        XCTAssertTrue(appState.contains("osrsSceneCompositor.restoreResumedScenes"))
        XCTAssertTrue(appState.contains("navigationHostGeneration"))
        XCTAssertFalse(appState.contains("navigationHostGeneration += 1"))
        XCTAssertTrue(appState.contains("osrsResumableArticleDidChange"))
        XCTAssertFalse(appState.contains("articleForegroundEpoch += 1"))
        let newsView = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/NewsView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(newsView.contains("osrsResumedNavigationHost"))
        XCTAssertFalse(newsView.contains("articleForegroundEpoch"))
        let compositor = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsSceneCompositor.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(compositor.contains("isAppContentWindow"))
        XCTAssertTrue(compositor.contains("windowLooksCompositorBlank"))
        XCTAssertTrue(compositor.contains("osrsSceneCompositorLooksBlank"))
        XCTAssertTrue(compositor.contains("TextEffects"))
        XCTAssertTrue(compositor.contains("removeStaleSnapshotOverlays"))
        XCTAssertTrue(compositor.contains("clearFrozenHostSnapshots"))
        XCTAssertTrue(compositor.contains("layer.contents = nil"))
        let tabBar = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Extensions/UITabBar+FastRestore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(tabBar.contains("floatingTabBarCoverViews"))
        XCTAssertTrue(tabBar.contains("_UITabBarContainerView"))
        XCTAssertFalse(tabBar.contains("_UIGraphicsView"))
        XCTAssertTrue(tabBar.contains("sendFloatingTabBarCoversBehindContent"))
        XCTAssertTrue(tabBar.contains("layer.zPosition"))
        XCTAssertTrue(tabBar.contains("cover.clipsToBounds = behind"))
        XCTAssertFalse(tabBar.contains("container.alpha = hidden ? 0"))
        let themeManager = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/OSRSThemeManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(themeManager.contains("osrsUnhideResumedHostViews"))
        XCTAssertTrue(themeManager.contains("osrsSceneCompositor.restore"))
        XCTAssertFalse(themeManager.contains("removeFromSuperview"))
        let app = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/osrswikiApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(app.contains("enum osrsAppRoot"))
        XCTAssertFalse(app.contains("WindowGroup {"))
        XCTAssertFalse(app.contains("WindowGroup("))
        XCTAssertFalse(app.contains("@main"))
        XCTAssertFalse(app.contains("SWIFTUI_DISABLE_MIXED_VIEW_HIERARCHY"))
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsAppDelegate.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(appDelegate.contains("@main"))
        XCTAssertTrue(appDelegate.contains("configuration.delegateClass = osrsSceneDelegate.self"))
        let sceneDelegate = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsSceneDelegate.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(sceneDelegate.contains("replacePrimaryWindow"))
        XCTAssertTrue(sceneDelegate.contains("requestSceneSessionRefresh"))
        XCTAssertTrue(sceneDelegate.contains("UIHostingController(rootView: osrsAppRoot.rootView)"))
        XCTAssertTrue(sceneDelegate.contains("CustomMainTabView"))
        XCTAssertFalse(sceneDelegate.contains("Always replace with the UIKit article host"))
        XCTAssertFalse(sceneDelegate.contains("osrsResumedArticleViewController"))
        XCTAssertFalse(sceneDelegate.contains("installForegroundArticleHostIfNeeded"))
        XCTAssertFalse(sceneDelegate.contains("foreground-article"))
        XCTAssertTrue(sceneDelegate.contains("restoreResumedScene"))
        XCTAssertTrue(sceneDelegate.contains("same SwiftUI host"))
        XCTAssertTrue(sceneDelegate.contains("reconnectSwiftUIHostToWindow"))
        XCTAssertTrue(sceneDelegate.contains("replaceRootViewController"))
        XCTAssertTrue(sceneDelegate.contains("existingSceneWindow"))
        XCTAssertTrue(sceneDelegate.contains("osrsAppSceneViewController"))
        XCTAssertTrue(sceneDelegate.contains("osrsInstall"))
        XCTAssertTrue(sceneDelegate.contains("sceneWillResignActive"))
        XCTAssertTrue(sceneDelegate.contains("finishedFirstActivation"))
        XCTAssertTrue(sceneDelegate.contains("first activation skip replace"))
        XCTAssertFalse(sceneDelegate.contains("WindowGroup"))
        XCTAssertFalse(sceneDelegate.contains("windowLevel = isResume ? .alert"))
        XCTAssertFalse(sceneDelegate.contains("other.windowScene = nil"))
        let resumedWindow = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsResumedSceneWindow.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(resumedWindow.contains("deferred to osrsSceneDelegate compositor restore"))
        XCTAssertFalse(resumedWindow.contains("osrsResumedArticleViewController"))
        XCTAssertFalse(resumedWindow.contains("webView.load(URLRequest"))
        XCTAssertFalse(resumedWindow.contains("oldschool.runescape.wiki"))
        XCTAssertFalse(resumedWindow.contains("isHidden = true"))
        XCTAssertFalse(resumedWindow.contains("promoteArticleSessionIfNeeded"))
        XCTAssertFalse(resumedWindow.contains("windowLevel = UIWindow.Level.normal + 1"))
        let tabView = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/CustomMainTabView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(tabView.contains("osrsResumedSceneWindow.bindRuntime"))
        XCTAssertTrue(tabView.contains("nativeTabContent"))
        XCTAssertTrue(tabView.contains("nativeTabContent"))
        XCTAssertFalse(tabView.contains("sceneRestoreNudge"))
        XCTAssertFalse(tabView.contains("articleForegroundEpoch"))
        XCTAssertFalse(tabView.contains("promoteArticleSessionIfNeeded"))
        let infoPlist = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Info.plist"),
            encoding: .utf8
        )
        XCTAssertTrue(infoPlist.contains("UIApplicationSupportsMultipleScenes"))
        XCTAssertTrue(infoPlist.contains("<false/>"))
        XCTAssertTrue(infoPlist.contains("osrswiki.osrsSceneDelegate"))
        XCTAssertTrue(infoPlist.contains("osrs.default.scene.v2"))
        let pbxproj = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertTrue(pbxproj.contains("INFOPLIST_KEY_UIApplicationSupportsMultipleScenes = NO"))
        XCTAssertTrue(pbxproj.contains("INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO"))
    }

    func testDeepNavigationFixtureAuditIsDebugOnlyAndLaunchGated() throws {
        let root = try repositoryRoot()
        let appStateSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/AppState.swift"),
            encoding: .utf8
        )
        let navigationSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/AppState+Navigation.swift"),
            encoding: .utf8
        )
        let fixtureSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Models/osrsDeepNavigationFixtureAudit.swift"),
            encoding: .utf8
        )
        let customMainTabSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/CustomMainTabView.swift"),
            encoding: .utf8
        )
        let testEnvironmentSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Utils/osrsTestEnvironment.swift"),
            encoding: .utf8
        )
        let deepNavigationUITestSource = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswikiUITests/DeepNavigationStackAuditUITests.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(fixtureSource.contains("-runDeepNavigationFixtureAuditForUITests"))
        XCTAssertTrue(appStateSource.contains("handleUITestDeepNavigationFixtureArguments"))
        XCTAssertTrue(appStateSource.contains("guard osrsTestEnvironment.runsDeepNavigationFixtureAuditForUITests else"))
        XCTAssertTrue(navigationSource.contains("runDeepNavigationFixtureAuditForUITests("))
        XCTAssertTrue(customMainTabSource.contains("deep_navigation_fixture_audit_state"))
        XCTAssertTrue(customMainTabSource.contains("#if DEBUG"))
        XCTAssertTrue(testEnvironmentSource.contains("usesDeepNavigationFixtureForUITests"))
        XCTAssertTrue(testEnvironmentSource.contains("runsDeepNavigationFixtureAuditForUITests"))
        XCTAssertTrue(testEnvironmentSource.contains("osrsUITestHarnessLaunchArgument"))
        XCTAssertTrue(testEnvironmentSource.contains("isRunningSimulatorUITestHarness"))
        XCTAssertTrue(testEnvironmentSource.contains("#if DEBUG && targetEnvironment(simulator)"))
        XCTAssertTrue(testEnvironmentSource.contains("isRunningSimulatorUITestHarness &&"))
        XCTAssertTrue(deepNavigationUITestSource.contains("\"-osrsUITestHarness\""))
        XCTAssertFalse(testEnvironmentSource.contains("#if DEBUG\n        ProcessInfo.processInfo.arguments.contains(osrsDeepNavigationFixtureAudit.useArticleFixtureLaunchArgument)"))
        XCTAssertFalse(testEnvironmentSource.contains("#if DEBUG\n        ProcessInfo.processInfo.arguments.contains(osrsDeepNavigationFixtureAudit.runAuditLaunchArgument)"))
    }

    @MainActor
    func testDeepNavigationFixtureAuditUsesNativeArticleStackForHundredLayerReverseOrder() {
        let appState = AppState()

        let result = appState.runDeepNavigationFixtureAuditForUITests(
            seed: 20260709,
            startOffset: 6,
            startCount: 2,
            targetDepth: 100
        )

        XCTAssertTrue(result.passed, result.accessibilityLabel)
        XCTAssertEqual(result.completedStarts, 2)
        XCTAssertEqual(result.forwardTransitions, 200)
        XCTAssertEqual(result.backTransitions, 200)
        XCTAssertEqual(result.mismatchCount, 0)
        XCTAssertEqual(appState.selectedTab, .search)
        XCTAssertEqual(appState.searchNavigationStack.count, 1)
        XCTAssertEqual(
            appState.activeArticleDestination?.url,
            osrsDeepNavigationFixtureAudit.articleURL(sampleOrdinal: 20_260_716, depth: 0)
        )
        XCTAssertTrue(appState.deepNavigationFixtureAuditDebugLabel.contains("status=pass"))
    }

    func testDeepNavigationFixturePageProvidesDeterministicNextArticleLink() throws {
        let page = try XCTUnwrap(osrsDeepNavigationFixtureAudit.page(
            for: osrsDeepNavigationFixtureAudit.articleURL(sampleOrdinal: 42, depth: 99),
            requestedTitle: nil
        ))

        XCTAssertEqual(page.title, "osrs Deep Navigation Fixture 42 Layer 99")
        XCTAssertEqual(page.nextURL, osrsDeepNavigationFixtureAudit.articleURL(sampleOrdinal: 42, depth: 100))
        XCTAssertTrue(page.bodyHTML.contains("href=\"/w/osrsDeepNavigationFixture/42/100\""))
        XCTAssertTrue(page.bodyHTML.contains("osrs fixture next article"))
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
}

private actor osrsAssetTransportTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor osrsAssetTransportCancellationProbe {
    private(set) var value = false

    func record(_ value: Bool) {
        self.value = value
    }
}

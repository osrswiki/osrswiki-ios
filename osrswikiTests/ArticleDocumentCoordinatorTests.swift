import XCTest
import WebKit
@testable import osrswiki

final class ArticleDocumentCoordinatorTests: XCTestCase {
    private let options = osrsArticleRenderOptions(
        usesDarkTheme: false,
        collapseTablesEnabled: true,
        articleTextScale: 1.0
    )

    func testConcurrentForegroundRequestsCoalesceFetchDecodeAndBuild() async throws {
        let fetchCount = LockedCounter()
        let buildCount = LockedCounter()
        let coordinator = makeCoordinator(
            fetcher: { _ in
                fetchCount.increment()
                try await Task.sleep(nanoseconds: 60_000_000)
                return Self.fixtureData(title: "Coal")
            },
            builder: { payload, _ in
                buildCount.increment()
                try await Task.sleep(nanoseconds: 20_000_000)
                return "<html>\(payload.normalizedHTML)</html>"
            }
        )
        let request = request("Coal")

        async let first = coordinator.preparedDocument(for: request, renderOptions: options)
        async let second = coordinator.preparedDocument(for: request, renderOptions: options)
        let documents = try await [first, second]

        XCTAssertEqual(documents.map(\.payload.title), ["Coal", "Coal"])
        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertEqual(buildCount.value, 1)
    }

    func testMeaningfulTitleCaseAndDiacriticsDoNotCoalesceOrCollide() async throws {
        let fetchCount = LockedCounter()
        let coordinator = makeCoordinator(fetcher: { url in
            fetchCount.increment()
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let distinctTitles = ["Abc", "ABc", "Café", "Cafe"]
        let requests = distinctTitles.map(request)

        XCTAssertNotEqual(requests[0].identity, requests[1].identity, "Second-character case is meaningful in a MediaWiki title")
        XCTAssertNotEqual(requests[2].identity, requests[3].identity, "Diacritics are meaningful in a MediaWiki title")

        for request in requests {
            let document = try await coordinator.preparedDocument(
                for: request,
                renderOptions: options
            )
            XCTAssertEqual(document.payload.title, request.requestedTitle)
        }
        for request in requests {
            _ = try await coordinator.preparedDocument(
                for: request,
                renderOptions: options
            )
        }

        XCTAssertEqual(fetchCount.value, distinctTitles.count)
    }

    func testUnderscoreAndRepeatedWhitespaceNormalizeToOneIdentity() {
        let underscore = osrsArticleDocumentIdentity(
            pageURL: URL(string: "https://oldschool.runescape.wiki/w/Rune___Scape")!,
            pageTitle: nil
        )
        let whitespace = osrsArticleDocumentIdentity(
            pageURL: URL(string: "https://example.invalid/article")!,
            pageTitle: "Rune   Scape"
        )

        XCTAssertEqual(underscore, whitespace)
    }

    func testIndexPHPTitleQueryPreservesMeaningfulCase() {
        let lowerSecondCharacter = osrsArticleDocumentIdentity(
            pageURL: URL(string: "https://oldschool.runescape.wiki/index.php?title=Abc")!,
            pageTitle: nil
        )
        let upperSecondCharacter = osrsArticleDocumentIdentity(
            pageURL: URL(string: "https://oldschool.runescape.wiki/index.php?title=ABc")!,
            pageTitle: nil
        )

        XCTAssertEqual(lowerSecondCharacter.value, "wiki-title:Abc")
        XCTAssertEqual(upperSecondCharacter.value, "wiki-title:ABc")
        XCTAssertNotEqual(lowerSecondCharacter, upperSecondCharacter)
    }

    func testGenericURLFallbackLowercasesOnlySchemeAndHost() {
        let upperPath = osrsArticleDocumentIdentity(
            pageURL: URL(string: "HTTPS://EXAMPLE.COM/Asset/A?variant=Upper")!,
            pageTitle: nil
        )
        let lowerPath = osrsArticleDocumentIdentity(
            pageURL: URL(string: "https://example.com/Asset/a?variant=Upper")!,
            pageTitle: nil
        )
        let lowerQuery = osrsArticleDocumentIdentity(
            pageURL: URL(string: "https://example.com/Asset/A?variant=upper")!,
            pageTitle: nil
        )

        XCTAssertTrue(upperPath.value.hasPrefix("url:https://example.com/"))
        XCTAssertNotEqual(upperPath, lowerPath)
        XCTAssertNotEqual(upperPath, lowerQuery)
    }

    func testPassiveCachePageIdentityIncludesQueryAndPreservesMeaningfulTitleCase() {
        let curidOne = ArticleViewModel.generatePageIdFromURL(
            URL(string: "https://oldschool.runescape.wiki/?curid=1")!
        )
        let curidTwo = ArticleViewModel.generatePageIdFromURL(
            URL(string: "https://oldschool.runescape.wiki/?curid=2")!
        )
        let titleCaseOne = ArticleViewModel.generatePageIdFromURL(
            URL(string: "https://oldschool.runescape.wiki/index.php?title=Abc")!
        )
        let titleCaseTwo = ArticleViewModel.generatePageIdFromURL(
            URL(string: "https://oldschool.runescape.wiki/index.php?title=ABc")!
        )
        XCTAssertNotEqual(curidOne, curidTwo)
        XCTAssertNotEqual(titleCaseOne, titleCaseTwo)

        let equivalentA = ArticleViewModel.generatePageIdFromURL(
            URL(string: "HTTPS://OLDSCHOOL.RUNESCAPE.WIKI/index.php?b=2&title=Caf%C3%A9&a=1#top")!
        )
        let equivalentB = ArticleViewModel.generatePageIdFromURL(
            URL(string: "https://oldschool.runescape.wiki/index.php?a=1&title=Caf%C3%A9&b=2")!
        )
        XCTAssertEqual(equivalentA, equivalentB)
    }

    func testAccessibilityScaleJavaScriptLiteralIsPOSIXAcrossDecimalCommaLocales() {
        XCTAssertEqual(ArticleViewModel.accessibilityScaleLiteral(1.25), "1.250")
        XCTAssertFalse(ArticleViewModel.accessibilityScaleLiteral(1.25).contains(","))
    }

    func testSmallLRUEvictionIsBoundedAndForcesRefetch() async throws {
        let fetchCount = LockedCounter()
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 1, documentCapacity: 1, timeToLive: 300),
            fetcher: { url in
                fetchCount.increment()
                return Self.fixtureData(title: Self.pageTitle(in: url))
            }
        )

        _ = try await coordinator.preparedDocument(for: request("A"), renderOptions: options)
        _ = try await coordinator.preparedDocument(for: request("B"), renderOptions: options)
        _ = try await coordinator.preparedDocument(for: request("A"), renderOptions: options)

        XCTAssertEqual(fetchCount.value, 3, "Capacity-one caches must evict the prior identity")
        let snapshot = await coordinator.debugSnapshot()
        XCTAssertLessThanOrEqual(snapshot.payloadCacheCount, 1)
        XCTAssertLessThanOrEqual(snapshot.documentCacheCount, 1)
    }

    func testTTLExpiryForcesFreshPayloadAndDocument() async throws {
        let now = LockedClock(Date(timeIntervalSince1970: 1_000))
        let fetchCount = LockedCounter()
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 2, documentCapacity: 2, timeToLive: 10),
            clock: { now.value },
            fetcher: { _ in
                fetchCount.increment()
                return Self.fixtureData(title: "TTL")
            }
        )
        let request = request("TTL")

        _ = try await coordinator.preparedDocument(for: request, renderOptions: options)
        now.advance(by: 11)
        _ = try await coordinator.preparedDocument(for: request, renderOptions: options)

        XCTAssertEqual(fetchCount.value, 2)
    }

    func testRedirectAliasAndCanonicalTitleSharePreparedDocumentCache() async throws {
        let fetchCount = LockedCounter()
        let buildCount = LockedCounter()
        let coordinator = makeCoordinator(
            fetcher: { _ in
                fetchCount.increment()
                return Self.fixtureData(title: "Canonical target")
            },
            builder: { payload, _ in
                buildCount.increment()
                return "<html>\(payload.normalizedHTML)</html>"
            }
        )

        let aliasDocument = try await coordinator.preparedDocument(
            for: request("Redirect alias"),
            renderOptions: options
        )
        let canonicalDocument = try await coordinator.preparedDocument(
            for: request("Canonical target"),
            renderOptions: options
        )

        XCTAssertEqual(aliasDocument.payload.resolvedTitle, "Canonical target")
        XCTAssertEqual(canonicalDocument.payload.resolvedTitle, "Canonical target")
        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertEqual(buildCount.value, 1)
    }

    func testRedirectAliasIndexStaysCapacityBoundAndDropsEvictedTargets() async throws {
        let fetchCount = LockedCounter()
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 2, documentCapacity: 2, timeToLive: 300),
            fetcher: { url in
                fetchCount.increment()
                return Self.fixtureData(title: "Canonical \(Self.pageTitle(in: url))")
            }
        )

        for index in 0..<16 {
            _ = try await coordinator.preparedDocument(
                for: request("Redirect \(index)"),
                renderOptions: options
            )
        }

        let snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(fetchCount.value, 16)
        XCTAssertEqual(snapshot.aliasCapacity, 4)
        XCTAssertLessThanOrEqual(snapshot.aliasCacheCount, snapshot.aliasCapacity)
        XCTAssertLessThanOrEqual(snapshot.aliasCacheCount, 2, "Aliases whose canonical cache entries were evicted must be pruned")
    }

    func testExpiredRedirectAliasCanRetargetWithoutServingTheOldCanonicalDocument() async throws {
        let now = LockedClock(Date(timeIntervalSince1970: 2_000))
        let fetchCount = LockedCounter()
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 2, documentCapacity: 2, timeToLive: 10),
            clock: { now.value },
            fetcher: { _ in
                fetchCount.increment()
                return Self.fixtureData(
                    title: fetchCount.value == 1 ? "Old canonical" : "New canonical"
                )
            }
        )
        let aliasRequest = request("Retargeted alias")

        let oldDocument = try await coordinator.preparedDocument(
            for: aliasRequest,
            renderOptions: options
        )
        XCTAssertEqual(oldDocument.payload.title, "Old canonical")
        let oldSnapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(oldSnapshot.aliasCacheCount, 1)

        now.advance(by: 11)
        let identityAfterExpiry = await coordinator.debugResolvedIdentity(
            for: aliasRequest.identity
        )
        XCTAssertEqual(
            identityAfterExpiry,
            aliasRequest.identity,
            "Expired alias entries must not resolve to stale canonical content"
        )
        let expiredSnapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(expiredSnapshot.aliasCacheCount, 0)

        let newDocument = try await coordinator.preparedDocument(
            for: aliasRequest,
            renderOptions: options
        )
        let canonicalDocument = try await coordinator.preparedDocument(
            for: request("New canonical"),
            renderOptions: options
        )

        XCTAssertEqual(newDocument.payload.title, "New canonical")
        XCTAssertEqual(canonicalDocument.payload.title, "New canonical")
        XCTAssertEqual(fetchCount.value, 2)
    }

    func testRedirectChainResolutionCompressesToTheLiveCanonicalIdentity() async throws {
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 3, documentCapacity: 3, timeToLive: 300),
            fetcher: { url in Self.fixtureData(title: Self.pageTitle(in: url)) }
        )
        let first = request("First alias").identity
        let second = request("Second alias").identity
        let canonical = request("Chain target").identity
        _ = try await coordinator.preparedDocument(
            for: request("Chain target"),
            renderOptions: options
        )
        await coordinator.debugInstallAlias(first, canonicalIdentity: second)
        await coordinator.debugInstallAlias(second, canonicalIdentity: canonical)

        let resolved = await coordinator.debugResolvedIdentity(for: first)
        let compressedFirst = await coordinator.debugAliasTarget(for: first)
        let compressedSecond = await coordinator.debugAliasTarget(for: second)
        XCTAssertEqual(resolved, canonical)
        XCTAssertEqual(compressedFirst, canonical)
        XCTAssertEqual(compressedSecond, canonical)
    }

    func testRedirectAliasSurvivesCachePruningWhileCanonicalFlightIsActive() async throws {
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 1, documentCapacity: 1, timeToLive: 300),
            fetcher: { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return Self.fixtureData(title: "In-flight canonical")
            }
        )
        let alias = request("In-flight alias").identity
        let canonicalRequest = request("In-flight canonical")
        let foreground = Task {
            try await coordinator.preparedDocument(
                for: canonicalRequest,
                renderOptions: options
            )
        }
        for _ in 0..<40 {
            let snapshot = await coordinator.debugSnapshot()
            if snapshot.payloadFlightCount == 1 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        await coordinator.debugInstallAlias(
            alias,
            canonicalIdentity: canonicalRequest.identity
        )
        let resolved = await coordinator.debugResolvedIdentity(for: alias)
        let snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(resolved, canonicalRequest.identity)
        XCTAssertEqual(snapshot.aliasCacheCount, 1)

        foreground.cancel()
        _ = try? await foreground.value
    }

    func testRedirectCycleFailsClosedAndIsRemoved() async throws {
        let coordinator = makeCoordinator(
            configuration: .init(payloadCapacity: 2, documentCapacity: 2, timeToLive: 300),
            fetcher: { url in Self.fixtureData(title: Self.pageTitle(in: url)) }
        )
        let first = request("Cycle A").identity
        let second = request("Cycle B").identity
        await coordinator.debugInstallAlias(first, canonicalIdentity: second)
        await coordinator.debugInstallAlias(second, canonicalIdentity: first)

        let resolved = await coordinator.debugResolvedIdentity(for: first)
        let snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(resolved, first)
        XCTAssertEqual(snapshot.aliasCacheCount, 0)
    }

    func testTransportFailureDoesNotPoisonCacheAndPreservesTypedOfflineError() async throws {
        let fetchCount = LockedCounter()
        let coordinator = makeCoordinator(fetcher: { _ in
            fetchCount.increment()
            if fetchCount.value == 1 {
                throw NetworkError.noConnection
            }
            return Self.fixtureData(title: "Recovery")
        })
        let request = request("Recovery")

        do {
            _ = try await coordinator.preparedDocument(for: request, renderOptions: options)
            XCTFail("Expected the original typed connectivity failure")
        } catch let error as NetworkError {
            XCTAssertTrue(error.isOfflineError)
        }

        let recovered = try await coordinator.preparedDocument(for: request, renderOptions: options)
        XCTAssertEqual(recovered.payload.title, "Recovery")
        XCTAssertEqual(fetchCount.value, 2)
    }

    func testForegroundPromotesAndJoinsInFlightPrewarm() async throws {
        let fetchCount = LockedCounter()
        let events = LockedEvents()
        let coordinator = makeCoordinator(
            fetcher: { _ in
                fetchCount.increment()
                try await Task.sleep(nanoseconds: 120_000_000)
                return Self.fixtureData(title: "Promoted")
            },
            eventSink: { events.append($0) }
        )
        let request = request("Promoted")
        let owner = UUID()
        let conditions = allowedConditions(isConstrained: false)

        let started = await coordinator.startPrewarm(
            owner: owner,
            request: request,
            renderOptions: options,
            conditions: conditions
        )
        XCTAssertTrue(started)
        try await Task.sleep(nanoseconds: 20_000_000)
        let foregroundTask = Task {
            try await coordinator.preparedDocument(
                for: request,
                renderOptions: options,
                purpose: .foreground
            )
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.reevaluateActivePrewarms(
            conditions: blockedConditions(isLowPowerModeEnabled: true)
        )
        let foreground = try await foregroundTask.value

        XCTAssertEqual(foreground.payload.title, "Promoted")
        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertTrue(events.values.contains { $0.phase == .promotion && $0.identity == request.identity })
    }

    func testPromotedPrewarmKeepsOneConfiguredNoStoreFlight() async throws {
        let foregroundFetchCount = LockedCounter()
        let speculativeFetchCount = LockedCounter()
        let coordinator = makeCoordinator(
            fetcher: { _ in
                foregroundFetchCount.increment()
                return Self.fixtureData(title: "Configured foreground")
            },
            prewarmFetcher: { _ in
                speculativeFetchCount.increment()
                try await Task.sleep(nanoseconds: 100_000_000)
                return Self.fixtureData(title: "Promoted no-store")
            }
        )
        let request = request("Promoted no-store")
        let owner = UUID()

        let started = await coordinator.startPrewarm(
            owner: owner,
            request: request,
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        XCTAssertTrue(started)
        try await Task.sleep(nanoseconds: 20_000_000)

        let document = try await coordinator.preparedDocument(
            for: request,
            renderOptions: options,
            purpose: .foreground
        )

        XCTAssertEqual(document.payload.title, "Promoted no-store")
        XCTAssertEqual(speculativeFetchCount.value, 1)
        XCTAssertEqual(foregroundFetchCount.value, 0)
    }

    @MainActor
    func testConfiguredNoStorePreservesProxyFirstFallbackAndForcedOfflineCacheRoute() {
        let manager = NetworkManager.shared
        manager.setForcedOfflineForTests(false)
        manager.configureProxyRouting(enabled: true, port: 43_210, allowsDirectFallback: true)
        defer {
            manager.setForcedOfflineForTests(false)
            manager.configureProxyRouting(enabled: false)
        }
        let originalURL = URL(string: "https://oldschool.runescape.wiki/api.php?action=parse&page=B")!

        let onlineCandidates = manager.requestURLsForTesting(
            for: originalURL,
            routingPolicy: .configuredNoStore
        )
        XCTAssertEqual(onlineCandidates.count, 2)
        XCTAssertEqual(onlineCandidates.first?.host, "127.0.0.1")
        XCTAssertEqual(onlineCandidates.last, originalURL)

        manager.setForcedOfflineForTests(true)
        let offlineCandidates = manager.requestURLsForTesting(
            for: originalURL,
            routingPolicy: .configuredNoStore
        )
        XCTAssertEqual(offlineCandidates.count, 1)
        XCTAssertEqual(offlineCandidates.first?.host, "127.0.0.1")
    }

    @MainActor
    func testProxyRewritePreservesPercentEncodedPathForExactGenerationIdentity() throws {
        let manager = NetworkManager.shared
        manager.setForcedOfflineForTests(false)
        manager.configureProxyRouting(enabled: true, port: 43_211, allowsDirectFallback: false)
        defer {
            manager.setForcedOfflineForTests(false)
            manager.configureProxyRouting(enabled: false)
        }

        let originalURL = try XCTUnwrap(URL(
            string: "https://oldschool.runescape.wiki/images/thumb/Banker_%28Varrock%2C_male%29_chathead.png/53px-Banker_%28Varrock%2C_male%29_chathead.png?rev=A%2FB%3Fmode%3Dfull%23anchor&variant=2"
        ))
        let originalComponents = try XCTUnwrap(URLComponents(
            url: originalURL,
            resolvingAgainstBaseURL: false
        ))
        let proxyURL = try XCTUnwrap(manager.requestURLsForTesting(
            for: originalURL,
            routingPolicy: .configured
        ).first)
        let proxyComponents = try XCTUnwrap(URLComponents(
            url: proxyURL,
            resolvingAgainstBaseURL: false
        ))

        XCTAssertTrue(proxyComponents.percentEncodedPath.contains("%28Varrock%2C_male%29"))
        XCTAssertFalse(proxyComponents.percentEncodedPath.contains("(Varrock,_male)"))
        XCTAssertEqual(
            proxyComponents.percentEncodedQuery,
            originalComponents.percentEncodedQuery,
            "Reserved query delimiters must remain encoded across loopback rewriting"
        )

        let prefix = "/https/"
        XCTAssertTrue(proxyComponents.percentEncodedPath.hasPrefix(prefix))
        let encodedTargetPath = String(proxyComponents.percentEncodedPath.dropFirst(prefix.count))
        let decodedServerURL = "https://\(encodedTargetPath)?\(try XCTUnwrap(proxyComponents.percentEncodedQuery))"
        XCTAssertEqual(
            osrsCanonicalNetworkURLString(decodedServerURL),
            osrsCanonicalNetworkURLString(originalURL.absoluteString)
        )
        XCTAssertEqual(
            LocalHTTPServer.cacheKeyForRequest(
                pageId: "encoded-generation",
                method: "GET",
                url: decodedServerURL
            ),
            LocalHTTPServer.cacheKeyForRequest(
                pageId: "encoded-generation",
                method: "GET",
                url: originalURL.absoluteString
            )
        )
    }

    func testSharedForegroundAndPrewarmPreparationBothUseConfiguredNoStoreRouting() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsArticleDocumentCoordinator.swift"),
            encoding: .utf8
        )
        let sharedStart = try XCTUnwrap(source.range(of: "static let shared = osrsArticleDocumentCoordinator("))
        let sharedEnd = try XCTUnwrap(source.range(of: "builder: { payload, options in", range: sharedStart.upperBound..<source.endIndex))
        let sharedConfiguration = String(source[sharedStart.lowerBound..<sharedEnd.lowerBound])

        XCTAssertEqual(
            sharedConfiguration.components(separatedBy: "routingPolicy: .configuredNoStore").count - 1,
            2,
            "A foreground miss and a speculative prewarm must share proxy-first/fallback behavior without inheriting an explicit save generation."
        )
    }

    @MainActor
    func testHiddenArticleReleasesPassiveOwnerBeforeAnotherTabPrewarms() async throws {
        let articleA = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Article_A")!,
            pageTitle: "Article A"
        )
        articleA.setArticleVisibility(true, allowsPassiveCaching: true)
        articleA.setWebView(WKWebView(frame: .zero))
        for _ in 0..<40 where ProxyInterceptorService.shared.activeCachePageIdForTesting == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertNotNil(ProxyInterceptorService.shared.activeCachePageIdForTesting)

        // A system TabView may retain article A, so disappearance—not deinit—is the boundary.
        articleA.cancelActiveWorkForNavigation()
        XCTAssertNil(ProxyInterceptorService.shared.activeCachePageIdForTesting)

        let fetchStarted = LockedCounter()
        let coordinator = makeCoordinator(
            fetcher: { _ in Self.fixtureData(title: "Article B") },
            prewarmFetcher: { _ in
                fetchStarted.increment()
                try await Task.sleep(nanoseconds: 80_000_000)
                return Self.fixtureData(title: "Article B")
            }
        )
        let owner = UUID()
        let started = await coordinator.startPrewarm(
            owner: owner,
            request: request("Article B"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        XCTAssertTrue(started)
        for _ in 0..<20 where fetchStarted.value == 0 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(fetchStarted.value, 1)
        XCTAssertNil(
            ProxyInterceptorService.shared.activeCachePageIdForTesting,
            "Prewarm B must not run inside hidden article A's passive save session"
        )
        await coordinator.cancelPrewarm(owner: owner)
    }

    @MainActor
    func testExplicitSaveLeaseDefersPassiveOwnerThenHandsOffRouting() async throws {
        let service = ProxyInterceptorService.shared
        service.stopLocalServer()
        defer { service.stopLocalServer() }
        let reservation = try XCTUnwrap(service.reserveExplicitSaveLease())
        XCTAssertTrue(service.hasExplicitSaveReservationForTesting)

        // This represents article B appearing while article A is still awaiting metadata. The
        // reservation is synchronous at A's Save tap, so B must wait without receiving a stale
        // token that A would later invalidate.
        let passivePreparation = Task { @MainActor in
            await service.enablePassiveCachingMode(pageId: "visible-passive")
        }
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(service.activeCachePageIdForTesting)
        XCTAssertTrue(service.hasExplicitSaveReservationForTesting)

        let explicitOwnerValue = await service.enableExplicitOfflineSaveMode(
            pageId: "explicit-save",
            saveGeneration: "test-generation",
            reservation: reservation
        )
        let explicitOwner = try XCTUnwrap(explicitOwnerValue)
        XCTAssertTrue(NetworkManager.shared.proxyRoutingStateForTesting.enabled)
        XCTAssertFalse(
            NetworkManager.shared.proxyRoutingStateForTesting.allowsDirectFallback,
            "Explicit-save success must not bypass the local atomic disk commit"
        )

        XCTAssertEqual(service.explicitSavePageIdForTesting, "explicit-save")
        XCTAssertEqual(service.activeCachePageIdForTesting, "explicit-save")
        XCTAssertFalse(
            NetworkManager.shared.proxyRoutingStateForTesting.allowsDirectFallback,
            "Opening another article must not preempt an in-progress authoritative save"
        )

        service.disableMode(owner: explicitOwner)
        let passiveOwnerValue = await passivePreparation.value
        let passiveOwner = try XCTUnwrap(passiveOwnerValue)
        XCTAssertTrue(
            NetworkManager.shared.proxyRoutingStateForTesting.enabled,
            "The latest visible passive owner must resume after explicit settlement"
        )
        XCTAssertEqual(service.activeCachePageIdForTesting, "visible-passive")

        service.disableMode(owner: passiveOwner)
        XCTAssertFalse(NetworkManager.shared.proxyRoutingStateForTesting.enabled)
    }

    @MainActor
    func testReleasedExplicitReservationAfterPreparationFailureUnblocksVisibleOwner() async throws {
        let service = ProxyInterceptorService.shared
        service.stopLocalServer()
        defer { service.stopLocalServer() }
        let reservation = try XCTUnwrap(service.reserveExplicitSaveLease())
        let waitingPresentation = Task { @MainActor in
            await service.enableCacheFirstMode(pageId: "visible-after-failure")
        }
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(service.activeCachePageIdForTesting)

        // This is the error/cancellation exit taken before an explicit token exists.
        service.releaseExplicitSaveReservation(reservation)
        let resumedValue = await waitingPresentation.value
        let resumed = try XCTUnwrap(resumedValue)
        XCTAssertEqual(service.activeCachePageIdForTesting, "visible-after-failure")
        service.disableMode(owner: resumed)
    }

    @MainActor
    func testSavedPresentationOwnerTransfersAtomicallyIntoExplicitRetryAndResumesLatestRoute() async throws {
        let service = ProxyInterceptorService.shared
        service.stopLocalServer()
        defer { service.stopLocalServer() }

        let savedOwnerValue = await service.enableCacheFirstMode(pageId: "saved-old-snapshot")
        let savedOwner = try XCTUnwrap(savedOwnerValue)
        XCTAssertEqual(service.activeCachePageIdForTesting, "saved-old-snapshot")

        let reservation = try XCTUnwrap(service.reserveExplicitSaveLease(
            replacingPresentationOwner: savedOwner
        ))
        XCTAssertNil(
            service.activeCachePageIdForTesting,
            "The exact saved presentation owner must be relinquished in the same actor turn that reserves explicit ownership"
        )
        XCTAssertTrue(service.hasExplicitSaveReservationForTesting)

        let visibleResume = Task { @MainActor in
            await service.enableCacheFirstMode(pageId: "saved-new-published-snapshot")
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertNil(service.activeCachePageIdForTesting)

        let explicitOwnerValue = await service.enableExplicitOfflineSaveMode(
            pageId: "saved-staging-snapshot",
            saveGeneration: "saved-retry-generation",
            fallbackPageId: "saved-old-snapshot",
            reservation: reservation
        )
        let explicitOwner = try XCTUnwrap(explicitOwnerValue)
        XCTAssertEqual(service.explicitSavePageIdForTesting, "saved-staging-snapshot")

        service.disableMode(owner: explicitOwner)
        let resumedOwnerValue = await visibleResume.value
        let resumedOwner = try XCTUnwrap(resumedOwnerValue)
        XCTAssertEqual(
            service.activeCachePageIdForTesting,
            "saved-new-published-snapshot",
            "A still-visible saved article must resume the newly published namespace, not its deleted old pointer"
        )
        service.disableMode(owner: resumedOwner)
    }

    @MainActor
    func testCancelledSavedRetryResumeCannotResurrectRouteAfterDisappear() async throws {
        let service = ProxyInterceptorService.shared
        service.stopLocalServer()
        defer { service.stopLocalServer() }

        let savedOwnerValue = await service.enableCacheOnlyMode(pageId: "saved-visible-before-cancel")
        let savedOwner = try XCTUnwrap(savedOwnerValue)
        let reservation = try XCTUnwrap(service.reserveExplicitSaveLease(
            replacingPresentationOwner: savedOwner
        ))
        let cancelledResume = Task { @MainActor in
            await service.enableCacheFirstMode(pageId: "must-not-resurrect")
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        cancelledResume.cancel()
        service.releaseExplicitSaveReservation(reservation)

        let cancelledOwner = await cancelledResume.value
        XCTAssertNil(cancelledOwner)
        XCTAssertNil(service.activeCachePageIdForTesting)
        XCTAssertFalse(NetworkManager.shared.proxyRoutingStateForTesting.enabled)
    }

    func testSaveActionReservesBeforeMetadataAndReleasesOnEveryExit() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        let function = try XCTUnwrap(source.range(of: "func performSaveAction("))
        let reservation = try XCTUnwrap(source.range(of: "reserveExplicitSaveLease()", range: function.upperBound..<source.endIndex))
        let deferredRelease = try XCTUnwrap(source.range(of: "releaseExplicitSaveReservation(explicitSaveReservation)", range: reservation.upperBound..<source.endIndex))
        let metadata = try XCTUnwrap(source.range(of: "let metadata = await fetchPageMetadata()", range: reservation.upperBound..<source.endIndex))
        let cancellationCheck = try XCTUnwrap(source.range(of: "try Task.checkCancellation()", range: metadata.upperBound..<source.endIndex))

        XCTAssertLessThan(reservation.lowerBound, metadata.lowerBound)
        XCTAssertLessThan(deferredRelease.lowerBound, metadata.lowerBound, "The release must be installed as a defer before metadata can suspend.")
        XCTAssertGreaterThan(cancellationCheck.lowerBound, metadata.lowerBound)
    }

    @MainActor
    func testCancelledOldModePreparationCannotStealNewOwnerAfterDelayedListenerReadiness() async throws {
        let service = ProxyInterceptorService.shared
        service.stopLocalServer()
        service.setServerStartupDelayForTesting(0.20)
        defer {
            service.setServerStartupDelayForTesting(0)
            service.stopLocalServer()
        }

        let startedAt = Date()
        let cancelledOldPreparation = Task { @MainActor in
            await service.enablePassiveCachingMode(pageId: "cancelled-old-owner")
        }
        await Task.yield()
        cancelledOldPreparation.cancel()

        // MainActor must keep processing while the shared listener is deliberately delayed.
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.15)
        XCTAssertNil(service.activeCachePageIdForTesting)

        let newOwnerValue = await service.enableCacheFirstMode(pageId: "current-new-owner")
        let newOwner = try XCTUnwrap(newOwnerValue)
        let oldOwner = await cancelledOldPreparation.value

        XCTAssertNil(oldOwner, "A canceled waiter must not install cache ownership after readiness")
        XCTAssertEqual(service.activeCachePageIdForTesting, "current-new-owner")
        XCTAssertTrue(NetworkManager.shared.proxyRoutingStateForTesting.enabled)

        service.disableMode(owner: newOwner)
    }

    func testLeavingVisibleRowCancelsUnderlyingWorkWhenNoConsumerRemains() async throws {
        let cancellationCount = LockedCounter()
        let coordinator = makeCoordinator(fetcher: { _ in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return Self.fixtureData(title: "Cancelled")
            } catch is CancellationError {
                cancellationCount.increment()
                throw CancellationError()
            }
        })
        let owner = UUID()
        let started = await coordinator.startPrewarm(
            owner: owner,
            request: request("Cancelled"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        XCTAssertTrue(started)
        try await Task.sleep(nanoseconds: 20_000_000)

        await coordinator.cancelPrewarm(owner: owner)
        try await Task.sleep(nanoseconds: 80_000_000)

        let snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(snapshot.activePrewarmCount, 0)
        XCTAssertEqual(snapshot.documentFlightCount, 0)
        XCTAssertEqual(snapshot.payloadFlightCount, 0)
        XCTAssertEqual(cancellationCount.value, 1)
    }

    func testVisibleRowDwellGateDoesNotScheduleUntilActuallyIntersectingViewport() {
        var gate = osrsArticlePrewarmVisibilityGate()

        XCTAssertEqual(
            gate.transition(.appeared(applicationIsActive: true, environmentAllowsPrewarm: true)),
            .none,
            "A lazily instantiated but offscreen row must not begin its dwell timer"
        )
        XCTAssertFalse(gate.isGeometricallyVisible)
        XCTAssertEqual(
            gate.transition(.visibilityChanged(true)),
            .schedule,
            "A partially visible row crossing the 10% SwiftUI threshold starts one dwell"
        )
        XCTAssertEqual(gate.transition(.visibilityChanged(true)), .none)
        XCTAssertEqual(gate.transition(.visibilityChanged(false)), .cancel)
        XCTAssertFalse(gate.isEligible)
        XCTAssertEqual(gate.transition(.visibilityChanged(true)), .schedule)
        XCTAssertEqual(gate.transition(.disappeared), .cancel)
        XCTAssertFalse(gate.isGeometricallyVisible)
    }

    func testVisibilityGateCancelsInBackgroundAndRequiresVisibleActiveStateToResume() {
        var gate = osrsArticlePrewarmVisibilityGate()

        XCTAssertEqual(
            gate.transition(.appeared(applicationIsActive: true, environmentAllowsPrewarm: true)),
            .none
        )
        XCTAssertEqual(gate.transition(.visibilityChanged(true)), .schedule)
        XCTAssertEqual(gate.transition(.applicationActivityChanged(false)), .cancel)
        XCTAssertEqual(gate.transition(.applicationActivityChanged(true)), .schedule)
        XCTAssertEqual(gate.transition(.visibilityChanged(false)), .cancel)
        XCTAssertEqual(gate.transition(.applicationActivityChanged(true)), .none)
    }

    func testMultiLinkBatchCancellationCannotStartOwnersAfterDisappear() async {
        let started = LockedUUIDs()
        let cancelled = LockedUUIDs()
        let firstStartReached = AsyncTestGate()
        let releaseFirstStart = AsyncTestGate()
        let requests = (0..<3).map { index in
            osrsArticlePrewarmBatchRequest(
                owner: UUID(),
                pageURL: URL(string: "https://oldschool.runescape.wiki/w/Batch_\(index)")!,
                pageTitle: "Batch \(index)"
            )
        }

        let task = Task {
            await osrsArticlePrewarmBatchRunner.run(
                requests,
                start: { request in
                    started.append(request.owner)
                    if request.owner == requests[0].owner {
                        await firstStartReached.open()
                        await releaseFirstStart.wait()
                    }
                },
                cancel: { owner in cancelled.append(owner) }
            )
        }

        await firstStartReached.wait()
        task.cancel()
        await releaseFirstStart.open()
        await task.value

        XCTAssertEqual(started.values, [requests[0].owner])
        XCTAssertEqual(Set(cancelled.values), Set(requests.map(\.owner)))
    }

    func testSuppressedVisibleRowSchedulesOnceWhenEnvironmentBecomesAllowed() {
        var gate = osrsArticlePrewarmVisibilityGate()

        XCTAssertEqual(
            gate.transition(.appeared(applicationIsActive: true, environmentAllowsPrewarm: false)),
            .none
        )
        XCTAssertEqual(gate.transition(.visibilityChanged(true)), .none)
        XCTAssertTrue(gate.isGeometricallyVisible)
        XCTAssertFalse(gate.isEligible)

        XCTAssertEqual(
            gate.transition(.environmentEligibilityChanged(true)),
            .schedule,
            "A low-power/thermal/offline-suppressed row must retry after conditions recover"
        )
        XCTAssertEqual(
            gate.transition(.environmentEligibilityChanged(true)),
            .none,
            "Repeated favorable notifications must not duplicate the owner or reset dwell"
        )
        XCTAssertEqual(gate.transition(.environmentEligibilityChanged(false)), .cancel)
    }

    func testDuplicateVisibleOwnersShareOnePrewarmIdentitySlot() async throws {
        let coordinator = makeCoordinator(fetcher: { url in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let firstOwner = UUID()
        let duplicateOwner = UUID()
        let distinctOwner = UUID()
        let suppressedOwner = UUID()

        let firstStarted = await coordinator.startPrewarm(
            owner: firstOwner,
            request: request("Duplicate A"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        let duplicateStarted = await coordinator.startPrewarm(
            owner: duplicateOwner,
            request: request("Duplicate A"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        let distinctStarted = await coordinator.startPrewarm(
            owner: distinctOwner,
            request: request("Distinct B"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        let suppressedStarted = await coordinator.startPrewarm(
            owner: suppressedOwner,
            request: request("Suppressed C"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )

        XCTAssertTrue(firstStarted)
        XCTAssertTrue(duplicateStarted)
        XCTAssertTrue(distinctStarted)
        XCTAssertTrue(suppressedStarted, "A third visible candidate should queue instead of being omitted")

        let snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(snapshot.activePrewarmCount, 3)
        XCTAssertEqual(snapshot.activePrewarmIdentityCount, 2)
        XCTAssertEqual(snapshot.pendingPrewarmCount, 1)

        await coordinator.cancelPrewarm(owner: firstOwner)
        await coordinator.cancelPrewarm(owner: duplicateOwner)
        for _ in 0..<20 {
            if await coordinator.debugSnapshot().pendingPrewarmCount == 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let resumedSnapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(resumedSnapshot.pendingPrewarmCount, 0)
        XCTAssertEqual(resumedSnapshot.activePrewarmIdentityCount, 2)
        await coordinator.cancelPrewarm(owner: distinctOwner)
        await coordinator.cancelPrewarm(owner: suppressedOwner)
    }

    func testDistinctForegroundPreemptsExactlyOnePurelySpeculativeIdentity() async throws {
        let cancellations = LockedURLs()
        let starts = LockedURLs()
        let coordinator = makeCoordinator(fetcher: { url in
            starts.append(url)
            let title = Self.pageTitle(in: url)
            if title == "Foreground C" {
                return Self.fixtureData(title: title)
            }
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return Self.fixtureData(title: title)
            } catch is CancellationError {
                cancellations.append(url)
                throw CancellationError()
            }
        })
        let firstOwner = UUID()
        let secondOwner = UUID()
        for (owner, title) in [(firstOwner, "Speculative A"), (secondOwner, "Speculative B")] {
            let accepted = await coordinator.startPrewarm(
                owner: owner,
                request: request(title),
                renderOptions: options,
                conditions: allowedConditions(isConstrained: false)
            )
            XCTAssertTrue(accepted)
        }
        for _ in 0..<40 {
            if await coordinator.debugSnapshot().payloadFlightCount == 2 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let foreground = try await coordinator.preparedDocument(
            for: request("Foreground C"),
            renderOptions: options,
            purpose: .foreground
        )
        XCTAssertEqual(foreground.payload.title, "Foreground C")
        for _ in 0..<40 where cancellations.values.count < 1 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(cancellations.values.count, 1)
        XCTAssertEqual(Set(starts.values.map(Self.pageTitle(in:))), [
            "Speculative A", "Speculative B", "Foreground C"
        ])

        await coordinator.cancelPrewarm(owner: firstOwner)
        await coordinator.cancelPrewarm(owner: secondOwner)
    }

    func testNonCooperativeCancellationKeepsOneBoundedForegroundLane() async throws {
        let speculationGate = AsyncTestGate()
        let firstForegroundGate = AsyncTestGate()
        let starts = LockedURLs()
        let concurrency = LockedConcurrencyProbe()
        let coordinator = makeCoordinator(fetcher: { url in
            starts.append(url)
            concurrency.begin()
            defer { concurrency.end() }
            let title = Self.pageTitle(in: url)
            switch title {
            case "Noncooperative speculation":
                await speculationGate.wait()
            case "Canceled foreground":
                await firstForegroundGate.wait()
            default:
                break
            }
            return Self.fixtureData(title: title)
        })

        let owner = UUID()
        let speculationAccepted = await coordinator.startPrewarm(
            owner: owner,
            request: request("Noncooperative speculation"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: true)
        )
        XCTAssertTrue(speculationAccepted)
        for _ in 0..<40 where starts.values.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(concurrency.current, 1)

        await coordinator.cancelPrewarm(owner: owner)
        let firstForeground = Task {
            try await coordinator.preparedDocument(
                for: request("Canceled foreground"),
                renderOptions: options
            )
        }
        for _ in 0..<40 where starts.values.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(concurrency.maximum, 2, "One tap may overlap one canceling speculation")

        firstForeground.cancel()
        let secondForeground = Task {
            try await coordinator.preparedDocument(
                for: request("Replacement foreground"),
                renderOptions: options
            )
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(starts.values.map(Self.pageTitle(in:)).contains("Replacement foreground"))
        XCTAssertEqual(concurrency.maximum, 2)

        await speculationGate.open()
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(
            starts.values.map(Self.pageTitle(in:)).contains("Replacement foreground"),
            "A canceled foreground still physically occupying the lane must block its replacement"
        )

        await firstForegroundGate.open()
        do {
            _ = try await firstForeground.value
            XCTFail("The canceled foreground must not publish after its noncooperative fetch returns")
        } catch is CancellationError {
            // Expected.
        }
        let replacement = try await secondForeground.value
        XCTAssertEqual(replacement.payload.title, "Replacement foreground")
        XCTAssertEqual(concurrency.maximum, 2)
    }

    func testTwoToOneDownshiftRetainsPhysicalSlotUntilCanceledRunCompletes() async throws {
        let firstGate = AsyncTestGate()
        let secondGate = AsyncTestGate()
        let starts = LockedURLs()
        let coordinator = makeCoordinator(fetcher: { url in
            starts.append(url)
            switch Self.pageTitle(in: url) {
            case "Downshift A": await firstGate.wait()
            case "Downshift B": await secondGate.wait()
            default: break
            }
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let firstOwner = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondOwner = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let queuedOwner = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))

        for (owner, title) in [(firstOwner, "Downshift A"), (secondOwner, "Downshift B")] {
            let accepted = await coordinator.startPrewarm(
                owner: owner,
                request: request(title),
                renderOptions: options,
                conditions: allowedConditions(isConstrained: false)
            )
            XCTAssertTrue(accepted)
        }
        for _ in 0..<40 where starts.values.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        await coordinator.reevaluateActivePrewarms(
            conditions: allowedConditions(isConstrained: true)
        )
        let queuedAccepted = await coordinator.startPrewarm(
            owner: queuedOwner,
            request: request("Queued after downshift"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: true)
        )
        XCTAssertTrue(queuedAccepted)
        var snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(snapshot.activePrewarmIdentityCount, 1)
        XCTAssertEqual(snapshot.retiringPrewarmCount, 1)
        XCTAssertEqual(snapshot.physicalPrewarmIdentityCount, 2)
        XCTAssertEqual(snapshot.pendingPrewarmCount, 1)

        await secondGate.open()
        for _ in 0..<40 {
            snapshot = await coordinator.debugSnapshot()
            if snapshot.retiringPrewarmCount == 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(snapshot.physicalPrewarmIdentityCount, 1)
        XCTAssertEqual(snapshot.pendingPrewarmCount, 1)
        XCTAssertFalse(starts.values.map(Self.pageTitle(in:)).contains("Queued after downshift"))

        await firstGate.open()
        for _ in 0..<40 where !starts.values.map(Self.pageTitle(in:)).contains("Queued after downshift") {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(starts.values.map(Self.pageTitle(in:)).contains("Queued after downshift"))
        await coordinator.cancelPrewarm(owner: queuedOwner)
    }

    func testForegroundStartsWhileTwoToOneDownshiftRetiresNonCooperativeSpeculation() async throws {
        let firstGate = AsyncTestGate()
        let secondGate = AsyncTestGate()
        let starts = LockedURLs()
        let concurrency = LockedConcurrencyProbe()
        let coordinator = makeCoordinator(fetcher: { url in
            starts.append(url)
            concurrency.begin()
            defer { concurrency.end() }
            switch Self.pageTitle(in: url) {
            case "Downshift noncooperative A": await firstGate.wait()
            case "Downshift noncooperative B": await secondGate.wait()
            default: break
            }
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let firstOwner = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let secondOwner = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))

        for (owner, title) in [
            (firstOwner, "Downshift noncooperative A"),
            (secondOwner, "Downshift noncooperative B")
        ] {
            let accepted = await coordinator.startPrewarm(
                owner: owner,
                request: request(title),
                renderOptions: options,
                conditions: allowedConditions(isConstrained: false)
            )
            XCTAssertTrue(accepted)
        }
        for _ in 0..<40 where starts.values.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        await coordinator.reevaluateActivePrewarms(
            conditions: allowedConditions(isConstrained: true)
        )
        let foreground = Task {
            try await coordinator.preparedDocument(
                for: request("Foreground after downshift"),
                renderOptions: options
            )
        }
        for _ in 0..<40 where !starts.values.map(Self.pageTitle(in:)).contains("Foreground after downshift") {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(
            starts.values.map(Self.pageTitle(in:)).contains("Foreground after downshift"),
            "A foreground open must not wait for noncooperative speculation retired by downshift"
        )
        XCTAssertEqual(concurrency.maximum, 3, "Only one foreground lane may overlap the two physical speculative requests")

        await firstGate.open()
        await secondGate.open()
        let foregroundDocument = try await foreground.value
        XCTAssertEqual(foregroundDocument.payload.title, "Foreground after downshift")
        await coordinator.cancelPrewarm(owner: firstOwner)
        await coordinator.cancelPrewarm(owner: secondOwner)
    }

    func testForegroundStartsWhileSuppressionRetiresNonCooperativeSpeculation() async throws {
        let speculationGate = AsyncTestGate()
        let starts = LockedURLs()
        let concurrency = LockedConcurrencyProbe()
        let coordinator = makeCoordinator(fetcher: { url in
            starts.append(url)
            concurrency.begin()
            defer { concurrency.end() }
            if Self.pageTitle(in: url) == "Suppressed noncooperative speculation" {
                await speculationGate.wait()
            }
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let owner = UUID()
        let accepted = await coordinator.startPrewarm(
            owner: owner,
            request: request("Suppressed noncooperative speculation"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: true)
        )
        XCTAssertTrue(accepted)
        for _ in 0..<40 where starts.values.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        await coordinator.reevaluateActivePrewarms(
            conditions: blockedConditions(isLowPowerModeEnabled: true)
        )
        let foreground = Task {
            try await coordinator.preparedDocument(
                for: request("Foreground after suppression"),
                renderOptions: options
            )
        }
        for _ in 0..<40 where !starts.values.map(Self.pageTitle(in:)).contains("Foreground after suppression") {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(
            starts.values.map(Self.pageTitle(in:)).contains("Foreground after suppression"),
            "A foreground open must not wait for speculation retired by a zero-limit transition"
        )
        XCTAssertEqual(concurrency.maximum, 2)

        await speculationGate.open()
        let foregroundDocument = try await foreground.value
        XCTAssertEqual(foregroundDocument.payload.title, "Foreground after suppression")
    }

    func testDuplicateOwnerRetirementCannotStarveDistinctForeground() async throws {
        let speculationGate = AsyncTestGate()
        let firstForegroundGate = AsyncTestGate()
        let starts = LockedURLs()
        let concurrency = LockedConcurrencyProbe()
        let coordinator = makeCoordinator(fetcher: { url in
            starts.append(url)
            concurrency.begin()
            defer { concurrency.end() }
            switch Self.pageTitle(in: url) {
            case "Duplicate constrained speculation": await speculationGate.wait()
            case "Duplicate-owner foreground": await firstForegroundGate.wait()
            default: break
            }
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let firstOwner = UUID()
        let duplicateOwner = UUID()
        for owner in [firstOwner, duplicateOwner] {
            let accepted = await coordinator.startPrewarm(
                owner: owner,
                request: request("Duplicate constrained speculation"),
                renderOptions: options,
                conditions: allowedConditions(isConstrained: true)
            )
            XCTAssertTrue(accepted)
        }
        for _ in 0..<40 where starts.values.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(starts.values.count, 1, "Duplicate owners must coalesce one speculative transport")

        await coordinator.cancelPrewarm(owner: firstOwner)
        let firstForeground = Task {
            try await coordinator.preparedDocument(
                for: request("Duplicate-owner foreground"),
                renderOptions: options
            )
        }
        for _ in 0..<40 where starts.values.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(starts.values.map(Self.pageTitle(in:)).contains("Duplicate-owner foreground"))
        XCTAssertEqual(concurrency.maximum, 2)

        firstForeground.cancel()
        let replacementForeground = Task {
            try await coordinator.preparedDocument(
                for: request("Duplicate-owner replacement foreground"),
                renderOptions: options
            )
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(starts.values.map(Self.pageTitle(in:)).contains("Duplicate-owner replacement foreground"))

        await speculationGate.open()
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(
            starts.values.map(Self.pageTitle(in:)).contains("Duplicate-owner replacement foreground"),
            "The serialized foreground lane must remain occupied until its canceled transport returns"
        )

        await firstForegroundGate.open()
        do {
            _ = try await firstForeground.value
            XCTFail("The canceled foreground must not publish")
        } catch is CancellationError {
            // Expected.
        }
        let replacementDocument = try await replacementForeground.value
        XCTAssertEqual(replacementDocument.payload.title, "Duplicate-owner replacement foreground")
        XCTAssertEqual(concurrency.maximum, 2)
        await coordinator.cancelPrewarm(owner: duplicateOwner)
    }

    func testPrewarmConstraintsAreDeterministicAndBounded() {
        XCTAssertEqual(allowedConditions(isConstrained: false).maximumConcurrentPrewarms, 2)
        XCTAssertEqual(allowedConditions(isConstrained: true).maximumConcurrentPrewarms, 1)

        XCTAssertEqual(
            osrsArticlePrewarmConditions(
                hasNetworkConnection: true,
                isConstrained: false,
                isLowPowerModeEnabled: true,
                thermalState: .nominal,
                isApplicationActive: true,
                isOfflineContentAvailable: false
            ).maximumConcurrentPrewarms,
            0
        )
        XCTAssertEqual(
            osrsArticlePrewarmConditions(
                hasNetworkConnection: true,
                isConstrained: false,
                isLowPowerModeEnabled: false,
                thermalState: .serious,
                isApplicationActive: true,
                isOfflineContentAvailable: false
            ).maximumConcurrentPrewarms,
            0
        )
        XCTAssertEqual(
            osrsArticlePrewarmConditions(
                hasNetworkConnection: true,
                isConstrained: false,
                isLowPowerModeEnabled: false,
                thermalState: .nominal,
                isApplicationActive: false,
                isOfflineContentAvailable: false
            ).maximumConcurrentPrewarms,
            0
        )
        XCTAssertEqual(
            osrsArticlePrewarmConditions(
                hasNetworkConnection: true,
                isConstrained: false,
                isLowPowerModeEnabled: false,
                thermalState: .nominal,
                isApplicationActive: true,
                isOfflineContentAvailable: true
            ).maximumConcurrentPrewarms,
            0
        )
    }

    func testIncreasingConcurrencyLimitImmediatelyDrainsVisibleQueue() async throws {
        let coordinator = makeCoordinator(fetcher: { url in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.fixtureData(title: Self.pageTitle(in: url))
        })
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstAccepted = await coordinator.startPrewarm(
            owner: firstOwner,
            request: request("Constrained A"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: true)
        )
        let secondAccepted = await coordinator.startPrewarm(
            owner: secondOwner,
            request: request("Queued B"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: true)
        )
        XCTAssertTrue(firstAccepted)
        XCTAssertTrue(secondAccepted)
        var snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(snapshot.activePrewarmIdentityCount, 1)
        XCTAssertEqual(snapshot.pendingPrewarmCount, 1)

        await coordinator.reevaluateActivePrewarms(
            conditions: allowedConditions(isConstrained: false)
        )
        snapshot = await coordinator.debugSnapshot()
        XCTAssertEqual(snapshot.activePrewarmIdentityCount, 2)
        XCTAssertEqual(snapshot.pendingPrewarmCount, 0)

        await coordinator.cancelPrewarm(owner: firstOwner)
        await coordinator.cancelPrewarm(owner: secondOwner)
    }

    func testLowPowerAndBackgroundTransitionsCancelActiveSpeculation() async throws {
        let lowPowerCoordinator = makeCoordinator(fetcher: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.fixtureData(title: "Low power")
        })
        for index in 0..<2 {
            let started = await lowPowerCoordinator.startPrewarm(
                owner: UUID(),
                request: request("Low power \(index)"),
                renderOptions: options,
                conditions: allowedConditions(isConstrained: false)
            )
            XCTAssertTrue(started)
        }
        let lowPowerBefore = await lowPowerCoordinator.debugSnapshot()
        XCTAssertEqual(lowPowerBefore.activePrewarmCount, 2)
        await lowPowerCoordinator.reevaluateActivePrewarms(
            conditions: blockedConditions(isLowPowerModeEnabled: true)
        )
        let lowPowerAfter = await lowPowerCoordinator.debugSnapshot()
        XCTAssertEqual(lowPowerAfter.activePrewarmCount, 0)

        let backgroundCoordinator = makeCoordinator(fetcher: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.fixtureData(title: "Background")
        })
        let started = await backgroundCoordinator.startPrewarm(
            owner: UUID(),
            request: request("Background"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )
        XCTAssertTrue(started)
        await backgroundCoordinator.reevaluateActivePrewarms(
            conditions: blockedConditions(isApplicationActive: false)
        )
        let backgroundAfter = await backgroundCoordinator.debugSnapshot()
        XCTAssertEqual(backgroundAfter.activePrewarmCount, 0)
    }

    func testPrewarmTransportIsParseDocumentOnlyAndNeverRequestsImagesMapsOrCharts() async throws {
        let requestedURLs = LockedURLs()
        let coordinator = makeCoordinator(fetcher: { url in
            requestedURLs.append(url)
            return Self.fixtureData(title: "Text only")
        })
        let owner = UUID()
        _ = await coordinator.startPrewarm(
            owner: owner,
            request: request("Text only"),
            renderOptions: options,
            conditions: allowedConditions(isConstrained: false)
        )

        for _ in 0..<40 {
            if await coordinator.debugSnapshot().activePrewarmCount == 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(requestedURLs.values.count, 1)
        let url = try XCTUnwrap(requestedURLs.values.first)
        XCTAssertEqual(url.lastPathComponent, "api.php")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value, "parse")
        XCTAssertFalse(url.absoluteString.localizedCaseInsensitiveContains("image"))
        XCTAssertFalse(url.absoluteString.localizedCaseInsensitiveContains("map"))
        XCTAssertFalse(url.absoluteString.localizedCaseInsensitiveContains("chart"))
    }

    func testVisibleRowHooksCoverHomeSearchSavedAndHistoryAndNormalLoadHasNoDetachedImageCrawl() throws {
        let root = try repositoryRoot()
        for path in [
            "platforms/ios/osrswiki/Views/NewsView.swift",
            "platforms/ios/osrswiki/Views/Components/SearchResultRowView.swift",
            "platforms/ios/osrswiki/Views/SavedPagesView.swift",
            "platforms/ios/osrswiki/Views/HistoryView.swift"
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(
                source.contains(".osrsPrewarmArticleWhenVisible(") ||
                    source.contains(".osrsPrewarmArticlesWhenVisible("),
                "Missing bounded visible-row hook in \(path)"
            )
        }

        let articleViewModel = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(articleViewModel.contains("proactivelyDownloadAllResources"))
        XCTAssertFalse(articleViewModel.contains("Task.detached(priority: .utility) { [weak self, tempPageId"))
        XCTAssertTrue(articleViewModel.contains("downloadBoundedOfflineResources"))
        XCTAssertTrue(articleViewModel.contains("persistExplicitSaveResponse"))
        XCTAssertTrue(articleViewModel.contains("maximumConcurrency: 6"))
        XCTAssertFalse(articleViewModel.contains("prefix(maximumOfflineImages)"))

        let proxy = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/ProxyInterceptorService.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(proxy.contains("A visible-article passive owner must yield to the explicit save"))

        let news = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Views/NewsView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(news.contains("startPrewarm("))
        XCTAssertTrue(articleViewModel.contains("adoptPreRenderedWebView"))
        XCTAssertTrue(articleViewModel.contains("osrsPreparedDocumentKey"))

        let coordinator = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Services/osrsArticleDocumentCoordinator.swift"),
            encoding: .utf8
        )
        let networkManager = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/Utils/NetworkManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(coordinator.contains("NetworkManager.shared.performDataRequest"))
        XCTAssertTrue(networkManager.contains("proxyAllowsDirectFallback"))
        XCTAssertTrue(articleViewModel.contains("if pageUrl.scheme == \"app-assets\""))
        XCTAssertTrue(articleViewModel.contains("loadUrlDirectlyInWebView"))
    }

    func testMapDiscoveryCannotRunBeforeWebKitReadyBoundary() throws {
        let html = """
        <p>Readable article text.</p>
        <div class="osrswiki-map" data-lat="3200" data-lon="3201" data-zoom="6" data-plane="0" id="map-a"></div>
        """
        var state = osrsDeferredMapPreloadState()
        state.stage(html, generation: 7)
        XCTAssertEqual(state.pendingGenerationCount, 1)
        XCTAssertNil(state.takeAfterWebKitReady(generation: 6))
        XCTAssertEqual(state.pendingGenerationCount, 1)

        let postReadyHTML = try XCTUnwrap(state.takeAfterWebKitReady(generation: 7))
        XCTAssertEqual(state.pendingGenerationCount, 0)
        XCTAssertEqual(osrsMapPreloadService.parseMapDataFromHTML(postReadyHTML).map(\.id), ["map-a"])

        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("platforms/ios/osrswiki/ViewModels/ArticleViewModel.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("osrsMapPreloadService.shared.preloadMapsFromHTML(html)"))
        XCTAssertTrue(source.contains("startDeferredMapPreloadAfterWebKitReady"))
    }

    private func makeCoordinator(
        configuration: osrsArticleDocumentCoordinator.Configuration = .init(),
        clock: @escaping osrsArticleDocumentCoordinator.Clock = { Date() },
        fetcher: @escaping osrsArticleDocumentCoordinator.Fetcher,
        prewarmFetcher: osrsArticleDocumentCoordinator.Fetcher? = nil,
        builder: @escaping osrsArticleDocumentCoordinator.Builder = { payload, _ in
            "<html>\(payload.normalizedHTML)</html>"
        },
        eventSink: @escaping osrsArticleDocumentCoordinator.EventSink = { _ in }
    ) -> osrsArticleDocumentCoordinator {
        osrsArticleDocumentCoordinator(
            configuration: configuration,
            clock: clock,
            fetcher: fetcher,
            prewarmFetcher: prewarmFetcher,
            builder: builder,
            eventSink: eventSink
        )
    }

    private func request(_ title: String) -> osrsArticleDocumentRequest {
        let encoded = title.replacingOccurrences(of: " ", with: "_")
        return osrsArticleDocumentRequest(
            pageURL: URL(string: "https://oldschool.runescape.wiki/w/\(encoded)")!,
            pageTitle: title
        )
    }

    private func allowedConditions(isConstrained: Bool) -> osrsArticlePrewarmConditions {
        osrsArticlePrewarmConditions(
            hasNetworkConnection: true,
            isConstrained: isConstrained,
            isLowPowerModeEnabled: false,
            thermalState: .nominal,
            isApplicationActive: true,
            isOfflineContentAvailable: false
        )
    }

    private func blockedConditions(
        isLowPowerModeEnabled: Bool = false,
        isApplicationActive: Bool = true
    ) -> osrsArticlePrewarmConditions {
        osrsArticlePrewarmConditions(
            hasNetworkConnection: true,
            isConstrained: false,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            thermalState: .nominal,
            isApplicationActive: isApplicationActive,
            isOfflineContentAvailable: false
        )
    }

    private static func fixtureData(title: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "parse": [
                "pageid": abs(title.hashValue % 10_000) + 1,
                "title": title,
                "displaytitle": title,
                "revid": 42,
                "text": ["*": "<p>\(title)</p><tr class=\"advanced-data\"><td>hidden</td></tr>"]
            ]
        ])
    }

    private static func pageTitle(in url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value ?? "Unknown"
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date

    init(_ value: Date) { storage = value }

    var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        storage = storage.addingTimeInterval(interval)
        lock.unlock()
    }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [osrsArticleTimingEvent] = []

    var values: [osrsArticleTimingEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: osrsArticleTimingEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

private final class LockedConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activeStorage = 0
    private var maximumStorage = 0

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeStorage
    }

    var maximum: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumStorage
    }

    func begin() {
        lock.lock()
        activeStorage += 1
        maximumStorage = max(maximumStorage, activeStorage)
        lock.unlock()
    }

    func end() {
        lock.lock()
        activeStorage -= 1
        lock.unlock()
    }
}

private final class LockedUUIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID] = []

    var values: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: UUID) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

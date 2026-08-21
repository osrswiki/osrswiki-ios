//
//  AppState Navigation Methods - Updated for unique destination types
//  CRITICAL FIX: Prevents cross-stack interference by using unique destination types
//

import Foundation
import SwiftUI
import UIKit

extension AppState {
#if DEBUG
    var osrsNavigationStackDebugLabel: String {
        "selected=\(selectedTab.rawValue);news=\(newsNavigationStack.count);saved=\(savedNavigationStack.count);search=\(searchNavigationStack.count);map=\(mapNavigationStack.count);more=\(moreNavigationStack.count);history=\(historyNavigationStack.count);active=\(activeArticleDestination?.url.absoluteString ?? "nil");articleBackActions=\(articleBackActionDebugCount)"
    }
#endif

    var activeArticleDestination: ArticleDestination? {
        switch selectedTab {
        case .news:
            if case .article(let destination) = newsNavigationStack.last {
                return destination
            }
        case .saved:
            if case .article(let destination) = savedNavigationStack.last {
                return destination
            }
        case .search:
            if case .article(let destination) = searchNavigationStack.last {
                return destination
            }
        case .map:
            if case .article(let destination) = mapNavigationStack.last {
                return destination
            }
        case .more:
            if case .article(let destination) = moreNavigationStack.last {
                return destination
            }
        }

        return nil
    }

    var canNavigateBackWithinActiveArticleStack: Bool {
        switch selectedTab {
        case .news:
            return hasArticleBelowTop(newsNavigationStack)
        case .saved:
            return hasArticleBelowTop(savedNavigationStack)
        case .search:
            return searchNavigationStack.count > 1
        case .map:
            return mapNavigationStack.count > 1
        case .more:
            return hasArticleBelowTop(moreNavigationStack)
        }
    }

    private func hasArticleBelowTop(_ stack: [NewsNavigationDestination]) -> Bool {
        guard stack.count > 1,
              case .article = stack[stack.count - 1],
              case .article = stack[stack.count - 2] else {
            return false
        }
        return true
    }

    private func hasArticleBelowTop(_ stack: [HistoryNavigationDestination]) -> Bool {
        guard stack.count > 1,
              case .article = stack[stack.count - 1],
              case .article = stack[stack.count - 2] else {
            return false
        }
        return true
    }

    private func hasArticleBelowTop(_ stack: [SavedNavigationDestination]) -> Bool {
        guard stack.count > 1,
              case .article = stack[stack.count - 1],
              case .article = stack[stack.count - 2] else {
            return false
        }
        return true
    }

    private func hasArticleBelowTop(_ stack: [MoreNavigationDestination]) -> Bool {
        guard stack.count > 1,
              case .article = stack[stack.count - 1],
              case .article = stack[stack.count - 2] else {
            return false
        }
        return true
    }

    // MARK: - Tab-Specific Navigation Methods

    func appendArticleDestinationForSelectedTab(_ articleDestination: ArticleDestination) {
        appendArticleDestination(articleDestination, to: selectedTab)
    }

    private func appendArticleDestination(_ articleDestination: ArticleDestination, to tab: TabItem) {
        osrsInteractiveArticleSwipe.captureVisibleBackPreview()
        switch tab {
        case .news:
            newsNavigationStack.append(.article(articleDestination))
        case .saved:
            savedNavigationStack.append(.article(articleDestination))
        case .search:
            searchNavigationStack.append(.article(articleDestination))
        case .map:
            mapNavigationStack.append(.article(articleDestination))
        case .more:
            moreNavigationStack.append(.article(articleDestination))
        }
        UserDefaults.standard.set(articleDestination.url.absoluteString, forKey: "osrs.lastResumableArticleURL")
        NotificationCenter.default.post(name: .osrsResumableArticleDidChange, object: articleDestination.url)
    }

    private func shouldAppendArticle(_ articleDestination: ArticleDestination, to tab: TabItem) -> Bool {
        let existingDestination: ArticleDestination?

        switch tab {
        case .news:
            if case .article(let destination) = newsNavigationStack.last {
                existingDestination = destination
            } else {
                existingDestination = nil
            }
        case .saved:
            if case .article(let destination) = savedNavigationStack.last {
                existingDestination = destination
            } else {
                existingDestination = nil
            }
        case .search:
            if case .article(let destination) = searchNavigationStack.last {
                existingDestination = destination
            } else {
                existingDestination = nil
            }
        case .map:
            if case .article(let destination) = mapNavigationStack.last {
                existingDestination = destination
            } else {
                existingDestination = nil
            }
        case .more:
            if case .article(let destination) = moreNavigationStack.last {
                existingDestination = destination
            } else {
                existingDestination = nil
            }
        }

        return existingDestination?.url != articleDestination.url
    }

    // Navigate to article from current tab context using appropriate destination type
    func navigateToArticle(title: String, url: URL, snippet: String? = nil, thumbnailUrl: URL? = nil, savedPageId: String? = nil) {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        let frameId = String(format: "%.3f", Date().timeIntervalSince1970)
        print("🔍 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: navigateToArticle called for '\(title)' | selectedTab: \(selectedTab.rawValue)")

        let targetTab = selectedTab
        let articleDestination = ArticleDestination(title: title, url: url, snippet: snippet, thumbnailUrl: thumbnailUrl, savedPageId: savedPageId)
        guard shouldAppendArticle(articleDestination, to: targetTab) else {
            print("⚠️ [\(timestamp)] APPSTATE: Duplicate article navigation suppressed for \(targetTab.rawValue)")
            return
        }

        print("🟢 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: Adding article to \(targetTab.rawValue) stack")
        osrsPreparedArticleWebViewStore.shared.pin(
            identity: osrsArticleDocumentIdentity(pageURL: url, pageTitle: title).value,
            foreground: true
        )
        appendArticleDestination(articleDestination, to: targetTab)

        print("🟢 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: Tab-specific navigation completed")
    }

    // Navigate to search from current tab context
    func navigateToSearch() {
        navigateToActiveSearch(startsVoiceRecognition: false)
    }

    func navigateToScopedSearch(_ scope: osrsSearchScope) {
        setSelectedTab(.news)
        newsNavigationStack.append(.scopedSearch(scope))
    }

    /// Routes an article toolbar action to the one canonical, active Search surface regardless
    /// of which tab owns the article. The SearchView acknowledges this generation exactly once;
    /// voice recognition is deliberately not started here because its result callbacks are
    /// installed by SearchView when that destination becomes active.
    func navigateToActiveSearch(startsVoiceRecognition: Bool = false) {
        nextSearchActivationGeneration &+= 1
        let returnContext = osrsSearchReturnContext(
            generation: nextSearchActivationGeneration,
            originTab: selectedTab,
            priorSearchNavigationStack: searchNavigationStack
        )
        let intent = osrsSearchActivationIntent(
            generation: nextSearchActivationGeneration,
            startsVoiceRecognition: startsVoiceRecognition,
            returnContext: returnContext
        )

        // Remove any article destination before exposing the Search tab's root. Do this before
        // publishing the intent so an already-mounted SearchView never handles it underneath an
        // article that is still on screen.
        searchNavigationStack.removeAll(keepingCapacity: true)
        if selectedTab != .search {
            setSelectedTab(.search)
        }
        pendingSearchActivationIntent = intent
    }

    /// Atomically acknowledges one Search activation generation. Duplicate SwiftUI lifecycle
    /// delivery (`onAppear` followed by `onChange`, or vice versa) cannot start voice twice.
    @discardableResult
    func consumeSearchActivationIntent(generation: UInt64) -> Bool {
        guard let intent = pendingSearchActivationIntent,
              intent.generation == generation else { return false }
        activeSearchReturnContext = intent.returnContext
        pendingSearchActivationIntent = nil
        return true
    }

    func cancelSearchActivationIntent() {
        pendingSearchActivationIntent = nil
    }

    /// Dismisses the canonical active Search surface back to exactly the source that launched
    /// it. For a Search-owned article this restores the saved Search navigation stack; for any
    /// other tab it restores that tab while preserving its untouched article stack.
    @discardableResult
    func returnFromActiveSearchIfNeeded() -> Bool {
        guard let context = activeSearchReturnContext else { return false }
        activeSearchReturnContext = nil
        pendingSearchActivationIntent = nil
        searchNavigationStack = context.priorSearchNavigationStack
        if selectedTab != context.originTab {
            setSelectedTab(context.originTab)
        }
        return true
    }

    func invalidateActiveSearchReturnContext() {
        activeSearchReturnContext = nil
    }

    // MARK: - History-Specific Navigation Methods

    // Navigate to search from History tab using history navigation stack
    func navigateToSearchFromHistory() {
        navigateToActiveSearch(startsVoiceRecognition: false)
    }

    // Navigate to search from Saved tab using saved navigation stack
    func navigateToSearchFromSaved() {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🔍 [\(timestamp)] APPSTATE: navigateToSearchFromSaved called")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("🟢 [\(timestamp)] APPSTATE: Adding search to savedNavigationStack")
            self.savedNavigationStack.append(.search)
        }
    }

    // Navigate to article from History context using history navigation stack
    func navigateToArticleInHistory(title: String, url: URL, snippet: String? = nil, thumbnailUrl: URL? = nil) {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        let frameId = String(format: "%.3f", Date().timeIntervalSince1970)
        print("🔍 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: navigateToArticleInHistory called for '\(title)'")
        print("🟢 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: ✅✅✅ HISTORY NAVIGATION - UNIQUE DESTINATION TYPE ✅✅✅")

        let articleDestination = ArticleDestination(title: title, url: url, snippet: snippet, thumbnailUrl: thumbnailUrl, savedPageId: nil)

        if case .article(let destination) = historyNavigationStack.last,
           destination.url == articleDestination.url {
            print("⚠️ [\(timestamp)] APPSTATE: Duplicate history navigation suppressed")
            return
        }

        print("🟢 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: Adding to historyNavigationStack with unique destination type")
        osrsPreparedArticleWebViewStore.shared.pin(
            identity: osrsArticleDocumentIdentity(pageURL: url, pageTitle: title).value,
            foreground: true
        )
        osrsInteractiveArticleSwipe.captureVisibleBackPreview()
        historyNavigationStack.append(.article(articleDestination))
        print("🟢 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: History navigation completed - only HistoryView handler will respond")
    }

    // URL-only navigation (convenience method for simple article navigation)
    func navigateToArticle(url: URL) {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🔍 [\(timestamp)] APPSTATE: navigateToArticle(url:) called for \(url)")

        let title = Self.articleTitle(from: url)

        // Use the rich navigation method
        navigateToArticle(title: title, url: url, snippet: nil, thumbnailUrl: nil)
    }

    func routeInternalArticleLink(_ url: URL, sourceArticleURL: URL? = nil) {
        guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) else {
            print("⚠️ APPSTATE: Ignoring non-article internal route request for \(url.absoluteString)")
            return
        }

        if let sourceArticleURL {
            guard let activeSourceURL = activeArticleDestination?.url,
                  osrsArticleLinkRouter.appArticleURL(for: activeSourceURL) == osrsArticleLinkRouter.appArticleURL(for: sourceArticleURL) else {
                print("⚠️ APPSTATE: Ignoring internal route from an inactive article source")
                return
            }
        }

        navigateToArticle(url: articleURL)
    }

#if DEBUG
    @discardableResult
    func runDeepNavigationFixtureAuditForUITests(
        seed: Int = osrsDeepNavigationFixtureAudit.defaultSeed,
        startOffset: Int = osrsDeepNavigationFixtureAudit.defaultStartOffset,
        startCount: Int = osrsDeepNavigationFixtureAudit.defaultStartCount,
        targetDepth: Int = osrsDeepNavigationFixtureAudit.defaultDepth
    ) -> osrsDeepNavigationFixtureAuditResult {
        let sanitizedStartCount = max(0, startCount)
        let sanitizedDepth = max(1, targetDepth)
        let started = CFAbsoluteTimeGetCurrent()
        var completedStarts = 0
        var forwardTransitions = 0
        var backTransitions = 0
        var firstMismatch: String?

        isDeepNavigationFixtureAuditRunning = true
        defer { isDeepNavigationFixtureAuditRunning = false }

        selectedTab = .search
        newsNavigationStack.removeAll(keepingCapacity: true)
        savedNavigationStack.removeAll(keepingCapacity: true)
        searchNavigationStack.removeAll(keepingCapacity: true)
        mapNavigationStack.removeAll(keepingCapacity: true)
        moreNavigationStack.removeAll(keepingCapacity: true)
        historyNavigationStack.removeAll(keepingCapacity: true)

        sampleLoop: for sampleSequence in startOffset..<(startOffset + sanitizedStartCount) {
            let sampleOrdinal = osrsDeepNavigationFixtureAudit.sampleOrdinal(seed: seed, sequence: sampleSequence)
            searchNavigationStack.removeAll(keepingCapacity: true)

            for depth in 0...sanitizedDepth {
                let destination = osrsDeepNavigationFixtureAudit.articleDestination(
                    sampleOrdinal: sampleOrdinal,
                    depth: depth
                )
                appendArticleDestinationForSelectedTab(destination)

                guard activeArticleDestination?.url == destination.url else {
                    firstMismatch = "forward sample=\(sampleOrdinal) depth=\(depth) expected=\(destination.url.absoluteString) observed=\(activeArticleDestination?.url.absoluteString ?? "nil")"
                    break sampleLoop
                }

                if depth > 0 {
                    forwardTransitions += 1
                }
            }

            for depth in stride(from: sanitizedDepth - 1, through: 0, by: -1) {
                let expectedURL = osrsDeepNavigationFixtureAudit.articleURL(
                    sampleOrdinal: sampleOrdinal,
                    depth: depth
                )

                guard navigateBackWithinActiveArticleStack() else {
                    firstMismatch = "back sample=\(sampleOrdinal) depth=\(depth) expected=\(expectedURL.absoluteString) observed=\(activeArticleDestination?.url.absoluteString ?? "nil")"
                    break sampleLoop
                }

                backTransitions += 1

                guard activeArticleDestination?.url == expectedURL else {
                    firstMismatch = "back sample=\(sampleOrdinal) depth=\(depth) expected=\(expectedURL.absoluteString) observed=\(activeArticleDestination?.url.absoluteString ?? "nil")"
                    break sampleLoop
                }
            }

            completedStarts += 1
        }

        let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        let mismatchCount = firstMismatch == nil ? 0 : 1
        let status = mismatchCount == 0 && completedStarts == sanitizedStartCount ? "pass" : "mismatch"
        let result = osrsDeepNavigationFixtureAuditResult(
            status: status,
            seed: seed,
            startOffset: startOffset,
            startCount: sanitizedStartCount,
            targetDepth: sanitizedDepth,
            completedStarts: completedStarts,
            forwardTransitions: forwardTransitions,
            backTransitions: backTransitions,
            mismatchCount: mismatchCount,
            firstMismatch: firstMismatch,
            elapsedMilliseconds: elapsedMilliseconds,
            finalActiveURL: activeArticleDestination?.url.absoluteString
        )
        deepNavigationFixtureAuditDebugLabel = result.accessibilityLabel
        return result
    }
#endif

    static func articleTitle(from url: URL) -> String {
        let path = url.path
        let encodedTitle: String
        if path.hasPrefix("/w/") {
            encodedTitle = String(path.dropFirst(3))
        } else {
            encodedTitle = url.lastPathComponent
        }

        let decodedTitle = encodedTitle
            .removingPercentEncoding?
            .replacingOccurrences(of: "_", with: " ") ?? encodedTitle.replacingOccurrences(of: "_", with: " ")

        return osrsStringUtils.extractMainTitle(decodedTitle)
    }

    // MARK: - Back Navigation

    private func logArticleNavigation(_ message: String) {
#if DEBUG
        if isDeepNavigationFixtureAuditRunning || osrsTestEnvironment.runsDeepNavigationFixtureAuditForUITests {
            return
        }
#endif
        print(message)
    }

    func beginArticleBackAction(
        articleIdentity: String,
        transitionIdentity: String
    ) -> Bool {
        guard activeArticleDestination?.navigationIdentity == articleIdentity else {
            logArticleNavigation("🔙 AppState: Suppressed stale article back callback")
            return false
        }
        guard lastAcceptedArticleBackTransitionIdentity != transitionIdentity else {
            logArticleNavigation("🔙 AppState: Suppressed duplicate article back transition")
            return false
        }
        return true
    }

    func completeArticleBackAction(transitionIdentity: String, accepted: Bool) {
        guard accepted else { return }
        lastAcceptedArticleBackTransitionIdentity = transitionIdentity
    }

    private func applyArticleNavigationChange(animated: Bool, _ body: () -> Void) {
        if animated {
            body()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    @discardableResult
    func navigateBackWithinActiveArticleStack(animated: Bool = true) -> Bool {
        switch selectedTab {
        case .news:
            guard hasArticleBelowTop(newsNavigationStack),
                  case .article = newsNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                newsNavigationStack.removeLast()
            }
            osrsInteractiveArticleSwipe.popCapturedBackPreview()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous news article")
        case .saved:
            guard hasArticleBelowTop(savedNavigationStack),
                  case .article = savedNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                savedNavigationStack.removeLast()
            }
            osrsInteractiveArticleSwipe.popCapturedBackPreview()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous saved article")
        case .search:
            guard searchNavigationStack.count > 1,
                  case .article = searchNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                searchNavigationStack.removeLast()
            }
            osrsInteractiveArticleSwipe.popCapturedBackPreview()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous search article")
        case .map:
            guard mapNavigationStack.count > 1,
                  case .article = mapNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                mapNavigationStack.removeLast()
            }
            osrsInteractiveArticleSwipe.popCapturedBackPreview()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous map article")
        case .more:
            guard hasArticleBelowTop(moreNavigationStack),
                  case .article = moreNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                moreNavigationStack.removeLast()
            }
            osrsInteractiveArticleSwipe.popCapturedBackPreview()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous more article")
        }

        return true
    }

    /// Pops the visible tab's root article before consulting WebView history. MediaWiki redirects
    /// can add an implementation-only WebView entry; allowing that entry to win made Home's back
    /// button appear inert while Search happened to work normally.
    @discardableResult
    func navigateBackFromActiveRootArticle(animated: Bool = true) -> Bool {
        switch selectedTab {
        case .news:
            guard !hasArticleBelowTop(newsNavigationStack), case .article = newsNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                newsNavigationStack.removeLast()
            }
        case .saved:
            guard !hasArticleBelowTop(savedNavigationStack), case .article = savedNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                savedNavigationStack.removeLast()
            }
        case .search:
            guard searchNavigationStack.count == 1, case .article = searchNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                searchNavigationStack.removeLast()
            }
        case .map:
            guard mapNavigationStack.count == 1, case .article = mapNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                mapNavigationStack.removeLast()
            }
        case .more:
            guard !hasArticleBelowTop(moreNavigationStack), case .article = moreNavigationStack.last else { return false }
            applyArticleNavigationChange(animated: animated) {
                moreNavigationStack.removeLast()
            }
        }
        osrsInteractiveArticleSwipe.popCapturedBackPreview()
        logArticleNavigation("🔙 AppState: ✅ Popped visible root article for \(selectedTab.rawValue)")
        return true
    }

    func navigateBack(animated: Bool = true) {
        let now = Date()
        guard now.timeIntervalSince(lastNavigationTime) >= navigationDebounceInterval else {
            print("🔙 AppState: Suppressed duplicate back navigation")
            return
        }
        lastNavigationTime = now

        print("🔙 AppState: navigateBack called for \(selectedTab.rawValue)")

        // Back always belongs to the visible tab. A retained off-screen stack must never consume it.
        switch selectedTab {
        case .news:
            if !newsNavigationStack.isEmpty {
                applyArticleNavigationChange(animated: animated) {
                    newsNavigationStack.removeLast()
                }
                print("🔙 AppState: ✅ Navigated back in newsNavigationStack")
            }
        case .saved:
            if !savedNavigationStack.isEmpty {
                applyArticleNavigationChange(animated: animated) {
                    savedNavigationStack.removeLast()
                }
                print("🔙 AppState: ✅ Navigated back in savedNavigationStack")
            }
        case .search:
            if !searchNavigationStack.isEmpty {
                applyArticleNavigationChange(animated: animated) {
                    searchNavigationStack.removeLast()
                }
                print("🔙 AppState: ✅ Navigated back in searchNavigationStack")
            }
        case .map:
            if !mapNavigationStack.isEmpty {
                applyArticleNavigationChange(animated: animated) {
                    mapNavigationStack.removeLast()
                }
                print("🔙 AppState: ✅ Navigated back in mapNavigationStack")
            }
        case .more:
            if !moreNavigationStack.isEmpty {
                applyArticleNavigationChange(animated: animated) {
                    moreNavigationStack.removeLast()
                }
                print("🔙 AppState: ✅ Navigated back in moreNavigationStack")
            }
        }
    }
}

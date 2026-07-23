//
//  AppState Navigation Methods - Updated for unique destination types
//  CRITICAL FIX: Prevents cross-stack interference by using unique destination types
//

import Foundation

extension AppState {
#if DEBUG
    var osrsNavigationStackDebugLabel: String {
        "selected=\(selectedTab.rawValue);news=\(newsNavigationStack.count);saved=\(savedNavigationStack.count);search=\(searchNavigationStack.count);map=\(mapNavigationStack.count);more=\(moreNavigationStack.count);history=\(historyNavigationStack.count);active=\(activeArticleDestination?.url.absoluteString ?? "nil");articleBackActions=\(articleBackActionDebugCount)"
    }
#endif

    var activeArticleDestination: ArticleDestination? {
        if case .article(let destination) = historyNavigationStack.last {
            return destination
        }

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
        if !historyNavigationStack.isEmpty {
            return hasArticleBelowTop(historyNavigationStack)
        }

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
        appendArticleDestination(articleDestination, to: targetTab)

        print("🟢 [\(timestamp)] [FRAME:\(frameId)] APPSTATE: Tab-specific navigation completed")
    }

    // Navigate to search from current tab context
    func navigateToSearch() {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🔍 [\(timestamp)] APPSTATE: navigateToSearch called for selectedTab: \(selectedTab.rawValue)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Priority 1: Check if we're in History context (historyNavigationStack has items)
            // This handles the History → Search → Article → Search (top bar) flow where selectedTab is .search
            // but navigation is managed by historyNavigationStack
            if !self.historyNavigationStack.isEmpty {
                print("🟢 [\(timestamp)] APPSTATE: ✅ Adding search to historyNavigationStack (History context)")
                self.historyNavigationStack.append(.search)
                return
            }

            // Priority 2: Fall back to selectedTab-based navigation for normal tab flows
            switch self.selectedTab {
            case .news:
                print("🟢 [\(timestamp)] APPSTATE: Adding search to newsNavigationStack")
                self.newsNavigationStack.append(.search)
            case .search:
                print("⚠️ [\(timestamp)] APPSTATE: Already in search tab - ignoring navigate to search")
                return
            default:
                print("⚠️ [\(timestamp)] APPSTATE: Search navigation not supported from \(self.selectedTab.rawValue) tab")
                return
            }
        }
    }

    // MARK: - History-Specific Navigation Methods

    // Navigate to search from History tab using history navigation stack
    func navigateToSearchFromHistory() {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🔍 [\(timestamp)] APPSTATE: navigateToSearchFromHistory called")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("🟢 [\(timestamp)] APPSTATE: Adding search to historyNavigationStack")
            self.historyNavigationStack.append(.search)
        }
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

    func routeInternalArticleLink(_ url: URL) {
        guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) else {
            print("⚠️ APPSTATE: Ignoring non-article internal route request for \(url.absoluteString)")
            return
        }

        guard !shouldSuppressInternalArticleRoute(articleURL) else {
            print("⚠️ APPSTATE: Ignoring recently popped internal article route for \(articleURL.absoluteString)")
            return
        }

        navigateToArticle(url: articleURL)
    }

    private func suppressInternalArticleRoute(_ url: URL) {
        suppressedInternalArticleRouteURL = url
        suppressedInternalArticleRouteUntil = Date().addingTimeInterval(internalArticleRouteSuppressionInterval)
    }

    private func shouldSuppressInternalArticleRoute(_ url: URL) -> Bool {
        guard let suppressedURL = suppressedInternalArticleRouteURL else {
            return false
        }

        guard Date() < suppressedInternalArticleRouteUntil else {
            suppressedInternalArticleRouteURL = nil
            suppressedInternalArticleRouteUntil = .distantPast
            return false
        }

        return suppressedURL == url
    }

    private func requestArticleBackStackRecoveryReload() {
        guard let destination = activeArticleDestination else { return }
        articleBackStackRecoveryDestination = destination
        articleBackStackRecoveryRequestID += 1
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

    private func bumpTopArticleNavigationRevision(in stack: inout [NewsNavigationDestination]) {
        guard let lastIndex = stack.indices.last,
              case .article(let destination) = stack[lastIndex] else { return }
        stack[lastIndex] = .article(destination.incrementingNavigationRevision())
    }

    private func bumpTopArticleNavigationRevision(in stack: inout [HistoryNavigationDestination]) {
        guard let lastIndex = stack.indices.last,
              case .article(let destination) = stack[lastIndex] else { return }
        stack[lastIndex] = .article(destination.incrementingNavigationRevision())
    }

    private func bumpTopArticleNavigationRevision(in stack: inout [SavedNavigationDestination]) {
        guard let lastIndex = stack.indices.last,
              case .article(let destination) = stack[lastIndex] else { return }
        stack[lastIndex] = .article(destination.incrementingNavigationRevision())
    }

    private func bumpTopArticleNavigationRevision(in stack: inout [SearchNavigationDestination]) {
        guard let lastIndex = stack.indices.last,
              case .article(let destination) = stack[lastIndex] else { return }
        stack[lastIndex] = .article(destination.incrementingNavigationRevision())
    }

    private func bumpTopArticleNavigationRevision(in stack: inout [MapNavigationDestination]) {
        guard let lastIndex = stack.indices.last,
              case .article(let destination) = stack[lastIndex] else { return }
        stack[lastIndex] = .article(destination.incrementingNavigationRevision())
    }

    private func bumpTopArticleNavigationRevision(in stack: inout [MoreNavigationDestination]) {
        guard let lastIndex = stack.indices.last,
              case .article(let destination) = stack[lastIndex] else { return }
        stack[lastIndex] = .article(destination.incrementingNavigationRevision())
    }

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

    func beginArticleBackAction() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastArticleBackActionTime) >= articleBackActionDebounceInterval else {
            logArticleNavigation("🔙 AppState: Suppressed duplicate article back action")
            return false
        }

        lastArticleBackActionTime = now
        return true
    }

    @discardableResult
    func navigateBackWithinActiveArticleStack() -> Bool {
        if !historyNavigationStack.isEmpty {
            guard hasArticleBelowTop(historyNavigationStack),
                  case .article(let poppedArticle) = historyNavigationStack.last else { return false }
            suppressInternalArticleRoute(poppedArticle.url)
            historyNavigationStack.removeLast()
            bumpTopArticleNavigationRevision(in: &historyNavigationStack)
            requestArticleBackStackRecoveryReload()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous history article")
            return true
        }

        switch selectedTab {
        case .news:
            guard hasArticleBelowTop(newsNavigationStack),
                  case .article(let poppedArticle) = newsNavigationStack.last else { return false }
            suppressInternalArticleRoute(poppedArticle.url)
            newsNavigationStack.removeLast()
            bumpTopArticleNavigationRevision(in: &newsNavigationStack)
            requestArticleBackStackRecoveryReload()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous news article")
        case .saved:
            guard hasArticleBelowTop(savedNavigationStack),
                  case .article(let poppedArticle) = savedNavigationStack.last else { return false }
            suppressInternalArticleRoute(poppedArticle.url)
            savedNavigationStack.removeLast()
            bumpTopArticleNavigationRevision(in: &savedNavigationStack)
            requestArticleBackStackRecoveryReload()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous saved article")
        case .search:
            guard searchNavigationStack.count > 1,
                  case .article(let poppedArticle) = searchNavigationStack.last else { return false }
            suppressInternalArticleRoute(poppedArticle.url)
            searchNavigationStack.removeLast()
            bumpTopArticleNavigationRevision(in: &searchNavigationStack)
            requestArticleBackStackRecoveryReload()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous search article")
        case .map:
            guard mapNavigationStack.count > 1,
                  case .article(let poppedArticle) = mapNavigationStack.last else { return false }
            suppressInternalArticleRoute(poppedArticle.url)
            mapNavigationStack.removeLast()
            bumpTopArticleNavigationRevision(in: &mapNavigationStack)
            requestArticleBackStackRecoveryReload()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous map article")
        case .more:
            guard hasArticleBelowTop(moreNavigationStack),
                  case .article(let poppedArticle) = moreNavigationStack.last else { return false }
            suppressInternalArticleRoute(poppedArticle.url)
            moreNavigationStack.removeLast()
            bumpTopArticleNavigationRevision(in: &moreNavigationStack)
            requestArticleBackStackRecoveryReload()
            logArticleNavigation("🔙 AppState: ✅ Navigated back to previous more article")
        }

        return true
    }

    func navigateBack() {
        let now = Date()
        guard now.timeIntervalSince(lastNavigationTime) >= navigationDebounceInterval else {
            print("🔙 AppState: Suppressed duplicate back navigation")
            return
        }
        lastNavigationTime = now

        print("🔙 AppState: navigateBack called for \(selectedTab.rawValue)")

        // Priority 1: Check if we're in History context (historyNavigationStack has items)
        // This handles the History → Search → Article flow where selectedTab is .search
        // but navigation is managed by historyNavigationStack
        if !historyNavigationStack.isEmpty {
            historyNavigationStack.removeLast()
            print("🔙 AppState: ✅ Navigated back in historyNavigationStack (History context)")
            return
        }

        // Priority 2: Fall back to selectedTab-based navigation for normal tab flows
        switch selectedTab {
        case .news:
            if !newsNavigationStack.isEmpty {
                newsNavigationStack.removeLast()
                print("🔙 AppState: ✅ Navigated back in newsNavigationStack")
            }
        case .saved:
            if !savedNavigationStack.isEmpty {
                savedNavigationStack.removeLast()
                print("🔙 AppState: ✅ Navigated back in savedNavigationStack")
            }
        case .search:
            if !searchNavigationStack.isEmpty {
                searchNavigationStack.removeLast()
                print("🔙 AppState: ✅ Navigated back in searchNavigationStack")
            }
        case .map:
            if !mapNavigationStack.isEmpty {
                mapNavigationStack.removeLast()
                print("🔙 AppState: ✅ Navigated back in mapNavigationStack")
            }
        case .more:
            if !moreNavigationStack.isEmpty {
                moreNavigationStack.removeLast()
                print("🔙 AppState: ✅ Navigated back in moreNavigationStack")
            }
        }
    }
}

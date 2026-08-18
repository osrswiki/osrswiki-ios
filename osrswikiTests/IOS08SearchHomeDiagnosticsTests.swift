//
//  IOS08SearchHomeDiagnosticsTests.swift
//  osrswikiTests
//
//  Regression guards for IOS-08 search/home correctness and diagnostics.
//

import XCTest

final class IOS08SearchHomeDiagnosticsTests: XCTestCase {
    private var projectRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url
    }

    func testSearchViewModelAppliesPaginationStateFromRepositoryResponse() throws {
        let source = try readSource("platforms/ios/osrswiki/ViewModels/SearchViewModel.swift")

        XCTAssertTrue(
            source.contains("hasMoreResults = response.hasMore"),
            "SearchViewModel should publish response.hasMore so the visible Load More control reflects real pagination state."
        )
        XCTAssertTrue(
            source.contains("hasMoreResults = false"),
            "SearchViewModel should reset pagination state when the current search state is cleared or fails."
        )
    }

    func testSearchUsesOneRankedRequestForSnippetsAndThumbnails() throws {
        let source = try readSource("platforms/ios/osrswiki/Repositories/SearchRepository.swift")
        let searchBody = try extractFunctionBody(named: "search", from: source)

        XCTAssertTrue(
            searchBody.contains("generator: \"search\"") &&
            searchBody.contains("generator: \"prefixsearch\"") &&
            searchBody.contains("SearchQueryPolicy.merge"),
            "Live search should union title-prefix hits with ranked fulltext."
        )
        XCTAssertTrue(
            searchBody.contains("async let"),
            "Prefix and fulltext fetches must start together so typeahead does not wait on a serial second trip."
        )
        XCTAssertTrue(
            searchBody.contains("fetchOpenSearchPagesIfNeeded") &&
            searchBody.contains("includeExtracts: true") &&
            searchBody.contains("includeExtracts: false"),
            "Paint website OpenSearch first; TextExtracts belongs only on the small prefix request."
        )
        XCTAssertTrue(
            source.contains("NetworkManager.shared.performDataRequest"),
            "Search still loads snippets and thumbnails through NetworkManager."
        )
    }

    func testSearchViewsDoNotRenderLoadingIndicators() throws {
        for path in [
            "platforms/ios/osrswiki/Views/SearchView.swift",
            "platforms/ios/osrswiki/Views/DedicatedSearchView.swift",
            "platforms/ios/osrswiki/Views/ImmediateStyledSearchView.swift",
            "platforms/ios/osrswiki/Views/Components/SearchResultRowView.swift"
        ] {
            XCTAssertFalse(try readSource(path).contains("ProgressView("), "\(path) should keep live search free of loading icons.")
        }
    }

    func testEveryArticleSearchSurfaceExposesVoiceSearch() throws {
        let requiredIdentifiersByFile: [String: [String]] = [
            "platforms/ios/osrswiki/Views/NewsView.swift": ["home_voice_search"],
            "platforms/ios/osrswiki/Views/SavedPagesView.swift": ["saved_voice_search", "saved_search_voice_search"],
            "platforms/ios/osrswiki/Views/HistoryView.swift": ["history_voice_search"],
            "platforms/ios/osrswiki/Views/SearchView.swift": ["search_history_voice_search", "search_voice_search"],
            "platforms/ios/osrswiki/Views/DedicatedSearchView.swift": ["dedicated_search_voice_search"],
            "platforms/ios/osrswiki/Views/ImmediateStyledSearchView.swift": ["immediate_search_voice_search"]
        ]

        for (path, identifiers) in requiredIdentifiersByFile {
            let source = try readSource(path)
            for identifier in identifiers {
                XCTAssertTrue(source.contains("\"\(identifier)\""), "\(path) should expose functional voice search as \(identifier)")
            }
            XCTAssertTrue(
                source.contains("speechManager.startVoiceRecognition()") ||
                    source.contains("navigateToActiveSearch(startsVoiceRecognition: true)"),
                "\(path) should wire its microphone to speech recognition"
            )
        }

        let helper = try readSource("platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift")
        XCTAssertFalse(helper.contains("beginVoiceSearchAfterNavigation"))

        let articleView = try readSource("platforms/ios/osrswiki/Views/ArticleView.swift")
        let articleToolbar = try readSource("platforms/ios/osrswiki/Views/Components/osrsArticleSearchBar.swift")
        XCTAssertTrue(articleToolbar.contains("\"article_voice_search\""))
        XCTAssertTrue(articleView.contains("appState.navigateToActiveSearch()"))
        XCTAssertTrue(articleView.contains("appState.navigateToActiveSearch(startsVoiceRecognition: true)"))

        let realmSelector = try readSource("platforms/ios/osrswiki/Views/OSRSMapLibreView.swift")
        XCTAssertTrue(realmSelector.contains("\"realm_selector_voice_search\""))
        XCTAssertTrue(realmSelector.contains("appState.speechManager.configure("))
        XCTAssertTrue(realmSelector.contains("store.query = result"))
        XCTAssertTrue(realmSelector.contains("store.query = partialResult"))
        XCTAssertTrue(realmSelector.contains("appState.speechManager.startVoiceRecognition()"))
    }

    func testRootTabsUseOneHeaderAndSearchLauncherContract() throws {
        let helper = try readSource("platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift")
        XCTAssertTrue(helper.contains("struct osrsThemedTabHeader"))
        XCTAssertTrue(helper.contains("struct osrsSearchLauncher"))
        XCTAssertTrue(helper.contains("enum osrsSearchControlGeometry"))
        XCTAssertTrue(helper.contains("static func pillShape(height: CGFloat) -> RoundedRectangle"))
        XCTAssertTrue(helper.contains("style: .circular"))
        XCTAssertTrue(helper.contains("osrsFloatingGlass(in: osrsSearchControlGeometry.pillShape"))
        XCTAssertTrue(helper.contains(".containerShape(shape)"))
        XCTAssertTrue(helper.contains(".clipShape(shape)"))
        XCTAssertFalse(helper.contains("RoundedRectangle(cornerRadius: 18"))
        XCTAssertTrue(helper.contains("struct osrsActiveSearchToolbar"))
        XCTAssertTrue(helper.contains("func osrsTabSearchLauncherLayout"))
        XCTAssertTrue(helper.contains("struct osrsTabSearchWithTrailingControl"))
        XCTAssertTrue(helper.contains("struct osrsGlassOverflowMenu"))
        XCTAssertTrue(helper.contains("private struct osrsUIKitSearchLauncherButton: UIViewRepresentable"))
        XCTAssertTrue(helper.contains("func makeUIView(context: Context) -> UIButton"))
        XCTAssertTrue(helper.contains("button.isAccessibilityElement = true"))
        XCTAssertTrue(helper.contains("button.titleLabel?.isAccessibilityElement = false"))
        XCTAssertTrue(helper.contains("button.accessibilityIdentifier = accessibilityIdentifier"))
        XCTAssertTrue(helper.contains("button.accessibilityLabel = title"))
        XCTAssertTrue(helper.contains("struct osrsUIKitSearchTextField: UIViewRepresentable"))
        XCTAssertTrue(helper.contains("func makeUIView(context: Context) -> UITextField"))
        XCTAssertTrue(helper.contains("@Binding var isFocused: Bool"))
        XCTAssertTrue(helper.contains("UIFont.preferredFont(forTextStyle: .callout)"))
        XCTAssertTrue(helper.contains("textField.adjustsFontForContentSizeCategory = true"))
        XCTAssertTrue(helper.contains("textField.accessibilityIdentifier = accessibilityIdentifier"))
        XCTAssertTrue(helper.contains("func sizeThatFits("))
        XCTAssertTrue(helper.contains("height: controlHeight"))
        XCTAssertFalse(helper.contains("height: proposal.height"), "UIKit search controls must reject greedy vertical proposals.")
        XCTAssertTrue(helper.contains("static let compactHeight: CGFloat = 48"))
        XCTAssertTrue(helper.contains("static let accessibilityHeight: CGFloat = 64"))
        XCTAssertFalse(helper.contains("textField.accessibilityLabel = placeholder"))
        XCTAssertTrue(helper.contains("scheduleTextDelivery(textField.text ?? \"\")"))
        XCTAssertTrue(helper.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.04"))
        XCTAssertTrue(helper.contains("deliverTextImmediately(textField.text ?? \"\")"))
        XCTAssertTrue(helper.contains("synchronizeExternalText(text, in: textField)"))
        XCTAssertTrue(helper.contains("textField.attributedPlaceholder?.string != placeholder"))
        XCTAssertFalse(helper.contains("func osrsAccessibleSearchTextFieldLayout()"))
        XCTAssertTrue(helper.contains(".opacity(text.isEmpty ? 0 : 1)"))
        XCTAssertTrue(helper.contains(".allowsHitTesting(!text.isEmpty)"))

        let searchSource = try readSource("platforms/ios/osrswiki/Views/SearchView.swift")
        XCTAssertEqual(
            searchSource.components(separatedBy: "osrsActiveSearchToolbar(").count - 1,
            1,
            "Canonical Search must use the shared active-search scaffold exactly once."
        )
        XCTAssertFalse(searchSource.contains("osrsUIKitSearchTextField("), "Search must not fork the shared editor geometry.")

        let searchView = try readSource("platforms/ios/osrswiki/Views/SearchView.swift")
        XCTAssertTrue(searchView.contains("osrsTabSearchWithTrailingControl("))
        XCTAssertTrue(searchView.contains("search_history_clear_button"))
        XCTAssertTrue(searchView.contains("if isSearchMode"))
        XCTAssertTrue(searchView.contains("activeSearchToolbar"))
        XCTAssertTrue(searchView.contains("Clear History"))

        let savedSource = try readSource("platforms/ios/osrswiki/Views/SavedPagesView.swift")
        XCTAssertTrue(savedSource.contains("osrsActiveSearchToolbar("))
        XCTAssertTrue(savedSource.contains("inputAccessibilityIdentifier: \"saved_search_input\""))
        XCTAssertTrue(savedSource.contains("backAccessibilityIdentifier: \"saved_search_back_button\""))
        XCTAssertTrue(savedSource.contains("clearAccessibilityIdentifier: \"saved_search_clear_button\""))
        XCTAssertTrue(savedSource.contains("osrsTabSearchWithTrailingControl("))
        XCTAssertTrue(savedSource.contains("osrsGlassOverflowMenu(accessibilityIdentifier: \"saved_header_menu\")"))
        XCTAssertTrue(savedSource.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)"))
        XCTAssertTrue(savedSource.contains("accessibilityIdentifier(\"saved_row_metadata\")"))
        XCTAssertTrue(savedSource.contains("Text(description)"), "Saved rows should render exactly one normal-size description preview.")
        XCTAssertTrue(savedSource.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)"))
        XCTAssertTrue(savedSource.contains(".accessibilityIdentifier(\"saved_row_preview\")"))
        XCTAssertFalse(savedSource.contains("arrow.down.circle.fill"))

        for path in [
            "platforms/ios/osrswiki/Views/NewsView.swift",
            "platforms/ios/osrswiki/Views/SavedPagesView.swift",
            "platforms/ios/osrswiki/Views/SearchView.swift"
        ] {
            let source = try readSource(path)
            XCTAssertFalse(source.contains("osrsThemedTabHeader("), "\(path) should not paint a redundant tab title")
            XCTAssertTrue(source.contains("osrsSearchLauncher("), "\(path) should use the shared search launcher")
            XCTAssertTrue(source.contains("osrsTabGlassAccessoryBar"), "\(path) should pin search as glass accessory chrome")
        }

        let accessory = try readSource("platforms/ios/osrswiki/Utils/osrsVoiceSearchAnimationHelper.swift")
        XCTAssertTrue(accessory.contains(".safeAreaInset(edge: .top, spacing: osrsOverlayChromeMetrics.pairedEdgeGap)"))
        XCTAssertTrue(accessory.contains("osrsOverlayChromeMetrics.pairedEdgeGap"))
        XCTAssertTrue(accessory.contains("osrsOverlayChromeMetrics.screenEdgeGap"))
        XCTAssertTrue(accessory.contains("edge == .top ? osrsOverlayChromeMetrics.topInset : 0"))
        XCTAssertTrue(accessory.contains("static let floatingBarHeight"))
        XCTAssertTrue(accessory.contains(".padding(.trailing, 16)"))
        XCTAssertTrue(accessory.contains(".frame(width: 80, alignment: .center)"))
        XCTAssertTrue(accessory.contains("osrsFloatingGlass"))
        XCTAssertFalse(accessory.contains(".safeAreaBar(edge: .top"))
        XCTAssertFalse(accessory.contains(".scrollEdgeEffectStyle(.soft, for: .top)"))
        let activeToolbar = accessory.components(separatedBy: "struct osrsActiveSearchToolbar").last ?? ""
        XCTAssertFalse(
            activeToolbar.contains(".padding(.horizontal, 16)"),
            "Active search must be the flipped launcher, not a double-inset capsule."
        )

        let homeSource = try readSource("platforms/ios/osrswiki/Views/NewsView.swift")
        XCTAssertEqual(
            homeSource.components(separatedBy: "NavigationStack(path: $appState.newsNavigationStack) {").count - 1,
            3,
            "Every Home variant should keep a NavigationStack around the tab root."
        )
        XCTAssertTrue(homeSource.contains("homeGlassAccessory"))
        XCTAssertTrue(homeSource.contains("osrsTabSearchWithTrailingControl("))
        XCTAssertTrue(homeSource.contains("osrsGlassIconButton("))
        XCTAssertFalse(
            homeSource.contains("GeometryReader { viewport in") || homeSource.contains("viewport.size"),
            "Home must not feed a system TabView's measured proposal back into its own frame; that forms an iOS 26 accessibility preference cycle."
        )
        XCTAssertGreaterThanOrEqual(
            homeSource.components(separatedBy: ".frame(maxWidth: .infinity, alignment: .leading)").count - 1,
            3,
            "Every Home feed should retain a full available-width content contract without a measured proposal dependency."
        )
        XCTAssertGreaterThanOrEqual(
            homeSource.components(separatedBy: ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)").count - 1,
            3,
            "Every Home root should expand into the NavigationStack viewport without an explicit measured-height dependency."
        )
        let refreshRange = try XCTUnwrap(homeSource.range(of: ".refreshable {"))
        let feedIdentifierRange = try XCTUnwrap(homeSource.range(of: ".accessibilityIdentifier(\"home_feed_scroll\")"))
        XCTAssertLessThan(
            refreshRange.lowerBound,
            feedIdentifierRange.lowerBound,
            "The Home feed identifier should describe the final refresh-enabled viewport rather than an intrinsic pre-refresh ScrollView wrapper."
        )
    }

    func testHomeForceRefreshTransformsSingleFetchedFeed() throws {
        let source = try readSource("platforms/ios/osrswiki/ViewModels/NewsViewModel.swift")
        let loadNewsBody = try extractFunctionBody(named: "loadNews", from: source)

        XCTAssertFalse(
            loadNewsBody.contains("fetchLatestNews(forceRefresh: forceRefresh)"),
            "NewsViewModel.loadNews(forceRefresh:) should not ask NewsRepository to fetch the same WikiFeed a second time."
        )
        XCTAssertTrue(
            loadNewsBody.contains("transformFeedToNewsItems(fetchedFeed)"),
            "NewsViewModel.loadNews(forceRefresh:) should derive legacy newsItems from the already fetched feed."
        )
    }

    func testLaneFilesDoNotContainContentLeakingDiagnostics() throws {
        let checkedFiles = [
            "platforms/ios/osrswiki/ViewModels/SearchViewModel.swift",
            "platforms/ios/osrswiki/Repositories/SearchRepository.swift",
            "platforms/ios/osrswiki/ViewModels/NewsViewModel.swift",
            "platforms/ios/osrswiki/Views/Components/SearchResultRowView.swift"
        ]

        for path in checkedFiles {
            let source = try readSource(path)
            XCTAssertFalse(
                source.contains("print(") || source.contains("NSLog("),
                "\(path) should not print search terms, result titles, snippets, or Home refresh diagnostics from production code."
            )
        }
    }

    func testNetworkManagerContentDiagnosticsAreDebugGated() throws {
        let source = try readSource("platforms/ios/osrswiki/Utils/NetworkManager.swift")

        XCTAssertTrue(
            source.contains("private func osrsNetworkDebugLog"),
            "NetworkManager should route URL and response diagnostics through a debug-only helper."
        )
        XCTAssertTrue(
            source.contains("#if DEBUG\n    print(message())\n#endif"),
            "NetworkManager diagnostics should compile out of release-like builds."
        )
        XCTAssertFalse(
            source.contains("print(\"🔍 NetworkManager") || source.contains("print(\"📄 NetworkManager"),
            "NetworkManager should not directly print search URLs or response bodies."
        )
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunctionBody(named functionName: String, from source: String) throws -> String {
        guard let functionRange = source.range(of: "func \(functionName)") else {
            XCTFail("Could not find function \(functionName)")
            return ""
        }

        guard let openingBrace = source[functionRange.lowerBound...].firstIndex(of: "{") else {
            XCTFail("Could not find opening brace for function \(functionName)")
            return ""
        }

        var depth = 0
        var current = openingBrace
        while current < source.endIndex {
            let character = source[current]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...current])
                }
            }
            current = source.index(after: current)
        }

        XCTFail("Could not find closing brace for function \(functionName)")
        return ""
    }
}

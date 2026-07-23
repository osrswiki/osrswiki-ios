//
//  ExpandedDeterministicStateTests.swift
//  osrswikiTests
//
//  Fake-backed and isolated-state coverage for the expanded iOS QA gate.
//

import XCTest
@testable import osrswiki

@MainActor
final class ExpandedDeterministicStateTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDownWithError() throws {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        try super.tearDownWithError()
    }

    func testSavedPagesUsesSeededIsolatedStoreForDestructiveClear() throws {
        let repository = SavedPagesRepository(userDefaults: makeUserDefaultsSuite())
        let page = makeSavedPage(id: "seeded-varrock", title: "Varrock")

        repository.addSavedPage(page)
        XCTAssertEqual(repository.getSavedPages().map(\.title), ["Varrock"])

        repository.clearSavedPages()
        XCTAssertTrue(repository.getSavedPages().isEmpty)
    }

    func testSavedPagesReplacesDuplicateURLInsteadOfDuplicatingRows() throws {
        let repository = SavedPagesRepository(userDefaults: makeUserDefaultsSuite())
        let first = makeSavedPage(id: "first", title: "Varrock")
        let replacement = makeSavedPage(id: "replacement", title: "Varrock updated")

        repository.addSavedPage(first)
        repository.addSavedPage(replacement)

        let savedPages = repository.getSavedPages()
        XCTAssertEqual(savedPages.count, 1)
        XCTAssertEqual(savedPages.first?.id, "replacement")
        XCTAssertEqual(savedPages.first?.title, "Varrock updated")
    }

    func testHistoryUsesSeededIsolatedStoreForDestructiveClear() throws {
        let repository = HistoryRepository(userDefaults: makeUserDefaultsSuite())
        repository.addToHistory(makeHistoryItem(id: "varrock", title: "Varrock"))
        repository.addToHistory(makeHistoryItem(id: "lumbridge", title: "Lumbridge"))

        XCTAssertEqual(repository.getHistory().count, 2)

        repository.clearHistory()
        XCTAssertTrue(repository.getHistory().isEmpty)
    }

    func testHistoryDeduplicatesByURLAndKeepsLatestVisitFirst() throws {
        let repository = HistoryRepository(userDefaults: makeUserDefaultsSuite())
        let oldVisit = makeHistoryItem(
            id: "old",
            title: "Varrock",
            visitedDate: Date(timeIntervalSince1970: 1_000)
        )
        let newVisit = makeHistoryItem(
            id: "new",
            title: "Varrock",
            visitedDate: Date(timeIntervalSince1970: 2_000)
        )

        repository.addToHistory(oldVisit)
        repository.addToHistory(newVisit)

        let history = repository.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, "new")
    }

    func testSpeechFakeFinalResultAndNoMatchStates() throws {
        let manager = osrsSpeechRecognitionManager()
        var finalResult: String?
        var partialResult: String?
        var errors: [String] = []
        var states: [osrsSpeechRecognitionManager.SpeechState] = []

        manager.configure(
            onResult: { finalResult = $0 },
            onPartialResult: { partialResult = $0 },
            onError: { errors.append($0) },
            onStateChanged: { states.append($0) }
        )

        manager.simulateRecognitionEventForTests(.partialResult("Var"))
        manager.simulateRecognitionEventForTests(.finalResult("Varrock"))
        manager.simulateRecognitionEventForTests(.noMatch)

        XCTAssertEqual(partialResult, "Var")
        XCTAssertEqual(finalResult, "Varrock")
        XCTAssertEqual(manager.currentState, .error)
        XCTAssertEqual(manager.errorMessage, "No speech detected. Please speak clearly and try again.")
        XCTAssertTrue(states.contains(.listening))
        XCTAssertTrue(states.contains(.processing))
        XCTAssertEqual(errors.last, "No speech detected. Please speak clearly and try again.")
    }

    func testSpeechFakeDeniedAndUnavailableStates() throws {
        let manager = osrsSpeechRecognitionManager()
        var errors: [String] = []
        manager.configure(onResult: { _ in }, onError: { errors.append($0) })

        manager.simulateRecognitionEventForTests(.denied)
        XCTAssertEqual(manager.currentState, .error)
        XCTAssertTrue(errors.last?.contains("requires speech recognition permission") == true)

        manager.simulateRecognitionEventForTests(.unavailable)
        XCTAssertEqual(manager.currentState, .error)
        XCTAssertEqual(errors.last, "Speech recognition is currently not available. Please try again later.")
    }

    func testDonationStateReducerCoversProductAndPurchaseOutcomes() throws {
        let product = osrsDonationProduct(id: "tip-1", displayName: "$1", amount: Decimal(1))

        XCTAssertEqual(
            osrsDonationStateReducer.reduceProductLoad(.loaded([product])),
            .productsAvailable([product])
        )
        XCTAssertEqual(
            osrsDonationStateReducer.reduceProductLoad(.loaded([])),
            .productsUnavailable("No donation products are currently available.")
        )
        XCTAssertEqual(
            osrsDonationStateReducer.reduceProductLoad(.unavailable("StoreKit unavailable")),
            .productsUnavailable("StoreKit unavailable")
        )
        XCTAssertEqual(osrsDonationStateReducer.beginPurchase(product: product), .purchasing(product))
        XCTAssertEqual(osrsDonationStateReducer.reducePurchase(.cancelled), .cancelled)
        XCTAssertEqual(osrsDonationStateReducer.reducePurchase(.pending), .pending)
        XCTAssertEqual(osrsDonationStateReducer.reducePurchase(.success), .succeeded)
        XCTAssertEqual(osrsDonationStateReducer.reducePurchase(.failed("declined")), .failed("declined"))
    }

    func testMapViewModelZoomControlsStayWithinBounds() throws {
        let viewModel = MapViewModel()

        for _ in 0..<10 {
            viewModel.zoomIn()
        }
        XCTAssertEqual(viewModel.zoomLevel, 5.0)
        XCTAssertEqual(viewModel.mapSize.width, 5_000)

        for _ in 0..<20 {
            viewModel.zoomOut()
        }
        XCTAssertEqual(viewModel.zoomLevel, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.mapSize.height, 500, accuracy: 0.0001)

        viewModel.resetZoom()
        XCTAssertEqual(viewModel.zoomLevel, 1.0)
        XCTAssertEqual(viewModel.mapSize, CGSize(width: 1_000, height: 1_000))
    }

    func testArticleViewModelInitialStateIsStableBeforeWebViewLoads() throws {
        let viewModel = ArticleViewModel(
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            pageTitle: "Varrock",
            snippet: "City article",
            thumbnailUrl: URL(string: "https://oldschool.runescape.wiki/images/Varrock.png")
        )

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.loadingProgress, 0)
        XCTAssertEqual(viewModel.pageTitle_, "Varrock")
        XCTAssertEqual(viewModel.snippet_, "City article")
        XCTAssertEqual(viewModel.saveState, .notSaved)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeUserDefaultsSuite() -> UserDefaults {
        let suiteName = "osrswiki-tests-\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func makeSavedPage(id: String, title: String) -> SavedPage {
        SavedPage(
            id: id,
            title: title,
            description: "Seeded page",
            url: URL(string: "https://oldschool.runescape.wiki/w/Varrock")!,
            thumbnailUrl: nil,
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: false,
            offlineDownloadDate: nil,
            offlineStatus: .notDownloaded,
            offlineFileSize: nil,
            offlineLocalPath: nil
        )
    }

    private func makeHistoryItem(
        id: String,
        title: String,
        visitedDate: Date = Date(timeIntervalSince1970: 1_735_732_800)
    ) -> HistoryItem {
        HistoryItem(
            id: id,
            pageTitle: title,
            pageUrl: URL(string: "https://oldschool.runescape.wiki/w/\(title)")!,
            visitedDate: visitedDate,
            thumbnailUrl: nil,
            description: "Seeded history item"
        )
    }
}

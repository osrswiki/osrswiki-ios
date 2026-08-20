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

    func testSavedRepositoryMutationSignalPostsAfterUnlockAndOnlyForRealTerminalChanges() throws {
        let repository = SavedPagesRepository(userDefaults: makeUserDefaultsSuite())
        let notificationExpectation = expectation(description: "real Saved mutations")
        notificationExpectation.expectedFulfillmentCount = 3
        notificationExpectation.assertForOverFulfill = true
        let probe = SavedRepositoryNotificationProbe(
            repository: repository,
            expectation: notificationExpectation
        )
        let observer = NotificationCenter.default.addObserver(
            forName: .osrsSavedPagesRepositoryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            probe.recordSynchronousMutation()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let generation = "saved-notification-generation"
        let downloading = SavedPage(
            id: "saved-notification",
            title: "Saved notification",
            description: "Already enriched",
            url: URL(string: "https://oldschool.runescape.wiki/w/Saved_notification")!,
            thumbnailUrl: URL(string: "https://oldschool.runescape.wiki/images/saved.png"),
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: false,
            offlineDownloadDate: nil,
            offlineStatus: .downloading,
            offlineFileSize: 512,
            offlineLocalPath: "saved-old-snapshot",
            durableSettlementVersion: nil,
            pendingSettlementGeneration: generation
        )
        repository.addSavedPage(downloading)

        XCTAssertFalse(repository.compareAndSwapOfflineSettlement(
            downloading.markingCurrentDurableSettlementAvailable(
                at: Date(),
                offlineLocalPath: "must-not-publish",
                offlineFileSize: 1_024
            ),
            expectedGeneration: "wrong-generation",
            expectedPriorCachePageId: downloading.offlineLocalPath
        ))
        XCTAssertNotNil(repository.updateSavedPageMetadata(
            id: downloading.id,
            description: downloading.description,
            thumbnailUrl: downloading.thumbnailUrl
        ), "No-op metadata still returns the latest record")

        let published = downloading.markingCurrentDurableSettlementAvailable(
            at: Date(),
            offlineLocalPath: "saved-new-snapshot",
            offlineFileSize: 2_048
        )
        XCTAssertTrue(repository.compareAndSwapOfflineSettlement(
            published,
            expectedGeneration: generation,
            expectedPriorCachePageId: downloading.offlineLocalPath
        ))
        XCTAssertNil(repository.removeSavedPage("missing-id"))
        XCTAssertEqual(repository.removeSavedPage(downloading.id)?.offlineLocalPath, "saved-new-snapshot")

        wait(for: [notificationExpectation], timeout: 2)
        XCTAssertEqual(probe.snapshotCounts, [1, 1, 0])
    }

    func testUnversionedAvailableSaveMigratesOnceToRetryableWithoutLosingNamespace() throws {
        let defaults = makeUserDefaultsSuite()
        let legacyAvailable = SavedPage(
            id: "legacy-available",
            title: "Legacy available",
            description: "Preserved metadata",
            url: URL(string: "https://oldschool.runescape.wiki/w/Legacy_available")!,
            thumbnailUrl: URL(string: "https://oldschool.runescape.wiki/images/legacy.png"),
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: true,
            offlineDownloadDate: Date(timeIntervalSince1970: 1_735_732_900),
            offlineStatus: .available,
            offlineFileSize: 4_096,
            offlineLocalPath: "legacy-available"
        )
        let encoded = try JSONEncoder().encode([legacyAvailable])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        object[0].removeValue(forKey: "durableSettlementVersion")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "saved_pages")
        let repository = SavedPagesRepository(userDefaults: defaults)

        let migrated = try XCTUnwrap(repository.getSavedPages().first)
        XCTAssertEqual(migrated.offlineStatus, .outdated)
        XCTAssertFalse(migrated.isOfflineAvailable)
        XCTAssertEqual(migrated.offlineLocalPath, legacyAvailable.offlineLocalPath)
        XCTAssertEqual(migrated.offlineDownloadDate, legacyAvailable.offlineDownloadDate)
        XCTAssertEqual(migrated.offlineFileSize, legacyAvailable.offlineFileSize)
        XCTAssertEqual(migrated.description, legacyAvailable.description)
        XCTAssertEqual(migrated.thumbnailUrl, legacyAvailable.thumbnailUrl)
        XCTAssertNil(migrated.durableSettlementVersion)
        XCTAssertTrue(migrated.canAttemptOfflineCacheRead)
        XCTAssertEqual(migrated.viewingURL.scheme, "app-assets")
        let onceMigratedData = defaults.data(forKey: "saved_pages")

        let relaunched = try XCTUnwrap(repository.getSavedPages().first)
        XCTAssertEqual(relaunched.offlineStatus, .outdated)
        XCTAssertEqual(defaults.data(forKey: "saved_pages"), onceMigratedData, "Migration must be idempotent on relaunch")
    }

    func testPreOfflineSchemaBookmarkMigratesVisibleAndRetryableWithoutClaimingDurability() async throws {
        let defaults = makeUserDefaultsSuite()
        let originalURL = try XCTUnwrap(URL(
            string: "https://oldschool.runescape.wiki/w/Legacy%3FQuestion%23Variant?redirect=A%23B"
        ))
        let thumbnailURL = try XCTUnwrap(URL(
            string: "https://oldschool.runescape.wiki/images/Legacy%20bookmark.png"
        ))
        let savedDate = Date(timeIntervalSince1970: 1_681_516_800)
        let legacy = LegacySavedPageFixture(
            id: "legacy-bookmark-id",
            title: "Legacy &amp; Bookmark",
            description: "Preserved legacy description",
            url: originalURL,
            thumbnailUrl: thumbnailURL,
            savedDate: savedDate,
            isOfflineAvailable: false
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "saved_pages")
        let repository = SavedPagesRepository(userDefaults: defaults)

        let migrated = try XCTUnwrap(repository.getSavedPages().first)
        XCTAssertEqual(migrated.id, legacy.id)
        XCTAssertEqual(migrated.title, legacy.title)
        XCTAssertEqual(migrated.description, legacy.description)
        XCTAssertEqual(migrated.url.absoluteString, originalURL.absoluteString)
        XCTAssertEqual(migrated.thumbnailUrl, thumbnailURL)
        XCTAssertEqual(migrated.savedDate, savedDate)
        XCTAssertEqual(migrated.offlineStatus, .outdated)
        XCTAssertEqual(migrated.offlineLocalPath, legacy.id)
        XCTAssertEqual(migrated.savedLibraryStatusLabel, "RETRY")
        XCTAssertFalse(migrated.isAvailableOffline)
        XCTAssertFalse(migrated.hasCurrentDurableSettlement)

        let viewModel = SavedPagesViewModel(savedPagesRepository: repository)
        await viewModel.loadSavedPages()
        XCTAssertEqual(viewModel.savedPages.map(\.id), [legacy.id])
        XCTAssertEqual(viewModel.filteredSavedPages(searchText: "legacy").map(\.id), [legacy.id])
        XCTAssertTrue(
            SavedPagesViewModel.exportReadingListText(from: repository.getSavedPages())
                .contains(originalURL.absoluteString),
            "The centralized visible-library contract must retain migrated bookmarks in export"
        )
        XCTAssertEqual(
            ArticleView.savedCacheRoutingMode(hasPersistedMainResponse: false, isOffline: false),
            .saveWhileServing,
            "A legacy identity without a persisted main response must remain an online/retryable bookmark"
        )
        XCTAssertEqual(
            ArticleView.savedCacheRoutingMode(hasPersistedMainResponse: false, isOffline: true),
            .cacheOnly,
            "The explicit forced-offline policy must never escape to origin for an uncached legacy bookmark"
        )
        XCTAssertEqual(
            ArticleView.savedCacheRoutingMode(hasPersistedMainResponse: true, isOffline: false),
            .cacheOnly,
            "A persisted snapshot must render immediately even while online; origin refresh is a background policy"
        )

        let firstMigrationData = try XCTUnwrap(defaults.data(forKey: "saved_pages"))
        let relaunched = try XCTUnwrap(repository.getSavedPages().first)
        XCTAssertEqual(relaunched.id, legacy.id)
        XCTAssertEqual(relaunched.offlineStatus, .outdated)
        XCTAssertEqual(defaults.data(forKey: "saved_pages"), firstMigrationData)
    }

    func testOutdatedSavedPageModernNavigationPreservesIdentityAndUsesPersistedCacheProbe() throws {
        let legacyAvailable = SavedPage(
            id: "legacy-readable",
            title: "Legacy readable",
            description: nil,
            url: URL(string: "https://oldschool.runescape.wiki/w/Legacy_readable")!,
            thumbnailUrl: nil,
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: true,
            offlineDownloadDate: Date(timeIntervalSince1970: 1_735_732_900),
            offlineStatus: .available,
            offlineFileSize: 1_024,
            offlineLocalPath: "legacy-readable-cache-v0"
        )
        let outdated = legacyAvailable.requiringDurableSettlementRefresh()
        let appState = AppState()
        appState.selectedTab = .saved

        SavedPagesViewModel().navigateToPage(outdated, appState: appState)

        guard case .article(let destination) = appState.savedNavigationStack.last else {
            return XCTFail("Modern Saved navigation must create an article destination")
        }
        XCTAssertEqual(destination.url, outdated.url)
        XCTAssertEqual(
            destination.savedPageId,
            outdated.offlineLocalPath,
            "The preserved cache namespace, not repository identity, must reach ArticleView"
        )
        XCTAssertEqual(
            ArticleView.savedCacheRoutingMode(hasPersistedMainResponse: true, isOffline: true),
            .cacheOnly,
            "An outdated record with a persisted main response remains best-effort readable offline"
        )
        XCTAssertEqual(
            ArticleView.savedCacheRoutingMode(hasPersistedMainResponse: true, isOffline: false),
            .cacheOnly,
            "Online viewing must still render the persisted snapshot immediately"
        )
        XCTAssertFalse(outdated.isAvailableOffline, "Readability must not falsely restore the durable Saved state")
    }

    func testSavedRepositoryRefreshesAfterArticlePopAtRootOrSearchButNotArticlePush() throws {
        let first = ArticleDestination(
            title: "First",
            url: URL(string: "https://oldschool.runescape.wiki/w/First")!
        )
        let second = ArticleDestination(
            title: "Second",
            url: URL(string: "https://oldschool.runescape.wiki/w/Second")!
        )

        XCTAssertTrue(SavedPagesView.shouldRefreshRepository(
            after: [.article(first)],
            before: []
        ))
        XCTAssertTrue(SavedPagesView.shouldRefreshRepository(
            after: [.search, .article(first)],
            before: [.search]
        ))
        XCTAssertFalse(SavedPagesView.shouldRefreshRepository(
            after: [.article(first)],
            before: [.article(first), .article(second)]
        ))
        XCTAssertFalse(SavedPagesView.shouldRefreshRepository(
            after: [.search],
            before: []
        ))
    }

    func testCurrentSettlementAndNonAvailableStatesAreNotMigrated() throws {
        let defaults = makeUserDefaultsSuite()
        let base = makeSavedPage(id: "base", title: "Base")
        let current = SavedPage(
            id: "current",
            title: "Current",
            description: nil,
            url: URL(string: "https://oldschool.runescape.wiki/w/Current")!,
            thumbnailUrl: nil,
            savedDate: base.savedDate,
            isOfflineAvailable: true,
            offlineDownloadDate: base.savedDate,
            offlineStatus: .available,
            offlineFileSize: 512,
            offlineLocalPath: "current",
            durableSettlementVersion: SavedPage.currentDurableSettlementVersion
        )
        let retryStates: [SavedPage.OfflineStatus] = [.notDownloaded, .downloading, .failed, .outdated]
        let pages = [current] + retryStates.enumerated().map { index, status in
            SavedPage(
                id: "retry-\(index)",
                title: status.rawValue,
                description: nil,
                url: URL(string: "https://oldschool.runescape.wiki/w/Retry_\(index)")!,
                thumbnailUrl: nil,
                savedDate: base.savedDate,
                isOfflineAvailable: false,
                offlineDownloadDate: nil,
                offlineStatus: status,
                offlineFileSize: nil,
                offlineLocalPath: status == .outdated ? "retry-\(index)" : nil
            )
        }
        defaults.set(try JSONEncoder().encode(pages), forKey: "saved_pages")

        let loaded = SavedPagesRepository(userDefaults: defaults).getSavedPages()
        XCTAssertEqual(loaded.first?.offlineStatus, .available)
        XCTAssertTrue(loaded.first?.hasCurrentDurableSettlement == true)
        XCTAssertEqual(Array(loaded.dropFirst()).map(\.offlineStatus), retryStates)
    }

    func testSavedLibraryHidesFirstTimePartialRecordsAndKeepsReadableRetriesTruthful() async throws {
        let repository = SavedPagesRepository(userDefaults: makeUserDefaultsSuite())
        let date = Date(timeIntervalSince1970: 1_735_732_800)
        let thumbnail = URL(string: "https://oldschool.runescape.wiki/images/library.png")!

        func page(
            id: String,
            status: SavedPage.OfflineStatus,
            priorPointer: String?,
            current: Bool = false
        ) -> SavedPage {
            SavedPage(
                id: id,
                title: id,
                description: "Description for \(id)",
                url: URL(string: "https://oldschool.runescape.wiki/w/\(id)")!,
                thumbnailUrl: thumbnail,
                savedDate: date,
                isOfflineAvailable: current,
                offlineDownloadDate: current ? date : nil,
                offlineStatus: status,
                offlineFileSize: priorPointer == nil ? nil : 2_048,
                offlineLocalPath: priorPointer,
                durableSettlementVersion: current ? SavedPage.currentDurableSettlementVersion : nil,
                pendingSettlementGeneration: status == .downloading ? "generation-\(id)" : nil
            )
        }

        let hiddenDownloading = page(id: "hidden-downloading", status: .downloading, priorPointer: nil)
        let hiddenFailed = page(id: "hidden-failed", status: .failed, priorPointer: nil)
        let updating = page(id: "visible-updating", status: .downloading, priorPointer: "snapshot-updating")
        let failedRetry = page(id: "visible-failed", status: .failed, priorPointer: "snapshot-failed")
        let outdatedRetry = page(id: "visible-outdated", status: .outdated, priorPointer: "snapshot-outdated")
        let settled = page(id: "visible-settled", status: .available, priorPointer: "snapshot-current", current: true)
        [hiddenDownloading, hiddenFailed, updating, failedRetry, outdatedRetry, settled]
            .forEach(repository.addSavedPage)

        let viewModel = SavedPagesViewModel(savedPagesRepository: repository)
        await viewModel.loadSavedPages()

        XCTAssertEqual(
            Set(viewModel.savedPages.map(\.id)),
            Set([updating.id, failedRetry.id, outdatedRetry.id, settled.id])
        )
        XCTAssertTrue(viewModel.filteredSavedPages(searchText: "hidden").isEmpty)
        XCTAssertEqual(updating.savedLibraryStatusLabel, "UPDATING")
        XCTAssertEqual(failedRetry.savedLibraryStatusLabel, "RETRY")
        XCTAssertEqual(outdatedRetry.savedLibraryStatusLabel, "RETRY")
        XCTAssertEqual(settled.savedLibraryStatusLabel, "SAVED")

        let export = SavedPagesViewModel.exportReadingListText(
            from: [hiddenDownloading, hiddenFailed, updating, failedRetry, outdatedRetry, settled]
        )
        XCTAssertFalse(export.contains(hiddenDownloading.title))
        XCTAssertFalse(export.contains(hiddenFailed.title))
        XCTAssertTrue(export.contains(updating.title))
        XCTAssertTrue(export.contains(failedRetry.title))
        XCTAssertTrue(export.contains(outdatedRetry.title))
        XCTAssertTrue(export.contains(settled.title))
    }

    func testMetadataAndReorderUseLatestPublishedSnapshotWhileStaleSettlementCASIsRejected() throws {
        let repository = SavedPagesRepository(userDefaults: makeUserDefaultsSuite())
        let generationA = "settlement-a"
        let inFlightA = SavedPage(
            id: "cas-page",
            title: "CAS page",
            description: nil,
            url: URL(string: "https://oldschool.runescape.wiki/w/CAS_page")!,
            thumbnailUrl: nil,
            savedDate: Date(timeIntervalSince1970: 1_735_732_800),
            isOfflineAvailable: false,
            offlineDownloadDate: nil,
            offlineStatus: .downloading,
            offlineFileSize: nil,
            offlineLocalPath: "cas-old",
            pendingSettlementGeneration: generationA
        )
        let other = makeSavedPage(id: "other-page", title: "Other")
        repository.addSavedPage(other)
        repository.addSavedPage(inFlightA)

        let publishedA = inFlightA.markingCurrentDurableSettlementAvailable(
            at: Date(timeIntervalSince1970: 1_735_733_000),
            offlineLocalPath: "cas-snapshot-a"
        )
        XCTAssertTrue(repository.compareAndSwapOfflineSettlement(
            publishedA,
            expectedGeneration: generationA,
            expectedPriorCachePageId: inFlightA.offlineLocalPath
        ))

        let thumbnail = URL(string: "https://oldschool.runescape.wiki/images/cas.png")!
        let enriched = try XCTUnwrap(repository.updateSavedPageMetadata(
            id: inFlightA.id,
            description: "Late network metadata",
            thumbnailUrl: thumbnail
        ))
        XCTAssertEqual(enriched.offlineCachePageId, "cas-snapshot-a")
        XCTAssertTrue(enriched.hasCurrentDurableSettlement)
        XCTAssertEqual(enriched.description, "Late network metadata")

        repository.updateOrder(pageIDs: [other.id, inFlightA.id])
        let reordered = repository.getSavedPages()
        XCTAssertEqual(reordered.map(\.id), [other.id, inFlightA.id])
        let afterReorder = try XCTUnwrap(reordered.last)
        XCTAssertEqual(afterReorder.offlineCachePageId, "cas-snapshot-a")
        XCTAssertTrue(afterReorder.hasCurrentDurableSettlement)
        XCTAssertEqual(afterReorder.thumbnailUrl, thumbnail)

        let generationB = "settlement-b"
        let inFlightB = SavedPage(
            id: inFlightA.id,
            title: inFlightA.title,
            description: afterReorder.description,
            url: inFlightA.url,
            thumbnailUrl: thumbnail,
            savedDate: inFlightA.savedDate,
            isOfflineAvailable: false,
            offlineDownloadDate: afterReorder.offlineDownloadDate,
            offlineStatus: .downloading,
            offlineFileSize: afterReorder.offlineFileSize,
            offlineLocalPath: afterReorder.offlineLocalPath,
            pendingSettlementGeneration: generationB
        )
        XCTAssertTrue(repository.updateSavedPage(inFlightB))
        XCTAssertFalse(repository.compareAndSwapOfflineSettlement(
            publishedA,
            expectedGeneration: generationA,
            expectedPriorCachePageId: inFlightA.offlineLocalPath
        ))
        let retainedB = try XCTUnwrap(repository.getSavedPages().first { $0.id == inFlightA.id })
        XCTAssertEqual(retainedB.pendingSettlementGeneration, generationB)
        XCTAssertEqual(retainedB.offlineStatus, .downloading)

        repository.clearSavedPages()
        let publishedB = inFlightB.markingCurrentDurableSettlementAvailable(
            at: Date(),
            offlineLocalPath: "cas-snapshot-b"
        )
        XCTAssertFalse(repository.compareAndSwapOfflineSettlement(
            publishedB,
            expectedGeneration: generationB,
            expectedPriorCachePageId: inFlightB.offlineLocalPath
        ))
        XCTAssertTrue(repository.getSavedPages().isEmpty, "Clear-all must tombstone every in-flight publication")
    }

    func testRemovalAndClearReturnLatestPublishedNamespacesInsteadOfStaleViewPointers() throws {
        let repository = SavedPagesRepository(userDefaults: makeUserDefaultsSuite())
        func inFlight(id: String, generation: String) -> SavedPage {
            SavedPage(
                id: id,
                title: id,
                description: nil,
                url: URL(string: "https://oldschool.runescape.wiki/w/\(id)")!,
                thumbnailUrl: nil,
                savedDate: Date(),
                isOfflineAvailable: false,
                offlineDownloadDate: nil,
                offlineStatus: .downloading,
                offlineFileSize: nil,
                offlineLocalPath: "\(id)-old",
                pendingSettlementGeneration: generation
            )
        }

        let staleSwipeRow = inFlight(id: "swipe", generation: "swipe-generation")
        repository.addSavedPage(staleSwipeRow)
        let publishedSwipe = staleSwipeRow.markingCurrentDurableSettlementAvailable(
            at: Date(),
            offlineLocalPath: "swipe-new-snapshot"
        )
        XCTAssertTrue(repository.compareAndSwapOfflineSettlement(
            publishedSwipe,
            expectedGeneration: "swipe-generation",
            expectedPriorCachePageId: staleSwipeRow.offlineLocalPath
        ))
        let actuallyRemoved = try XCTUnwrap(repository.removeSavedPage(staleSwipeRow.id))
        XCTAssertEqual(actuallyRemoved.offlineCachePageId, "swipe-new-snapshot")

        let staleClearRow = inFlight(id: "clear", generation: "clear-generation")
        repository.addSavedPage(staleClearRow)
        let publishedClear = staleClearRow.markingCurrentDurableSettlementAvailable(
            at: Date(),
            offlineLocalPath: "clear-new-snapshot"
        )
        XCTAssertTrue(repository.compareAndSwapOfflineSettlement(
            publishedClear,
            expectedGeneration: "clear-generation",
            expectedPriorCachePageId: staleClearRow.offlineLocalPath
        ))
        repository.addSavedPage(makeSavedPage(id: "clear-other", title: "Other"))

        let cleared = repository.clearSavedPages()
        XCTAssertEqual(
            Set(cleared.map(\.offlineCachePageId)),
            Set(["clear-new-snapshot", "clear-other"])
        )
        XCTAssertTrue(repository.getSavedPages().isEmpty)
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

    func testHistoryRepositoryNormalizesLegacyEntitiesAndPersistsRefreshedMetadata() throws {
        let defaults = makeUserDefaultsSuite()
        let repository = HistoryRepository(userDefaults: defaults)
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Wyrmscraig_%26_Sailing_Changes"))
        repository.addToHistory(
            HistoryItem(
                id: "update-history",
                pageTitle: "Update:Wyrmscraig &amp;amp; Sailing Changes",
                pageUrl: pageURL,
                visitedDate: Date(timeIntervalSince1970: 1_735_732_800),
                thumbnailUrl: nil,
                description: "News &amp;amp; patch notes",
                metadataUpdatedAt: nil
            )
        )

        var stored = try XCTUnwrap(repository.getHistory().first)
        XCTAssertEqual(stored.displayTitle, "Wyrmscraig & Sailing Changes")
        XCTAssertEqual(stored.description, "News & patch notes")
        XCTAssertNil(stored.metadataUpdatedAt)

        let thumbnail = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/Wyrmscraig.png"))
        let refreshedAt = Date(timeIntervalSince1970: 1_735_819_200)
        repository.updateMetadata(
            for: pageURL,
            thumbnailUrl: thumbnail,
            description: "Updated summary",
            updatedAt: refreshedAt
        )

        stored = try XCTUnwrap(repository.getHistory().first)
        XCTAssertEqual(stored.thumbnailUrl, thumbnail)
        XCTAssertEqual(stored.description, "Updated summary")
        XCTAssertEqual(stored.metadataUpdatedAt, refreshedAt)
    }

    func testIncompleteHistoryMetadataRefreshRemainsEligibleForRetry() throws {
        let defaults = makeUserDefaultsSuite()
        let repository = HistoryRepository(userDefaults: defaults)
        let pageURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:Wyrmscraig_%26_Sailing_Changes"))
        repository.addToHistory(
            HistoryItem(
                id: "incomplete-update-history",
                pageTitle: "Update:Wyrmscraig &amp; Sailing Changes",
                pageUrl: pageURL,
                visitedDate: Date(timeIntervalSince1970: 1_735_732_800),
                thumbnailUrl: nil,
                description: nil
            )
        )

        repository.updateMetadata(
            for: pageURL,
            thumbnailUrl: nil,
            description: "Partial summary only",
            updatedAt: Date(timeIntervalSince1970: 1_735_819_200)
        )

        let stored = try XCTUnwrap(repository.getHistory().first)
        XCTAssertEqual(stored.description, "Partial summary only")
        XCTAssertNil(stored.thumbnailUrl)
        XCTAssertNil(stored.metadataUpdatedAt, "Partial enrichment must retry instead of appearing fresh for seven days.")
    }

    func testWyrmscraigHistoryMetadataCanRecoverFromCachedHomeUpdate() throws {
        let articleURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Update:Wyrmscraig_%26_Sailing_Changes"))
        let thumbnailURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/thumb/Wyrmscraig.png/320px-Wyrmscraig.png"))
        let item = HistoryItem(
            id: "wyrmscraig-history",
            pageTitle: "Update:Wyrmscraig &amp;amp; Sailing Changes",
            pageUrl: articleURL,
            visitedDate: Date(timeIntervalSince1970: 1_735_732_800),
            thumbnailUrl: nil,
            description: nil
        )
        let feed = WikiFeed(
            recentUpdates: [
                UpdateItem(
                    title: "Wyrmscraig & Sailing Changes",
                    snippet: "Wyrmscraig update notes",
                    imageUrl: thumbnailURL.absoluteString,
                    articleUrl: articleURL.absoluteString
                )
            ],
            announcements: [],
            onThisDay: nil,
            popularPages: []
        )

        let metadata = try XCTUnwrap(osrsHistoryUpdateMetadataResolver.cachedMetadata(for: item, in: feed))
        XCTAssertEqual(metadata.thumbnailUrl, thumbnailURL)
        XCTAssertEqual(metadata.description, "Wyrmscraig update notes")
    }

    func testWyrmscraigSavedMetadataCanRecoverFromCachedHomeUpdate() throws {
        let thumbnailURL = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/images/thumb/Wyrmscraig.png/320px-Wyrmscraig.png"))
        let feed = WikiFeed(
            recentUpdates: [
                UpdateItem(
                    title: "Wyrmscraig & Sailing Changes",
                    snippet: "Wyrmscraig update notes",
                    imageUrl: thumbnailURL.absoluteString,
                    articleUrl: "https://oldschool.runescape.wiki/w/Update:Wyrmscraig_%26_Sailing_Changes"
                )
            ],
            announcements: [],
            onThisDay: nil,
            popularPages: []
        )

        let metadata = try XCTUnwrap(
            osrsHistoryUpdateMetadataResolver.cachedMetadata(
                forTitle: "Update:Wyrmscraig &amp;amp; Sailing Changes",
                in: feed
            )
        )
        XCTAssertEqual(metadata.thumbnailUrl, thumbnailURL)
        XCTAssertEqual(metadata.description, "Wyrmscraig update notes")
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

private struct LegacySavedPageFixture: Codable {
    let id: String
    let title: String
    let description: String?
    let url: URL
    let thumbnailUrl: URL?
    let savedDate: Date
    let isOfflineAvailable: Bool
}

private final class SavedRepositoryNotificationProbe: @unchecked Sendable {
    let repository: SavedPagesRepository
    let expectation: XCTestExpectation
    private let lock = NSLock()
    private var snapshotCountsStorage: [Int] = []

    init(repository: SavedPagesRepository, expectation: XCTestExpectation) {
        self.repository = repository
        self.expectation = expectation
    }

    var snapshotCounts: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return snapshotCountsStorage
    }

    func recordSynchronousMutation() {
        // Re-entering the repository synchronously proves notifications are posted only after
        // the global storage lock is released.
        let count = repository.getSavedPages().count
        lock.lock()
        snapshotCountsStorage.append(count)
        lock.unlock()
        expectation.fulfill()
    }
}

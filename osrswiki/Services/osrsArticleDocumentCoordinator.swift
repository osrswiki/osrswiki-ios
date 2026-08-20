//
//  osrsArticleDocumentCoordinator.swift
//  OSRS Wiki
//
//  Bounded article preparation shared by visible-row prewarming and foreground opens.
//

import Foundation
import SwiftUI
import UIKit

enum osrsWikiParseRequest {
    static let endpoint = "https://oldschool.runescape.wiki/api.php"

    static func queryItems(page: String? = nil, pageId: Int? = nil) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "prop", value: "text|displaytitle|revid"),
            URLQueryItem(name: "disablelimitreport", value: "1"),
            URLQueryItem(name: "disableeditsection", value: "1"),
            URLQueryItem(name: "wrapoutputclass", value: "mw-parser-output"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "maxage", value: "300"),
            URLQueryItem(name: "smaxage", value: "300")
        ]
        if let page, !page.isEmpty {
            items.append(URLQueryItem(name: "page", value: page))
        } else if let pageId {
            items.append(URLQueryItem(name: "pageid", value: String(pageId)))
        }
        return items
    }

    static func url(page: String? = nil, pageId: Int? = nil) -> URL? {
        var components = URLComponents(string: endpoint)
        components?.queryItems = queryItems(page: page, pageId: pageId)
        return components?.url
    }
}

struct osrsArticleDocumentIdentity: Hashable, Sendable, CustomStringConvertible {
    let value: String

    init(pageURL: URL, pageTitle: String?) {
        if let articleTitle = Self.articleTitle(from: pageURL) {
            value = "wiki-title:\(Self.normalized(articleTitle))"
            return
        }

        let normalizedTitle = pageTitle.map(Self.normalized) ?? ""
        if !normalizedTitle.isEmpty {
            // A caller-provided title and the same title encoded in a MediaWiki URL are
            // two representations of one article. Keep one identity namespace so a
            // fallback-title request can join/cache-hit the canonical URL request.
            value = "wiki-title:\(normalizedTitle)"
            return
        }

        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if let scheme = components?.scheme { components?.scheme = scheme.lowercased() }
        if let host = components?.host { components?.host = host.lowercased() }
        value = "url:\((components?.url ?? pageURL).absoluteString)"
    }

    var description: String { value }

    static func requestedTitle(pageURL: URL, fallbackTitle: String?) -> String {
        if let articleTitle = articleTitle(from: pageURL) {
            return articleTitle.replacingOccurrences(of: "_", with: " ")
        }

        let fallback = fallbackTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        return fallback?.isEmpty == false ? fallback! : pageURL.lastPathComponent.replacingOccurrences(of: "_", with: " ")
    }

    private static func articleTitle(from url: URL) -> String? {
        let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        if let range = encodedPath.range(of: "/w/", options: [.caseInsensitive]) {
            let encodedTitle = String(encodedPath[range.upperBound...])
            if !encodedTitle.isEmpty {
                return encodedTitle.removingPercentEncoding ?? encodedTitle
            }
        }

        let queryTitle = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("title") == .orderedSame })?
            .value
        return queryTitle?.isEmpty == false ? queryTitle : nil
    }

    private static func normalized(_ title: String) -> String {
        let canonicalUnicode = title.precomposedStringWithCanonicalMapping
        return canonicalUnicode
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

struct osrsArticleDocumentRequest: Hashable, Sendable {
    let pageURL: URL
    let requestedTitle: String
    let identity: osrsArticleDocumentIdentity

    init(pageURL: URL, pageTitle: String?) {
        self.pageURL = pageURL
        requestedTitle = osrsArticleDocumentIdentity.requestedTitle(pageURL: pageURL, fallbackTitle: pageTitle)
        identity = osrsArticleDocumentIdentity(pageURL: pageURL, pageTitle: pageTitle)
    }

    var parseRequestURL: URL? {
        osrsWikiParseRequest.url(page: requestedTitle)
    }
}

struct osrsArticleRenderOptions: Hashable, Sendable {
    let usesDarkTheme: Bool
    let collapseTablesEnabled: Bool
    let wrapTableCellsEnabled: Bool
    let articleTextScale: Double
    let floorNumberingBodyClass: String

    init(
        usesDarkTheme: Bool,
        collapseTablesEnabled: Bool,
        wrapTableCellsEnabled: Bool = false,
        articleTextScale: Double,
        floorNumberingBodyClass: String = osrsArticleFloorConvention.current().bodyClass
    ) {
        self.usesDarkTheme = usesDarkTheme
        self.collapseTablesEnabled = collapseTablesEnabled
        self.wrapTableCellsEnabled = wrapTableCellsEnabled
        self.articleTextScale = min(max(articleTextScale, 0.85), 1.40)
        self.floorNumberingBodyClass = floorNumberingBodyClass
    }
}

struct osrsPreparedArticlePayload: Sendable {
    let payload: osrsArticleParsePayload
    let normalizedHTML: String
}

struct osrsPreparedArticleDocument: Sendable {
    let request: osrsArticleDocumentRequest
    let payload: osrsArticleParsePayload
    let html: String
}

enum osrsArticlePreparationPurpose: String, Sendable {
    case foreground
    case prewarm
}

enum osrsArticleTimingPhase: String, Sendable {
    case lookup
    case fetch
    case decode
    case normalize
    case build
    case webKitReady = "webkit-ready"
    case cacheHit = "cache-hit"
    case promotion
    case cancellation
    case suppressed
}

struct osrsArticleTimingEvent: Sendable {
    let phase: osrsArticleTimingPhase
    let identity: osrsArticleDocumentIdentity
    let elapsedMilliseconds: Double
    let detail: String
}

struct osrsArticlePrewarmConditions: Equatable, Sendable {
    let hasNetworkConnection: Bool
    let isConstrained: Bool
    let isLowPowerModeEnabled: Bool
    let thermalState: ProcessInfo.ThermalState
    let isApplicationActive: Bool
    let isOfflineContentAvailable: Bool

    var maximumConcurrentPrewarms: Int {
        if ProcessInfo.processInfo.arguments.contains("-disableArticlePrewarm") {
            return 0
        }
        if UserDefaults.standard.bool(forKey: "osrs_disable_article_prewarm") {
            return 0
        }
        guard hasNetworkConnection,
              !isLowPowerModeEnabled,
              isApplicationActive,
              !isOfflineContentAvailable else {
            return 0
        }
        switch thermalState {
        case .serious, .critical:
            return 0
        case .nominal, .fair:
            return isConstrained ? 1 : 2
        @unknown default:
            return 0
        }
    }

    @MainActor
    static func current(isOfflineContentAvailable: Bool) -> osrsArticlePrewarmConditions {
        osrsArticlePrewarmConditions(
            hasNetworkConnection: NetworkManager.shared.isConnected,
            isConstrained: NetworkManager.shared.isConstrained || NetworkManager.shared.isExpensive,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState,
            isApplicationActive: UIApplication.shared.applicationState == .active,
            isOfflineContentAvailable: isOfflineContentAvailable
        )
    }
}

enum osrsArticlePayloadPreparer {
    static func decode(_ data: Data, requestedTitle: String?) throws -> osrsArticleParsePayload {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidData
        }

        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? String ?? "unknown"
            if code == "missingtitle" {
                throw NetworkError.pageNotFound(requestedTitle)
            }
            throw NetworkError.serverError(404)
        }

        guard let parse = json["parse"] as? [String: Any],
              let title = parse["title"] as? String,
              let pageID = parse["pageid"] as? Int,
              let html = htmlContent(from: parse) else {
            throw NetworkError.invalidData
        }

        return osrsArticleParsePayload(
            pageId: pageID,
            title: title,
            displayTitle: parse["displaytitle"] as? String,
            revisionId: parse["revid"] as? Int,
            htmlContent: html
        )
    }

    private static func htmlContent(from parse: [String: Any]) -> String? {
        if let html = parse["text"] as? String {
            return html
        }
        if let wrapped = parse["text"] as? [String: Any] {
            return wrapped["*"] as? String
        }
        return nil
    }

    static func normalize(_ html: String) -> String {
        var result = html
        for selector in ["advanced-data", "leagues-global-flag", "infobox-padding"] {
            let pattern = "<tr[^>]*?class=[\"'][^\"']*?\(selector)[^\"']*?[\"'][^>]*?>.*?</tr>"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.removeSubrange(range)
            }
        }
        return result
    }
}

actor osrsArticleDocumentCoordinator {
    struct Configuration: Sendable {
        var payloadCapacity: Int = 6
        var documentCapacity: Int = 6
        var timeToLive: TimeInterval = 5 * 60
    }

    typealias Fetcher = @Sendable (URL) async throws -> Data
    typealias Builder = @Sendable (osrsPreparedArticlePayload, osrsArticleRenderOptions) async throws -> String
    typealias Clock = @Sendable () -> Date
    typealias EventSink = @Sendable (osrsArticleTimingEvent) -> Void

    static let shared = osrsArticleDocumentCoordinator(
        configuration: Configuration(),
        clock: { Date() },
        fetcher: { url in
            let (data, _) = try await NetworkManager.shared.performDataRequest(
                url: url,
                retryCount: 2,
                routingPolicy: .configuredNoStore
            )
            return data
        },
        prewarmFetcher: { url in
            let (data, _) = try await NetworkManager.shared.performDataRequest(
                url: url,
                retryCount: 2,
                routingPolicy: .configuredNoStore
            )
            return data
        },
        builder: { payload, options in
            try await osrsArticleDocumentCoordinator.liveBuilder(payload: payload, options: options)
        },
        eventSink: { event in
            osrsArticleDocumentCoordinator.debugEventSink(event)
        }
    )

    private struct CacheEntry<Value> {
        let value: Value
        let expiry: Date
        var access: UInt64
    }

    private struct AliasEntry {
        var canonicalIdentity: osrsArticleDocumentIdentity
        let expiry: Date
        var access: UInt64
    }

    private struct PayloadFlight {
        let id: UUID
        let task: Task<osrsPreparedArticlePayload, Error>
        var consumers: [UUID: osrsArticlePreparationPurpose]
        var hasForegroundConsumer: Bool
    }

    private struct DocumentKey: Hashable {
        let identity: osrsArticleDocumentIdentity
        let renderOptions: osrsArticleRenderOptions
    }

    private struct DocumentFlight {
        let id: UUID
        let task: Task<osrsPreparedArticleDocument, Error>
        var consumers: [UUID: osrsArticlePreparationPurpose]
        var hasForegroundConsumer: Bool
    }

    private struct ActivePrewarm {
        let runID: UUID
        let identity: osrsArticleDocumentIdentity
        let key: DocumentKey
        let task: Task<Void, Never>
    }

    private struct RetiringPrewarm {
        let identity: osrsArticleDocumentIdentity
        let key: DocumentKey
        let task: Task<Void, Never>
    }

    private struct PendingPrewarm {
        let request: osrsArticleDocumentRequest
        let renderOptions: osrsArticleRenderOptions
        var conditions: osrsArticlePrewarmConditions
        let order: UInt64
    }

    private let configuration: Configuration
    private let clock: Clock
    private let fetcher: Fetcher
    private let prewarmFetcher: Fetcher
    private let builder: Builder
    private let eventSink: EventSink
    private var payloadCache: [osrsArticleDocumentIdentity: CacheEntry<osrsPreparedArticlePayload>] = [:]
    private var documentCache: [DocumentKey: CacheEntry<osrsPreparedArticleDocument>] = [:]
    private var payloadFlights: [osrsArticleDocumentIdentity: PayloadFlight] = [:]
    private var documentFlights: [DocumentKey: DocumentFlight] = [:]
    private var activePrewarms: [UUID: ActivePrewarm] = [:]
    /// Cancellation is advisory. Keep canceled wrapper runs here until their shared document task
    /// physically returns so slow/non-cooperative transports continue consuming scheduler space.
    private var retiringPrewarms: [UUID: RetiringPrewarm] = [:]
    private var pendingPrewarms: [UUID: PendingPrewarm] = [:]
    private var pendingPrewarmCounter: UInt64 = 0
    private var schedulerConcurrencyLimit = 2
    private var foregroundCancellationLaneToken: UUID?
    private var foregroundAdmissionWaiters: Set<UUID> = []
    private var schedulerWaitContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var canonicalIdentityByAlias: [osrsArticleDocumentIdentity: AliasEntry] = [:]
    private var accessCounter: UInt64 = 0

    /// Keep enough aliases for two redirect spellings per live cache slot while preserving a
    /// hard upper bound even if a remote page accumulates many historical redirect names.
    private var aliasCapacity: Int {
        max(0, max(configuration.payloadCapacity, configuration.documentCapacity) * 2)
    }

    init(
        configuration: Configuration,
        clock: @escaping Clock,
        fetcher: @escaping Fetcher,
        prewarmFetcher: Fetcher? = nil,
        builder: @escaping Builder,
        eventSink: @escaping EventSink = { _ in }
    ) {
        self.configuration = configuration
        self.clock = clock
        self.fetcher = fetcher
        self.prewarmFetcher = prewarmFetcher ?? fetcher
        self.builder = builder
        self.eventSink = eventSink
    }

    func preparedDocument(
        for request: osrsArticleDocumentRequest,
        renderOptions: osrsArticleRenderOptions,
        purpose: osrsArticlePreparationPurpose = .foreground
    ) async throws -> osrsPreparedArticleDocument {
        let lookupStart = clock()
        let key = DocumentKey(
            identity: resolvedIdentity(for: request.identity),
            renderOptions: renderOptions
        )
        emit(.lookup, request.identity, since: lookupStart, detail: purpose.rawValue)

        if let cached = cachedDocument(for: key) {
            emit(.cacheHit, request.identity, since: lookupStart, detail: "document")
            return cached
        }

        var foregroundLaneToken: UUID?
        if purpose == .foreground, documentFlights[key] == nil {
            foregroundLaneToken = try await acquireForegroundAdmission(excluding: key)
        }
        defer {
            if let foregroundLaneToken {
                releaseForegroundAdmission(foregroundLaneToken)
            }
        }

        let consumerID = UUID()
        let handle = documentFlight(
            for: key,
            request: request,
            renderOptions: renderOptions,
            consumerID: consumerID,
            purpose: purpose
        )

        do {
            let document = try await withTaskCancellationHandler {
                try await handle.task.value
            } onCancel: {
                Task { await self.cancelDocumentConsumer(key: key, consumerID: consumerID) }
            }
            try Task.checkCancellation()
            completeDocumentFlight(key: key, flightID: handle.flightID, document: document)
            return document
        } catch {
            if Task.isCancelled {
                cancelDocumentConsumer(key: key, consumerID: consumerID)
            } else {
                failDocumentFlight(key: key, flightID: handle.flightID)
            }
            throw error
        }
    }

    @discardableResult
    func startPrewarm(
        owner: UUID,
        request: osrsArticleDocumentRequest,
        renderOptions: osrsArticleRenderOptions,
        conditions: osrsArticlePrewarmConditions
    ) -> Bool {
        pendingPrewarms.removeValue(forKey: owner)
        let limit = conditions.maximumConcurrentPrewarms
        schedulerConcurrencyLimit = limit
        if activePrewarms[owner] != nil {
            retirePrewarm(owner: owner)
            signalSchedulerChange()
        }
        let key = DocumentKey(
            identity: resolvedIdentity(for: request.identity),
            renderOptions: renderOptions
        )
        let activeKeys = Set(activePrewarms.values.map(\.key))
        guard limit > 0 else {
            emit(.suppressed, request.identity, elapsedMilliseconds: 0, detail: "limit=\(limit),active-identities=\(activeKeys.count)")
            return false
        }
        let canJoinActiveIdentity = activeKeys.contains(key)
        guard canJoinActiveIdentity || canStartNewSpeculation(limit: limit) else {
            pendingPrewarmCounter &+= 1
            pendingPrewarms[owner] = PendingPrewarm(
                request: request,
                renderOptions: renderOptions,
                conditions: conditions,
                order: pendingPrewarmCounter
            )
            emit(.suppressed, request.identity, elapsedMilliseconds: 0, detail: "queued,limit=\(limit),active-identities=\(activeKeys.count)")
            return true
        }

        let runID = UUID()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let document = try await self.preparedDocument(
                    for: request,
                    renderOptions: renderOptions,
                    purpose: .prewarm
                )
                await MainActor.run {
                    osrsPreparedArticleWebViewStore.shared.preload(
                        document: document,
                        options: renderOptions
                    )
                }
            } catch is CancellationError {
                await self.emitCancellation(for: request.identity, detail: "prewarm")
            } catch {
                // Prewarming is speculative and must never surface an article error.
            }
            await self.finishPrewarm(owner: owner, runID: runID)
        }
        activePrewarms[owner] = ActivePrewarm(
            runID: runID,
            identity: request.identity,
            key: key,
            task: task
        )
        return true
    }

    func cancelPrewarm(owner: UUID) {
        pendingPrewarms.removeValue(forKey: owner)
        if activePrewarms[owner] != nil {
            retirePrewarm(owner: owner)
            signalSchedulerChange()
        }
        startQueuedPrewarmsIfPossible()
    }

    /// A distinct foreground open must not become a third bandwidth consumer behind two purely
    /// speculative flights. Preempt one whole speculative identity (including duplicate row
    /// owners) while preserving any flight already promoted by a foreground consumer.
    @discardableResult
    private func preemptOneSpeculativeIdentityForForeground(excluding foregroundKey: DocumentKey) -> Bool {
        let candidateKeys = Set(activePrewarms.values.map(\.key))
            .filter { $0 != foregroundKey }
            .filter { documentFlights[$0]?.hasForegroundConsumer != true }
            .sorted { $0.identity.value < $1.identity.value }
        guard let keyToPreempt = candidateKeys.first else { return false }

        let owners = activePrewarms.compactMap { owner, active in
            active.key == keyToPreempt ? owner : nil
        }
        for owner in owners {
            retirePrewarm(owner: owner)
        }

        if let documentFlight = documentFlights.removeValue(forKey: keyToPreempt),
           !documentFlight.hasForegroundConsumer {
            documentFlight.task.cancel()
        }
        if let payloadFlight = payloadFlights[keyToPreempt.identity],
           !payloadFlight.hasForegroundConsumer {
            payloadFlights.removeValue(forKey: keyToPreempt.identity)
            payloadFlight.task.cancel()
        }
        emit(
            .cancellation,
            keyToPreempt.identity,
            elapsedMilliseconds: 0,
            detail: "foreground-preemption"
        )
        return true
    }

    func reevaluateActivePrewarms(conditions: osrsArticlePrewarmConditions) {
        schedulerConcurrencyLimit = conditions.maximumConcurrentPrewarms
        if conditions.maximumConcurrentPrewarms == 0 {
            pendingPrewarms.removeAll()
        } else {
            for owner in pendingPrewarms.keys {
                pendingPrewarms[owner]?.conditions = conditions
            }
        }
        let limit = conditions.maximumConcurrentPrewarms
        let orderedEntries = activePrewarms.sorted { lhs, rhs in
            lhs.key.uuidString < rhs.key.uuidString
        }
        var retainedKeys: Set<DocumentKey> = []
        for (_, active) in orderedEntries where retainedKeys.count < limit {
            retainedKeys.insert(active.key)
        }
        if Set(activePrewarms.values.map(\.key)).count > retainedKeys.count {
            let ownersToCancel = orderedEntries.compactMap { owner, active in
                retainedKeys.contains(active.key) ? nil : owner
            }
            for owner in ownersToCancel {
                guard let active = activePrewarms[owner] else { continue }
                emit(.cancellation, active.identity, elapsedMilliseconds: 0, detail: "constraint-change")
                // Cancelling only the prewarm consumer is safe after promotion: a matching foreground
                // consumer remains registered on the shared document flight and keeps it alive.
                retirePrewarm(owner: owner)
            }
        }
        signalSchedulerChange()
        startQueuedPrewarmsIfPossible()
    }

    func invalidate(_ identity: osrsArticleDocumentIdentity) {
        let resolvedIdentity = resolvedIdentity(for: identity)
        payloadCache.removeValue(forKey: identity)
        payloadCache.removeValue(forKey: resolvedIdentity)
        documentCache = documentCache.filter {
            $0.key.identity != identity && $0.key.identity != resolvedIdentity
        }

        if let flight = payloadFlights.removeValue(forKey: identity) {
            flight.task.cancel()
        }
        if resolvedIdentity != identity,
           let flight = payloadFlights.removeValue(forKey: resolvedIdentity) {
            flight.task.cancel()
        }
        let matchingDocumentKeys = documentFlights.keys.filter {
            $0.identity == identity || $0.identity == resolvedIdentity
        }
        for key in matchingDocumentKeys {
            documentFlights.removeValue(forKey: key)?.task.cancel()
        }
        canonicalIdentityByAlias = canonicalIdentityByAlias.filter {
            $0.key != identity && $0.key != resolvedIdentity &&
                $0.value.canonicalIdentity != identity &&
                $0.value.canonicalIdentity != resolvedIdentity
        }
        pruneAliases(now: clock())
    }

    func recordWebKitReady(identity: osrsArticleDocumentIdentity, elapsed: TimeInterval) {
        emit(.webKitReady, identity, elapsedMilliseconds: elapsed * 1_000, detail: "didFinish")
    }

    func recordNavigationCancellation(identity: osrsArticleDocumentIdentity) {
        emit(.cancellation, identity, elapsedMilliseconds: 0, detail: "navigation")
    }

#if DEBUG
    struct DebugSnapshot: Sendable {
        let payloadCacheCount: Int
        let documentCacheCount: Int
        let aliasCacheCount: Int
        let aliasCapacity: Int
        let payloadFlightCount: Int
        let documentFlightCount: Int
        let activePrewarmCount: Int
        let activePrewarmIdentityCount: Int
        let retiringPrewarmCount: Int
        let physicalPrewarmIdentityCount: Int
        let pendingPrewarmCount: Int
    }

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            payloadCacheCount: payloadCache.count,
            documentCacheCount: documentCache.count,
            aliasCacheCount: canonicalIdentityByAlias.count,
            aliasCapacity: aliasCapacity,
            payloadFlightCount: payloadFlights.count,
            documentFlightCount: documentFlights.count,
            activePrewarmCount: activePrewarms.count,
            activePrewarmIdentityCount: Set(activePrewarms.values.map(\.key)).count,
            retiringPrewarmCount: retiringPrewarms.count,
            physicalPrewarmIdentityCount: physicalPrewarmKeys.count,
            pendingPrewarmCount: pendingPrewarms.count
        )
    }

    func debugInstallAlias(
        _ alias: osrsArticleDocumentIdentity,
        canonicalIdentity: osrsArticleDocumentIdentity
    ) {
        installAlias(alias, canonicalIdentity: canonicalIdentity, pruneOrphans: false)
    }

    func debugResolvedIdentity(
        for identity: osrsArticleDocumentIdentity
    ) -> osrsArticleDocumentIdentity {
        resolvedIdentity(for: identity)
    }

    func debugAliasTarget(
        for identity: osrsArticleDocumentIdentity
    ) -> osrsArticleDocumentIdentity? {
        canonicalIdentityByAlias[identity]?.canonicalIdentity
    }
#endif

    private func preparedPayload(
        for request: osrsArticleDocumentRequest,
        purpose: osrsArticlePreparationPurpose
    ) async throws -> osrsPreparedArticlePayload {
        let identity = resolvedIdentity(for: request.identity)
        if let cached = cachedPayload(for: identity) {
            emit(.cacheHit, request.identity, elapsedMilliseconds: 0, detail: "payload")
            return cached
        }

        let consumerID = UUID()
        let handle = payloadFlight(
            for: request,
            identity: identity,
            consumerID: consumerID,
            purpose: purpose
        )
        do {
            let payload = try await withTaskCancellationHandler {
                try await handle.task.value
            } onCancel: {
                Task { await self.cancelPayloadConsumer(identity: identity, consumerID: consumerID) }
            }
            try Task.checkCancellation()
            completePayloadFlight(identity: identity, flightID: handle.flightID, payload: payload)
            return payload
        } catch {
            if Task.isCancelled {
                cancelPayloadConsumer(identity: identity, consumerID: consumerID)
            } else {
                failPayloadFlight(identity: identity, flightID: handle.flightID)
            }
            throw error
        }
    }

    private func payloadFlight(
        for request: osrsArticleDocumentRequest,
        identity: osrsArticleDocumentIdentity,
        consumerID: UUID,
        purpose: osrsArticlePreparationPurpose
    ) -> (flightID: UUID, task: Task<osrsPreparedArticlePayload, Error>) {
        if var existing = payloadFlights[identity] {
            existing.consumers[consumerID] = purpose
            if purpose == .foreground, !existing.hasForegroundConsumer {
                existing.hasForegroundConsumer = true
                emit(.promotion, request.identity, elapsedMilliseconds: 0, detail: "payload")
            }
            payloadFlights[identity] = existing
            return (existing.id, existing.task)
        }

        let flightID = UUID()
        let fetcher = purpose == .prewarm ? self.prewarmFetcher : self.fetcher
        let eventSink = self.eventSink
        let clock = self.clock
        let task = Task(priority: purpose == .foreground ? .userInitiated : .utility) {
            guard let url = request.parseRequestURL else { throw NetworkError.invalidResponse }
            try Task.checkCancellation()

            let fetchStart = clock()
            let data = try await fetcher(url)
            eventSink(Self.event(.fetch, request.identity, since: fetchStart, clock: clock, detail: "bytes=\(data.count)"))
            try Task.checkCancellation()

            let decodeStart = clock()
            let payload = try await Self.decodeOffMain(data, requestedTitle: request.requestedTitle)
            eventSink(Self.event(.decode, request.identity, since: decodeStart, clock: clock, detail: "page-id=\(payload.pageId)"))
            try Task.checkCancellation()

            let normalizeStart = clock()
            let normalizedHTML = try await Self.normalizeOffMain(payload.htmlContent)
            eventSink(Self.event(.normalize, request.identity, since: normalizeStart, clock: clock, detail: "characters=\(normalizedHTML.count)"))
            try Task.checkCancellation()
            return osrsPreparedArticlePayload(payload: payload, normalizedHTML: normalizedHTML)
        }

        payloadFlights[identity] = PayloadFlight(
            id: flightID,
            task: task,
            consumers: [consumerID: purpose],
            hasForegroundConsumer: purpose == .foreground
        )
        return (flightID, task)
    }

    private func documentFlight(
        for key: DocumentKey,
        request: osrsArticleDocumentRequest,
        renderOptions: osrsArticleRenderOptions,
        consumerID: UUID,
        purpose: osrsArticlePreparationPurpose
    ) -> (flightID: UUID, task: Task<osrsPreparedArticleDocument, Error>) {
        if var existing = documentFlights[key] {
            existing.consumers[consumerID] = purpose
            if purpose == .foreground, !existing.hasForegroundConsumer {
                existing.hasForegroundConsumer = true
                emit(.promotion, request.identity, elapsedMilliseconds: 0, detail: "document")
                promotePayloadIfNeeded(identity: key.identity)
            }
            documentFlights[key] = existing
            return (existing.id, existing.task)
        }

        let flightID = UUID()
        let builder = self.builder
        let clock = self.clock
        let eventSink = self.eventSink
        let task = Task(priority: purpose == .foreground ? .userInitiated : .utility) { [weak self] in
            guard let self else { throw CancellationError() }
            let payload = try await self.preparedPayload(for: request, purpose: purpose)
            try Task.checkCancellation()
            let buildStart = clock()
            let html = try await builder(payload, renderOptions)
            eventSink(Self.event(.build, request.identity, since: buildStart, clock: clock, detail: "characters=\(html.count)"))
            try Task.checkCancellation()
            return osrsPreparedArticleDocument(request: request, payload: payload.payload, html: html)
        }
        documentFlights[key] = DocumentFlight(
            id: flightID,
            task: task,
            consumers: [consumerID: purpose],
            hasForegroundConsumer: purpose == .foreground
        )
        return (flightID, task)
    }

    private func promotePayloadIfNeeded(identity: osrsArticleDocumentIdentity) {
        guard var flight = payloadFlights[identity], !flight.hasForegroundConsumer else { return }
        flight.hasForegroundConsumer = true
        payloadFlights[identity] = flight
        emit(.promotion, identity, elapsedMilliseconds: 0, detail: "payload")
    }

    func cachedPayload(for request: osrsArticleDocumentRequest) -> osrsPreparedArticlePayload? {
        cachedPayload(for: resolvedIdentity(for: request.identity))
    }

    private func cachedPayload(for identity: osrsArticleDocumentIdentity) -> osrsPreparedArticlePayload? {
        purgeExpiredEntries()
        guard var entry = payloadCache[identity] else { return nil }
        accessCounter &+= 1
        entry.access = accessCounter
        payloadCache[identity] = entry
        return entry.value
    }

    private func cachedDocument(for key: DocumentKey) -> osrsPreparedArticleDocument? {
        purgeExpiredEntries()
        guard var entry = documentCache[key] else { return nil }
        accessCounter &+= 1
        entry.access = accessCounter
        documentCache[key] = entry
        return entry.value
    }

    private func completePayloadFlight(
        identity: osrsArticleDocumentIdentity,
        flightID: UUID,
        payload: osrsPreparedArticlePayload
    ) {
        guard payloadFlights[identity]?.id == flightID else { return }
        payloadFlights.removeValue(forKey: identity)
        let canonicalIdentity = canonicalIdentity(for: payload.payload)
        accessCounter &+= 1
        payloadCache[canonicalIdentity] = CacheEntry(
            value: payload,
            expiry: clock().addingTimeInterval(configuration.timeToLive),
            access: accessCounter
        )
        evictPayloadsIfNeeded()
        installAlias(identity, canonicalIdentity: canonicalIdentity)
    }

    private func completeDocumentFlight(
        key: DocumentKey,
        flightID: UUID,
        document: osrsPreparedArticleDocument
    ) {
        guard documentFlights[key]?.id == flightID else { return }
        documentFlights.removeValue(forKey: key)
        let canonicalIdentity = canonicalIdentity(for: document.payload)
        let canonicalKey = DocumentKey(
            identity: canonicalIdentity,
            renderOptions: key.renderOptions
        )
        accessCounter &+= 1
        documentCache[canonicalKey] = CacheEntry(
            value: document,
            expiry: clock().addingTimeInterval(configuration.timeToLive),
            access: accessCounter
        )
        evictDocumentsIfNeeded()
        installAlias(key.identity, canonicalIdentity: canonicalIdentity)
    }

    private func failPayloadFlight(identity: osrsArticleDocumentIdentity, flightID: UUID) {
        guard payloadFlights[identity]?.id == flightID else { return }
        payloadFlights.removeValue(forKey: identity)
    }

    private func failDocumentFlight(key: DocumentKey, flightID: UUID) {
        guard documentFlights[key]?.id == flightID else { return }
        documentFlights.removeValue(forKey: key)
    }

    private func cancelPayloadConsumer(identity: osrsArticleDocumentIdentity, consumerID: UUID) {
        guard var flight = payloadFlights[identity] else { return }
        flight.consumers.removeValue(forKey: consumerID)
        if flight.consumers.isEmpty {
            payloadFlights.removeValue(forKey: identity)
            flight.task.cancel()
            emit(.cancellation, identity, elapsedMilliseconds: 0, detail: "payload-no-consumers")
        } else {
            flight.hasForegroundConsumer = flight.consumers.values.contains(.foreground)
            payloadFlights[identity] = flight
        }
    }

    private func cancelDocumentConsumer(key: DocumentKey, consumerID: UUID) {
        guard var flight = documentFlights[key] else { return }
        flight.consumers.removeValue(forKey: consumerID)
        if flight.consumers.isEmpty {
            documentFlights.removeValue(forKey: key)
            flight.task.cancel()
            emit(.cancellation, key.identity, elapsedMilliseconds: 0, detail: "document-no-consumers")
        } else {
            flight.hasForegroundConsumer = flight.consumers.values.contains(.foreground)
            documentFlights[key] = flight
        }
    }

    private var physicalPrewarmKeys: Set<DocumentKey> {
        Set(activePrewarms.values.map(\.key))
            .union(retiringPrewarms.values.map(\.key))
    }

    private var foregroundEligibleRetiringKeys: Set<DocumentKey> {
        let liveKeys = Set(activePrewarms.values.map(\.key))
        return Set(retiringPrewarms.values.map(\.key)).subtracting(liveKeys)
    }

    private func canStartNewSpeculation(limit: Int) -> Bool {
        guard limit > 0,
              retiringPrewarms.isEmpty,
              foregroundCancellationLaneToken == nil,
              foregroundAdmissionWaiters.isEmpty else {
            return false
        }
        return physicalPrewarmKeys.count < limit
    }

    private func retirePrewarm(owner: UUID) {
        guard let active = activePrewarms.removeValue(forKey: owner) else { return }
        retiringPrewarms[active.runID] = RetiringPrewarm(
            identity: active.identity,
            key: active.key,
            task: active.task
        )
        active.task.cancel()
    }

    /// Foreground opens may use one temporary lane over exactly one canceling speculative key.
    /// The token stays held until the foreground wrapper physically returns, so repeatedly
    /// canceling foreground work cannot grow transport concurrency without bound.
    private func acquireForegroundAdmission(excluding foregroundKey: DocumentKey) async throws -> UUID? {
        let waiterID = UUID()
        var registeredAsWaiter = false
        defer {
            foregroundAdmissionWaiters.remove(waiterID)
            if let continuation = schedulerWaitContinuations.removeValue(forKey: waiterID) {
                continuation.resume()
            }
        }

        while true {
            try Task.checkCancellation()
            if documentFlights[foregroundKey] != nil {
                return nil
            }

            if foregroundCancellationLaneToken == nil {
                let limit = max(schedulerConcurrencyLimit, 1)
                let physicalCount = physicalPrewarmKeys.count

                if retiringPrewarms.isEmpty, physicalCount < limit {
                    return nil
                }

                if !retiringPrewarms.isEmpty, physicalCount < limit {
                    let token = UUID()
                    foregroundCancellationLaneToken = token
                    return token
                }

                let eligibleRetiringKeys = foregroundEligibleRetiringKeys
                // A user-opened foreground article must not be starved by a canceled transport
                // that ignores cancellation. Any distinct retiring speculative identity can lend
                // one serialized foreground lane, even after a 2 -> 1 downshift or full
                // suppression leaves the physical count above the new limit. The token still
                // prevents a second foreground wrapper from compounding that overlap.
                if !eligibleRetiringKeys.isEmpty {
                    let token = UUID()
                    foregroundCancellationLaneToken = token
                    return token
                }

                // A canceled duplicate owner can remain retiring for the same identity that an
                // active speculative owner still holds. That wrapper is not a distinct physical
                // lane, so preempt the remaining speculative identity before lending the single
                // foreground lane instead of waiting indefinitely for the shared transport.
                if physicalCount >= limit,
                   preemptOneSpeculativeIdentityForForeground(excluding: foregroundKey) {
                    let token = UUID()
                    foregroundCancellationLaneToken = token
                    return token
                }
            }

            if !registeredAsWaiter {
                foregroundAdmissionWaiters.insert(waiterID)
                registeredAsWaiter = true
            }
            try await waitForSchedulerChange(waiterID: waiterID)
        }
    }

    private func releaseForegroundAdmission(_ token: UUID) {
        guard foregroundCancellationLaneToken == token else { return }
        foregroundCancellationLaneToken = nil
        signalSchedulerChange()
        startQueuedPrewarmsIfPossible()
    }

    private func waitForSchedulerChange(waiterID: UUID) async throws {
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                schedulerWaitContinuations[waiterID] = continuation
            }
        } onCancel: {
            Task { await self.cancelSchedulerWaiter(waiterID) }
        }
        try Task.checkCancellation()
    }

    private func cancelSchedulerWaiter(_ waiterID: UUID) {
        schedulerWaitContinuations.removeValue(forKey: waiterID)?.resume()
    }

    private func signalSchedulerChange() {
        let continuations = Array(schedulerWaitContinuations.values)
        schedulerWaitContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func finishPrewarm(owner: UUID, runID: UUID) {
        var finishedPhysicalRun = false
        if activePrewarms[owner]?.runID == runID {
            activePrewarms.removeValue(forKey: owner)
            finishedPhysicalRun = true
        }
        if retiringPrewarms.removeValue(forKey: runID) != nil {
            finishedPhysicalRun = true
        }
        guard finishedPhysicalRun else { return }
        signalSchedulerChange()
        startQueuedPrewarmsIfPossible()
    }

    private func startQueuedPrewarmsIfPossible() {
        let queuedOwners = pendingPrewarms.sorted { $0.value.order < $1.value.order }.map(\.key)
        for owner in queuedOwners {
            guard let pending = pendingPrewarms[owner] else { continue }
            let key = DocumentKey(
                identity: resolvedIdentity(for: pending.request.identity),
                renderOptions: pending.renderOptions
            )
            let activeKeys = Set(activePrewarms.values.map(\.key))
            let limit = pending.conditions.maximumConcurrentPrewarms
            guard limit > 0 else {
                pendingPrewarms.removeValue(forKey: owner)
                continue
            }
            guard activeKeys.contains(key) || canStartNewSpeculation(limit: limit) else {
                continue
            }
            pendingPrewarms.removeValue(forKey: owner)
            _ = startPrewarm(
                owner: owner,
                request: pending.request,
                renderOptions: pending.renderOptions,
                conditions: pending.conditions
            )
        }
    }

    private func purgeExpiredEntries() {
        let now = clock()
        payloadCache = payloadCache.filter { $0.value.expiry > now }
        documentCache = documentCache.filter { $0.value.expiry > now }
        pruneAliases(now: now)
    }

    private func evictPayloadsIfNeeded() {
        while payloadCache.count > max(configuration.payloadCapacity, 0),
              let key = payloadCache.min(by: { $0.value.access < $1.value.access })?.key {
            payloadCache.removeValue(forKey: key)
        }
        pruneAliases(now: clock())
    }

    private func evictDocumentsIfNeeded() {
        while documentCache.count > max(configuration.documentCapacity, 0),
              let key = documentCache.min(by: { $0.value.access < $1.value.access })?.key {
            documentCache.removeValue(forKey: key)
        }
        pruneAliases(now: clock())
    }

    private func resolvedIdentity(
        for identity: osrsArticleDocumentIdentity
    ) -> osrsArticleDocumentIdentity {
        purgeExpiredEntries()
        guard aliasCapacity > 0 else { return identity }

        var current = identity
        var visited: Set<osrsArticleDocumentIdentity> = [identity]
        var path: [osrsArticleDocumentIdentity] = []
        var earliestExpiry: Date?

        for _ in 0..<aliasCapacity {
            guard var entry = canonicalIdentityByAlias[current] else { break }
            guard !visited.contains(entry.canonicalIdentity) else {
                // A malformed or retargeted cycle must fail closed and cannot remain resident.
                path.append(current)
                for cycleIdentity in path {
                    canonicalIdentityByAlias.removeValue(forKey: cycleIdentity)
                }
                return identity
            }

            accessCounter &+= 1
            entry.access = accessCounter
            canonicalIdentityByAlias[current] = entry
            earliestExpiry = min(earliestExpiry ?? entry.expiry, entry.expiry)
            path.append(current)
            visited.insert(entry.canonicalIdentity)
            current = entry.canonicalIdentity
        }

        // A valid chain cannot exceed the bounded alias cache. Treat an over-depth chain like a
        // cycle rather than returning a partially resolved identity.
        if path.count == aliasCapacity, canonicalIdentityByAlias[current] != nil {
            for chainedIdentity in path {
                canonicalIdentityByAlias.removeValue(forKey: chainedIdentity)
            }
            return identity
        }

        if current != identity, let expiry = earliestExpiry {
            for alias in path where alias != current {
                accessCounter &+= 1
                canonicalIdentityByAlias[alias] = AliasEntry(
                    canonicalIdentity: current,
                    expiry: expiry,
                    access: accessCounter
                )
            }
        }
        evictAliasesIfNeeded()
        return current
    }

    private func installAlias(
        _ alias: osrsArticleDocumentIdentity,
        canonicalIdentity: osrsArticleDocumentIdentity,
        pruneOrphans: Bool = true
    ) {
        guard alias != canonicalIdentity, aliasCapacity > 0 else { return }
        let now = clock()
        accessCounter &+= 1
        canonicalIdentityByAlias[alias] = AliasEntry(
            canonicalIdentity: canonicalIdentity,
            expiry: now.addingTimeInterval(configuration.timeToLive),
            access: accessCounter
        )
        evictAliasesIfNeeded()
        if pruneOrphans {
            pruneAliases(now: now)
        }
    }

    private func evictAliasesIfNeeded() {
        while canonicalIdentityByAlias.count > aliasCapacity,
              let key = canonicalIdentityByAlias.min(by: { $0.value.access < $1.value.access })?.key {
            canonicalIdentityByAlias.removeValue(forKey: key)
        }
    }

    private func pruneAliases(now: Date) {
        canonicalIdentityByAlias = canonicalIdentityByAlias.filter { $0.value.expiry > now }
        guard !canonicalIdentityByAlias.isEmpty else { return }

        let entries = canonicalIdentityByAlias
        let liveCanonicalIdentities = Set(payloadCache.keys)
            .union(documentCache.keys.map(\.identity))
            .union(payloadFlights.keys)
            .union(documentFlights.keys.map(\.identity))
            .union(activePrewarms.values.map(\.key.identity))
        var retainedAliases: Set<osrsArticleDocumentIdentity> = []

        for alias in entries.keys {
            var current = alias
            var visited: Set<osrsArticleDocumentIdentity> = []
            var path: [osrsArticleDocumentIdentity] = []

            for _ in 0...entries.count {
                guard visited.insert(current).inserted else {
                    break
                }
                if let entry = entries[current], entry.expiry > now {
                    path.append(current)
                    current = entry.canonicalIdentity
                } else {
                    if liveCanonicalIdentities.contains(current) {
                        retainedAliases.formUnion(path)
                    }
                    break
                }
            }
        }

        canonicalIdentityByAlias = canonicalIdentityByAlias.filter {
            retainedAliases.contains($0.key)
        }
        evictAliasesIfNeeded()
    }

    private func canonicalIdentity(
        for payload: osrsArticleParsePayload
    ) -> osrsArticleDocumentIdentity {
        let pathTitle = payload.title.replacingOccurrences(of: " ", with: "_")
        let encodedTitle = pathTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathTitle
        let url = URL(string: "https://oldschool.runescape.wiki/w/\(encodedTitle)")!
        return osrsArticleDocumentIdentity(pageURL: url, pageTitle: payload.title)
    }

    private func emit(
        _ phase: osrsArticleTimingPhase,
        _ identity: osrsArticleDocumentIdentity,
        since start: Date,
        detail: String
    ) {
        eventSink(Self.event(phase, identity, since: start, clock: clock, detail: detail))
    }

    private func emit(
        _ phase: osrsArticleTimingPhase,
        _ identity: osrsArticleDocumentIdentity,
        elapsedMilliseconds: Double,
        detail: String
    ) {
        eventSink(osrsArticleTimingEvent(
            phase: phase,
            identity: identity,
            elapsedMilliseconds: elapsedMilliseconds,
            detail: detail
        ))
    }

    private func emitCancellation(for identity: osrsArticleDocumentIdentity, detail: String) {
        emit(.cancellation, identity, elapsedMilliseconds: 0, detail: detail)
    }

    private static func event(
        _ phase: osrsArticleTimingPhase,
        _ identity: osrsArticleDocumentIdentity,
        since start: Date,
        clock: Clock,
        detail: String
    ) -> osrsArticleTimingEvent {
        osrsArticleTimingEvent(
            phase: phase,
            identity: identity,
            elapsedMilliseconds: max(0, clock().timeIntervalSince(start) * 1_000),
            detail: detail
        )
    }

    private static func decodeOffMain(_ data: Data, requestedTitle: String) async throws -> osrsArticleParsePayload {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try osrsArticlePayloadPreparer.decode(data, requestedTitle: requestedTitle)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func normalizeOffMain(_ html: String) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = osrsArticlePayloadPreparer.normalize(html)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func liveBuilder(
        payload: osrsPreparedArticlePayload,
        options: osrsArticleRenderOptions
    ) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let theme: any osrsThemeProtocol = options.usesDarkTheme ? osrsDarkTheme() : osrsLightTheme()
            let html = osrsPageHtmlBuilder().buildFullHtmlDocument(
                title: payload.payload.displayTitle ?? payload.payload.title,
                bodyContent: payload.normalizedHTML,
                theme: theme,
                collapseTablesEnabled: options.collapseTablesEnabled,
                includeAssetLinks: true,
                articleTextScale: CGFloat(options.articleTextScale),
                floorConvention: options.floorNumberingBodyClass == osrsArticleFloorConvention.us.bodyClass
                    ? .us
                    : .gb,
                wrapTableCellsEnabled: options.wrapTableCellsEnabled,
                canonicalTitle: payload.payload.title
            )
            try Task.checkCancellation()
            return html
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func debugEventSink(_ event: osrsArticleTimingEvent) {
#if DEBUG
        print(
            "[ArticlePipeline] phase=\(event.phase.rawValue) " +
            "identity=\(event.identity.value) " +
            "elapsed_ms=\(String(format: "%.2f", event.elapsedMilliseconds)) " +
            "detail=\(event.detail)"
        )
#endif
    }
}

struct osrsArticlePrewarmVisibilityGate {
    enum Event {
        case appeared(applicationIsActive: Bool, environmentAllowsPrewarm: Bool)
        case visibilityChanged(Bool)
        case applicationActivityChanged(Bool)
        case environmentEligibilityChanged(Bool)
        case disappeared
    }

    enum Action: Equatable {
        case none
        case schedule
        case cancel
    }

    private(set) var hasAppeared = false
    private(set) var isGeometricallyVisible = false
    private(set) var applicationIsActive = false
    private(set) var environmentAllowsPrewarm = false

    var isEligible: Bool {
        hasAppeared && isGeometricallyVisible && applicationIsActive && environmentAllowsPrewarm
    }

    mutating func transition(_ event: Event) -> Action {
        let wasEligible = isEligible
        switch event {
        case .appeared(let applicationIsActive, let environmentAllowsPrewarm):
            hasAppeared = true
            self.applicationIsActive = applicationIsActive
            self.environmentAllowsPrewarm = environmentAllowsPrewarm
        case .visibilityChanged(let isVisible):
            isGeometricallyVisible = isVisible
        case .applicationActivityChanged(let isActive):
            applicationIsActive = isActive
        case .environmentEligibilityChanged(let isAllowed):
            environmentAllowsPrewarm = isAllowed
        case .disappeared:
            hasAppeared = false
            isGeometricallyVisible = false
        }

        if isEligible, !wasEligible {
            return .schedule
        }
        if !isEligible, wasEligible || event.requiresCancellation {
            return .cancel
        }
        return .none
    }
}

private extension osrsArticlePrewarmVisibilityGate.Event {
    var requiresCancellation: Bool {
        switch self {
        case .visibilityChanged(false),
             .applicationActivityChanged(false),
             .environmentEligibilityChanged(false),
             .disappeared:
            return true
        case .appeared,
             .visibilityChanged(true),
             .applicationActivityChanged(true),
             .environmentEligibilityChanged(true):
            return false
        }
    }
}

/// `onScrollVisibilityChange` can be delivered while SwiftUI is evaluating the scroll
/// preference graph. Mutating a view's `@State` from that callback makes the same graph
/// re-enter itself during an accessibility snapshot on iOS 26. Coalesce visibility-only
/// changes onto the next main turn; appearance and disappearance still own the lifecycle.
@MainActor
final class osrsArticlePrewarmVisibilityRelay: ObservableObject {
    private var generation = 0

    func enqueue(
        _ isVisible: Bool,
        action: @escaping @MainActor (Bool) -> Void
    ) {
        generation &+= 1
        let requestedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, requestedGeneration == self.generation else { return }
            action(isVisible)
        }
    }

    func invalidate() {
        generation &+= 1
    }
}

struct osrsArticlePrewarmBatchRequest: Sendable {
    let owner: UUID
    let pageURL: URL
    let pageTitle: String?
}

enum osrsArticlePrewarmBatchRunner {
    static func run(
        _ requests: [osrsArticlePrewarmBatchRequest],
        start: @escaping @Sendable (osrsArticlePrewarmBatchRequest) async -> Void,
        cancel: @escaping @Sendable (UUID) async -> Void
    ) async {
        for (index, request) in requests.enumerated() {
            guard !Task.isCancelled else {
                for remaining in requests[index...] { await cancel(remaining.owner) }
                return
            }

            await start(request)

            guard !Task.isCancelled else {
                for remaining in requests[index...] { await cancel(remaining.owner) }
                return
            }
        }
    }
}

private struct osrsArticleVisibleRowPrewarmModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeManager: osrsThemeManager
    let pageURL: URL?
    let pageTitle: String?
    let additionalPageURLs: [URL]
    let isOfflineContentAvailable: Bool
    @State private var owners: [UUID] = []
    @State private var dwellTask: Task<Void, Never>?
    @State private var visibilityGate = osrsArticlePrewarmVisibilityGate()
    @StateObject private var visibilityRelay = osrsArticlePrewarmVisibilityRelay()

    func body(content: Content) -> some View {
        content
            .onAppear {
                handleVisibilityAction(
                    visibilityGate.transition(
                        .appeared(
                            applicationIsActive: scenePhase == .active,
                            environmentAllowsPrewarm: currentConditions().maximumConcurrentPrewarms > 0
                        )
                    )
                )
            }
            .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                visibilityRelay.enqueue(isVisible) { deferredVisibility in
                    handleVisibilityAction(
                        visibilityGate.transition(.visibilityChanged(deferredVisibility))
                    )
                }
            }
            .onDisappear {
                visibilityRelay.invalidate()
                handleVisibilityAction(visibilityGate.transition(.disappeared))
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleVisibilityAction(
                    visibilityGate.transition(
                        .applicationActivityChanged(newPhase == .active)
                    )
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                handleEnvironmentChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                handleEnvironmentChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .osrsNetworkPathConditionsDidChange)) { _ in
                handleEnvironmentChange()
            }
            .onChange(of: isOfflineContentAvailable) { _, _ in
                handleEnvironmentChange()
            }
            .onChange(of: themeManager.collapseTables) { _, _ in
                handleEnvironmentChange()
            }
            .onChange(of: themeManager.articleTextScale) { _, _ in
                handleEnvironmentChange()
            }
    }

    private func handleVisibilityAction(_ action: osrsArticlePrewarmVisibilityGate.Action) {
        switch action {
        case .none:
            break
        case .schedule:
            schedule()
        case .cancel:
            cancel()
        }
    }

    private func schedule() {
        cancel()
        let pageURLs = ([pageURL].compactMap { $0 } + additionalPageURLs).reduce(into: [URL]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        guard !pageURLs.isEmpty, !isOfflineContentAvailable else { return }
        let newOwners = pageURLs.map { _ in UUID() }
        owners = newOwners
        let renderOptions = osrsArticleRenderOptions(
            usesDarkTheme: themeManager.currentTheme is osrsDarkTheme,
            collapseTablesEnabled: themeManager.collapseTables,
            wrapTableCellsEnabled: themeManager.wrapTableCells,
            articleTextScale: Double(themeManager.articleTextScale)
        )
        dwellTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
                try Task.checkCancellation()
                let conditions = osrsArticlePrewarmConditions.current(
                    isOfflineContentAvailable: isOfflineContentAvailable
                )
                let requests = pageURLs.enumerated().map { index, pageURL in
                    osrsArticlePrewarmBatchRequest(
                        owner: newOwners[index],
                        pageURL: pageURL,
                        pageTitle: index == 0 ? pageTitle : nil
                    )
                }
                await osrsArticlePrewarmBatchRunner.run(
                    requests,
                    start: { request in
                        _ = await osrsArticleDocumentCoordinator.shared.startPrewarm(
                            owner: request.owner,
                            request: osrsArticleDocumentRequest(
                                pageURL: request.pageURL,
                                pageTitle: request.pageTitle
                            ),
                            renderOptions: renderOptions,
                            conditions: conditions
                        )
                    },
                    cancel: { owner in
                        await osrsArticleDocumentCoordinator.shared.cancelPrewarm(owner: owner)
                    }
                )
            } catch {
                // Leaving the row or backgrounding the app is the expected cancellation path.
            }
        }
    }

    private func cancel() {
        dwellTask?.cancel()
        dwellTask = nil
        let cancelledOwners = owners
        owners = []
        Task {
            for owner in cancelledOwners {
                await osrsArticleDocumentCoordinator.shared.cancelPrewarm(owner: owner)
            }
        }
    }

    private func handleEnvironmentChange() {
        let conditions = currentConditions()
        handleVisibilityAction(
            visibilityGate.transition(
                .environmentEligibilityChanged(conditions.maximumConcurrentPrewarms > 0)
            )
        )
        Task {
            await osrsArticleDocumentCoordinator.shared.reevaluateActivePrewarms(
                conditions: conditions
            )
        }
    }

    private func currentConditions() -> osrsArticlePrewarmConditions {
        osrsArticlePrewarmConditions.current(
            isOfflineContentAvailable: isOfflineContentAvailable
        )
    }
}

extension View {
    func osrsPrewarmArticleWhenVisible(
        pageURL: URL?,
        pageTitle: String?,
        isOfflineContentAvailable: Bool = false
    ) -> some View {
        modifier(osrsArticleVisibleRowPrewarmModifier(
            pageURL: pageURL,
            pageTitle: pageTitle,
            additionalPageURLs: [],
            isOfflineContentAvailable: isOfflineContentAvailable
        ))
    }


    func osrsPrewarmArticlesWhenVisible(
        pageURLs: [URL],
        isOfflineContentAvailable: Bool = false
    ) -> some View {
        modifier(osrsArticleVisibleRowPrewarmModifier(
            pageURL: nil,
            pageTitle: nil,
            additionalPageURLs: pageURLs,
            isOfflineContentAvailable: isOfflineContentAvailable
        ))
    }
}

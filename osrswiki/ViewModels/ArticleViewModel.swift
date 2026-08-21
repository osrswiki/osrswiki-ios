//
//  ArticleViewModel.swift
//  OSRS Wiki
//
//  Created on iOS webviewer implementation session
//  Updated for article rendering parity with Android
//

import SwiftUI
import UIKit
import WebKit
import Combine
import CryptoKit

// TIMELINE LOGGING: Precise timestamp formatter for tracking loading phases
extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Notification Names
extension Notification.Name {
    static let showAppearanceSettings = Notification.Name("showAppearanceSettings")
    static let osrsInternalArticleLinkRequested = Notification.Name("osrsInternalArticleLinkRequested")
    static let osrsPlayYouTubeRequested = Notification.Name("osrsPlayYouTubeRequested")
}

// MARK: - Color Extension for Hex Conversion
extension Color {
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(red * 255.0)
        let g = Int(green * 255.0)
        let b = Int(blue * 255.0)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Supporting Types

/// Save state enum matching Android PageActionBarManager.SaveState
enum osrsArticleBottomBarSaveState: Equatable {
    case notSaved
    case downloading
    case saved
    case error
}

struct osrsArticleParsePayload: Sendable {
    let pageId: Int
    let title: String
    let displayTitle: String?
    let revisionId: Int?
    let htmlContent: String

    var resolvedTitle: String {
        guard let displayTitle, !displayTitle.isEmpty else {
            return title
        }
        let normalizedTitle = osrsStringUtils.extractMainTitle(displayTitle)
        return normalizedTitle.isEmpty ? title : normalizedTitle
    }
}

enum osrsArticleNavigationDecision: Equatable {
    case appArticle(URL)
    case floorNumberingSettings
    case external(URL)
    case allow
}

enum osrsExternalNavigationAction: Equatable {
    case allowInWebView
    case openInBrowser
    case cancelSilently
}

enum osrsOfflineResourceSettlementError: LocalizedError, Equatable, Sendable {
    case requiredResourcesFailed(count: Int)

    var errorDescription: String? {
        switch self {
        case .requiredResourcesFailed:
            return "Some article images could not be saved for offline use. Please try again."
        }
    }
}

enum osrsOfflineArticleResourceSettlement {
    typealias Downloader = @Sendable (URL) async throws -> Data?

    private struct PlannedResource: Hashable, Sendable {
        let url: URL
        let stylesheetDepth: Int?
    }

    private static let maximumStylesheetBytes = 512 * 1024
    private static let maximumStylesheetDepth = 3

    /// Enumerate rendered article artwork, not navigation or interactive media bodies. The
    /// allowlist covers images (including deferred/responsive forms), picture sources, video
    /// posters, SVG images, image-typed objects, and authored CSS artwork/imports.
    nonisolated static func requiredImageURLs(from html: String) -> [URL] {
        requiredImageURLsInDocumentOrder(from: html).sorted { $0.absoluteString < $1.absoluteString }
    }

    nonisolated static func requiredImageURLsInDocumentOrder(from html: String) -> [URL] {
        initialResourcePlan(from: html).map(\.url)
    }

    nonisolated static func infoboxImageURLs(from html: String) -> [URL] {
        var seen: Set<URL> = []
        var urls: [URL] = []
        for fragment in infoboxFragments(from: html) {
            for url in initialResourcePlan(from: fragment).map(\.url) where seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    nonisolated static func firstViewSlotURLs(from html: String) -> [URL] {
        var seen: Set<URL> = []
        var urls: [URL] = []
        let chunks = infoboxFragments(from: html) + resourcePoolFragments(from: html) + [leadPrefix(from: html)]
        for fragment in chunks {
            for url in initialResourcePlan(from: fragment).map(\.url) where seen.insert(url).inserted {
                urls.append(url)
                if urls.count >= osrsLiveArticleAssetPlan.firstViewCap {
                    return urls
                }
            }
        }
        return urls
    }

    nonisolated static func networkURL(from raw: String) -> URL? {
        normalizedNetworkURL(raw, relativeTo: URL(string: "https://oldschool.runescape.wiki/")!)
    }

    private nonisolated static func infoboxFragments(from html: String) -> [String] {
        let pattern = #"<table\b[^>]*class=["'][^"']*infobox[^"']*["'][^>]*>[\s\S]*?</table>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            guard let range = Range($0.range, in: html) else { return nil }
            return String(html[range])
        }
    }

    private nonisolated static func leadPrefix(from html: String) -> String {
        let pattern = #"(?i)<h2\b|<[^>]*class=["'][^"']*mw-heading"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else {
            return html
        }
        return String(html[..<range.lowerBound])
    }

    private nonisolated static func dataResourceClassNeedles(from html: String) -> [String] {
        let pattern = #"data-resource-class=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            guard let range = Range($0.range(at: 1), in: html) else { return nil }
            var selector = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if selector.hasPrefix(".") {
                selector.removeFirst()
            }
            return selector.isEmpty ? nil : selector
        }
    }

    private nonisolated static func resourcePoolFragments(from html: String) -> [String] {
        let needleOptions: String.CompareOptions = [.caseInsensitive]
        var fragments: [String] = []
        var searchStart = html.startIndex
        let needles = ["infobox-switch-resources", "infobox-resources-", "switch-infobox"]
            + dataResourceClassNeedles(from: html)
        while searchStart < html.endIndex {
            var classRange: Range<String.Index>?
            for needle in needles {
                guard let found = html.range(
                    of: needle,
                    options: needleOptions,
                    range: searchStart..<html.endIndex
                ) else { continue }
                if classRange == nil || found.lowerBound < classRange!.lowerBound {
                    classRange = found
                }
            }
            guard let classRange else { break }
            let prefix = html[..<classRange.lowerBound]
            let divStart = prefix.range(of: "<div", options: [.backwards, .caseInsensitive])
            let tableStart = prefix.range(of: "<table", options: [.backwards, .caseInsensitive])
            let start = [divStart, tableStart].compactMap { $0 }.max(by: { $0.lowerBound < $1.lowerBound })
            guard let start else {
                searchStart = classRange.upperBound
                continue
            }
            if html[start].lowercased().hasPrefix("<table"),
               let fragment = tableFragment(in: html, from: start.lowerBound) {
                fragments.append(fragment)
                searchStart = html.index(start.lowerBound, offsetBy: fragment.count, limitedBy: html.endIndex)
                    ?? html.endIndex
            } else if let fragment = balancedDivFragment(in: html, from: start.lowerBound) {
                fragments.append(fragment)
                searchStart = html.index(start.lowerBound, offsetBy: fragment.count, limitedBy: html.endIndex)
                    ?? html.endIndex
            } else {
                searchStart = classRange.upperBound
            }
        }
        return fragments
    }

    private nonisolated static func tableFragment(in html: String, from start: String.Index) -> String? {
        let remaining = String(html[start...])
        let pattern = #"(?is)^<table\b[\s\S]*?</table>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
              let range = Range(match.range, in: remaining) else {
            return nil
        }
        return String(remaining[range])
    }

    private nonisolated static func balancedDivFragment(in html: String, from start: String.Index) -> String? {
        var depth = 0
        var index = start
        let open = "<div"
        let close = "</div"
        while index < html.endIndex {
            let remaining = html[index...]
            if remaining.lowercased().hasPrefix(open) {
                depth += 1
                index = html.index(index, offsetBy: open.count, limitedBy: html.endIndex) ?? html.endIndex
                continue
            }
            if remaining.lowercased().hasPrefix(close) {
                depth -= 1
                guard let closeEnd = remaining.range(of: ">") else { return nil }
                index = closeEnd.upperBound
                if depth == 0 {
                    return String(html[start..<index])
                }
                continue
            }
            index = html.index(after: index)
        }
        return nil
    }

    private nonisolated static func initialResourcePlan(from html: String) -> [PlannedResource] {
        var rawValues: [String] = []
        var stylesheetValues: [String] = []

        func tagMatches(_ pattern: String, in source: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return []
            }
            return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
                guard let range = Range($0.range, in: source) else { return nil }
                return String(source[range])
            }
        }

        func attribute(_ name: String, in tag: String) -> String? {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"(?:^|\s)"# + escapedName + #"\s*=\s*[\"']([^\"']+)[\"']"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: tag) else { return nil }
            return String(tag[range])
        }

        func appendImageAttributes(from tag: String) {
            for name in ["src", "data-src", "data-osrs-deferred-src", "data-original", "data-lazy-src"] {
                if let value = attribute(name, in: tag) { rawValues.append(value) }
            }
            for name in ["srcset", "data-srcset", "data-osrs-deferred-srcset", "data-lazy-srcset"] {
                if let value = attribute(name, in: tag) {
                    rawValues.append(contentsOf: srcsetURLs(from: value))
                }
            }
        }

        for tag in tagMatches(#"<img\b[^>]*>"#, in: html) {
            appendImageAttributes(from: tag)
        }
        for picture in tagMatches(#"<picture\b[^>]*>[\s\S]*?</picture\s*>"#, in: html) {
            for source in tagMatches(#"<source\b[^>]*>"#, in: picture) {
                for name in ["srcset", "data-srcset", "data-osrs-deferred-srcset", "data-lazy-srcset"] {
                    if let value = attribute(name, in: source) {
                        rawValues.append(contentsOf: srcsetURLs(from: value))
                    }
                }
            }
        }
        for tag in tagMatches(#"<video\b[^>]*>"#, in: html) {
            if let poster = attribute("poster", in: tag) { rawValues.append(poster) }
        }
        for tag in tagMatches(#"<(?:svg:)?image\b[^>]*>"#, in: html) {
            for name in ["href", "xlink:href"] {
                if let value = attribute(name, in: tag) { rawValues.append(value) }
            }
        }
        for tag in tagMatches(#"<object\b[^>]*>"#, in: html) {
            guard attribute("type", in: tag)?.lowercased().hasPrefix("image/") == true else {
                continue
            }
            if let data = attribute("data", in: tag) { rawValues.append(data) }
        }

        for tag in tagMatches(#"<link\b[^>]*>"#, in: html) {
            let relationship = attribute("rel", in: tag)?.lowercased() ?? ""
            guard relationship.split(whereSeparator: \.isWhitespace).contains("stylesheet"),
                  let href = attribute("href", in: tag) else { continue }
            stylesheetValues.append(href)
        }

        // Restrict CSS parsing to authored style attributes and <style> blocks. Text such as
        // `url(...)` inside scripts or article prose is not a rendered dependency.
        var inlineCSSFragments: [String] = []
        // Match the opening delimiter, rather than excluding both quote kinds. CSS commonly
        // uses single-quoted url(...) inside a double-quoted style attribute (and vice versa).
        let styleAttributePattern = #"\sstyle\s*=\s*(?:\"([^\"]*)\"|'([^']*)')"#
        if let regex = try? NSRegularExpression(pattern: styleAttributePattern, options: [.caseInsensitive]) {
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard match.numberOfRanges > 2 else { continue }
                let capturedRange = [1, 2]
                    .map { match.range(at: $0) }
                    .first { $0.location != NSNotFound }
                guard let capturedRange,
                      let range = Range(capturedRange, in: html) else { continue }
                inlineCSSFragments.append(String(html[range]))
            }
        }
        let styleBlockPattern = #"<style\b[^>]*>([\s\S]*?)</style\s*>"#
        if let regex = try? NSRegularExpression(pattern: styleBlockPattern, options: [.caseInsensitive]) {
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { continue }
                inlineCSSFragments.append(String(html[range]))
            }
        }

        let baseURL = URL(string: "https://oldschool.runescape.wiki/")!
        var plan = rawValues.compactMap { raw in
            normalizedNetworkURL(raw, relativeTo: baseURL).map {
                PlannedResource(url: $0, stylesheetDepth: nil)
            }
        }
        for css in inlineCSSFragments {
            plan.append(contentsOf: cssDependencies(from: css, baseURL: baseURL, importDepth: 0))
        }
        plan.append(contentsOf: stylesheetValues.compactMap { raw in
            normalizedNetworkURL(raw, relativeTo: baseURL).map {
                PlannedResource(url: $0, stylesheetDepth: 0)
            }
        })

        var seen: Set<URL> = []
        return plan.filter { seen.insert($0.url).inserted }
    }

    private nonisolated static func srcsetURLs(from value: String) -> [String] {
        // A data URI contains a comma that is payload, not a candidate separator. Embedded data
        // needs no download, so remove each complete data candidate before splitting the rest.
        let withoutEmbeddedData = value.replacingOccurrences(
            of: #"data:[^\s]+(?:\s+\d+(?:\.\d+)?[wx])?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutEmbeddedData.split(separator: ",").compactMap { candidate in
            candidate.split(whereSeparator: \.isWhitespace).first.map(String.init)
        }
    }

    @discardableResult
    static func settle(
        html: String,
        maximumConcurrency: Int = 6,
        maximumRecursiveStylesheetResources: Int = 4_096,
        downloader: @escaping Downloader
    ) async throws -> [URL] {
        precondition(maximumConcurrency > 0)
        precondition(maximumRecursiveStylesheetResources > 0)
        try Task.checkCancellation()
        var pending = initialResourcePlan(from: html)
        var seen = Set(pending.map(\.url))
        var settled: [URL] = []
        var failureCount = 0
        var recursiveStylesheetResourceCount = 0
        var cursor = 0

        while cursor < pending.count {
            try Task.checkCancellation()
            let end = min(cursor + maximumConcurrency, pending.count)
            let batch = Array(pending[cursor..<end])
            cursor = end
            try await withThrowingTaskGroup(of: (PlannedResource, Data?, Bool).self) { group in
                for item in batch {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let data = try await downloader(item.url)
                            try Task.checkCancellation()
                            return (item, data, true)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return (item, nil, false)
                        }
                    }
                }
                for try await (item, data, succeeded) in group {
                    guard succeeded else {
                        failureCount += 1
                        continue
                    }
                    settled.append(item.url)
                    guard let depth = item.stylesheetDepth, let data else { continue }
                    guard data.count <= maximumStylesheetBytes,
                          let css = String(data: data, encoding: .utf8) else {
                        failureCount += 1
                        continue
                    }
                    let dependencies = cssDependencies(
                        from: css,
                        baseURL: item.url,
                        importDepth: depth + 1
                    )
                    if depth >= maximumStylesheetDepth, !dependencies.isEmpty {
                        failureCount += 1
                        continue
                    }
                    for dependency in dependencies where seen.insert(dependency.url).inserted {
                        recursiveStylesheetResourceCount += 1
                        guard recursiveStylesheetResourceCount <= maximumRecursiveStylesheetResources else {
                            failureCount += 1
                            continue
                        }
                        pending.append(dependency)
                    }
                }
            }
        }

        try Task.checkCancellation()
        guard failureCount == 0 else {
            throw osrsOfflineResourceSettlementError.requiredResourcesFailed(count: failureCount)
        }
        return settled.sorted { $0.absoluteString < $1.absoluteString }
    }

    private nonisolated static func cssDependencies(
        from css: String,
        baseURL: URL,
        importDepth: Int
    ) -> [PlannedResource] {
        let withoutComments = css.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression
        )
        // Offline settlement intentionally owns article imagery/artwork, not fonts. Remove
        // complete @font-face blocks before scanning url(...) so their src descriptors cannot
        // pull WOFF/TTF assets into the required durable set. Imports and ordinary background
        // declarations remain eligible below.
        let artworkCSS = withoutComments.replacingOccurrences(
            of: #"@font-face\s*\{[\s\S]*?\}"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        var imports: Set<URL> = []
        let importPattern = #"@import\s+(?:url\(\s*)?[\"']?([^\"')\s;]+)"#
        if let regex = try? NSRegularExpression(pattern: importPattern, options: [.caseInsensitive]) {
            for match in regex.matches(
                in: artworkCSS,
                range: NSRange(artworkCSS.startIndex..., in: artworkCSS)
            ) where match.numberOfRanges > 1 {
                guard let range = Range(match.range(at: 1), in: artworkCSS),
                      let url = normalizedNetworkURL(String(artworkCSS[range]), relativeTo: baseURL) else {
                    continue
                }
                imports.insert(url)
            }
        }

        var result = imports.map { PlannedResource(url: $0, stylesheetDepth: importDepth) }
        let urlPattern = #"url\(\s*[\"']?([^\"')]+)[\"']?\s*\)"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) {
            for match in regex.matches(
                in: artworkCSS,
                range: NSRange(artworkCSS.startIndex..., in: artworkCSS)
            ) where match.numberOfRanges > 1 {
                guard let range = Range(match.range(at: 1), in: artworkCSS),
                      let url = normalizedNetworkURL(String(artworkCSS[range]), relativeTo: baseURL),
                      !imports.contains(url) else { continue }
                result.append(PlannedResource(url: url, stylesheetDepth: nil))
            }
        }
        return result
    }

    private nonisolated static func normalizedNetworkURL(
        _ rawValue: String,
        relativeTo baseURL: URL
    ) -> URL? {
        var value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        // A bare fragment references an element/paint server in the current document and does
        // not represent a network resource. Reject it before relative resolution; otherwise
        // removing the fragment below would manufacture a bogus base-document download.
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("/") {
            value = "https://oldschool.runescape.wiki" + value
        } else if URL(string: value)?.scheme == nil {
            guard let relative = URL(string: value, relativeTo: baseURL)?.absoluteURL else { return nil }
            value = relative.absoluteString
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        // URL fragments select a client-side view within one HTTP representation; they are
        // never transmitted to the server. Canonicalize them out before resource deduplication,
        // download, and exact-generation verification so sprite.svg#one and sprite.svg#two share
        // the same durable cache identity.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }
}

struct osrsDeferredMapPreloadState {
    private var htmlByGeneration: [Int: String] = [:]
    var pendingGenerationCount: Int { htmlByGeneration.count }

    mutating func stage(_ html: String, generation: Int) {
        htmlByGeneration = [generation: html]
    }

    mutating func takeAfterWebKitReady(generation: Int) -> String? {
        htmlByGeneration.removeValue(forKey: generation)
    }

    mutating func cancelAll() {
        htmlByGeneration.removeAll()
    }
}

@MainActor
class ArticleViewModel: NSObject, ObservableObject {
    @Published var isLoading: Bool = false
    @Published var pendingYouTubeEmbedURL: URL?
    @Published var needsContentProcessRecovery: Bool = false
    /// Incremented when the on-screen WKWebView must be rebuilt after a compositor-blank resume.
    @Published var webViewRenderGeneration: Int = 0
    /// Cancels a stale delayed foreground probe when another foreground cycle starts.
    private var foregroundDocumentProbeGeneration = 0

    /// True when this view model still owns a rendered article document. Returning
    /// from background must not start a new network load just because SwiftUI
    /// re-ran `onAppear`.
    var hasReusableRenderedArticle: Bool {
        !isLoading &&
            !isRefreshing &&
            !needsContentProcessRecovery &&
            webView != nil &&
            webView?.url != nil &&
            webView?.url?.absoluteString != "about:blank"
    }

    /// Reappear must reload a terminated or empty document, including after a
    /// prewarm adopt onto a dead WKWebView, without skipping a healthy page.
    var shouldReloadArticleOnReappear: Bool {
        if needsContentProcessRecovery {
            return true
        }
        if isLoading || isRefreshing {
            return false
        }
        return webView == nil
            || webView?.url == nil
            || webView?.url?.absoluteString == "about:blank"
    }

    private static let osrsRenderedDocumentHealthScript = """
    (function() {
        try {
            var body = document.body;
            if (!body) return { ok: false, reason: 'nobody' };
            var htmlLen = (body.innerHTML || '').length;
            var textLen = ((body.innerText || body.textContent || '').replace(/\\s+/g, '')).length;
            var hasArticle = !!(
                document.getElementById('mw-content-text') ||
                document.getElementById('bodyContent') ||
                document.getElementById('content')
            );
            var style = window.getComputedStyle(body);
            var hidden = style.visibility === 'hidden' || style.display === 'none';
            return {
                ok: !hidden && htmlLen > 32 && (textLen > 0 || hasArticle || !!body.querySelector('img, table, p')),
                htmlLen: htmlLen,
                textLen: textLen
            };
        } catch (e) {
            return { ok: false, reason: String(e) };
        }
    })()
    """

    private var lastForegroundRecoveryAt: TimeInterval = 0

    func recoverRenderedDocumentAfterBackground() {
        let now = Date().timeIntervalSince1970
        if now - lastForegroundRecoveryAt < 1 {
            wakeRenderedDocumentAfterBackground()
            return
        }
        lastForegroundRecoveryAt = now
        // A healthy DOM can still sit behind a blank window compositor.
        // Rebuild WebKit only when the document probe says the page is gone.
        wakeRenderedDocumentAfterBackground()
    }

    func markNeedsContentProcessRecovery(rebuildWebView: Bool = false) {
        if rebuildWebView {
            webViewRenderGeneration += 1
        }
        isRefreshing = false
        needsContentProcessRecovery = true
    }

    /// WKWebView can go blank after backgrounding without firing the terminate callback.
    /// Probe the live document on foreground and recover when it is empty.
    func wakeRenderedDocumentAfterBackground() {
        guard let webView else {
            markNeedsContentProcessRecovery(rebuildWebView: true)
            return
        }
        webView.isHidden = false
        webView.alpha = 1
        webView.scrollView.isHidden = false
        webView.scrollView.alpha = 1
        webView.scrollView.layer.setNeedsDisplay()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        let offset = webView.scrollView.contentOffset
        webView.scrollView.setContentOffset(
            CGPoint(x: offset.x, y: offset.y + 1),
            animated: false
        )
        webView.scrollView.setContentOffset(offset, animated: false)
        webView.evaluateJavaScript(
            "void(document.body && (document.body.style.visibility = 'visible')); window.scrollBy(0,1); window.scrollBy(0,-1);"
        )
        probeRenderedDocumentHealthOnForeground(force: true)
    }

    func probeRenderedDocumentHealthOnForeground(force: Bool = false) {
        if !force, isLoading || isRefreshing {
            return
        }
        if shouldReloadArticleOnReappear {
            markNeedsContentProcessRecovery()
            return
        }
        guard let webView else {
            markNeedsContentProcessRecovery(rebuildWebView: true)
            return
        }
        foregroundDocumentProbeGeneration += 1
        let generation = foregroundDocumentProbeGeneration
        webView.evaluateJavaScript(Self.osrsRenderedDocumentHealthScript) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard generation == self.foregroundDocumentProbeGeneration else { return }
                if error != nil {
                    self.markNeedsContentProcessRecovery(rebuildWebView: true)
                    return
                }
                let ok: Bool
                if let dict = result as? [String: Any] {
                    ok = (dict["ok"] as? NSNumber)?.boolValue ?? (dict["ok"] as? Bool) ?? false
                } else if let flag = result as? Bool {
                    ok = flag
                } else if let number = result as? NSNumber {
                    ok = number.boolValue
                } else {
                    ok = false
                }
                if !ok {
                    print("⚠️ ArticleViewModel: Foreground document probe found a blank article; recovering")
                    self.markNeedsContentProcessRecovery(rebuildWebView: true)
                    return
                }
                self.probeRenderedSnapshotIfNeeded(webView, generation: generation)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard generation == self.foregroundDocumentProbeGeneration else { return }
            guard !self.needsContentProcessRecovery else { return }
            self.probeRenderedSnapshotIfNeeded(webView, generation: generation)
        }
    }

    /// DOM can stay healthy while WKWebView's compositor is a uniform theme color.
    private func probeRenderedSnapshotIfNeeded(_ webView: WKWebView, generation: Int) {
        webView.takeSnapshot(with: nil) { [weak self] image, error in
            Task { @MainActor in
                guard let self else { return }
                guard generation == self.foregroundDocumentProbeGeneration else { return }
                if error != nil || image == nil || Self.osrsSnapshotLooksCompositorBlank(image) {
                    if self.isLoading && !self.articleRevealedForWarm {
                        return
                    }
                    print("⚠️ ArticleViewModel: Foreground snapshot found a compositor-blank article; recovering")
                    self.markNeedsContentProcessRecovery(rebuildWebView: true)
                }
            }
        }
    }

    static func osrsSnapshotLooksCompositorBlank(_ image: UIImage?) -> Bool {
        guard let image else { return true }
        let sample = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(sample, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: sample))
        guard let tiny = UIGraphicsGetImageFromCurrentImageContext()?.cgImage,
              let data = tiny.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return true
        }
        let count = tiny.width * tiny.height
        guard count > 0 else { return true }
        var minLuminance = 255
        var maxLuminance = 0
        for index in 0..<count {
            let offset = index * 4
            let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
        }
        return (maxLuminance - minLuminance) < 10
    }
    @Published var loadingProgress: Double = 0.0
    @Published var loadingProgressText: String? = nil
    @Published var errorMessage: String?
    @Published var isRefreshing: Bool = false
    @Published var pageTitle: String = ""
    @Published var isBookmarked: Bool = false
    @Published var hasTableOfContents: Bool = false
    @Published var tableOfContents: [TableOfContentsSection] = []

    // Bottom bar state management - matching Android PageActionBarManager
    @Published var saveState: osrsArticleBottomBarSaveState = .notSaved
    @Published var saveProgress: Double = 0.0

    private(set) var pageUrl: URL
    private(set) var pageTitle_: String?
    let pageId: Int?
    private(set) var collapseTablesEnabled: Bool
    private(set) var wrapTableCellsEnabled: Bool = false
    private(set) var snippet_: String?  // Metadata for rich history display
    private(set) var thumbnailUrl_: URL?  // Metadata for rich history display
    let excludeFromHistory: Bool  // Exclude from history tracking (for preview generation)
    private(set) var savedCachePageId: String?

    weak var webView: WKWebView?
    private var adoptedPreRenderedDocument = false
#if DEBUG
    private var didForceArticleReloadNetworkFailureForUITests = false
#endif
    private var cancellables = Set<AnyCancellable>()
    private var progressObserver: NSKeyValueObservation?
    private var currentLoadTask: Task<Void, Never>?
    private var currentLoadGeneration = 0
    private var webKitReadyGeneration: Int?
    private var javaScriptReadyGeneration: Int?
    private var completedLoadGeneration: Int?
    private var webKitNavigationGenerations: [ObjectIdentifier: Int] = [:]
    private var readinessTimeoutWorkItem: DispatchWorkItem?
    private var reloadTimeoutWorkItem: DispatchWorkItem?
    private var refreshTimeoutWorkItem: DispatchWorkItem?
    private var deferredRefreshWorkItem: DispatchWorkItem?
    // FREEZE FIX: Defer heavy initialization - create these async to avoid blocking main thread
    private var contentLoader: osrsPageContentLoader?
    private let savedPagesRepository = SavedPagesRepository()
    private let historyRepository = HistoryRepository()
    private var proxyCacheSessionToken: ProxyCacheSessionToken?
    private var passiveCachePageId: String?
    private var passiveCachePreparationTask: Task<Void, Never>?
    private var passiveCachePreparationGeneration: UInt64 = 0
    private var articleIsVisible = false
    private var passiveCachingAllowedWhileVisible = false
    private var accessibilityReflowEnabled = false
    private var accessibilityTextScale: CGFloat = 1.0
    private var articleTextScale: CGFloat = 1.0
    private var lastTableOfContentsHTML: String?
    private var lastLoadedArticleHTML: String?
    private var forceNextDocumentReload = false
    private var articlePipelineLoads: [Int: (identity: osrsArticleDocumentIdentity, startedAt: Date)] = [:]
    private var resolvedPageTitleForHistory: String?
    private var resolvedPageUrlForHistory: URL?
    var navigateToInternalArticle: ((URL) -> Void)?
    private var routedObservedArticleNavigationURLs = Set<String>()
    private var renderedArticleIdentityProbe: Timer?
    private var renderedArticleIdentityProbeAttempts = 0
    private var deferredMapPreloadState = osrsDeferredMapPreloadState()
    private var deferredMapPreloadTask: Task<Void, Never>?
    private var liveAssetWarmer: osrsLiveArticleAssetWarmer?
    private var liveAssetWarmTask: Task<Void, Never>?
    private var firstViewOpenAt: CFAbsoluteTime?
    private var pendingFirstViewComplete = false
    private var firstViewCompletePosted = false
    private var pendingArticleLoadTheme: (any osrsThemeProtocol)?
    private var pendingArticleLoadIsReload = false
    private var articleRevealedForWarm = false

    // TIMING MEASUREMENT: Track progress completion vs page visibility delay
    var progressCompletionTime: Date?
    private var pageVisibilityTime: Date?
    @Published var lastMeasuredDelay: TimeInterval? = nil

    init(pageUrl: URL, pageTitle: String? = nil, pageId: Int? = nil, snippet: String? = nil, thumbnailUrl: URL? = nil, collapseTablesEnabled: Bool = true, excludeFromHistory: Bool = false) {
        self.pageUrl = pageUrl
        self.pageTitle_ = pageTitle
        self.pageId = pageId
        self.collapseTablesEnabled = collapseTablesEnabled
        self.snippet_ = snippet
        self.thumbnailUrl_ = thumbnailUrl
        self.excludeFromHistory = excludeFromHistory
        super.init()
        osrsPreparedArticleWebViewStore.shared.pin(
            identity: osrsArticleDocumentIdentity(pageURL: pageUrl, pageTitle: pageTitle).value,
            foreground: true
        )
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverRenderedDocumentAfterBackground()
            }
            .store(in: &cancellables)
        print("🏗️ ArticleViewModel: Lightweight init completed for '\(pageTitle ?? "unknown")' - heavy loading deferred")
    }

    func bindSavedCachePageId(_ pageId: String?) {
        savedCachePageId = pageId
    }

    private func resolvedSavedCachePageId() -> String? {
        savedCachePageId ?? currentSavedCachePageIdForArticle()
    }

    private func readyToPaintHTML(theme: any osrsThemeProtocol) -> String? {
        guard #available(iOS 17.0, *),
              let pageId = resolvedSavedCachePageId(),
              let stored = ProxyInterceptorService.shared.readPaintHTML(pageId: pageId),
              osrsSavedPaintHtml.isFullDocument(stored)
        else {
            return nil
        }
        return applyingLivePaintPreferences(stored, theme: theme)
    }

    private func applyingLivePaintPreferences(_ html: String, theme: any osrsThemeProtocol) -> String {
        let scale = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(min(max(articleTextScale, 0.85), 1.40))
        )
        let chromeClearance = Int(
            (osrsSearchControlGeometry.compactHeight + osrsOverlayChromeMetrics.pairedEdgeGap + 8).rounded()
        )
        let bottomChrome = Int(
            (osrsOverlayChromeMetrics.floatingBarHeight + osrsOverlayChromeMetrics.pairedEdgeGap + 24).rounded()
        )
        return osrsSavedPaintHtml.applyingLivePreferences(
            html,
            isDark: theme is osrsDarkTheme,
            wrapEnabled: wrapTableCellsEnabled,
            scaleCssValue: scale,
            chromeClearancePx: chromeClearance,
            bottomChromePx: bottomChrome,
            safeAreaTopPx: Int(osrsOverlayChromeMetrics.topInset.rounded()),
            safeAreaBottomPx: Int(osrsOverlayChromeMetrics.bottomInset.rounded())
        )
    }

    private func persistPaintHTML(
        bodyHTML: String,
        displayTitle: String,
        canonicalTitle: String,
        pageId: String? = nil
    ) {
        guard #available(iOS 17.0, *), let pageId = pageId ?? resolvedSavedCachePageId() else { return }
        let builder = osrsPageHtmlBuilder()
        var html = builder.buildFullHtmlDocument(
            title: displayTitle,
            bodyContent: bodyHTML,
            theme: osrsLightTheme(),
            collapseTablesEnabled: collapseTablesEnabled,
            includeAssetLinks: true,
            articleTextScale: articleTextScale,
            wrapTableCellsEnabled: wrapTableCellsEnabled,
            canonicalTitle: canonicalTitle,
            inlineFirstPaintCss: true,
            bakeChromeInsets: false
        )
        html = osrsSavedPaintHtml.inlineLinkedFirstPaintCss(html) { path in
            builder.loadAssetText(path)
        }
        ProxyInterceptorService.shared.writePaintHTML(pageId: pageId, html: html)
    }

    private func lazyMaterializePaintHTMLIfNeeded(
        bodyHTML: String,
        displayTitle: String,
        canonicalTitle: String,
        theme: any osrsThemeProtocol
    ) {
        guard #available(iOS 17.0, *), let pageId = resolvedSavedCachePageId() else { return }
        if ProxyInterceptorService.shared.readPaintHTML(pageId: pageId) == nil {
            persistPaintHTML(
                bodyHTML: bodyHTML,
                displayTitle: displayTitle,
                canonicalTitle: canonicalTitle
            )
        }
        _ = theme
    }

    func loadArticleDestination(_ destination: ArticleDestination, theme: any osrsThemeProtocol) {
        let previousURL = pageUrl
        pageUrl = destination.url
        pageTitle_ = destination.title
        snippet_ = destination.snippet
        thumbnailUrl_ = destination.thumbnailUrl
        pageTitle = destination.title ?? extractTitleFromUrl(destination.url)
        hasTableOfContents = false
        tableOfContents = []
        isBookmarked = false

        if articleIsVisible, passiveCachingAllowedWhileVisible {
            beginPassiveCachingSessionIfNeeded(forceRefresh: true)
        }

        print("🔄 ArticleViewModel: Rebinding visible article from \(previousURL.absoluteString) to active destination \(destination.url.absoluteString)")
        loadArticle(theme: theme, isReload: true)
    }

    nonisolated static func makeParseRequestURL(pageTitle: String) -> URL? {
        osrsWikiParseRequest.url(page: pageTitle)
    }

    static func articleURL(forResolvedTitle title: String) -> URL? {
        let pathTitle = title.replacingOccurrences(of: " ", with: "_")
        guard let encodedTitle = pathTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://oldschool.runescape.wiki/w/\(encodedTitle)")
    }

    static func articleNavigationDecision(for url: URL) -> osrsArticleNavigationDecision {
        if osrsArticleLinkRouter.isFloorNumberingSettingsURL(url) {
            return .floorNumberingSettings
        }

        if let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) {
            return .appArticle(articleURL)
        }

        if let externalWikiURL = osrsArticleLinkRouter.externalWikiURLForNonArticleAppAssetURL(url) {
            return .external(externalWikiURL)
        }

        if shouldOpenExternallyForArticleNavigation(url) {
            return .external(url)
        }

        return .allow
    }

    /// Embed iframes (YouTube, etc.) load as non-main-frame `.other` navigations.
    /// Opening those in Safari made the player invisible and felt like a phantom tap.
    /// Open the system browser only for an explicit user-activated main-frame link.
    static func osrsExternalNavigationAction(
        navigationType: WKNavigationType,
        isMainFrame: Bool
    ) -> osrsExternalNavigationAction {
        if !isMainFrame {
            return .allowInWebView
        }
        if navigationType == .linkActivated {
            return .openInBrowser
        }
        return .cancelSilently
    }

    static func osrsShouldUseWebViewArticleHistory(currentURL: URL?, pageURL: URL) -> Bool {
        osrsShouldPromoteWebViewArticleNavigation(candidateURL: currentURL, pageURL: pageURL)
    }

    static func osrsShouldPromoteWebViewArticleNavigation(candidateURL: URL?, pageURL: URL) -> Bool {
        guard let candidateURL,
              let currentIdentity = osrsArticleHistoryIdentity(for: candidateURL),
              let pageIdentity = osrsArticleHistoryIdentity(for: pageURL) else {
            return false
        }

        return currentIdentity != pageIdentity
    }

    private static func osrsArticleHistoryIdentity(for url: URL) -> String? {
        guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url),
              var components = URLComponents(url: articleURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = nil

        let scheme = components.scheme?.lowercased() ?? ""
        let host = components.host?.lowercased() ?? ""
        let decodedPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
        let decodedQuery = components.percentEncodedQuery?.removingPercentEncoding ?? components.query ?? ""

        return "\(scheme)://\(host)\(decodedPath)?\(decodedQuery)"
    }

    nonisolated static func decodeParsePayload(_ data: Data, requestedTitle: String? = nil) throws -> osrsArticleParsePayload {
        try osrsArticlePayloadPreparer.decode(data, requestedTitle: requestedTitle)
    }

    // FREEZE FIX: Async content loader initialization - following Android's coroutineScope.launch pattern
    private func initializeContentLoaderAsync() async -> osrsPageContentLoader {
        return await withCheckedContinuation { continuation in
            // Move to background thread for heavy initialization
            Task.detached(priority: .userInitiated) {
                print("🔨 ArticleViewModel: Creating content loader on background thread")
                let loader = osrsPageContentLoader()
                print("✅ ArticleViewModel: Content loader created successfully")
                continuation.resume(returning: loader)
            }
        }
    }

    // FREEZE FIX: Get content loader async, creating it only when needed
    private func getContentLoader() async -> osrsPageContentLoader {
        if let existingLoader = contentLoader {
            return existingLoader
        }

        let newLoader = await initializeContentLoaderAsync()
        await MainActor.run {
            self.contentLoader = newLoader
        }
        return newLoader
    }

    func setAccessibilityReflowEnabled(_ enabled: Bool, textScale: CGFloat = 1.0) {
        accessibilityReflowEnabled = enabled
        accessibilityTextScale = textScale
        applyAccessibilityReflow(to: webView)
    }

    func setArticleTextScale(_ scale: CGFloat) {
        articleTextScale = min(max(scale, 0.85), 1.40)
        applyArticleTextScale(to: webView)
    }

    func applyFloorNumberingConvention(_ convention: osrsArticleFloorConvention) {
        applyFloorNumberingConvention(convention, to: webView)
        if let html = lastTableOfContentsHTML {
            applyTableOfContents(from: html, convention: convention)
        }
    }

    func setCollapseTablesEnabled(_ enabled: Bool) {
        collapseTablesEnabled = enabled
    }

    func applyWrapTableCells(_ enabled: Bool) {
        wrapTableCellsEnabled = enabled
        applyWrapTableCells(enabled, to: webView)
    }

    private func applyArticleTextScale(to webView: WKWebView?) {
        guard let webView else { return }
        let scaleLiteral = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(articleTextScale)
        )
        webView.evaluateJavaScript("""
            (function() {
                document.documentElement.style.setProperty(
                    '--osrs-article-user-text-scale',
                    '\(scaleLiteral)'
                );
            })();
        """)
    }

    private func applyFloorNumberingConvention(
        _ convention: osrsArticleFloorConvention,
        to webView: WKWebView?
    ) {
        guard let webView else { return }
        let bodyClass = convention.bodyClass
        webView.evaluateJavaScript("""
            (function() {
                var body = document.body;
                if (!body) return;
                body.classList.remove('floornumber-setting-gb', 'floornumber-setting-us');
                body.classList.add('\(bodyClass)');
            })();
        """)
    }

    private func applyWrapTableCells(_ enabled: Bool, to webView: WKWebView?) {
        guard let webView else { return }
        let enabledLiteral = enabled ? "true" : "false"
        webView.evaluateJavaScript("""
            (function() {
                var enabled = \(enabledLiteral);
                if (typeof window.osrsApplyTableCellWrapPreference === 'function') {
                    window.osrsApplyTableCellWrapPreference(enabled);
                    return;
                }
                [document.documentElement, document.body].forEach(function(element) {
                    if (element) {
                        element.classList.toggle('osrs-table-cells-wrap', enabled);
                    }
                });
            })();
        """)
    }

    private func applyAccessibilityReflow(to webView: WKWebView?) {
        guard let webView else { return }
        let enabledLiteral = accessibilityReflowEnabled ? "true" : "false"
        let scaleLiteral = Self.accessibilityScaleLiteral(accessibilityTextScale)
        webView.evaluateJavaScript("""
            (function() {
                var enabled = \(enabledLiteral);
                var textScale = \(scaleLiteral);
                document.documentElement.style.setProperty('--osrs-article-text-scale', String(textScale));
                [document.documentElement, document.body].forEach(function(element) {
                    if (element) {
                        element.classList.toggle('osrs-accessibility-reflow', enabled);
                    }
                });
            })();
        """)
    }

    nonisolated static func accessibilityScaleLiteral(_ scale: CGFloat) -> String {
        String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(scale)
        )
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        setupWebViewObservers()

        // Configure the WebView once. Cache ownership is activated separately by visibility so
        // an iOS 26 TabView retaining an offscreen article cannot own later speculative traffic.
        if #available(iOS 17.0, *) {
            let configured = ProxyInterceptorService.shared.configureWebViewForProxyInterception(webView)
            if configured {
                if let assetHandler = webView.configuration.urlSchemeHandler(forURLScheme: "app-assets") as? IOSAssetHandler {
                    ProxyInterceptorService.shared.registerAssetHandler(assetHandler)
                }
            } else {
                print("⚠️ ArticleViewModel: Failed to enable lazy caching - falling back to traditional approach")
            }
        }

        beginPassiveCachingSessionIfNeeded()

        checkIfPageIsSaved()
        if let theme = pendingArticleLoadTheme {
            loadArticle(theme: theme, isReload: pendingArticleLoadIsReload)
        }
    }

    func adoptPreRenderedWebView(_ webView: WKWebView) {
        adoptedPreRenderedDocument = true
        setWebView(webView)
    }

    /// SwiftUI may retain an ArticleView and its WebView while another root tab is selected.
    /// Tie the singleton proxy/save owner to geometric screen visibility instead of object life.
    func setArticleVisibility(_ isVisible: Bool, allowsPassiveCaching: Bool) {
        articleIsVisible = isVisible
        passiveCachingAllowedWhileVisible = allowsPassiveCaching
        if isVisible, allowsPassiveCaching {
            beginPassiveCachingSessionIfNeeded()
        } else {
            suspendPassiveCachingSession()
        }
    }

    private func beginPassiveCachingSessionIfNeeded(forceRefresh: Bool = false) {
        guard articleIsVisible, passiveCachingAllowedWhileVisible else { return }
        guard #available(iOS 17.0, *), let webView else { return }
        if (proxyCacheSessionToken != nil || passiveCachePreparationTask != nil), !forceRefresh {
            return
        }

        let pageId = Self.generatePageIdFromURL(pageUrl)
        suspendPassiveCachingSession(removingPassiveCache: passiveCachePageId != pageId)
        passiveCachePageId = pageId
        passiveCachePreparationGeneration &+= 1
        let preparationGeneration = passiveCachePreparationGeneration
        passiveCachePreparationTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            let token = await ProxyInterceptorService.shared.enablePassiveCachingMode(pageId: pageId)
            if self.passiveCachePreparationGeneration == preparationGeneration {
                self.passiveCachePreparationTask = nil
            }
            guard let token,
                  !Task.isCancelled,
                  self.passiveCachePreparationGeneration == preparationGeneration,
                  self.articleIsVisible,
                  self.passiveCachingAllowedWhileVisible,
                  self.passiveCachePageId == pageId else {
                if let token {
                    ProxyInterceptorService.shared.disableMode(owner: token)
                }
                return
            }

            self.proxyCacheSessionToken = token
            if let assetHandler = webView?.configuration.urlSchemeHandler(forURLScheme: "app-assets") as? IOSAssetHandler {
                assetHandler.enableOfflineSaveMode(pageId: pageId)
            }
            print("✅ ArticleViewModel: Visible-article passive cache session enabled for \(pageId)")
            self.startLiveArticleAssetWarmIfNeeded()
        }
    }

    private func suspendPassiveCachingSession(removingPassiveCache: Bool = true) {
        stopLiveArticleAssetWarm()
        passiveCachePreparationGeneration &+= 1
        passiveCachePreparationTask?.cancel()
        passiveCachePreparationTask = nil
        if #available(iOS 17.0, *), let token = proxyCacheSessionToken {
            ProxyInterceptorService.shared.disableMode(owner: token)
            proxyCacheSessionToken = nil
        }
        if removingPassiveCache, #available(iOS 17.0, *), let passiveCachePageId {
            // Passive browsing data is speculative and visibility-owned. Explicit saved
            // namespaces use repository UUIDs and are never removed by this lifecycle cleanup.
            self.passiveCachePageId = nil
            Task {
                await ProxyInterceptorService.shared.removeCachedResponses(pageId: passiveCachePageId)
            }
        }
        if let assetHandler = webView?.configuration.urlSchemeHandler(forURLScheme: "app-assets") as? IOSAssetHandler {
            assetHandler.disableOfflineSaveMode()
        }
    }

    /// Generate a consistent page ID from URL for cache key management
    nonisolated static func generatePageIdFromURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if let scheme = components?.scheme { components?.scheme = scheme.lowercased() }
        if let host = components?.host { components?.host = host.lowercased() }
        if let queryItems = components?.queryItems {
            components?.queryItems = queryItems.sorted {
                if $0.name == $1.name { return ($0.value ?? "") < ($1.value ?? "") }
                return $0.name < $1.name
            }
        }
        let canonical = components?.string ?? url.absoluteString
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "browsing_\(digest)"
    }

    func promoteLiveArticleAssets(_ rawValues: [String]) {
        let urls = rawValues.compactMap(osrsOfflineArticleResourceSettlement.networkURL(from:))
        guard !urls.isEmpty else { return }
        liveAssetWarmer?.promote(urls)
    }

    func noteBackgroundWorkUserInteraction() {
        osrsBackgroundWorkGate.shared.noteUserInteraction()
    }

    func markFirstViewComplete() {
        if firstViewCompletePosted {
            return
        }
        guard let started = firstViewOpenAt else {
            pendingFirstViewComplete = true
            return
        }
        firstViewCompletePosted = true
        firstViewOpenAt = nil
        pendingFirstViewComplete = false
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        NSLog("osrsFirstViewComplete elapsedMs=%d", elapsedMs)
    }

    private func notifyAdoptedFirstViewComplete(_ webView: WKWebView) {
        markFirstViewComplete()
        webView.evaluateJavaScript(
            "window.osrsNotifyFirstViewComplete && window.osrsNotifyFirstViewComplete()"
        )
    }

    private func startLiveArticleAssetWarmIfNeeded() {
        guard articleRevealedForWarm,
              passiveCachingAllowedWhileVisible,
              let pageId = proxyCacheSessionToken?.pageId,
              liveAssetWarmTask == nil else { return }
        let html = lastLoadedArticleHTML ?? lastTableOfContentsHTML ?? ""
        guard !html.isEmpty else { return }
        let warmer = osrsLiveArticleAssetWarmer(
            pageId: pageId,
            isCached: { url in
                await ProxyInterceptorService.shared.hasPersistedResponseAsync(pageId: pageId, url: url)
            },
            fetch: { url in
                _ = try? await NetworkManager.shared.performDataRequest(url: url, retryCount: 0)
            }
        )
        liveAssetWarmer = warmer
        liveAssetWarmTask = Task.detached(priority: .utility) { [weak self] in
            await warmer.warm(html: html)
            await MainActor.run {
                guard let self, self.liveAssetWarmer === warmer else { return }
                self.liveAssetWarmTask = nil
            }
        }
    }

    private func stopLiveArticleAssetWarm() {
        liveAssetWarmTask?.cancel()
        liveAssetWarmTask = nil
        liveAssetWarmer?.cancel()
        liveAssetWarmer = nil
    }

    private func setupWebViewObservers() {
        guard let webView = webView else { return }

        // Smart progress mapping - embed WebKit's automatic progress into total progress phases
        // This matches Android's approach: map WebView 0-100% to appropriate phase ranges
        progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.updateProgressFromWebKit(webView.estimatedProgress)
            }
        }
    }

    // Smart progress mapping matching Android's implementation
    func updateProgressFromWebKit(_ webKitProgress: Double) {
        let webKitPercent = Int(webKitProgress * 100)
        let timestamp = Date()
        let timeString = DateFormatter.timeFormatter.string(from: timestamp)

        if isLoading {
            // Map WebKit progress to appropriate phase based on current loading stage
            let mappedProgress: Double
            let progressText: String

            if webKitPercent < 10 {
                // Initial loading phase: 0-10% WebKit -> 5-15% total
                mappedProgress = 0.05 + (webKitProgress * 0.1)
                progressText = "Starting download..."
            } else if webKitPercent < 50 {
                // Content fetching phase: 10-50% WebKit -> 15-50% total
                mappedProgress = 0.15 + ((webKitProgress - 0.1) * 0.875) // 0.875 = (0.5-0.15)/(0.5-0.1)
                progressText = "Downloading content..."
            } else if webKitPercent < 95 {
                // Rendering phase: 50-95% WebKit -> 50-95% total
                mappedProgress = 0.5 + ((webKitProgress - 0.5) * 1.0)
                progressText = "Rendering page..."
            } else {
                // ANDROID PARITY: Cap at 95% until JavaScript signals content ready
                mappedProgress = 0.95
                progressText = "Finalizing content..."
            }

            self.loadingProgress = mappedProgress
            self.loadingProgressText = progressText

            // ANDROID PARITY: Don't complete on WebKit 100% - wait for JavaScript signal
            if webKitProgress >= 1.0 {
                // TIMING MEASUREMENT: Record when WebKit completes (not final completion)
                self.progressCompletionTime = timestamp
                print("📊 [\(timeString)] 🔴 WEBKIT COMPLETE: WebKit reached 100%, waiting for JavaScript content readiness...")

                // Progress stays at 95% and loading continues until "StylingScriptsComplete"
                self.loadingProgress = 0.95
                self.loadingProgressText = "Finalizing content..."
                self.isLoading = true
            } else {
                self.isLoading = true
            }

            print("📊 [\(timeString)] Progress mapping: WebKit \(Int(webKitProgress * 100))% -> Total \(Int(mappedProgress * 100))% (\(progressText))")
        }
    }

    private func beginArticleLoad() -> Int {
        if let activePipeline = articlePipelineLoads.removeValue(forKey: currentLoadGeneration) {
            Task {
                await osrsArticleDocumentCoordinator.shared.recordNavigationCancellation(
                    identity: activePipeline.identity
                )
            }
        }
        currentLoadTask?.cancel()
        currentLoadTask = nil
        articleRevealedForWarm = false
        stopLiveArticleAssetWarm()
        readinessTimeoutWorkItem?.cancel()
        reloadTimeoutWorkItem?.cancel()
        refreshTimeoutWorkItem?.cancel()
        deferredRefreshWorkItem?.cancel()
        deferredMapPreloadTask?.cancel()
        deferredMapPreloadTask = nil
        deferredMapPreloadState.cancelAll()
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
        renderedArticleIdentityProbeAttempts = 0

        currentLoadGeneration += 1
        firstViewCompletePosted = false
        firstViewOpenAt = CFAbsoluteTimeGetCurrent()
        if pendingFirstViewComplete {
            markFirstViewComplete()
        }
        osrsFirstViewPrewarmStore.shared.pin(
            identity: osrsArticleDocumentIdentity(pageURL: pageUrl, pageTitle: pageTitle).value
        )
        webKitReadyGeneration = nil
        javaScriptReadyGeneration = nil
        completedLoadGeneration = nil
        webKitNavigationGenerations.removeAll()
        routedObservedArticleNavigationURLs.removeAll()

        let generation = currentLoadGeneration
        print("🧭 ArticleViewModel: Starting load generation \(generation)")
        if !adoptedPreRenderedDocument {
            webView?.stopLoading()
        }
        return generation
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == currentLoadGeneration
    }

    /// Navigation-away must not leave parsing, WebKit, or readiness callbacks competing with Home.
    func cancelActiveWorkForNavigation() {
        articleIsVisible = false
        articleRevealedForWarm = false
        stopLiveArticleAssetWarm()
        suspendPassiveCachingSession()
        if let activePipeline = articlePipelineLoads.removeValue(forKey: currentLoadGeneration) {
            Task {
                await osrsArticleDocumentCoordinator.shared.recordNavigationCancellation(
                    identity: activePipeline.identity
                )
            }
        }
        currentLoadTask?.cancel()
        currentLoadTask = nil
        currentLoadGeneration += 1
        readinessTimeoutWorkItem?.cancel()
        reloadTimeoutWorkItem?.cancel()
        refreshTimeoutWorkItem?.cancel()
        deferredRefreshWorkItem?.cancel()
        deferredMapPreloadTask?.cancel()
        deferredMapPreloadTask = nil
        deferredMapPreloadState.cancelAll()
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
        webView?.stopLoading()
        isLoading = false
        isRefreshing = false
        pendingFirstViewComplete = false
        firstViewCompletePosted = false
        firstViewOpenAt = nil
    }

    private func bindWebKitNavigation(_ navigation: WKNavigation?, to generation: Int) {
        guard let navigation = navigation else {
            print("⚠️ ArticleViewModel: WebKit did not return a navigation for generation \(generation)")
            return
        }

        webKitNavigationGenerations[ObjectIdentifier(navigation)] = generation
        print("🧭 ArticleViewModel: Bound WebKit navigation to generation \(generation)")
    }

    private func boundGeneration(for navigation: WKNavigation?) -> Int? {
        guard let navigation = navigation else {
#if DEBUG
            return currentLoadGeneration
#else
            return nil
#endif
        }

        return webKitNavigationGenerations[ObjectIdentifier(navigation)]
    }

    private func clearBoundWebKitNavigation(_ navigation: WKNavigation?) {
        guard let navigation = navigation else { return }
        webKitNavigationGenerations.removeValue(forKey: ObjectIdentifier(navigation))
    }

    private func htmlWithLoadGeneration(_ html: String, generation: Int) -> String {
        let generationScript = """
        <script>window.__osrsArticleLoadGeneration = \(generation);</script>
        """

        if let headEnd = html.range(of: "</head>", options: [.caseInsensitive]) {
            var htmlWithGeneration = html
            htmlWithGeneration.insert(contentsOf: generationScript, at: headEnd.lowerBound)
            return htmlWithGeneration
        }

        return generationScript + html
    }

    func loadArticle(theme: any osrsThemeProtocol = osrsLightTheme(), isReload: Bool = false) {
        guard webView != nil else {
            pendingArticleLoadTheme = theme
            pendingArticleLoadIsReload = isReload
            print("❌ ArticleViewModel: WebView not set")
            return
        }
        pendingArticleLoadTheme = nil
        let loadGeneration = beginArticleLoad()
        if adoptedPreRenderedDocument, let webView {
            notifyAdoptedFirstViewComplete(webView)
        }
        let skipPaintOpen = isReload || forceNextDocumentReload
        let paintHTML = skipPaintOpen ? nil : readyToPaintHTML(theme: theme)
        let paintOpenStarted = CFAbsoluteTimeGetCurrent()

        // Android parity: Use blank overlay approach for all reloads (manual and automatic)
        if isReload {
            isRefreshing = true
            loadingProgressText = "Refreshing page..."
        } else if paintHTML != nil {
            isLoading = false
            loadingProgressText = nil
        } else {
            isLoading = true
        }
        errorMessage = nil
        resolvedPageTitleForHistory = nil
        resolvedPageUrlForHistory = nil

        // DIAGNOSTIC LOGGING: Enhanced URL and parameter analysis
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🚀 LOADING STARTED: Beginning article load process")
        print("📊 [\(timeString)] 📋 LOAD PARAMS: pageUrl=\(pageUrl), pageTitle=\(pageTitle_ ?? "nil"), pageId=\(pageId?.description ?? "nil")")
        print("🛠️ DIAGNOSTIC: Detailed URL analysis:")
        print("  - Full URL: \(pageUrl.absoluteString)")
        print("  - URL Scheme: \(pageUrl.scheme ?? "nil")")
        print("  - URL Host: \(pageUrl.host ?? "nil")")
        print("  - URL Path: \(pageUrl.path)")
        print("  - URL Query: \(pageUrl.query ?? "nil")")
        print("  - URL Fragment: \(pageUrl.fragment ?? "nil")")

        // Check domain validation compatibility
        let hostContainsWiki = osrsWebKitSecurityPolicy.isTrustedWikiHost(pageUrl.host)
        print("🛠️ DIAGNOSTIC: Domain validation check:")
        print("  - Host contains wiki domain: \(hostContainsWiki)")
        print("  - Would pass shouldOpenExternally: \(!Self.shouldOpenExternallyForArticleNavigation(pageUrl))")

        // Safety timeout for reload cases to prevent stuck refresh state
        if isReload {
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.isCurrentLoad(loadGeneration) && self.isRefreshing {
                    let timeoutString = DateFormatter.timeFormatter.string(from: Date())
                    print("⚠️ [\(timeoutString)] RELOAD TIMEOUT: Force-resetting stuck reload refresh state")
                    self.isRefreshing = false
                    self.errorMessage = "Reload timed out. Please try again."
                }
            }
            reloadTimeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
        }

        // TIMING MEASUREMENT: Reset timing measurements for new page load
        progressCompletionTime = nil
        pageVisibilityTime = nil

        // Initial progress will be set by WebKit observer

        // Debug: Print raw title hex bytes to detect encoding issues
        if let rawTitle = pageTitle_ {
            print("🔗 DEBUG: Raw title: '\(rawTitle)'")
            print("🔗 DEBUG: Title UTF-8 bytes: \(rawTitle.utf8.map { String(format: "%02X", $0) }.joined(separator: " "))")
            print("🔗 DEBUG: Title.count: \(rawTitle.count)")
            print("🔗 DEBUG: Title contains %: \(rawTitle.contains("%"))")
            print("🔗 DEBUG: Title contains colon: \(rawTitle.contains(":"))")
        }

        // Extract canonical title from URL (like Android does)
        let titleToLoad: String
        if let cleanPageTitle = pageTitle_?.trimmingCharacters(in: .whitespacesAndNewlines), !cleanPageTitle.isEmpty {
            // Use the provided title (for cases like search results)
            print("📄 ArticleViewModel: Using provided title: '\(cleanPageTitle)'")

            // Defensive check: detect potential corruption early
            if cleanPageTitle.contains("%20") && !cleanPageTitle.hasPrefix("http") {
                print("⚠️ ArticleViewModel: ALERT - Title contains URL encoding but isn't a URL!")
                print("⚠️ ArticleViewModel: This suggests title corruption - falling back to URL extraction")
                titleToLoad = extractTitleFromUrl(pageUrl)
                print("📄 ArticleViewModel: Extracted title from URL due to corruption: '\(titleToLoad)'")
            } else {
                titleToLoad = cleanUpTitle(cleanPageTitle)
                print("📄 ArticleViewModel: After cleanUpTitle: '\(titleToLoad)'")
            }
        } else {
            // Extract canonical title from URL (like Android does)
            titleToLoad = extractTitleFromUrl(pageUrl)
            print("📄 ArticleViewModel: Extracted canonical title from URL: '\(titleToLoad)'")
        }

        // CUSTOM SCHEME DETECTION: Check if this is an offline URL that should bypass API
        if pageUrl.scheme == "app-assets" {
            print("🔧 ArticleViewModel: Detected custom scheme URL - loading directly in WebView")
            print("🔧 ArticleViewModel: Bypassing API for offline content: \(pageUrl.absoluteString)")
            loadUrlDirectlyInWebView(theme: theme, generation: loadGeneration)
            return
        }

#if DEBUG
        if osrsTestEnvironment.usesDeepNavigationFixtureForUITests,
           let fixturePage = osrsDeepNavigationFixtureAudit.page(for: pageUrl, requestedTitle: pageTitle_) {
            loadDeepNavigationFixturePage(fixturePage, theme: theme, generation: loadGeneration)
            return
        }
#endif

        let documentRequest = osrsArticleDocumentRequest(pageURL: pageUrl, pageTitle: titleToLoad)
        let renderOptions = osrsArticleRenderOptions(
            usesDarkTheme: theme is osrsDarkTheme,
            collapseTablesEnabled: collapseTablesEnabled,
            wrapTableCellsEnabled: wrapTableCellsEnabled,
            articleTextScale: Double(articleTextScale)
        )
        let shouldForceDocumentReload = forceNextDocumentReload
        forceNextDocumentReload = false
        articlePipelineLoads[loadGeneration] = (documentRequest.identity, Date())

        currentLoadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
#if DEBUG
                if osrsTestEnvironment.forcesArticleReloadNetworkFailureAfterFirstSuccessForUITests,
                   self.isRefreshing,
                   !self.didForceArticleReloadNetworkFailureForUITests {
                    self.didForceArticleReloadNetworkFailureForUITests = true
                    print("🧪 ArticleViewModel: Forced one-shot article reload network failure for UI test")
                    throw NetworkError.noConnection
                }
#endif
                if !shouldForceDocumentReload,
                   let paintHTML {
                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - paintOpenStarted) * 1000)
                    print("⚡ ArticlePaintOpen: persisted snapshot chars=\(paintHTML.count) elapsedMs=\(elapsedMs)")
                    await self.loadCustomHtml(paintHTML, theme: theme, generation: loadGeneration)
                    await MainActor.run {
                        if self.isCurrentLoad(loadGeneration) {
                            self.checkIfPageIsSaved()
                        }
                    }
                    return
                }
                if shouldForceDocumentReload {
                    await osrsArticleDocumentCoordinator.shared.invalidate(documentRequest.identity)
                }
                let document = try await osrsArticleDocumentCoordinator.shared.preparedDocument(
                    for: documentRequest,
                    renderOptions: renderOptions,
                    purpose: .foreground
                )
                let payload = document.payload
                print("✅ ArticleViewModel: Prepared shared document - Title: '\(payload.title)', HTML: \(document.html.count) characters")

                // Load in WebView on main thread
                await MainActor.run {
                    if self.isCurrentLoad(loadGeneration) {
                        self.pageTitle = payload.resolvedTitle
                        self.resolvedPageTitleForHistory = payload.resolvedTitle
                        self.resolvedPageUrlForHistory = Self.articleURL(forResolvedTitle: payload.title)
                    }
                }
                try Task.checkCancellation()
                guard await MainActor.run(body: { self.isCurrentLoad(loadGeneration) }) else {
                    print("🚫 ArticleViewModel: Ignoring stale HTML load for generation \(loadGeneration)")
                    return
                }
                await self.loadCustomHtml(document.html, theme: theme, generation: loadGeneration)
                await MainActor.run {
                    if self.isCurrentLoad(loadGeneration) {
                        self.lastLoadedArticleHTML = payload.htmlContent
                    }
                }
                self.lazyMaterializePaintHTMLIfNeeded(
                    bodyHTML: payload.htmlContent,
                    displayTitle: payload.displayTitle ?? payload.title,
                    canonicalTitle: payload.title,
                    theme: theme
                )

                // Check if this page is already saved
                await MainActor.run {
                    if self.isCurrentLoad(loadGeneration) {
                        self.checkIfPageIsSaved()
                    }
                }

            } catch is CancellationError {
                print("🚫 ArticleViewModel: Article load cancelled for generation \(loadGeneration)")
            } catch let networkError as NetworkError {
                print("❌ ArticleViewModel: Network error loading article: \(networkError.localizedDescription)")
                print("🛠️ DIAGNOSTIC: Network error details:")
                print("  - Error type: \(networkError)")
                print("  - User message: \(networkError.userMessage)")
                print("  - Is offline error: \(networkError.isOfflineError)")
                print("  - Original URL: \(pageUrl.absoluteString)")
                await MainActor.run {
                    guard self.isCurrentLoad(loadGeneration) else {
                        print("🚫 ArticleViewModel: Ignoring stale network error for generation \(loadGeneration)")
                        return
                    }
                    self.errorMessage = networkError.userMessage
                    self.isLoading = false

                    // If it's an offline error, we could show different UI
                    if networkError.isOfflineError {
                        print("📵 ArticleViewModel: Device appears to be offline")
                    }
                }
            } catch {
                print("❌ ArticleViewModel: Unexpected error loading article: \(error)")
                print("🛠️ DIAGNOSTIC: Unexpected error details:")
                print("  - Error type: \(type(of: error))")
                print("  - Error description: \(error.localizedDescription)")
                print("  - Error: \(error)")
                print("  - Original URL: \(pageUrl.absoluteString)")
                if let nsError = error as NSError? {
                    print("  - Error domain: \(nsError.domain)")
                    print("  - Error code: \(nsError.code)")
                    print("  - User info: \(nsError.userInfo)")
                }
                await MainActor.run {
                    guard self.isCurrentLoad(loadGeneration) else {
                        print("🚫 ArticleViewModel: Ignoring stale load error for generation \(loadGeneration)")
                        return
                    }
                    self.errorMessage = UserFacingError.message(for: error, fallback: "This page could not be loaded. Please try again.")
                    self.isLoading = false
                }
            }
        }
    }

#if DEBUG
    private func loadDeepNavigationFixturePage(
        _ fixturePage: osrsDeepNavigationFixturePage,
        theme: any osrsThemeProtocol,
        generation: Int
    ) {
        pageTitle = fixturePage.title
        resolvedPageTitleForHistory = fixturePage.title
        resolvedPageUrlForHistory = fixturePage.url

        let htmlBuilder = osrsPageHtmlBuilder()
        let finalHtml = htmlBuilder.buildFullHtmlDocument(
            title: fixturePage.title,
            bodyContent: fixturePage.bodyHTML,
            theme: theme,
            collapseTablesEnabled: false,
            includeAssetLinks: false,
            articleTextScale: articleTextScale,
            wrapTableCellsEnabled: wrapTableCellsEnabled
        )

        currentLoadTask = Task { [weak self] in
            guard let self = self else { return }
            await self.loadCustomHtml(finalHtml, theme: theme, generation: generation)
            await MainActor.run {
                if self.isCurrentLoad(generation) {
                    self.checkIfPageIsSaved()
                }
            }
        }
    }
#endif

    func reloadArticle(theme: any osrsThemeProtocol = osrsLightTheme()) {
        loadArticle(theme: theme)
    }

    /// Refresh page with Android-parity behavior: show progress bar over blank page
    /// Uses SwiftUI view state management with WebView overlay approach
    func refreshPage(theme: any osrsThemeProtocol = osrsLightTheme()) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("🔄 [\(timeString)] REFRESH: Starting SwiftUI overlay-based page refresh with blank page")
        forceNextDocumentReload = true

        // Step 1: Set refresh state - this will overlay blank view on top of WebView
        isRefreshing = true

        // Step 2: Reset UI state for clean loading experience
        errorMessage = nil
        loadingProgress = 0.1
        loadingProgressText = "Refreshing page..."

        // Reset timing measurements
        progressCompletionTime = nil
        pageVisibilityTime = nil

        print("🔄 [\(timeString)] REFRESH: Blank overlay active, WebView still present for loading")

        // Step 3: Safety timeout to prevent stuck refresh state
        let refreshGeneration = currentLoadGeneration
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isCurrentLoad(refreshGeneration) && self.isRefreshing {
                let timeoutString = DateFormatter.timeFormatter.string(from: Date())
                print("⚠️ [\(timeoutString)] REFRESH TIMEOUT: Force-resetting stuck refresh state")
                self.isRefreshing = false
                self.errorMessage = "Refresh timed out. Please try again."
            }
        }
        refreshTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)

#if DEBUG
        if osrsTestEnvironment.forcesArticleRefreshFailureForUITests {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.isRefreshing else { return }
                self.isRefreshing = false
                self.isLoading = false
                self.loadingProgress = 0
                self.loadingProgressText = nil
                self.errorMessage = "Network connection lost while refreshing. Please try again."
                print("🧪 ArticleViewModel: Forced article refresh failure for UI test")
            }
            return
        }
#endif

        // Step 4: Small delay to ensure UI updates, then load new content
        let refreshWorkItem = DispatchWorkItem { [weak self] in
            print("🔄 [\(timeString)] REFRESH: Starting content load with WebView overlaid but present")
            self?.loadArticle(theme: theme)
        }
        deferredRefreshWorkItem = refreshWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: refreshWorkItem)
    }

    /// Remove unwanted infobox sections that should be hidden by default
    /// Matches Android's preprocessHtml behavior in PageAssetDownloader.kt
    private func removeUnwantedInfoboxSections(from html: String) -> String {
        var processedHtml = html

        // Selectors to remove (matching Android)
        let selectorsToRemove = [
            "advanced-data",
            "leagues-global-flag",
            "infobox-padding"
        ]

        for selector in selectorsToRemove {
            // Pattern to match <tr> elements with the class anywhere in the class attribute
            let pattern = "<tr[^>]*?class=[\"'][^\"']*?\(selector)[^\"']*?[\"'][^>]*?>.*?</tr>"

            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                let matches = regex.matches(in: processedHtml, range: NSRange(location: 0, length: processedHtml.utf16.count))

                if matches.count > 0 {
                    print("🔍 ArticleViewModel: Found \(matches.count) elements with class '\(selector)' to remove")
                }

                // Remove matches in reverse order to maintain correct indices
                for match in matches.reversed() {
                    if let range = Range(match.range, in: processedHtml) {
                        processedHtml.removeSubrange(range)
                    }
                }
            } catch {
                print("❌ ArticleViewModel: Failed to create regex for selector '\(selector)': \(error)")
            }
        }

        return processedHtml
    }

    private func handleDownloadProgress(_ progress: osrsDownloadProgress, theme: any osrsThemeProtocol) async {
        switch progress {
        case .fetchingHtml(let progressValue):
            let scaledProgress = 0.05 + (Double(progressValue) * 0.05)
            await MainActor.run {
                loadingProgress = scaledProgress
            }
            print("📥 ArticleViewModel: Fetching HTML \(progressValue)% - scaled to \(Int(scaledProgress * 100))%")

        case .fetchingAssets(let progressValue):
            let scaledProgress = 0.10 + (Double(progressValue) * 0.40)
            await MainActor.run {
                loadingProgress = scaledProgress
            }
            print("📦 ArticleViewModel: Fetching assets \(progressValue)% - scaled to \(Int(scaledProgress * 100))%")

        case .success(let pageContent):
            print("✅ ArticleViewModel: Successfully loaded page content")
            // Progress updated automatically by WebKit observer

            // FREEZE FIX: Get content loader async - defer heavy initialization until needed
            let loader = await getContentLoader()

            // Build the final HTML document
            let finalHtml = loader.buildFullHtmlDocument(
                pageContent: pageContent,
                theme: theme,
                collapseTablesEnabled: collapseTablesEnabled,
                articleTextScale: articleTextScale,
                wrapTableCellsEnabled: wrapTableCellsEnabled
            )

            print("🏗️ ArticleViewModel: Built custom HTML document (\(finalHtml.count) characters)")

            await MainActor.run {
                // Update page title
                pageTitle = pageContent.parseResult.displaytitle ?? pageContent.parseResult.title ?? "OSRS Wiki"
                applyTableOfContents(from: pageContent.processedHtml)
            }

            // Load the custom HTML in WebView
            await loadCustomHtml(finalHtml, theme: theme, generation: currentLoadGeneration)

        case .failure(let error):
            print("❌ ArticleViewModel: Failed to load content: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                errorMessage = UserFacingError.message(for: error, fallback: "This page could not be loaded. Please try again.")
            }
        }
    }

    private func loadCustomHtml(_ html: String, theme: any osrsThemeProtocol = osrsLightTheme(), generation: Int) async {
        guard let webView = webView else { return }
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Skipping stale WebView load for generation \(generation)")
            return
        }

        print("🌐 ArticleViewModel: Loading custom HTML in WebView")
        print("🌐 ArticleViewModel: HTML content length: \(html.count) characters")

        if adoptedPreRenderedDocument, webView.osrsPreparedDocumentKey != nil,
           !needsContentProcessRecovery,
           webView.url != nil,
           webView.url?.absoluteString != "about:blank" {
            adoptedPreRenderedDocument = false
            print("⚡ ArticleViewModel: Using pre-rendered WKWebView; skipping loadHTMLString")
            deferredMapPreloadState.stage(html, generation: generation)
            await osrsArticleDocumentCoordinator.shared.recordWebKitReady(
                identity: osrsArticleDocumentIdentity(pageURL: pageUrl, pageTitle: pageTitle_),
                elapsed: 0
            )
            markWebKitReady(for: generation)
            markJavaScriptReady(for: generation)
            notifyAdoptedFirstViewComplete(webView)
            startDeferredMapPreloadAfterWebKitReady(generation: generation, webView: webView)
            return
        }
        adoptedPreRenderedDocument = false

        // Native map discovery is staged but deliberately cannot parse or instantiate MapLibre
        // before WebKit commits the text document for this generation.
        deferredMapPreloadState.stage(html, generation: generation)

        // Keep wiki base URL for content
        // CRITICAL FIX: Use custom scheme baseURL to avoid mixed content security blocking
        // WebKit treats custom schemes as insecure and blocks them when baseURL is HTTPS
        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
        let customBaseURL = URL(string: "\(customScheme)://localhost/")!
        print("🔧 CRITICAL FIX: Using custom scheme baseURL: \(customBaseURL) instead of HTTPS")
        print("🔧 This resolves WebKit mixed content security blocking that prevented WKURLSchemeHandler from being called")

        // Option B: Skip WKUserScript injection - assets loaded via WKURLSchemeHandler
        print("📱 Option B: Skipping WKUserScript injection - using WKURLSchemeHandler for asset loading")

        let navigation = webView.loadHTMLString(htmlWithLoadGeneration(html, generation: generation), baseURL: customBaseURL)
        bindWebKitNavigation(navigation, to: generation)
        scheduleReadinessTimeout(for: generation)
    }

    private func startDeferredMapPreloadAfterWebKitReady(
        generation: Int,
        webView: WKWebView
    ) {
        guard let html = deferredMapPreloadState.takeAfterWebKitReady(generation: generation),
              let parentView = webView.superview else { return }
        deferredMapPreloadTask?.cancel()
        deferredMapPreloadTask = Task { @MainActor [weak self] in
            let parsingTask = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                let maps = osrsMapPreloadService.parseMapDataFromHTML(html)
                try Task.checkCancellation()
                return maps
            }
            do {
                let maps = try await withTaskCancellationHandler {
                    try await parsingTask.value
                } onCancel: {
                    parsingTask.cancel()
                }
                guard let self, self.isCurrentLoad(generation), !Task.isCancelled else { return }
                await osrsBackgroundWorkGate.shared.waitWhilePaused()
                guard self.isCurrentLoad(generation), !Task.isCancelled else { return }
                osrsMapPreloadService.shared.setParentView(parentView)
                osrsMapPreloadService.shared.preloadMaps(maps)
            } catch {
                // Navigation cancellation is the expected way deferred native-map work ends.
            }
        }
    }

    // MARK: - Direct WebView Loading for Custom Schemes

    /// Load URLs directly in WebView - now handles web archives via loadFileURL
    /// Used for offline content stored as .webarchive files
    private func loadUrlDirectlyInWebView(theme: any osrsThemeProtocol, generation: Int) {
        guard let webView = webView else {
            print("❌ ArticleViewModel: WebView not set for direct loading")
            errorMessage = "This page could not be displayed. Please try again."
            isLoading = false
            isRefreshing = false
            return
        }

        print("🔧 ArticleViewModel: Starting web archive loading")
        print("🔧 ArticleViewModel: Loading URL: \(pageUrl.absoluteString)")

        // NEW: Check if this is a web archive request (app-assets://saved-pages/pageId)
        if pageUrl.scheme == "app-assets" && pageUrl.host == "saved-pages" {
            print("📦 ArticleViewModel: Detected web archive request")
            loadWebArchiveFile(generation: generation)
            return
        }

        // Fallback for other custom schemes (shouldn't happen with web archives)
        print("🌐 ArticleViewModel: Loading non-archive custom scheme URL")

        // Apply theme colors first (like API-based loading does)
        injectBundleAssetsViaUserScript(webView: webView)

        // Create URL request and load directly
        let request = URLRequest(url: pageUrl)
        let navigation = webView.load(request)
        bindWebKitNavigation(navigation, to: generation)
        scheduleReadinessTimeout(for: generation)

        print("🔧 ArticleViewModel: Direct URL request initiated")

        // Note: Progress tracking and completion will be handled by existing WebView delegates
        // (didStartProvisionalNavigation, didFinish, etc.)
    }

    /// Load web archive file using iOS-native loadFileURL method
    private func loadWebArchiveFile(generation: Int) {
        guard let webView = webView else {
            print("❌ ArticleViewModel: WebView not available for web archive loading")
            errorMessage = "This saved page could not be displayed. Please try again."
            isLoading = false
            return
        }

        // Extract page ID from URL: app-assets://saved-pages/pageId
        let pathComponents = pageUrl.path.components(separatedBy: "/").filter { !$0.isEmpty }
        guard let pageId = pathComponents.first else {
            print("❌ ArticleViewModel: Could not extract page ID from URL: \(pageUrl.absoluteString)")
            errorMessage = "This saved page could not be opened."
            isLoading = false
            return
        }

        print("📦 ArticleViewModel: Loading web archive for page ID: \(pageId)")

        // Get web archive file URL from OfflineContentService
        let offlineService = OfflineContentService.shared
        let archiveFileURL = offlineService.webArchiveFileURL(for: pageId)

        // Check if web archive exists
        guard FileManager.default.fileExists(atPath: archiveFileURL.path) else {
            print("❌ ArticleViewModel: Web archive not found at: \(archiveFileURL.path)")
            errorMessage = "Offline content not available"
            isLoading = false
            return
        }

        print("📦 ArticleViewModel: Found web archive at: \(archiveFileURL.path)")

        // Apply theme colors first (like API-based loading does)
        injectBundleAssetsViaUserScript(webView: webView)

        // Load web archive using iOS-native method
        // Allow read access to the entire offline_pages directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let offlineDirectory = documentsDirectory.appendingPathComponent("offline_pages")

        print("📦 ArticleViewModel: Loading web archive with read access to: \(offlineDirectory.path)")
        let navigation = webView.loadFileURL(archiveFileURL, allowingReadAccessTo: offlineDirectory)
        bindWebKitNavigation(navigation, to: generation)
        scheduleReadinessTimeout(for: generation)

        // Schedule enhanced diagnostics, base URL injection, and MediaWiki re-initialization after content loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard self.isCurrentLoad(generation) else { return }
            self.injectBaseURLFix()
            self.diagnoseWebArchiveJavaScript()

            // Add MediaWiki re-initialization after diagnostics
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.isCurrentLoad(generation) else { return }
                self.reinitializeMediaWikiForWebArchive()
            }
        }

        print("✅ ArticleViewModel: Web archive load initiated")
    }

    /// Diagnose JavaScript execution issues in web archive context
    private func diagnoseWebArchiveJavaScript() {
        guard let webView = webView else { return }

        print("🔍 JAVASCRIPT DIAGNOSIS: Starting comprehensive JavaScript execution analysis for web archives...")

        let diagnosticScript = """
            (function() {
                console.log('🔍 JS DIAGNOSIS: Starting JavaScript execution analysis...');

                // Test 1: Basic JavaScript execution
                try {
                    var testVar = 'JavaScript execution works';
                    console.log('✅ JS DIAGNOSIS: Basic JavaScript execution: ' + testVar);
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: Basic JavaScript failed: ' + error);
                    return 'basic_js_failed';
                }

                // Test 2: DOM access
                try {
                    var bodyExists = document.body !== null;
                    var headExists = document.head !== null;
                    console.log('✅ JS DIAGNOSIS: DOM access - body: ' + bodyExists + ', head: ' + headExists);
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: DOM access failed: ' + error);
                    return 'dom_access_failed';
                }

                // Test 3: Event listener attachment
                try {
                    var testDiv = document.createElement('div');
                    testDiv.addEventListener('click', function() {});
                    console.log('✅ JS DIAGNOSIS: Event listener attachment works');
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: Event listener attachment failed: ' + error);
                    return 'event_listener_failed';
                }

                // Test 4: Check for collapsible elements
                var collapsibleElements = document.querySelectorAll('.mw-collapsible');
                console.log('🔍 JS DIAGNOSIS: Found ' + collapsibleElements.length + ' collapsible elements');

                if (collapsibleElements.length > 0) {
                    var firstCollapsible = collapsibleElements[0];
                    console.log('🔍 JS DIAGNOSIS: First collapsible element classes: ' + firstCollapsible.className);

                    // Check if collapsible elements have click handlers
                    try {
                        var hasClickHandler = firstCollapsible.onclick !== null;
                        console.log('🔍 JS DIAGNOSIS: First collapsible has onclick handler: ' + hasClickHandler);

                        // Try to manually attach a click handler
                        firstCollapsible.addEventListener('click', function(e) {
                            console.log('🔍 JS DIAGNOSIS: Manual click handler triggered on collapsible element');
                        });
                        console.log('✅ JS DIAGNOSIS: Successfully attached manual click handler to collapsible');
                    } catch (error) {
                        console.log('❌ JS DIAGNOSIS: Failed to attach click handler to collapsible: ' + error);
                    }
                } else {
                    console.log('⚠️ JS DIAGNOSIS: No collapsible elements found in document');
                }

                // Test 5: Check jQuery availability
                try {
                    var jqueryAvailable = typeof jQuery !== 'undefined' || typeof $ !== 'undefined';
                    console.log('🔍 JS DIAGNOSIS: jQuery available: ' + jqueryAvailable);
                    if (jqueryAvailable && typeof $ !== 'undefined') {
                        console.log('🔍 JS DIAGNOSIS: jQuery version: ' + ($.fn ? $.fn.jquery : 'unknown'));
                    }
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: jQuery check failed: ' + error);
                }

                // Test 6: Check MediaWiki JavaScript
                try {
                    var mwAvailable = typeof mw !== 'undefined';
                    console.log('🔍 JS DIAGNOSIS: MediaWiki (mw) available: ' + mwAvailable);
                    if (mwAvailable) {
                        console.log('🔍 JS DIAGNOSIS: MediaWiki config exists: ' + (typeof mw.config !== 'undefined'));
                    }
                } catch (error) {
                    console.log('❌ JS DIAGNOSIS: MediaWiki check failed: ' + error);
                }

                console.log('🔍 JS DIAGNOSIS: JavaScript execution analysis complete');
                return 'diagnosis_complete';
            })();
        """

        webView.evaluateJavaScript(diagnosticScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ JAVASCRIPT DIAGNOSIS: Script execution failed: \(error)")
                } else if let resultString = result as? String {
                    print("✅ JAVASCRIPT DIAGNOSIS: Analysis completed with result: \(resultString)")
                } else {
                    print("✅ JAVASCRIPT DIAGNOSIS: Analysis completed successfully")
                }

                // Follow up with collapsible-specific diagnosis
                self.diagnoseCollapsibleContainers()
            }
        }
    }

    /// Specifically diagnose collapsible container functionality
    private func diagnoseCollapsibleContainers() {
        guard let webView = webView else { return }

        print("📋 COLLAPSIBLE DIAGNOSIS: Analyzing collapsible container functionality...")

        let collapsibleScript = """
            (function() {
                console.log('📋 COLLAPSIBLE DIAGNOSIS: Starting collapsible container analysis...');

                // Find all collapsible elements
                var collapsibles = document.querySelectorAll('.mw-collapsible');
                console.log('📋 Found ' + collapsibles.length + ' .mw-collapsible elements');

                if (collapsibles.length === 0) {
                    // Try alternative selectors
                    var altCollapsibles = document.querySelectorAll('[data-expandtext], .collapsible, .mw-collapsible-toggle');
                    console.log('📋 Found ' + altCollapsibles.length + ' alternative collapsible elements');
                    collapsibles = altCollapsibles;
                }

                if (collapsibles.length > 0) {
                    var firstCollapsible = collapsibles[0];

                    // Analyze the structure
                    console.log('📋 First collapsible element:');
                    console.log('  - Tag: ' + firstCollapsible.tagName);
                    console.log('  - Classes: ' + firstCollapsible.className);
                    console.log('  - Has data attributes: ' + Object.keys(firstCollapsible.dataset).join(', '));

                    // Look for toggle elements
                    var toggles = firstCollapsible.querySelectorAll('.mw-collapsible-toggle, .collapsible-toggle');
                    console.log('  - Toggle elements found: ' + toggles.length);

                    if (toggles.length > 0) {
                        var firstToggle = toggles[0];
                        console.log('  - First toggle classes: ' + firstToggle.className);
                        console.log('  - First toggle text: ' + firstToggle.textContent.trim());

                        // Try to simulate a click
                        try {
                            console.log('📋 Attempting to simulate click on toggle...');
                            firstToggle.click();
                            console.log('✅ Click simulation succeeded');
                        } catch (error) {
                            console.log('❌ Click simulation failed: ' + error);
                        }
                    }

                    return 'found_' + collapsibles.length + '_collapsibles';
                } else {
                    console.log('❌ No collapsible elements found in document');
                    return 'no_collapsibles_found';
                }
            })();
        """

        webView.evaluateJavaScript(collapsibleScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ COLLAPSIBLE DIAGNOSIS: Script execution failed: \(error)")
                } else if let resultString = result as? String {
                    print("✅ COLLAPSIBLE DIAGNOSIS: Analysis completed with result: \(resultString)")
                } else {
                    print("✅ COLLAPSIBLE DIAGNOSIS: Analysis completed successfully")
                }
            }
        }
    }

    /// Inject base URL to fix relative links in web archive content
    private func injectBaseURLFix() {
        guard let webView = webView else { return }

        let baseURLScript = """
            (function() {
                // Check if base tag already exists
                if (document.querySelector('base')) {
                    console.log('Base URL already set, skipping injection');
                    return;
                }

                // Create and inject base URL
                var base = document.createElement('base');
                base.href = 'https://oldschool.runescape.wiki/';

                // Insert at beginning of head
                var head = document.head || document.getElementsByTagName('head')[0];
                if (head.firstChild) {
                    head.insertBefore(base, head.firstChild);
                } else {
                    head.appendChild(base);
                }

                console.log('Injected base URL for web archive content');

                // Also fix any remaining relative URLs in the content
                var links = document.querySelectorAll('a[href^="/"], a[href^="./"], a[href^="../"]');
                links.forEach(function(link) {
                    var href = link.getAttribute('href');
                    if (href.startsWith('/')) {
                        link.href = 'https://oldschool.runescape.wiki' + href;
                    }
                });

                console.log('Fixed ' + links.length + ' relative links');
            })();
        """

        webView.evaluateJavaScript(baseURLScript) { result, error in
            if let error = error {
                print("❌ ArticleViewModel: Base URL injection failed: \(error.localizedDescription)")
            } else {
                print("✅ ArticleViewModel: Base URL injection completed")
            }
        }
    }

    /// Re-initialize MediaWiki JavaScript functionality for web archives
    private func reinitializeMediaWikiForWebArchive() {
        guard let webView = webView else { return }

        print("🔧 MEDIAWIKI RE-INIT: Starting MediaWiki JavaScript re-initialization for web archives...")

        let mediaWikiReinitScript = """
            (function() {
                console.log('🔧 MEDIAWIKI RE-INIT: Re-initializing MediaWiki functionality for web archives...');

                // Step 1: Initialize basic MediaWiki objects if they don't exist
                if (typeof mw === 'undefined') {
                    console.log('🔧 MEDIAWIKI RE-INIT: Creating basic MediaWiki object...');
                    window.mw = {
                        config: {
                            get: function(key) {
                                console.log('🔧 MW CONFIG: Getting config for: ' + key);
                                return null;
                            }
                        },
                        loader: {
                            load: function(modules) {
                                console.log('🔧 MW LOADER: Loading modules: ' + modules);
                            }
                        },
                        hook: function(name) {
                            console.log('🔧 MW HOOK: Hook called: ' + name);
                            return {
                                add: function(callback) {
                                    console.log('🔧 MW HOOK: Adding callback for: ' + name);
                                    if (typeof callback === 'function') {
                                        setTimeout(callback, 10);
                                    }
                                }
                            };
                        }
                    };
                }

                // Step 2: Find and manually initialize collapsible elements
                var collapsibleElements = document.querySelectorAll('.mw-collapsible, .collapsible');
                console.log('🔧 MEDIAWIKI RE-INIT: Found ' + collapsibleElements.length + ' collapsible elements to initialize');

                if (collapsibleElements.length > 0) {
                    collapsibleElements.forEach(function(element, index) {
                        try {
                            console.log('🔧 MEDIAWIKI RE-INIT: Initializing collapsible element ' + (index + 1));

                            // Add necessary classes if missing
                            if (!element.classList.contains('mw-collapsible')) {
                                element.classList.add('mw-collapsible');
                            }

                            // Find or create toggle button
                            var toggleButton = element.querySelector('.mw-collapsible-toggle');
                            if (!toggleButton) {
                                // Look for existing toggle elements with different classes
                                toggleButton = element.querySelector('.collapsible-toggle, [data-toggle]');
                            }

                            if (!toggleButton) {
                                // Create a new toggle button
                                toggleButton = document.createElement('span');
                                toggleButton.className = 'mw-collapsible-toggle';
                                toggleButton.innerHTML = '[hide]';
                                toggleButton.style.cursor = 'pointer';
                                toggleButton.style.color = '#0645ad';
                                toggleButton.style.fontSize = '0.8em';
                                toggleButton.style.marginLeft = '0.5em';

                                // Insert toggle button at the beginning of the element
                                var firstChild = element.firstElementChild;
                                if (firstChild) {
                                    firstChild.appendChild(toggleButton);
                                } else {
                                    element.appendChild(toggleButton);
                                }

                                console.log('🔧 MEDIAWIKI RE-INIT: Created new toggle button for element ' + (index + 1));
                            }

                            // Find collapsible content (everything except the first row/header)
                            var collapsibleContent = [];
                            var children = Array.from(element.children);

                            if (element.tagName === 'TABLE') {
                                // For tables, hide all rows except the first
                                var rows = element.querySelectorAll('tr');
                                if (rows.length > 1) {
                                    for (var i = 1; i < rows.length; i++) {
                                        collapsibleContent.push(rows[i]);
                                    }
                                }
                            } else {
                                // For other elements, hide all children except the first
                                if (children.length > 1) {
                                    for (var i = 1; i < children.length; i++) {
                                        collapsibleContent.push(children[i]);
                                    }
                                }
                            }

                            // Add click handler to toggle button
                            toggleButton.onclick = function() {
                                var isCollapsed = element.classList.contains('mw-collapsed');

                                if (isCollapsed) {
                                    // Expand: show content and update button text
                                    element.classList.remove('mw-collapsed');
                                    collapsibleContent.forEach(function(item) {
                                        item.style.display = '';
                                    });
                                    toggleButton.innerHTML = '[hide]';
                                    console.log('🔧 MEDIAWIKI RE-INIT: Expanded collapsible element');
                                } else {
                                    // Collapse: hide content and update button text
                                    element.classList.add('mw-collapsed');
                                    collapsibleContent.forEach(function(item) {
                                        item.style.display = 'none';
                                    });
                                    toggleButton.innerHTML = '[show]';
                                    console.log('🔧 MEDIAWIKI RE-INIT: Collapsed collapsible element');
                                }
                            };

                            // Set initial state - check if element should start collapsed
                            var shouldStartCollapsed = element.classList.contains('mw-collapsed') ||
                                                     element.classList.contains('collapsed');

                            if (shouldStartCollapsed) {
                                element.classList.add('mw-collapsed');
                                collapsibleContent.forEach(function(item) {
                                    item.style.display = 'none';
                                });
                                toggleButton.innerHTML = '[show]';
                            } else {
                                element.classList.remove('mw-collapsed');
                                collapsibleContent.forEach(function(item) {
                                    item.style.display = '';
                                });
                                toggleButton.innerHTML = '[hide]';
                            }

                            console.log('🔧 MEDIAWIKI RE-INIT: Successfully initialized collapsible element ' + (index + 1) + ', starts ' + (shouldStartCollapsed ? 'collapsed' : 'expanded'));

                        } catch (error) {
                            console.log('❌ MEDIAWIKI RE-INIT: Failed to initialize collapsible element ' + (index + 1) + ': ' + error);
                        }
                    });

                    console.log('✅ MEDIAWIKI RE-INIT: Successfully re-initialized ' + collapsibleElements.length + ' collapsible elements');
                    return 'reinitialized_' + collapsibleElements.length + '_collapsibles';

                } else {
                    console.log('⚠️ MEDIAWIKI RE-INIT: No collapsible elements found to re-initialize');
                    return 'no_collapsibles_found';
                }

            })();
        """

        webView.evaluateJavaScript(mediaWikiReinitScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ MEDIAWIKI RE-INIT: Re-initialization failed: \(error)")
                } else if let resultString = result as? String {
                    print("✅ MEDIAWIKI RE-INIT: Re-initialization completed with result: \(resultString)")

                    // Verify the fix worked by running diagnostics again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.verifyCollapsibleFunctionality()
                    }
                } else {
                    print("✅ MEDIAWIKI RE-INIT: Re-initialization completed successfully")
                }
            }
        }
    }

    /// Verify that collapsible functionality is working after re-initialization
    private func verifyCollapsibleFunctionality() {
        guard let webView = webView else { return }

        print("🧪 VERIFICATION: Testing collapsible functionality after re-initialization...")

        let verificationScript = """
            (function() {
                console.log('🧪 VERIFICATION: Testing collapsible functionality...');

                var collapsibles = document.querySelectorAll('.mw-collapsible');
                console.log('🧪 Found ' + collapsibles.length + ' collapsible elements for verification');

                if (collapsibles.length > 0) {
                    var firstCollapsible = collapsibles[0];
                    var toggleButton = firstCollapsible.querySelector('.mw-collapsible-toggle');

                    if (toggleButton) {
                        console.log('🧪 VERIFICATION: Found toggle button, testing click functionality...');

                        // Simulate a click to test functionality
                        var initialState = firstCollapsible.classList.contains('mw-collapsed');
                        console.log('🧪 Initial state - collapsed: ' + initialState);

                        // Trigger click
                        toggleButton.click();

                        // Check if state changed
                        var newState = firstCollapsible.classList.contains('mw-collapsed');
                        console.log('🧪 New state after click - collapsed: ' + newState);

                        if (initialState !== newState) {
                            console.log('✅ VERIFICATION: Collapsible functionality is working correctly!');
                            return 'collapsible_working';
                        } else {
                            console.log('❌ VERIFICATION: Collapsible state did not change - functionality may be broken');
                            return 'collapsible_not_working';
                        }
                    } else {
                        console.log('❌ VERIFICATION: No toggle button found');
                        return 'no_toggle_button';
                    }
                } else {
                    console.log('❌ VERIFICATION: No collapsible elements found for verification');
                    return 'no_collapsibles';
                }
            })();
        """

        webView.evaluateJavaScript(verificationScript) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ VERIFICATION: Verification script failed: \(error)")
                } else if let resultString = result as? String {
                    print("🧪 VERIFICATION: Functionality verification completed with result: \(resultString)")
                } else {
                    print("🧪 VERIFICATION: Verification completed successfully")
                }
            }
        }
    }

    /// Extract page ID from URL - handles both custom schemes and real HTTPS URLs
    private func extractPageIdFromURL(_ url: URL) -> String? {
        // Handle legacy custom scheme URLs: app-assets://saved-pages/pageId
        if url.scheme == "app-assets" && url.host == "saved-pages" {
            let pathComponents = url.path.components(separatedBy: "/").filter { !$0.isEmpty }
            return pathComponents.first
        }

        // NEW: Handle real HTTPS URLs by looking up saved page by URL
        if url.scheme == "https" && osrsWebKitSecurityPolicy.isTrustedWikiHost(url.host) {
            // For real HTTPS URLs, we need to find the saved page that matches this URL
            // This enables offline caching for pages accessed directly via real URLs
            return findSavedPageIdForURL(url)
        }

        return nil
    }

    /// Find saved page ID that matches the given HTTPS URL
    private func findSavedPageIdForURL(_ url: URL) -> String? {
        // Query saved pages repository to find a page with matching URL
        let savedPagesRepository = SavedPagesRepository()
        let allSavedPages = savedPagesRepository.getSavedPages()

        // Find saved page with matching URL (normalized for comparison)
        let urlString = url.absoluteString
        let normalizedUrlString = normalizeWikiURL(url).absoluteString

        for savedPage in allSavedPages {
            let savedUrlString = savedPage.url.absoluteString
            let normalizedSavedUrl = normalizeWikiURL(savedPage.url).absoluteString

            // Check exact match or normalized match
            if savedUrlString == urlString ||
               normalizedSavedUrl == normalizedUrlString ||
               savedUrlString == normalizedUrlString ||
               normalizedSavedUrl == urlString {
                print("✅ ArticleViewModel: Found saved page ID \(savedPage.id) for URL: \(urlString)")
                return savedPage.id
            }
        }

        print("ℹ️ ArticleViewModel: No saved page found for URL: \(urlString)")
        return nil
    }

    /// Normalize URL for comparison (reuse SavedPagesViewModel logic)
    private func normalizeWikiURL(_ originalUrl: URL) -> URL {
        let urlString = originalUrl.absoluteString

        // Handle URL encoding issues like %26 → &
        let decodedUrlString: String
        if urlString.contains("%") {
            decodedUrlString = urlString.removingPercentEncoding ?? urlString
        } else {
            decodedUrlString = urlString
        }

        guard let decodedUrl = URL(string: decodedUrlString) else {
            return originalUrl
        }

        // Check if URL is already in correct format
        if osrsWebKitSecurityPolicy.isTrustedWikiHost(decodedUrl.host) &&
           decodedUrl.path.hasPrefix("/w/") {
            return decodedUrl
        }

        // Try to convert API URLs to article URLs
        if decodedUrl.path.contains("api.php") {
            if let pageComponent = URLComponents(url: decodedUrl, resolvingAgainstBaseURL: false),
               let queryItems = pageComponent.queryItems,
               let pageItem = queryItems.first(where: { $0.name == "page" }),
               let pageTitle = pageItem.value {
                let normalizedTitle = pageTitle.replacingOccurrences(of: " ", with: "_")
                if let normalizedUrl = URL(string: "https://oldschool.runescape.wiki/w/\(normalizedTitle)") {
                    return normalizedUrl
                }
            }
        }

        return decodedUrl
    }

    /// Check if page has complete cached assets (simplified check)
    private func hasCompleteCachedAssets(pageId: String) -> Bool {
        // For now, assume we always need to cache assets on first load
        // In the future, this could check if critical resources are already cached
        return false
    }

    // MARK: - History Tracking

    /// Add this page visit to history with enriched metadata
    /// Matches Android's PageHistoryManager.logPageVisit() functionality
    private func addToHistory(generation: Int) {
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Skipping stale history write for generation \(generation)")
            return
        }

        // Skip history tracking if excluded (for preview generation)
        guard !excludeFromHistory else {
            print("📚 ArticleViewModel: Skipping history tracking - excludeFromHistory=true")
            return
        }
        let pageTitle = resolvedPageTitleForHistory?.isEmpty == false
            ? resolvedPageTitleForHistory!
            : (pageTitle_?.isEmpty == false ? pageTitle_! : extractTitleFromUrl(pageUrl))
        let historyPageUrl = resolvedPageUrlForHistory ?? pageUrl

        // Use enriched history functionality to fetch metadata if not already available
        Task { [weak self] in
            guard let self = self else { return }
            if thumbnailUrl_ != nil && snippet_ != nil {
                // We already have metadata from navigation, use it directly
                let historyItem = HistoryItem(
                    id: UUID().uuidString,
                    pageTitle: pageTitle,
                    pageUrl: historyPageUrl,
                    visitedDate: Date(),
                    thumbnailUrl: thumbnailUrl_,
                    description: snippet_,
                    metadataUpdatedAt: Date()
                )

                await MainActor.run {
                    guard self.isCurrentLoad(generation) else {
                        print("🚫 ArticleViewModel: Skipping stale direct history write for generation \(generation)")
                        return
                    }
                    self.historyRepository.addToHistory(historyItem)
                    print("📚 ArticleViewModel: Added page to history with existing metadata: '\(historyItem.pageTitle)'")
                }
            } else {
                // Fetch enriched metadata for this page (matches Android behavior)
                let historyItem = await historyRepository.makeEnrichedHistoryEntry(
                    pageTitle: pageTitle,
                    pageUrl: historyPageUrl,
                    visitedDate: Date()
                )
                await MainActor.run {
                    guard self.isCurrentLoad(generation) else {
                        print("🚫 ArticleViewModel: Skipping stale enriched history write for generation \(generation)")
                        return
                    }
                    self.historyRepository.addToHistory(historyItem)
                    print("📚 ArticleViewModel: Added enriched page to history: '\(pageTitle)'")
                }
            }
        }
    }

    private func injectBundleAssetsViaUserScript(webView: WKWebView) {
        print("🎨 ArticleViewModel: Injecting CSS/JS assets via WKUserScript")

        // Remove any existing user scripts to avoid duplicates
        webView.configuration.userContentController.removeAllUserScripts()

        // Inject CSS files
        let cssAssets = [
            "themes.css",
            "base.css",
            "fonts.css",
            "layout.css",
            "components.css",
            "wiki-integration.css",
            "navbox_styles.css",
            "collapsible_tables.css",
            "collapsible_sections.css",
            "switch_infobox_styles.css",
            "fixes.css",
            "ios-article-aesthetics.css"
        ]

        // Load and inject CSS
        var combinedCSS = ""
        for cssFile in cssAssets {
            if let path = Bundle.main.path(forResource: cssFile, ofType: nil),
               let cssContent = try? String(contentsOfFile: path) {
                combinedCSS += cssContent + "\n"
                print("✅ Loaded CSS: \(cssFile)")
            } else {
                print("❌ Failed to load CSS: \(cssFile)")
            }
        }

        if !combinedCSS.isEmpty {
            let cssInjectionScript = """
            var style = document.createElement('style');
            style.innerHTML = `\(combinedCSS.replacingOccurrences(of: "`", with: "\\`"))`;
            document.head.appendChild(style);
            console.log('📱 iOS: Injected CSS styles via WKUserScript');
            """

            let cssUserScript = WKUserScript(source: cssInjectionScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(cssUserScript)
        }

        // Inject JavaScript files
        let jsAssets = [
            "startup.js",
            "tablesort.min.js",
            "tablesort_init.js",
            "gadget_calc_core.js",
            "osrs_calculator_runtime.js",
            "article_tools.js",
            "collapsible_content.js",
            "first_viewport_assets.js",
            "live_article_asset_warm.js",
            "infobox_switcher_bootstrap.js",
            "switch_infobox.js",
            "map_bridge.js",
            "horizontal_scroll_interceptor.js",
            "responsive_videos.js",
            "mobile_article_polish.js",
            "clipboard_bridge.js"
        ]

        // Load and inject JavaScript
        for jsFile in jsAssets {
            if let path = Bundle.main.path(forResource: jsFile, ofType: nil),
               let jsContent = try? String(contentsOfFile: path) {

                let jsInjectionScript = """
                \(jsContent)
                console.log('📱 iOS: Loaded JS script: \(jsFile)');
                """

                let jsUserScript = WKUserScript(source: jsInjectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                webView.configuration.userContentController.addUserScript(jsUserScript)
                print("✅ Injected JS: \(jsFile)")
            } else {
                print("❌ Failed to load JS: \(jsFile)")
            }
        }

        print("🎨 ArticleViewModel: Asset injection complete")
    }

    /// Inject theme colors into WebView (called from ArticleWebView.updateUIView)
    func injectThemeColors(_ themeManager: osrsThemeManager) {
        // Option B: Apply theme colors and final styling touches to achieve Android parity
        guard let webView = webView else { return }

        print("🎨 Option B: Applying theme colors and final styling for Android parity")
        applyThemeColors(webView: webView, themeManager: themeManager) {
            print("✅ Option B: Theme colors applied successfully")
        }
    }

    func applyLiveTheme(_ theme: any osrsThemeProtocol, themeManager: osrsThemeManager) {
        injectThemeColors(themeManager)
        let isDark = theme is osrsDarkTheme
        let pageColor = UIColor(theme.background)
        webView?.underPageBackgroundColor = pageColor
        webView?.backgroundColor = pageColor
        webView?.scrollView.backgroundColor = pageColor
        webView?.evaluateJavaScript(
            "if (window.OSRSWikiTheme) { window.OSRSWikiTheme.switchTheme(\(isDark)); }"
        )
        osrsPreparedArticleWebViewStore.shared.removeAll()
    }

    /// Apply iOS theme colors as CSS variables to match Android behavior
    private func applyThemeColors(webView: WKWebView, themeManager: osrsThemeManager, completion: @escaping () -> Void) {
        print("🎨 ArticleViewModel: Applying iOS theme colors as CSS variables")

        // Get current theme colors from iOS theme manager
        let currentTheme = themeManager.currentTheme

        // Map iOS theme colors to CSS variables (matching Android's colorSurfaceVariant etc)
        let themeColors: [String: String] = [
            "--colorsurface": currentTheme.surface.toHexString(),
            "--coloronsurface": currentTheme.onSurface.toHexString(),
            "--colorsurfacevariant": currentTheme.surfaceVariant.toHexString(),
            "--coloronsurfacevariant": currentTheme.onSurfaceVariant.toHexString(),
            "--colorprimarycontainer": currentTheme.primaryContainer.toHexString(),
            "--coloronprimarycontainer": currentTheme.onPrimaryContainer.toHexString(),
            "--coloroutline": currentTheme.outline.toHexString(),
            "--ooui-interface": currentTheme.surfaceVariant.toHexString(),
            "--ooui-interface-border": currentTheme.outline.toHexString()
        ]

        // Build JavaScript object string
        let jsObjectEntries = themeColors.map { key, value in
            "    '\(key)': '\(value)'"
        }.joined(separator: ",\n")

        // Create JavaScript to inject CSS custom properties
        let script = """
        (function() {
            try {
                console.log('📱 iOS: Starting theme color and font injection...');

                const themeColors = {
                \(jsObjectEntries)
                };

                console.log('📱 iOS: Theme colors object created:', themeColors);

                for (const [key, value] of Object.entries(themeColors)) {
                    document.documentElement.style.setProperty(key, value);
                }
                console.log('📱 iOS: Applied theme colors as CSS variables');

                // FEATURE PARITY FIX 1: Remove edit links like Android does
                console.log('📱 iOS: Removing [edit | edit source] links for Android parity');
                const editLinks = document.querySelectorAll('span.mw-editsection');
                editLinks.forEach(link => {
                    link.remove();
                });
                console.log('📱 iOS: Removed', editLinks.length, 'edit links');

                console.log('📱 iOS: ✅ All styling fixes completed successfully');

            } catch (error) {
                console.error('📱 iOS: CRITICAL ERROR in theme/font injection:', error);
                console.error('📱 iOS: Error name:', error.name);
                console.error('📱 iOS: Error message:', error.message);
                console.error('📱 iOS: Error stack:', error.stack);
            }
        })();
        """

        print("🎨 ArticleViewModel: Evaluating theme color injection JavaScript")
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("❌ ArticleViewModel: Theme color injection failed: \(error.localizedDescription)")
            } else {
                print("✅ ArticleViewModel: Theme colors applied successfully")
            }
            completion()
        }
    }

    /// Build HTML with proper asset links matching Android's approach
    private func buildHtmlWithAssetLinks(originalHtml: String, theme: any osrsThemeProtocol) -> String {
        print("🔗 ArticleViewModel: Building HTML with iOS asset links")

        // Extract body content and title from original HTML
        let bodyContent = extractBodyContent(from: originalHtml)
        let titleContent = extractTitleContent(from: originalHtml) ?? pageTitle

        // Use osrsPageHtmlBuilder to generate HTML with asset links
        let htmlBuilder = osrsPageHtmlBuilder()
        var htmlWithLinks = htmlBuilder.buildFullHtmlDocument(
            title: titleContent,
            bodyContent: bodyContent,
            theme: theme,
            collapseTablesEnabled: collapseTablesEnabled,
            includeAssetLinks: true,  // This generates <link> and <script> tags
            articleTextScale: articleTextScale,
            wrapTableCellsEnabled: wrapTableCellsEnabled
        )

        // Replace href and src attributes to use ios-assets:// scheme for internal resources only
        // CRITICAL FIX: Only convert relative/internal URLs, preserve external URLs
        htmlWithLinks = convertInternalUrlsToCustomScheme(htmlWithLinks)

        print("🔗 ArticleViewModel: Generated HTML with iOS asset links (\(htmlWithLinks.count) characters)")
        return htmlWithLinks
    }

    /// Convert only internal/relative URLs to custom scheme, preserve external URLs
    /// CRITICAL FIX: Prevents external wiki URLs from being converted to localhost
    private func convertInternalUrlsToCustomScheme(_ html: String) -> String {
        var processedHtml = html

        // Use regex to find and replace only relative/internal URLs
        // Pattern: href="something" or src="something" where something doesn't start with http/https

        // Fix href attributes - only convert non-HTTP URLs
        let hrefPattern = #"href="(?!https?://)([^"]+)""#
        processedHtml = processedHtml.replacingOccurrences(
            of: hrefPattern,
            with: "href=\"ios-assets://localhost/$1\"",
            options: .regularExpression
        )

        // Fix src attributes - only convert non-HTTP URLs
        let srcPattern = #"src="(?!https?://)([^"]+)""#
        processedHtml = processedHtml.replacingOccurrences(
            of: srcPattern,
            with: "src=\"ios-assets://localhost/$1\"",
            options: .regularExpression
        )

        print("🔧 FIXED: Converted only relative URLs to custom scheme, preserved external URLs")
        return processedHtml
    }

    // FREEZE FIX: Make HTML building async to prevent main thread blocking during asset loading
    private func buildEnhancedHtmlWithWorkingCSS(originalHtml: String) async -> String {
        print("🎨 ArticleViewModel: Building enhanced HTML with working CSS/JS system")

        // Load and verify CSS/JS assets from bundle (like the working test environment)
        let cssContent = await loadAllCSSAssets()
        let jsContent = await loadAllJSAssets()

        print("🎨 ArticleViewModel: Loaded \(cssContent.count) chars CSS, \(jsContent.count) chars JS")

        // Extract body content from original HTML
        let bodyContent = extractBodyContent(from: originalHtml)
        let titleContent = extractTitleContent(from: originalHtml) ?? pageTitle

        // Build final HTML with working inline styles that render properly
        let finalHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(titleContent)</title>
            <style>
                \(cssContent)

                /* Enhanced dark theme styles that actually work */
                body {
                    background-color: #1a1a1a !important;
                    color: #ffffff !important;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    line-height: 1.6;
                    margin: 0;
                    padding: 20px;
                }

                .page-header {
                    color: #ffd700 !important;
                    background: #2d2d2d !important;
                    padding: 15px !important;
                    margin: 0 0 20px 0 !important;
                    border-radius: 8px !important;
                }

                .wikitable {
                    background-color: #333 !important;
                    border: 2px solid #666 !important;
                    color: #ffffff !important;
                }

                .wikitable th {
                    background-color: #444 !important;
                    color: #ffd700 !important;
                    border: 1px solid #666 !important;
                }

                .wikitable td {
                    background-color: #2a2a2a !important;
                    border: 1px solid #666 !important;
                    color: #ffffff !important;
                }

                a {
                    color: #66b3ff !important;
                }

                a:visited {
                    color: #bb99ff !important;
                }

                /* Infobox styling */
                .infobox {
                    background-color: #2d2d2d !important;
                    border: 2px solid #666 !important;
                    color: #ffffff !important;
                }

                .infobox-header {
                    background-color: #444 !important;
                    color: #ffd700 !important;
                }
            </style>
        </head>
        <body>
            \(bodyContent)
            <script>
                \(jsContent)

                // Enhanced console debugging
                console.log('🎉 ArticleViewModel: Enhanced HTML with working CSS loaded successfully!');

                // Theme application
                document.body.classList.add('theme-osrs-dark');

                // Make page visible
                document.body.style.visibility = 'visible';
            </script>
        </body>
        </html>
        """

        print("🎨 ArticleViewModel: Built enhanced HTML document (\(finalHtml.count) characters)")
        return finalHtml
    }

    // FREEZE FIX: Make CSS asset loading async to prevent main thread blocking
    private func loadAllCSSAssets() async -> String {
        let cssFiles = [
            "styles/themes.css",
            "styles/base.css",
            "styles/fonts.css",
            "styles/layout.css",
            "styles/components.css",
            "styles/wiki-integration.css",
            "styles/navbox_styles.css",
            "web/collapsible_tables.css",
            "web/collapsible_sections.css",
            "styles/infobox_switcher.css",
            "styles/fixes.css",
            "styles/ios-article-aesthetics.css"
        ]

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var combinedCSS = ""
                var loadedCount = 0

                for cssFile in cssFiles {
                    if let path = Bundle.main.path(forResource: cssFile.replacingOccurrences(of: ".css", with: ""), ofType: "css", inDirectory: cssFile.contains("/") ? String(cssFile.prefix(upTo: cssFile.lastIndex(of: "/")!)) : nil),
                       let content = try? String(contentsOfFile: path) {
                        combinedCSS += content + "\n"
                        loadedCount += 1
                        print("✅ ArticleViewModel: Loaded CSS asset: \(cssFile)")
                    } else {
                        print("❌ ArticleViewModel: Failed to load CSS asset: \(cssFile)")
                    }
                }

                print("📊 ArticleViewModel: Successfully loaded \(loadedCount)/\(cssFiles.count) CSS files")
                continuation.resume(returning: combinedCSS)
            }
        }
    }

    // FREEZE FIX: Make JS asset loading async to prevent main thread blocking
    private func loadAllJSAssets() async -> String {
        let jsFiles = [
            "startup.js",
            "js/tablesort.min.js",
            "js/tablesort_init.js",
            "js/mediawiki/gadget_calc_core.js",
            "web/osrs_calculator_runtime.js",
            "web/article_tools.js",
            "web/collapsible_content.js",
            "web/first_viewport_assets.js",
            "web/live_article_asset_warm.js",
            "web/infobox_switcher_bootstrap.js",
            "web/switch_infobox.js",
            "web/map_bridge.js",
            "web/horizontal_scroll_interceptor.js",
            "web/responsive_videos.js",
            "web/mobile_article_polish.js",
            "web/clipboard_bridge.js"
        ]

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var combinedJS = ""
                var loadedCount = 0

                for jsFile in jsFiles {
                    if let path = Bundle.main.path(forResource: jsFile.replacingOccurrences(of: ".js", with: ""), ofType: "js", inDirectory: jsFile.contains("/") ? String(jsFile.prefix(upTo: jsFile.lastIndex(of: "/")!)) : nil),
                       let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        combinedJS += content + "\n"
                        loadedCount += 1
                        print("✅ ArticleViewModel: Loaded JS asset: \(jsFile)")
                    } else {
                        print("❌ ArticleViewModel: Failed to load JS asset: \(jsFile)")
                    }
                }

                print("📊 ArticleViewModel: Successfully loaded \(loadedCount)/\(jsFiles.count) JS files")
                continuation.resume(returning: combinedJS)
            }
        }
    }

    private func extractBodyContent(from html: String) -> String {
        // Extract content between <body> tags
        if let bodyStart = html.range(of: "<body", options: .caseInsensitive),
           let bodyTagEnd = html.range(of: ">", range: bodyStart.upperBound..<html.endIndex),
           let bodyEnd = html.range(of: "</body>", options: .caseInsensitive) {
            return String(html[bodyTagEnd.upperBound..<bodyEnd.lowerBound])
        }

        // If no body tags found, return the entire HTML as content
        return html
    }

    private func extractTitleContent(from html: String) -> String? {
        // Extract title from HTML
        if let titleStart = html.range(of: "<title>", options: .caseInsensitive),
           let titleEnd = html.range(of: "</title>", options: .caseInsensitive) {
            return String(html[titleStart.upperBound..<titleEnd.lowerBound])
        }
        return nil
    }

    private func loadTestHtml() {
        print("🧪 ArticleViewModel: Loading test HTML")

        let testHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Test Article</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #FF0000 !important;
                    color: #FFFFFF !important;
                    min-height: 100vh;
                }
                h1 {
                    color: #FFFF00 !important;
                    background: #000000;
                    padding: 10px;
                    margin: 0 0 20px 0;
                }
                .test-content {
                    background: #0000FF !important;
                    color: #FFFFFF !important;
                    padding: 20px;
                    border: 3px solid #FFFFFF;
                    margin: 20px 0;
                }
                p, li { color: #FFFFFF !important; }
                code {
                    background: #FFFF00 !important;
                    color: #000000 !important;
                    padding: 2px 4px;
                }
            </style>
        </head>
        <body>
            <h1>🧪 DEBUG: Test Article Loaded Successfully!</h1>
            <div class="test-content">
                <p><strong>SUCCESS!</strong> If you can see this colorful test page, the custom HTML loading is working!</p>
                <p>Original URL: <code>\(pageUrl.absoluteString)</code></p>
                <p>Page Title: <code>\(pageTitle_ ?? "nil")</code></p>
                <p>Page ID: <code>\(pageId?.description ?? "nil")</code></p>
                <p>Status Check:</p>
                <ul>
                    <li>✅ ArticleViewModel.loadArticle() was called</li>
                    <li>✅ loadTestHtml() was executed</li>
                    <li>✅ WebView.loadHTMLString() was called</li>
                    <li>✅ HTML is rendering in WebView</li>
                </ul>
                <p><strong>Next step:</strong> Debug the actual wiki API loading mechanism...</p>
            </div>
            <script>
                console.log('🧪 Test HTML loaded successfully!');
                document.body.style.visibility = 'visible';
            </script>
        </body>
        </html>
        """

        print("🧪 ArticleViewModel: About to call loadHTMLString")
        print("🧪 ArticleViewModel: webView is \(webView == nil ? "nil" : "not nil")")

        if let webView = webView {
            print("🧪 ArticleViewModel: Calling webView.loadHTMLString with \(testHtml.count) characters...")

            // Use proper base URL like Android does - create a local asset domain
            let baseURL = URL(string: "https://oldschool.runescape.wiki/")!
            webView.loadHTMLString(testHtml, baseURL: baseURL)
            print("🧪 ArticleViewModel: loadHTMLString called successfully with baseURL: \(baseURL)")

            // After loading, reveal the body like Android does
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("🧪 ArticleViewModel: Revealing body content...")
                self.revealBody(webView: webView)
            }
        } else {
            print("❌ ArticleViewModel: webView is nil! Cannot load HTML")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isLoading = false
            self.loadingProgress = 1.0
            self.pageTitle = "Test Article"
        }
    }

    func completeLoadingWithBodyReveal() {
        markJavaScriptReady(for: currentLoadGeneration)
    }

    func completeLoadingWithBodyReveal(loadGeneration: Int?) {
        guard let loadGeneration = loadGeneration else {
            print("🚫 ArticleViewModel: Ignoring JavaScript readiness without load generation")
            return
        }
        markJavaScriptReady(for: loadGeneration)
    }

    private func scheduleReadinessTimeout(for generation: Int) {
        readinessTimeoutWorkItem?.cancel()

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrentLoad(generation), self.isLoading || self.isRefreshing else { return }
            let timeString = DateFormatter.timeFormatter.string(from: Date())
            print("⚠️ [\(timeString)] ARTICLE READINESS TIMEOUT: generation \(generation) did not reach WebKit+JS readiness")
            self.isLoading = false
            self.isRefreshing = false
            self.loadingProgressText = nil
            self.errorMessage = "Page rendering timed out. Please try reloading."
        }

        readinessTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
    }

    private func markWebKitReady(for generation: Int) {
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring stale WebKit readiness for generation \(generation)")
            return
        }

        webKitReadyGeneration = generation
        attemptCompleteCurrentLoad(generation: generation)
    }

    private func markJavaScriptReady(for generation: Int) {
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring stale JavaScript readiness for generation \(generation)")
            return
        }

        javaScriptReadyGeneration = generation
        if isLoading || isRefreshing {
            loadingProgress = max(loadingProgress, 0.97)
            loadingProgressText = "Revealing content..."
        }
        attemptCompleteCurrentLoad(generation: generation)
    }

    private func attemptCompleteCurrentLoad(generation: Int) {
        guard isCurrentLoad(generation),
              webKitReadyGeneration == generation,
              javaScriptReadyGeneration == generation,
              completedLoadGeneration != generation else {
            return
        }

        completedLoadGeneration = generation
        readinessTimeoutWorkItem?.cancel()
        finishLoadingWithBodyReveal(generation: generation)
    }

    private func finishLoadingWithBodyReveal(generation: Int) {
        guard let webView = webView else {
            print("❌ ArticleViewModel: WebView not available for body reveal")
            return
        }

        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🏁 COMPLETING PROGRESS: WebKit and JS ready for generation \(generation)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isCurrentLoad(generation) else {
                print("🚫 ArticleViewModel: Ignoring stale reveal for generation \(generation)")
                return
            }

            let revealTimeString = DateFormatter.timeFormatter.string(from: Date())
            print("📊 [\(revealTimeString)] 👁️ REVEALING BODY: Making content visible to user...")

            // CRITICAL FIX: Wrap JavaScript to not return value that causes WKWebView type error
            let revealBodyJs = """
                (function() {
                    try {
                        if (document.body) {
                            document.body.style.visibility = 'visible';
                            console.log('📱 iOS: Body visibility set to visible');
                            return 'success';
                        } else {
                            console.log('📱 iOS: document.body not found');
                            return 'no_body';
                        }
                    } catch (error) {
                        console.log('📱 iOS: Error revealing body:', error);
                        return 'error';
                    }
                })();
            """

            webView.evaluateJavaScript(revealBodyJs) { result, error in
                DispatchQueue.main.async {
                    guard self.isCurrentLoad(generation) else {
                        print("🚫 ArticleViewModel: Ignoring stale reveal callback for generation \(generation)")
                        return
                    }
                    let completionTimeString = DateFormatter.timeFormatter.string(from: Date())
                    if let error = error {
                        print("📊 [\(completionTimeString)] ❌ BODY REVEAL FAILED: \(error)")
                        // Attempt fallback approach
                        webView.evaluateJavaScript("void(document.body && (document.body.style.visibility = 'visible'));") { fallbackResult, fallbackError in
                            if let fallbackError = fallbackError {
                                print("📊 [\(completionTimeString)] ❌ FALLBACK REVEAL FAILED: \(fallbackError)")
                            } else {
                                print("📊 [\(completionTimeString)] ✅ FALLBACK REVEAL SUCCEEDED")
                            }
                        }
                    } else if let resultString = result as? String {
                        print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - result: \(resultString)")
                    } else {
                        print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - user can see page content!")
                    }

                    // Record final page visibility time for timing measurements
                    self.pageVisibilityTime = Date()
                    self.progressCompletionTime = Date()
                    self.loadingProgress = 1.0
                    self.loadingProgressText = "Complete!"
                    self.isLoading = false
                    self.isRefreshing = false
                    print("✅ ArticleViewModel: Loading completed for generation \(generation)!")
                    self.addToHistory(generation: generation)
                    self.startRenderedArticleIdentityProbe(for: generation)
                    self.articleRevealedForWarm = true
                    self.startLiveArticleAssetWarmIfNeeded()
                }
            }
        }
    }

    private func revealBody(webView: WKWebView) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        // CRITICAL FIX: Wrap JavaScript to not return value that causes WKWebView type error
        let revealBodyJs = """
            (function() {
                try {
                    if (document.body) {
                        document.body.style.visibility = 'visible';
                        console.log('📱 iOS: Body visibility set to visible');
                        return 'success';
                    } else {
                        console.log('📱 iOS: document.body not found');
                        return 'no_body';
                    }
                } catch (error) {
                    console.log('📱 iOS: Error revealing body:', error);
                    return 'error';
                }
            })();
        """
        print("📊 [\(timeString)] 👁️ REVEALING BODY: Making content visible to user...")

        webView.evaluateJavaScript(revealBodyJs) { result, error in
            let completionTimeString = DateFormatter.timeFormatter.string(from: Date())
            if let error = error {
                print("📊 [\(completionTimeString)] ❌ BODY REVEAL FAILED: \(error)")
                // Attempt fallback approach
                webView.evaluateJavaScript("void(document.body && (document.body.style.visibility = 'visible'));") { fallbackResult, fallbackError in
                    if let fallbackError = fallbackError {
                        print("📊 [\(completionTimeString)] ❌ FALLBACK REVEAL FAILED: \(fallbackError)")
                    } else {
                        print("📊 [\(completionTimeString)] ✅ FALLBACK REVEAL SUCCEEDED")
                    }
                }
            } else if let resultString = result as? String {
                print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - result: \(resultString)")
            } else {
                print("📊 [\(completionTimeString)] ✅ CONTENT NOW VISIBLE: Body revealed - user can see page content!")
            }
        }
    }

    private func extractTitleFromUrl(_ url: URL) -> String {
        // Extract article title from wiki URL
        // Examples:
        // https://oldschool.runescape.wiki/w/Dragon -> "Dragon"
        // https://oldschool.runescape.wiki/w/Update:The_Way_of_the_Forester -> "Update:The Way of the Forester"
        // https://oldschool.runescape.wiki/?curid=123 -> fall back to URL

        print("🔗 ArticleViewModel: Processing URL: \(url.absoluteString)")

        let path = url.path
        print("🔗 ArticleViewModel: URL path: '\(path)'")

        if path.hasPrefix("/w/") {
            let encodedTitle = String(path.dropFirst(3)) // Remove "/w/"
            print("🔗 ArticleViewModel: Raw encoded title: '\(encodedTitle)'")

            // First decode any URL encoding
            let partiallyDecoded = encodedTitle.removingPercentEncoding ?? encodedTitle
            print("🔗 ArticleViewModel: After percent decoding: '\(partiallyDecoded)'")

            // Then replace underscores with spaces (wiki convention)
            let decodedTitle = partiallyDecoded.replacingOccurrences(of: "_", with: " ")
            print("🔗 ArticleViewModel: Final decoded title: '\(decodedTitle)'")

            // Clean up any remaining encoding artifacts
            let cleanTitle = cleanUpTitle(decodedTitle)
            print("🔗 ArticleViewModel: Cleaned title: '\(cleanTitle)'")

            return cleanTitle
        }

        // For curid URLs, we'd need the pageId which should be passed in init
        let fallback = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let cleanFallback = cleanUpTitle(fallback.replacingOccurrences(of: "_", with: " "))
        print("🔗 ArticleViewModel: Using fallback title '\(cleanFallback)' from URL")
        return cleanFallback
    }

    private func cleanUpTitle(_ title: String) -> String {
        var cleanTitle = title

        // Remove any remaining percent-encoded characters that might have slipped through
        while cleanTitle.contains("%") && cleanTitle != (cleanTitle.removingPercentEncoding ?? cleanTitle) {
            cleanTitle = cleanTitle.removingPercentEncoding ?? cleanTitle
        }

        // Clean up common encoding artifacts
        cleanTitle = cleanTitle
            .replacingOccurrences(of: "%20-", with: " ")  // Fix malformed encoding
            .replacingOccurrences(of: "%20", with: " ")   // Any remaining %20
            .replacingOccurrences(of: "%3A", with: ":")   // Colon
            .replacingOccurrences(of: "%2C", with: ",")   // Comma
            .replacingOccurrences(of: "%26", with: "&")   // Ampersand
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple spaces into single spaces
        while cleanTitle.contains("  ") {
            cleanTitle = cleanTitle.replacingOccurrences(of: "  ", with: " ")
        }

        return cleanTitle
    }

    func goBack() -> Bool {
        guard let webView = webView, webView.canGoBack else { return false }
        webView.goBack()
        return true
    }

    var articleBackTransitionIdentity: String {
        let renderedURL = webView?.url?.absoluteString ?? pageUrl.absoluteString
        return "page=\(pageUrl.absoluteString)|rendered=\(renderedURL)"
    }

    func goBackToPreviousWebViewArticleIfNeeded() -> Bool {
        guard let webView = webView,
              webView.canGoBack,
              let currentURL = webView.url,
              Self.osrsShouldUseWebViewArticleHistory(currentURL: currentURL, pageURL: pageUrl) else {
            return false
        }

        print("🔙 ArticleViewModel: Falling back to WebView article history from \(currentURL.absoluteString)")
        webView.goBack()
        return true
    }

    func goForward() -> Bool {
        guard let webView = webView, webView.canGoForward else { return false }
        webView.goForward()
        return true
    }

    func toggleBookmark() {
        isBookmarked.toggle()
        // TODO: Implement actual bookmark persistence
    }

    func scrollToSection(_ sectionId: String) {
        webView?.evaluateJavaScript(Self.osrsScrollToSectionScript(for: sectionId)) { [weak self] result, _ in
            guard let webView = self?.webView else { return }
            let y: CGFloat
            if let number = result as? Double {
                y = CGFloat(number)
            } else if let number = result as? Int {
                y = CGFloat(number)
            } else if let number = result as? NSNumber {
                y = CGFloat(truncating: number)
            } else {
                return
            }
            guard y >= 0 else { return }
            webView.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }

    static func osrsScrollToSectionScript(for sectionId: String) -> String {
        let sectionIdLiteral = osrsJavaScriptStringLiteral(sectionId)
        return """
            (function() {
                const sectionId = \(sectionIdLiteral);
                const escapedId = (window.CSS && CSS.escape)
                    ? CSS.escape(sectionId)
                    : sectionId.replace(/[\"\\\\]/g, '\\\\$&');
                const wanted = sectionId.replace(/_/g, ' ').trim().toLowerCase();
                let element = document.getElementById(sectionId)
                    || document.querySelector('[id="' + escapedId + '"]')
                    || Array.from(document.querySelectorAll('caption, h1, h2, h3, h4, th, .mw-headline')).find(function(node) {
                        const clone = node.cloneNode(true);
                        const hideSel = document.body.classList.contains('floornumber-setting-us')
                            ? '.floornumber-gb, .floornumber-help'
                            : '.floornumber-us, .floornumber-help';
                        clone.querySelectorAll(hideSel).forEach(function(mark) { mark.remove(); });
                        return (clone.textContent || '').replace(/\\s+/g, ' ').trim().toLowerCase() === wanted
                            || (node.id || '').toLowerCase() === sectionId.toLowerCase();
                    });
                if (!element) {
                    return -1;
                }

                const headerOffset = (function() {
                    const cs = getComputedStyle(document.documentElement);
                    const parsePx = function(value) {
                        const n = parseFloat(value);
                        return Number.isFinite(n) ? n : 0;
                    };
                    return Math.max(parsePx(cs.scrollPaddingTop), parsePx(cs.paddingTop), 0);
                })();
                if (headerOffset > 0) {
                    element.style.scrollMarginTop = headerOffset + 'px';
                }
                const rectTop = element.getBoundingClientRect().top;
                const scrollTop = window.pageYOffset || document.documentElement.scrollTop || 0;
                const targetY = Math.max(0, scrollTop + rectTop - headerOffset);
                try { window.scrollTo(0, targetY); } catch (e2) {}
                return targetY;
            })();
        """
    }

    private static func osrsJavaScriptStringLiteral(_ value: String) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let encodedArray = String(data: data, encoding: .utf8),
              encodedArray.count >= 2 else {
            return "\"\""
        }

        return String(encodedArray.dropFirst().dropLast())
    }

    func clearError() {
        errorMessage = nil
    }

    // JavaScript bridge methods - updated to match Android CSS variable injection
    // (Note: The injectThemeColors implementation is now at line 395)

    private func applyTableOfContents(
        from html: String,
        convention: osrsArticleFloorConvention = .current()
    ) {
        lastTableOfContentsHTML = html
        lastLoadedArticleHTML = html
        let sections = osrsArticleTableOfContentsExtractor.extract(
            displayTitle: pageTitle,
            html: html,
            convention: convention
        )
        tableOfContents = sections
        hasTableOfContents = sections.count > 1
    }

    func extractTableOfContents() {
        if !tableOfContents.isEmpty {
            hasTableOfContents = true
            return
        }
        let tocScript = """
            (function() {
                const headings = document.querySelectorAll('h2, h3');
                const toc = [];

                headings.forEach((heading, index) => {
                    const level = parseInt(heading.tagName.substring(1));
                    const clone = heading.cloneNode(true);
                    const hideSel = document.body.classList.contains('floornumber-setting-us')
                        ? '.floornumber-gb, .floornumber-help'
                        : '.floornumber-us, .floornumber-help';
                    clone.querySelectorAll(hideSel).forEach((node) => node.remove());
                    const text = (clone.textContent || '').replace(/\\s+/g, ' ').trim();
                    const id = heading.id || heading.querySelector('[id]')?.id || ('heading-' + index);

                    if (!heading.id) {
                        heading.id = id;
                    }

                    if (text) {
                        toc.push({
                            id: id,
                            title: text,
                            level: level
                        });
                    }
                });

                return JSON.stringify(toc);
            })();
        """

        webView?.evaluateJavaScript(tocScript) { [weak self] result, error in
            guard let self = self,
                  let jsonString = result as? String,
                  let jsonData = jsonString.data(using: .utf8) else { return }

            do {
                let sections = try JSONDecoder().decode([TableOfContentsSection].self, from: jsonData)
                DispatchQueue.main.async {
                    self.tableOfContents = sections
                    self.hasTableOfContents = !sections.isEmpty
                }
            } catch {
                print("Failed to parse table of contents: \(error)")
            }
        }
    }

    deinit {
        if let proxyCacheSessionToken {
            Task { @MainActor in
                ProxyInterceptorService.shared.disableMode(owner: proxyCacheSessionToken)
            }
        }
        currentLoadTask?.cancel()
        readinessTimeoutWorkItem?.cancel()
        reloadTimeoutWorkItem?.cancel()
        refreshTimeoutWorkItem?.cancel()
        deferredRefreshWorkItem?.cancel()
        deferredMapPreloadTask?.cancel()
        progressObserver?.invalidate()
        renderedArticleIdentityProbe?.invalidate()

        // Clean up preloaded maps when ArticleViewModel is deallocated
        Task { @MainActor in
            osrsMapPreloadService.shared.clearPreloadedMaps()
        }

        print("🧹 ArticleViewModel: Cleaned up and deallocated")
    }
}

// MARK: - WKNavigationDelegate
extension ArticleViewModel: WKNavigationDelegate {
    func recoverRenderedArticleMismatchIfNeeded(
        theme: any osrsThemeProtocol,
        fallbackToNativeBack: @escaping () -> Void
    ) -> Bool {
        guard let webView = webView else {
            return false
        }

        webView.evaluateJavaScript(Self.renderedArticleTitleScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else {
                    fallbackToNativeBack()
                    return
                }

                if let error = error {
                    print("⚠️ ArticleViewModel: Rendered mismatch recovery probe failed: \(error.localizedDescription)")
                    fallbackToNativeBack()
                    return
                }

                guard let renderedTitle = result as? String,
                      !renderedTitle.isEmpty,
                      let renderedArticleURL = Self.articleURL(forResolvedTitle: renderedTitle),
                      renderedArticleURL.absoluteString != self.pageUrl.absoluteString else {
                    fallbackToNativeBack()
                    return
                }

                print("🔙 ArticleViewModel: Recovering source article after unbound rendered article mutation")
                print("  - Rendered title: \(renderedTitle)")
                print("  - Rendered URL: \(renderedArticleURL.absoluteString)")
                print("  - Expected URL: \(self.pageUrl.absoluteString)")
                self.stopRenderedArticleIdentityProbe()
                self.loadArticle(theme: theme, isReload: true)
            }
        }

        return true
    }

    private static let renderedArticleTitleScript = """
        (function() {
            const candidates = [
                document.querySelector('#firstHeading'),
                document.querySelector('h1.page-header'),
                document.querySelector('.mw-page-title-main'),
                document.querySelector('h1')
            ];
            for (const candidate of candidates) {
                if (candidate && candidate.textContent) {
                    const text = candidate.textContent.trim();
                    if (text) {
                        return text;
                    }
                }
            }
            if (document.title) {
                return document.title.replace(/\\s+-\\s+OSRS Wiki.*$/i, '').trim();
            }
            return '';
        })();
        """

    private func startRenderedArticleIdentityProbe(for generation: Int) {
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
        renderedArticleIdentityProbeAttempts = 0

        guard isCurrentLoad(generation), !excludeFromHistory else { return }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self, self.isCurrentLoad(generation), let webView = self.webView else {
                    timer.invalidate()
                    return
                }

                self.renderedArticleIdentityProbeAttempts += 1
                if self.renderedArticleIdentityProbeAttempts > 24 {
                    timer.invalidate()
                    if let activeTimer = self.renderedArticleIdentityProbe, activeTimer === timer {
                        self.renderedArticleIdentityProbe = nil
                    }
                    return
                }

                self.routeRenderedArticleNavigationIfNeeded(in: webView, context: "renderedArticleIdentityProbe")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        renderedArticleIdentityProbe = timer
    }

    private func stopRenderedArticleIdentityProbe() {
        renderedArticleIdentityProbe?.invalidate()
        renderedArticleIdentityProbe = nil
    }

    private func routeRenderedArticleNavigationIfNeeded(in webView: WKWebView, context: String) {
        webView.evaluateJavaScript(Self.renderedArticleTitleScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("⚠️ WEBVIEW: Rendered article identity probe failed: \(error.localizedDescription)")
                    return
                }
                guard let renderedTitle = result as? String,
                      !renderedTitle.isEmpty,
                      renderedTitle.contains("/"),
                      let articleURL = Self.articleURL(forResolvedTitle: renderedTitle) else {
                    return
                }

                guard articleURL.absoluteString != self.pageUrl.absoluteString else {
                    return
                }

                let routeKey = articleURL.absoluteString
                guard !self.routedObservedArticleNavigationURLs.contains(routeKey) else {
                    return
                }

                self.routedObservedArticleNavigationURLs.insert(routeKey)
                self.stopRenderedArticleIdentityProbe()
                print("🔄 WEBVIEW: Promoting rendered \(context) article identity into native stack:")
                print("  - Rendered title: \(renderedTitle)")
                print("  - Article URL: \(articleURL.absoluteString)")
                print("  - Current ArticleViewModel URL: \(self.pageUrl.absoluteString)")
                self.navigateToInternalArticle?(articleURL)
            }
        }
    }

    private func routeObservedUnboundArticleNavigationIfNeeded(in webView: WKWebView, context: String) -> Bool {
        guard let observedURL = webView.url,
              let articleURL = osrsArticleLinkRouter.appArticleURL(for: observedURL) else {
            return false
        }

        guard Self.osrsShouldPromoteWebViewArticleNavigation(candidateURL: articleURL, pageURL: pageUrl) else {
            return false
        }

        let routeKey = articleURL.absoluteString
        guard !routedObservedArticleNavigationURLs.contains(routeKey) else {
            return true
        }

        routedObservedArticleNavigationURLs.insert(routeKey)
        print("🔄 WEBVIEW: Promoting unbound \(context) article navigation into native stack:")
        print("  - Observed URL: \(observedURL.absoluteString)")
        print("  - Article URL: \(articleURL.absoluteString)")
        print("  - Current ArticleViewModel URL: \(pageUrl.absoluteString)")

        webView.stopLoading()
        DispatchQueue.main.async { [weak self] in
            self?.navigateToInternalArticle?(articleURL)
        }
        return true
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🚀 WEBVIEW: didStartProvisionalNavigation - WebKit started loading")
        print("🛠️ WEBVIEW DIAGNOSTIC: Navigation details:")
        print("  - Current URL: \(webView.url?.absoluteString ?? "nil")")
        print("  - Loading: \(webView.isLoading)")
        print("  - Estimated Progress: \(webView.estimatedProgress)")
        print("  - Can Go Back: \(webView.canGoBack)")
        print("  - Can Go Forward: \(webView.canGoForward)")

        if boundGeneration(for: navigation) == nil,
           routeObservedUnboundArticleNavigationIfNeeded(in: webView, context: "didStartProvisionalNavigation") {
            return
        }

        guard let generation = boundGeneration(for: navigation),
              isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring didStartProvisionalNavigation for stale or unbound WebKit navigation")
            return
        }

        isLoading = true
        errorMessage = nil
    }

    private func osrsLogCalculatorProbe(in webView: WKWebView) {
        let script = """
        (function() {
            if (!document.querySelector('pre.jcConfig')) { return null; }
            var form = document.querySelector('[id$="Form"], #form');
            return JSON.stringify({
                coreImpl: !!window.__osrsCalcCoreImplemented,
                coreRan: !!window.__osrsCalcCoreFactoryRan,
                coreAttr: document.documentElement.getAttribute('data-osrs-calc-core'),
                jquery: typeof (window.jQuery || window.$),
                OO: !!(window.OO && OO.ui && OO.ui.FieldsetLayout),
                widgets: !!(window.mw && mw.widgets && mw.widgets.TitleInputWidget),
                rs: !!(window.rs && typeof rs.hasLocalStorage === 'function'),
                bodyContent: !!document.getElementById('bodyContent'),
                jc: document.querySelectorAll('pre.jcConfig').length,
                waiting: !!(form && /please wait/i.test(form.textContent || '')),
                formId: form ? form.id : null,
                patched: !!(window.jQuery && jQuery.ajax && jQuery.ajax.__osrsCalculatorPatched),
                resultLen: (function() {
                    var node = document.querySelector('[id$="Result"]');
                    return node ? (node.textContent || '').trim().length : 0;
                })(),
                resultPreview: (function() {
                    var node = document.querySelector('[id$="Result"]');
                    return node ? String(node.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 160) : '';
                })(),
                loader: (window.mw && mw.loader && mw.loader.getState) ? {
                    jquery: mw.loader.getState('jquery'),
                    oojs: mw.loader.getState('oojs'),
                    ooui: mw.loader.getState('oojs-ui-core'),
                    widgets: mw.loader.getState('mediawiki.widgets'),
                    calc: mw.loader.getState('ext.gadget.calc-core')
                } : null,
                errors: window.__osrsCalcErrors || []
            });
        })();
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak webView] in
            webView?.evaluateJavaScript(script) { result, error in
                NSLog("osrsCalcProbe: %@ error=%@", String(describing: result), String(describing: error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🌐 WEBKIT NAVIGATION FINISHED: Basic HTML loaded")
        if boundGeneration(for: navigation) == nil,
           routeObservedUnboundArticleNavigationIfNeeded(in: webView, context: "didFinish") {
            return
        }

        guard let generation = boundGeneration(for: navigation) else {
            print("🚫 ArticleViewModel: Ignoring didFinish for unbound WebKit navigation")
            return
        }
        guard isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring stale didFinish for generation \(generation)")
            return
        }
        clearBoundWebKitNavigation(navigation)
        osrsLogCalculatorProbe(in: webView)
        startDeferredMapPreloadAfterWebKitReady(generation: generation, webView: webView)
        if let pipeline = articlePipelineLoads.removeValue(forKey: generation) {
            let elapsed = Date().timeIntervalSince(pipeline.startedAt)
            Task {
                await osrsArticleDocumentCoordinator.shared.recordWebKitReady(
                    identity: pipeline.identity,
                    elapsed: elapsed
                )
            }
        }

        // TIMING MEASUREMENT: Record when WebView navigation completes (NOT when content is visible)
        if progressCompletionTime != nil && pageVisibilityTime == nil {
            pageVisibilityTime = Date()
            print("📊 [\(timeString)] 📄 NAVIGATION COMPLETE: WebView finished loading HTML")

            // Calculate and log the delay
            if let startTime = progressCompletionTime, let endTime = pageVisibilityTime {
                let delay = endTime.timeIntervalSince(startTime)

                // Store the measured delay for external access
                self.lastMeasuredDelay = delay

                print("📊 TIMING RESULT: Progress-to-page delay = \(String(format: "%.3f", delay))s")

                // Provide automated optimization suggestions based on measured data
                if delay > 0.5 {
                    print("🔧 OPTIMIZATION: SEVERE delay detected (\(String(format: "%.3f", delay))s). Check WebView rendering pipeline.")
                } else if delay > 0.1 {
                    print("🔧 OPTIMIZATION: MODERATE delay (\(String(format: "%.3f", delay))s). Consider optimizing progress completion logic.")
                } else {
                    print("✅ OPTIMIZATION: Timing is within acceptable range (\(String(format: "%.3f", delay))s).")
                }
            }
        }

        // Extract table of contents from the loaded content
        extractTableOfContents()
        markWebKitReady(for: generation)
        applyAccessibilityReflow(to: webView)

        // CRITICAL FIX: Complete progress for web archives immediately after loading
        if pageUrl.scheme == "app-assets" || webView.url?.scheme == "file" {
            print("📦 [\(timeString)] WEB ARCHIVE LOADED: Marking JavaScript readiness for generation \(generation)")
            completeLoadingWithBodyReveal(loadGeneration: generation)
            return
        }

        // For live HTTPS pages: Inject styling complete notification similar to Android
        webView.evaluateJavaScript("""
            if (window.RenderTimeline) {
                window.RenderTimeline.log('Event: StylingScriptsComplete:\(generation)');
            }
        """)

        print("🎉 ArticleViewModel: Page rendering complete")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        osrsWebViewThemePaint.noteWebContentProcessTerminated(webView)
        print("⚠️ ArticleViewModel: Web content process terminated; requesting article recovery")
        adoptedPreRenderedDocument = false
        forceNextDocumentReload = true
        needsContentProcessRecovery = true
    }

    func playYouTubeVideo(id: String) {
        guard let url = osrsYouTubeEmbed.playerURL(videoID: id) else { return }
        pendingYouTubeEmbedURL = url
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] ❌ WEBVIEW: didFail - Navigation failed after starting")
        analyzeWebViewError(error: error, context: "didFail", webView: webView)

        guard let generation = boundGeneration(for: navigation),
              isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring didFail for stale or unbound WebKit navigation")
            return
        }
        clearBoundWebKitNavigation(navigation)
        isLoading = false
        isRefreshing = false
        errorMessage = UserFacingError.message(for: error, fallback: "This page could not be loaded. Please try again.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] ❌ WEBVIEW: didFailProvisionalNavigation - Navigation failed before starting")
        analyzeWebViewError(error: error, context: "didFailProvisionalNavigation", webView: webView)

        guard let generation = boundGeneration(for: navigation),
              isCurrentLoad(generation) else {
            print("🚫 ArticleViewModel: Ignoring provisional failure for stale or unbound WebKit navigation")
            return
        }
        clearBoundWebKitNavigation(navigation)
        isLoading = false
        isRefreshing = false
        errorMessage = UserFacingError.message(for: error, fallback: "This page could not be loaded. Please try again.")
    }

    // MARK: - Comprehensive Error Analysis

    private func analyzeWebViewError(error: Error, context: String, webView: WKWebView) {
        print("🛠️ WEBVIEW ERROR ANALYSIS (\(context)):")
        print("  - Error Domain: \(error._domain)")
        print("  - Error Code: \(error._code)")
        print("  - Error Description: \(error.localizedDescription)")
        print("  - Current URL: \(webView.url?.absoluteString ?? "nil")")
        print("  - Target URL: \(pageUrl.absoluteString)")

        // Analyze specific error types
        if let nsError = error as NSError? {
            print("  - NSError Domain: \(nsError.domain)")
            print("  - NSError Code: \(nsError.code)")
            print("  - NSError UserInfo: \(nsError.userInfo)")

            // Analyze common WebKit error codes
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                print("  - ANALYSIS: No internet connection")
            case NSURLErrorTimedOut:
                print("  - ANALYSIS: Request timed out")
            case NSURLErrorCannotFindHost:
                print("  - ANALYSIS: Cannot find host - DNS resolution failed")
            case NSURLErrorCannotConnectToHost:
                print("  - ANALYSIS: Cannot connect to host - network/firewall issue")
            case NSURLErrorNetworkConnectionLost:
                print("  - ANALYSIS: Network connection lost during request")
            case NSURLErrorDNSLookupFailed:
                print("  - ANALYSIS: DNS lookup failed")
            case NSURLErrorHTTPTooManyRedirects:
                print("  - ANALYSIS: Too many HTTP redirects")
            case NSURLErrorResourceUnavailable:
                print("  - ANALYSIS: Resource unavailable")
            case NSURLErrorNotConnectedToInternet:
                print("  - ANALYSIS: Not connected to internet")
            case NSURLErrorBadURL:
                print("  - ANALYSIS: Malformed URL")
            case NSURLErrorUnsupportedURL:
                print("  - ANALYSIS: Unsupported URL scheme")
            case NSURLErrorCannotParseResponse:
                print("  - ANALYSIS: Cannot parse server response")
            default:
                print("  - ANALYSIS: Unknown error code \(nsError.code)")
            }

            // Check for specific WebKit error domains
            if nsError.domain == "WebKitErrorDomain" {
                print("  - ANALYSIS: WebKit-specific error")
                switch nsError.code {
                case 101:
                    print("  - ANALYSIS: WebKit frame load interrupted")
                case 102:
                    print("  - ANALYSIS: WebKit cancelled")
                case 204:
                    print("  - ANALYSIS: WebKit plugin will handle load")
                default:
                    print("  - ANALYSIS: Unknown WebKit error code \(nsError.code)")
                }
            }
        }

        // Check network connectivity
        print("🛠️ CONNECTIVITY CHECK:")
        print("  - Can make basic HTTP request: Testing...")
        testBasicConnectivity()

        // Check URL accessibility
        print("🛠️ URL ACCESSIBILITY CHECK:")
        testUrlAccessibility(url: pageUrl)
    }

    private func testBasicConnectivity() {
        guard let testUrl = URL(string: "https://www.google.com") else { return }

        let task = URLSession.shared.dataTask(with: testUrl) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("  - Basic connectivity test FAILED: \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("  - Basic connectivity test PASSED: HTTP \(httpResponse.statusCode)")
                } else {
                    print("  - Basic connectivity test: Unknown response type")
                }
            }
        }
        task.resume()
    }

    private func testUrlAccessibility(url: URL) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("  - Target URL test FAILED: \(error.localizedDescription)")
                    print("  - Target URL error domain: \(error._domain)")
                    print("  - Target URL error code: \(error._code)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("  - Target URL test PASSED: HTTP \(httpResponse.statusCode)")
                    if let data = data {
                        print("  - Target URL response size: \(data.count) bytes")
                        print("  - Target URL content preview: \(String(data: data.prefix(200), encoding: .utf8) ?? "binary")")
                    }
                } else {
                    print("  - Target URL test: Unknown response type")
                }
            }
        }
        task.resume()
    }

    private func handleArticleNavigationPolicy(
        for navigationAction: WKNavigationAction,
        in webView: WKWebView,
        timeString: String
    ) -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            print("⚠️ WEBVIEW: Navigation action has no URL")
            return .allow
        }

        print("🛠️ NAVIGATION POLICY ANALYSIS:")
        print("  - Target URL: \(url.absoluteString)")
        print("  - URL Scheme: \(url.scheme ?? "nil")")
        print("  - URL Host: \(url.host ?? "nil")")
        print("  - Navigation Type: \(navigationActionTypeString(navigationAction.navigationType))")
        print("  - Source Frame: \(navigationAction.sourceFrame.isMainFrame ? "main" : "subframe")")
        print("  - Target Frame: \(navigationAction.targetFrame?.isMainFrame == true ? "main" : navigationAction.targetFrame != nil ? "subframe" : "nil")")
        print("  - HTTP Method: \(navigationAction.request.httpMethod ?? "nil")")
        print("  - User Agent: \(navigationAction.request.value(forHTTPHeaderField: "User-Agent") ?? "nil")")

        switch Self.articleNavigationDecision(for: url) {
        case .appArticle(let articleURL):
            guard Self.osrsShouldPromoteWebViewArticleNavigation(candidateURL: articleURL, pageURL: pageUrl) else {
                print("↪️ WEBVIEW: Allowing same-article navigation in WebView:")
                print("  - Original: \(url.absoluteString)")
                print("  - Current ArticleViewModel URL: \(pageUrl.absoluteString)")
                return .allow
            }

            print("🔄 WEBVIEW: Routing internal article link through app navigation:")
            print("  - Original: \(url.absoluteString)")
            print("  - Article URL: \(articleURL.absoluteString)")

            webView.stopLoading()
            DispatchQueue.main.async { [weak self] in
                self?.navigateToInternalArticle?(articleURL)
            }
            return .cancel

        case .floorNumberingSettings:
            print("🔄 WEBVIEW: Opening floor numbering Appearance setting")
            webView.stopLoading()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showAppearanceSettings,
                    object: nil,
                    userInfo: ["highlightFloorNumbering": true]
                )
            }
            return .cancel

        case .external(let externalURL):
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            switch Self.osrsExternalNavigationAction(
                navigationType: navigationAction.navigationType,
                isMainFrame: isMainFrame
            ) {
            case .allowInWebView:
                print("  - Allowing embed/subframe load in WebView: \(url.absoluteString)")
                return .allow
            case .openInBrowser:
                print("  - Should open externally: true")
                print("📊 [\(timeString)] 🚀 WEBVIEW: Opening externally, cancelling WebView navigation")
                print("  - Original: \(url.absoluteString)")
                print("  - External URL: \(externalURL.absoluteString)")
                UIApplication.shared.open(externalURL)
                return .cancel
            case .cancelSilently:
                print("  - Cancelling ungestured main-frame external navigation without opening Safari")
                print("  - Original: \(url.absoluteString)")
                return .cancel
            }

        case .allow:
            print("  - Should open externally: false")
            return .allow
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🔗 WEBVIEW: decidePolicyFor navigationAction")

        let policy = handleArticleNavigationPolicy(for: navigationAction, in: webView, timeString: timeString)
        if policy == .cancel {
            decisionHandler(.cancel)
            return
        }

        print("📊 [\(timeString)] ✅ WEBVIEW: Allowing navigation in WebView")
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        let timeString = DateFormatter.timeFormatter.string(from: Date())
        print("📊 [\(timeString)] 🔗 WEBVIEW: decidePolicyFor navigationAction with webpage preferences")

        let policy = handleArticleNavigationPolicy(for: navigationAction, in: webView, timeString: timeString)
        if policy == .cancel {
            decisionHandler(.cancel, preferences)
            return
        }

        print("📊 [\(timeString)] ✅ WEBVIEW: Allowing navigation in WebView")
        decisionHandler(.allow, preferences)
    }

    private func navigationActionTypeString(_ type: WKNavigationType) -> String {
        switch type {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .formResubmitted:
            return "formResubmitted"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }

    private static func shouldOpenExternallyForArticleNavigation(_ url: URL) -> Bool {
        // CRITICAL: Allow our custom scheme for WKURLSchemeHandler
        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
        if url.scheme == customScheme {
            print("🔧 Allowing internal navigation for custom scheme: \(url.scheme ?? "nil")")
            return false // Keep internal for our custom asset scheme
        }

        // CRITICAL FIX: Allow web archive file:// URLs from offline_pages directory
        if url.scheme == "file" {
            let urlPath = url.path

            // Check if this is a web archive file in our offline_pages directory
            if urlPath.contains("offline_pages") && urlPath.hasSuffix(".webarchive") {
                print("🔧 Allowing internal navigation for offline web archive: \(urlPath)")
                return false // Keep internal for offline web archives
            }

            // Block other file:// URLs for security
            print("⚠️ Blocking external file:// URL for security: \(urlPath)")
            return true
        }

        // Open non-wiki links externally
        guard let host = url.host else { return true }
        return !osrsWebKitSecurityPolicy.isTrustedWikiHost(host)
    }

    // MARK: - Bottom Bar Actions

    /// Check if current page is already saved - matches Android PageReadingListManager.observeAndRefreshSaveButtonState()
    private func checkIfPageIsSaved() {
        guard !pageTitle.isEmpty else { return }

        let savedPages = savedPagesRepository.getSavedPages()
        let cleanTitle = cleanPageTitle(pageTitle)
        let matchingPage = savedPages.first { savedPage in
            savedPage.url == pageUrl || savedPage.title == cleanTitle || savedPage.title == pageTitle
        }
        let controlState = Self.saveControlState(for: matchingPage)

        isBookmarked = controlState.isBookmarked
        saveState = controlState.saveState
        saveProgress = controlState.progress

        print("🔖 ArticleViewModel: Checked save status - isBookmarked: \(isBookmarked), saveState: \(saveState)")
    }

    static func saveControlState(
        for savedPage: SavedPage?
    ) -> (isBookmarked: Bool, saveState: osrsArticleBottomBarSaveState, progress: Double) {
        guard let savedPage else { return (false, .notSaved, 0) }
        switch savedPage.offlineStatus {
        case .available where savedPage.hasCurrentDurableSettlement:
            return (true, .saved, 1)
        case .available, .notDownloaded, .downloading, .failed, .outdated:
            return (false, .error, 0)
        }
    }

    static func offlineSaveRecordID(existingIncompletePage: SavedPage?) -> String {
        existingIncompletePage?.id ?? UUID().uuidString
    }

    /// Saved-page metadata keeps the exact authored URL. Decoding the entire absolute string can
    /// turn escaped path data such as `%3F` or `%23` into URL delimiters and change the article.
    nonisolated static func savedPageURLForPersistence(_ pageURL: URL) -> URL {
        pageURL
    }

    nonisolated static func offlineSaveStagingPageID(
        recordID: String,
        saveGeneration: String
    ) -> String {
        let digest = SHA256.hash(data: Data("\(recordID)|\(saveGeneration)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(recordID)__snapshot__\(digest.prefix(24))"
    }

    static func failedOfflineSaveRecord(from savedPage: SavedPage) -> SavedPage {
        SavedPage(
            id: savedPage.id,
            title: savedPage.title,
            description: savedPage.description,
            url: savedPage.url,
            thumbnailUrl: savedPage.thumbnailUrl,
            savedDate: savedPage.savedDate,
            isOfflineAvailable: false,
            offlineDownloadDate: savedPage.offlineDownloadDate,
            offlineStatus: .failed,
            offlineFileSize: savedPage.offlineFileSize,
            offlineLocalPath: savedPage.offlineLocalPath,
            durableSettlementVersion: nil,
            pendingSettlementGeneration: nil,
            revisionId: savedPage.revisionId
        )
    }

    /// Save/bookmark toggle action - matches Android PageReadingListManager functionality
    func performSaveAction(
        explicitSaveReservation preReservedExplicitSaveLease: ProxyExplicitSaveReservation? = nil,
        refreshExistingSnapshot: Bool = false
    ) async {
        guard saveState != .downloading else {
            if #available(iOS 17.0, *), let preReservedExplicitSaveLease {
                ProxyInterceptorService.shared.releaseExplicitSaveReservation(preReservedExplicitSaveLease)
            }
            return
        }

        print("🔖 ArticleViewModel: Save action triggered - current state: \(saveState), bookmarked: \(isBookmarked)")

        if isBookmarked && !refreshExistingSnapshot {
            if #available(iOS 17.0, *), let preReservedExplicitSaveLease {
                // Defensive only: ArticleView never transfers a lease for an unsave, but do not
                // strand the singleton if a future caller violates that contract.
                ProxyInterceptorService.shared.releaseExplicitSaveReservation(preReservedExplicitSaveLease)
            }
            // Remove from saved pages - matches Android unsaving logic
            saveState = .downloading
            saveProgress = 0.0

            do {
                // Find and remove the saved page
                let savedPages = savedPagesRepository.getSavedPages()
                if let savedPage = savedPages.first(where: { $0.url == pageUrl || $0.title == pageTitle }) {
                    // Show progress while removing
                    for progress in stride(from: 0.0, through: 1.0, by: 0.2) {
                        await MainActor.run {
                            self.saveProgress = progress
                        }
                        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
                    }

                    // Remove from repository
                    guard let removedPage = savedPagesRepository.removeSavedPage(savedPage.id) else {
                        throw CancellationError()
                    }
                    if #available(iOS 17.0, *) {
                        await ProxyInterceptorService.shared.removeCachedResponses(pageId: removedPage.offlineCachePageId)
                    }

                    await MainActor.run {
                        self.isBookmarked = false
                        self.saveState = .notSaved
                        self.saveProgress = 0.0
                        print("✅ ArticleViewModel: Successfully removed page from saved pages")
                    }
                } else {
                    await MainActor.run {
                        self.saveState = .error
                        print("❌ ArticleViewModel: Could not find saved page to remove")
                    }
                }
            } catch {
                await MainActor.run {
                    self.saveState = .error
                    print("❌ ArticleViewModel: Error removing saved page: \(error)")
                }
            }
        } else {
            // Save for offline reading - matches Android saving logic
            saveState = .downloading
            saveProgress = 0.0
            let saveStartedAt = CFAbsoluteTimeGetCurrent()
            var browsingSessionPageId: String?

            var explicitSaveReservation = preReservedExplicitSaveLease
            var explicitOfflineSaveToken: ProxyCacheSessionToken?
            var settledRevisionId: Int?
            if #available(iOS 17.0, *) {
                // This is intentionally synchronous on MainActor and precedes metadata/network
                // awaits. New article presentation owners will wait behind the reservation.
                browsingSessionPageId = passiveCachePageId
                suspendPassiveCachingSession(removingPassiveCache: false)
                if explicitSaveReservation == nil {
                    guard let reservation = ProxyInterceptorService.shared.reserveExplicitSaveLease() else {
                        saveState = .error
                        if articleIsVisible && passiveCachingAllowedWhileVisible {
                            beginPassiveCachingSessionIfNeeded()
                        }
                        return
                    }
                    explicitSaveReservation = reservation
                }
            }
            defer {
                if #available(iOS 17.0, *), let explicitOfflineSaveToken {
                    ProxyInterceptorService.shared.disableMode(owner: explicitOfflineSaveToken)
                }
                if #available(iOS 17.0, *), let explicitSaveReservation {
                    ProxyInterceptorService.shared.releaseExplicitSaveReservation(explicitSaveReservation)
                }
                if articleIsVisible && passiveCachingAllowedWhileVisible {
                    beginPassiveCachingSessionIfNeeded()
                }
            }

            do {
                    print("🔄 ArticleViewModel: Starting page save process...")

                    // Step 1: Fetch page metadata from API
                    await MainActor.run { self.saveProgress = 0.1 }

                    let metadata = await fetchPageMetadata()
                    try Task.checkCancellation()

                    // Step 2: Create SavedPage object with proper metadata
                    await MainActor.run { self.saveProgress = 0.2 }

                    // CRITICAL VALIDATION: Clean title and URL to prevent encoding issues
                    let rawTitle = cleanPageTitle(pageTitle)
                    let cleanTitle = rawTitle.decodingHTMLEntities() // Remove HTML entities like &amp;
                    let cleanUrl = Self.savedPageURLForPersistence(pageUrl)

                    print("🔧 VALIDATION: Page save validation")
                    print("  - Raw title: '\(rawTitle)'")
                    print("  - Clean title: '\(cleanTitle)'")
                    print("  - Raw URL: \(pageUrl.absoluteString)")
                    print("  - Clean URL: \(cleanUrl.absoluteString)")

                    let incompleteRetryPage = savedPagesRepository.getSavedPages().first { candidate in
                        candidate.offlineStatus != .available &&
                            (candidate.url == pageUrl || candidate.title == cleanTitle || candidate.title == pageTitle)
                    }
                    let saveGeneration = UUID().uuidString
                    let savedPage = SavedPage(
                        id: Self.offlineSaveRecordID(existingIncompletePage: incompleteRetryPage),
                        title: cleanTitle,
                        description: metadata.description?.decodingHTMLEntities() ?? extractPageDescription(),
                        url: cleanUrl,
                        // Preserve the rich thumbnail already carried by Home/Search/History
                        // navigation. Some update pages do not expose a pageimages thumbnail,
                        // even though the feed supplied the correct card image.
                        thumbnailUrl: metadata.thumbnailUrl ?? thumbnailUrl_ ?? extractThumbnailUrl(),
                        savedDate: Date(),
                        isOfflineAvailable: false, // Will be updated when offline content is downloaded
                        offlineDownloadDate: incompleteRetryPage?.offlineDownloadDate,
                        offlineStatus: .downloading,
                        offlineFileSize: incompleteRetryPage?.offlineFileSize,
                        offlineLocalPath: incompleteRetryPage?.offlineLocalPath,
                        durableSettlementVersion: nil,
                        pendingSettlementGeneration: saveGeneration
                    )

                    // Step 3: Save page metadata to repository
                    await MainActor.run { self.saveProgress = 0.3 }

                    if incompleteRetryPage == nil {
                        savedPagesRepository.addSavedPage(savedPage)
                        print("📱 ArticleViewModel: Added page metadata to repository")
                    } else {
                        guard savedPagesRepository.updateSavedPage(savedPage) else {
                            throw CancellationError()
                        }
                        print("🔁 ArticleViewModel: Retrying failed offline save with existing metadata identity")
                    }

                    // Step 4: Mark existing lazy-cached content as saved (Android-style instant save)
                    await MainActor.run { self.saveProgress = 0.5 }

                    print("⚡ ArticleViewModel: Using lazy caching - marking existing cache as saved")

                    var unpublishedStagingPageId: String?
                    do {
                        var durableOfflineReady = false
                        var durableOfflineByteCount: Int64?
                        var publishedCachePageId = savedPage.id

                        // Use modern iOS 17+ lazy caching approach
                        if #available(iOS 17.0, *) {
                            print("🚀 ArticleViewModel: Lazy caching implementation - instant save")

                            // First save copies exact required URLs from this-view browsing
                            // bytes, then GETs the rest. Refresh still prefers the prior
                            // durable generation. Completeness is the required URL set, not
                            // the browsing namespace.

                            let stagingPageId = Self.offlineSaveStagingPageID(
                                recordID: savedPage.id,
                                saveGeneration: saveGeneration
                            )
                            unpublishedStagingPageId = stagingPageId
                            guard let explicitSaveReservation else {
                                throw osrsOfflineResourceSettlementError.requiredResourcesFailed(count: 1)
                            }
                            guard let offlineSaveToken = await ProxyInterceptorService.shared.enableExplicitOfflineSaveMode(
                                pageId: stagingPageId,
                                saveGeneration: saveGeneration,
                                fallbackPageId: savedPage.offlineLocalPath,
                                reservation: explicitSaveReservation
                            ) else {
                                throw osrsOfflineResourceSettlementError.requiredResourcesFailed(count: 1)
                            }
                            explicitOfflineSaveToken = offlineSaveToken

                            let documentRequest = osrsArticleDocumentRequest(pageURL: pageUrl, pageTitle: cleanTitle)
                            guard let apiURL = documentRequest.parseRequestURL ?? Self.makeParseRequestURL(pageTitle: cleanTitle) else {
                                throw NetworkError.invalidResponse
                            }
                            print("📡 ArticleViewModel: Persisting article HTML for explicit offline save")
                            let cachedPayload = refreshExistingSnapshot
                                ? nil
                                : await osrsArticleDocumentCoordinator.shared.cachedPayload(for: documentRequest)
                            let response: osrsParseResponse
                            let parseData: Data
                            if let cachedPayload {
                                response = osrsParseResponse(
                                    parse: osrsParseResult(
                                        pageid: cachedPayload.payload.pageId,
                                        title: cachedPayload.payload.title,
                                        displaytitle: cachedPayload.payload.displayTitle,
                                        revid: cachedPayload.payload.revisionId,
                                        text: cachedPayload.payload.htmlContent
                                    )
                                )
                                parseData = try JSONEncoder().encode(response)
                            } else {
                                let fetched = try await NetworkManager.shared.performExplicitOfflineDataRequest(
                                    url: apiURL,
                                    retryCount: 1
                                )
                                parseData = fetched.0
                                response = try JSONDecoder().decode(osrsParseResponse.self, from: parseData)
                            }
                            settledRevisionId = response.parse.revid
                            persistPaintHTML(
                                bodyHTML: response.parse.text,
                                displayTitle: response.parse.displaytitle ?? cleanTitle,
                                canonicalTitle: response.parse.title ?? cleanTitle,
                                pageId: stagingPageId
                            )
                            if !(await ProxyInterceptorService.shared.hasPersistedResponseAsync(
                                pageId: stagingPageId,
                                url: apiURL,
                                saveGeneration: saveGeneration
                            )) {
                                let persistResponse = HTTPURLResponse(
                                    url: apiURL,
                                    statusCode: 200,
                                    httpVersion: "HTTP/1.1",
                                    headerFields: ["Content-Type": "application/json"]
                                )!
                                let persisted = await ProxyInterceptorService.shared.persistExplicitSaveResponse(
                                    pageId: stagingPageId,
                                    url: apiURL,
                                    data: parseData,
                                    response: persistResponse,
                                    saveGeneration: saveGeneration
                                )
                                guard persisted else {
                                    throw osrsOfflineResourceSettlementError.requiredResourcesFailed(count: 1)
                                }
                            }

                            await osrsCalculatorSaveWarmer.warmDefaultParse(
                                from: response.parse.text,
                                pageTitle: documentRequest.requestedTitle
                            )

                            let requiredResourceURLs: [URL]
                            do {
                                requiredResourceURLs = try await downloadBoundedOfflineResources(
                                    pageId: stagingPageId,
                                    htmlContent: response.parse.text,
                                    saveGeneration: saveGeneration,
                                    priorPageId: savedPage.offlineLocalPath,
                                    sessionPageId: browsingSessionPageId
                                )
                            } catch {
                                print("⚠️ ArticleViewModel: Offline artwork settlement incomplete: \(error)")
                                requiredResourceURLs = []
                            }

                            let mainResponsePersisted = await ProxyInterceptorService.shared.hasPersistedResponseAsync(
                                pageId: stagingPageId,
                                url: apiURL,
                                saveGeneration: saveGeneration
                            )
                            let persistedByteCount = await ProxyInterceptorService.shared.persistedByteCountAsync(
                                pageId: stagingPageId,
                                urls: [apiURL] + requiredResourceURLs,
                                saveGeneration: saveGeneration
                            )
                            // The article document is the durable save. Artwork is best-effort so a
                            // single image persist miss cannot strand the user on Retry.
                            durableOfflineReady = mainResponsePersisted
                            durableOfflineByteCount = persistedByteCount
                            publishedCachePageId = stagingPageId
                            await MainActor.run { self.saveProgress = 0.8 }
                            print("✅ ArticleViewModel: Explicit offline resource settlement completed")

                            await MainActor.run { self.saveProgress = 0.9 }

                        } else {
                            print("📦 ArticleViewModel: Using legacy web archive approach (iOS <17)")

                            // Create web archive using iOS-native createWebArchiveData
                            guard let webView = webView else {
                                throw NSError(domain: "ArticleViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not available for web archive creation"])
                            }

                            try await OfflineContentService.shared.createWebArchive(
                                from: webView,
                                pageId: savedPage.id,
                                title: cleanTitle,
                                originalURL: cleanUrl
                            )
                            durableOfflineReady = OfflineContentService.shared.isPageAvailableOffline(pageId: savedPage.id)
                        }

                        guard durableOfflineReady else {
                            throw NSError(
                                domain: "ArticleViewModel",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Offline cache is incomplete; saved page will remain unavailable offline"]
                            )
                        }

                        await MainActor.run { self.saveProgress = 0.8 }
                        print("✅ ArticleViewModel: Offline content download completed")

                        // Update SavedPage to reflect offline availability
                        let updatedSavedPage = savedPage.markingCurrentDurableSettlementAvailable(
                            at: Date(),
                            offlineLocalPath: publishedCachePageId,
                            offlineFileSize: durableOfflineByteCount,
                            revisionId: settledRevisionId
                        )

                        // This one metadata update is the publish point. Until it succeeds,
                        // readers keep resolving the prior cache namespace byte-for-byte.
                        guard savedPagesRepository.compareAndSwapOfflineSettlement(
                            updatedSavedPage,
                            expectedGeneration: saveGeneration,
                            expectedPriorCachePageId: savedPage.offlineLocalPath
                        ) else {
                            throw CancellationError()
                        }
                        unpublishedStagingPageId = nil
                        print("📱 ArticleViewModel: Updated saved page with offline availability")

                        if #available(iOS 17.0, *),
                           let priorCachePageId = savedPage.offlineLocalPath,
                           priorCachePageId != publishedCachePageId {
                            Task { @MainActor in
                                await ProxyInterceptorService.shared.removeCachedResponses(pageId: priorCachePageId)
                            }
                        }

                        await MainActor.run { self.saveProgress = 0.9 }

                    } catch {
                        print("❌ ArticleViewModel: Offline download failed: \(error)")

                        if #available(iOS 17.0, *), let unpublishedStagingPageId {
                            await ProxyInterceptorService.shared.removeCachedResponses(pageId: unpublishedStagingPageId)
                        }

                        // Update page status to failed but keep the metadata save
                        let failedSavedPage = Self.failedOfflineSaveRecord(from: savedPage)

                        if savedPagesRepository.compareAndSwapOfflineSettlement(
                            failedSavedPage,
                            expectedGeneration: saveGeneration,
                            expectedPriorCachePageId: savedPage.offlineLocalPath
                        ) {
                            print("📱 ArticleViewModel: Marked saved page as offline download failed")
                        } else {
                            print("🗑️ ArticleViewModel: Save record was removed while refresh was active")
                        }

                        await MainActor.run { self.saveProgress = 0.9 }

                        // Keep metadata for an in-place retry, but do not present this as saved.
                        throw error
                    }

                    // Step 5: Complete save process
                    await MainActor.run {
                        self.isBookmarked = true
                        self.saveState = .saved
                        self.saveProgress = 1.0
                        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - saveStartedAt) * 1000)
                        NSLog("osrsSnapshotSave: title=%@ phase=total elapsedMs=%d", cleanTitle, elapsedMs)
                        print("✅ ArticleViewModel: Successfully saved page")
                    }

            } catch {
                await MainActor.run {
                    self.saveState = .error
                    self.saveProgress = 0.0
                    print("❌ ArticleViewModel: Error saving page: \(error)")
                }
            }
        }
    }

    func markOfflineSaveRetryUnavailable() {
        isBookmarked = false
        saveState = .error
        saveProgress = 0
    }

    func currentSavedCachePageIdForArticle() -> String? {
        let cleanTitle = cleanPageTitle(pageTitle)
        return savedPagesRepository.getSavedPages().first { candidate in
            candidate.url == pageUrl || candidate.title == cleanTitle || candidate.title == pageTitle
        }?.offlineCachePageId
    }

    /// Clean page title by removing HTML tags - matches Android title cleaning
    private func cleanPageTitle(_ title: String) -> String {
        // Remove HTML tags like <span class="mw-page-title-main">Varrock</span>
        let cleanTitle = title.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Explicit offline saves cache every unique article image with bounded concurrency, while
    /// article loading and visible-row preparation remain text/document-only and never wait here.
    private func downloadBoundedOfflineResources(
        pageId: String,
        htmlContent: String,
        saveGeneration: String,
        priorPageId: String? = nil,
        sessionPageId: String? = nil
    ) async throws -> [URL] {
        print("🚀 ArticleViewModel: Starting bounded offline resource download for pageId: \(pageId)")
        let artworkStartedAt = CFAbsoluteTimeGetCurrent()
        final class osrsReuseCounts: @unchecked Sendable {
            private let lock = NSLock()
            private var reusedValue = 0
            private var fetchedValue = 0
            func addReused() {
                lock.lock()
                reusedValue += 1
                lock.unlock()
            }
            func addFetched() {
                lock.lock()
                fetchedValue += 1
                lock.unlock()
            }
            var reused: Int {
                lock.lock()
                defer { lock.unlock() }
                return reusedValue
            }
            var fetched: Int {
                lock.lock()
                defer { lock.unlock() }
                return fetchedValue
            }
        }
        let reuseCounts = osrsReuseCounts()
        let settledURLs = try await osrsOfflineArticleResourceSettlement.settle(
            html: htmlContent,
            maximumConcurrency: 6
        ) { url in
            if await ProxyInterceptorService.shared.hasPersistedResponseAsync(
                pageId: pageId,
                url: url,
                saveGeneration: saveGeneration
            ) {
                return Data()
            }
            for sourcePageId in osrsSavedPageAssetReuse.copySourcePageIds(
                priorPageId: priorPageId,
                sessionPageId: sessionPageId
            ) where sourcePageId != pageId {
                if let copied = await ProxyInterceptorService.shared.copyCachedResponse(
                    from: sourcePageId,
                    to: pageId,
                    url: url,
                    saveGeneration: saveGeneration
                ) {
                    reuseCounts.addReused()
                    return copied
                }
            }
            let (data, response) = try await NetworkManager.shared.performExplicitOfflineDataRequest(
                url: url,
                retryCount: 1
            )
            reuseCounts.addFetched()
            if await ProxyInterceptorService.shared.hasPersistedResponseAsync(
                pageId: pageId,
                url: url,
                saveGeneration: saveGeneration
            ) {
                return data
            }
            let persisted = await ProxyInterceptorService.shared.persistExplicitSaveResponse(
                pageId: pageId,
                url: url,
                data: data,
                response: response,
                saveGeneration: saveGeneration
            )
            guard persisted else {
                throw osrsOfflineResourceSettlementError.requiredResourcesFailed(count: 1)
            }
            return data
        }
        print("✅ ArticleViewModel: Settled \(settledURLs.count) required offline images reused=\(reuseCounts.reused) fetched=\(reuseCounts.fetched)")
        let artworkElapsedMs = Int((CFAbsoluteTimeGetCurrent() - artworkStartedAt) * 1000)
        NSLog("osrsSnapshotSave: phase=artwork elapsedMs=%d reused=%d fetched=%d required=%d", artworkElapsedMs, reuseCounts.reused, reuseCounts.fetched, settledURLs.count)
        return settledURLs
    }

    /// Fetch page metadata from MediaWiki API - matches Android metadata extraction
    private func fetchPageMetadata() async -> (description: String?, thumbnailUrl: URL?) {
        let cleanTitle = cleanPageTitle(pageTitle)

        // Build MediaWiki API URL to get page info and images
        var components = URLComponents(string: "https://oldschool.runescape.wiki/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "titles", value: cleanTitle),
            URLQueryItem(name: "prop", value: "extracts|pageimages"),
            URLQueryItem(name: "exintro", value: "1"), // Only intro section
            URLQueryItem(name: "explaintext", value: "1"), // Plain text, not HTML
            URLQueryItem(name: "exsectionformat", value: "plain"),
            URLQueryItem(name: "exchars", value: "200"), // Limit to 200 characters
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "200") // 200px thumbnail
        ]

        guard let url = components.url else {
            print("❌ ArticleViewModel: Failed to build metadata API URL")
            return (nil, nil)
        }

        do {
            let (data, _) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let query = json["query"] as? [String: Any],
               let pages = query["pages"] as? [[String: Any]],
               let page = pages.first {

                // Extract description
                let description = page["extract"] as? String

                // Extract thumbnail URL
                var thumbnailUrl: URL?
                if let thumbnail = page["thumbnail"] as? [String: Any],
                   let thumbnailSource = thumbnail["source"] as? String {
                    thumbnailUrl = URL(string: thumbnailSource)
                }

                print("📱 ArticleViewModel: Fetched metadata - description: \(description?.prefix(50) ?? "nil"), thumbnail: \(thumbnailUrl?.absoluteString ?? "nil")")

                return (description, thumbnailUrl)
            }
        } catch let networkError as NetworkError {
            print("❌ ArticleViewModel: Network error fetching page metadata: \(networkError.localizedDescription)")
            // Metadata fetch failures are non-critical, so we just log and continue
        } catch {
            print("❌ ArticleViewModel: Error fetching page metadata: \(error)")
        }

        return (nil, nil)
    }

    /// Extract page description from current content - matches Android getSnippet() functionality
    private func extractPageDescription() -> String? {
        // Fallback description if metadata fetch fails
        return "OSRS Wiki article: \(cleanPageTitle(pageTitle))"
    }

    /// Extract thumbnail URL from current content - matches Android getThumbnailUrl() functionality
    private func extractThumbnailUrl() -> URL? {
        // Fallback - will be replaced by API metadata
        return nil
    }

    /// Find in page action - matches Android FindInPageManager functionality
    func performFindInPageAction(onPresented: (() -> Void)? = nil) {
        guard let webView = webView else { return }

        // Expand collapsible sections like Android does
        let expandScript = """
            document.querySelectorAll('.collapsible-closed').forEach(function(e) {
                e.classList.remove('collapsible-closed');
            });
        """
        webView.evaluateJavaScript(expandScript) { [weak self] (_, error) in
            if let error = error {
                print("🚨 ArticleViewModel: Error expanding collapsible content: \(error)")
            }

            // After expanding content, present the native find interface
            DispatchQueue.main.async {
                self?.presentNativeFindInterface()
                onPresented?()
            }
        }

        print("🔍 ArticleViewModel: Find in page requested - expanding collapsible content")
    }

    /// Present native iOS find interface using UIFindInteraction (iOS 16+)
    private func presentNativeFindInterface() {
        guard let webView = webView else { return }

        if #available(iOS 16.0, *) {
            // Use native UIFindInteraction for iOS 16+
            webView.findInteraction?.presentFindNavigator(showingReplace: false)
            print("🔍 ArticleViewModel: Presented native find interface (iOS 16+)")
        } else {
            // Fallback for iOS 14-15: Use basic findString API
            // Note: This requires user input, so we'd need a custom UI
            print("🔍 ArticleViewModel: iOS 16+ required for full find interface. Consider implementing custom UI for older iOS versions.")
        }
    }

    /// Hide find in page interface - matches Android toggle behavior
    func hideFindInPageAction() {
        guard let webView = webView else { return }

        if #available(iOS 16.0, *) {
            // Dismiss the native find interface
            webView.findInteraction?.dismissFindNavigator()
            print("🔍 ArticleViewModel: Dismissed native find interface")
        }
    }

    func isNativeFindNavigatorVisible() -> Bool {
        guard let webView = webView else { return false }

        if #available(iOS 16.0, *) {
            return webView.findInteraction?.isFindNavigatorVisible ?? false
        }

        return false
    }

    /// Appearance/theme action - matches Android AppearanceSettingsActivity
    func performAppearanceAction() {
        // Navigate to appearance settings by sending notification
        // This matches Android's behavior of launching AppearanceSettingsActivity
        NotificationCenter.default.post(name: .showAppearanceSettings, object: nil)
        print("🎨 ArticleViewModel: Navigating to appearance settings")
    }

    /// Contents action - matches Android ContentsHandler functionality
    func performContentsAction() {
        // This is already handled by the existing table of contents functionality
        // The ArticleView will show the table of contents sheet
        print("📋 ArticleViewModel: Contents requested - hasTableOfContents: \(hasTableOfContents)")
    }

    /// Apply intelligent size rules to eliminate wasteful caching
    /// Returns appropriate size variants based on original image size
    private func generateIntelligentSizeVariants(originalSize: Int) -> [String] {
        switch originalSize {
        case 0...30:
            // TINY IMAGES (icons, badges, small UI elements)
            // Only cache original + retina (2x) - no massive sizes needed
            let retinaSize = min(originalSize * 2, 60) // Cap retina at 60px for tiny images
            return [String(retinaSize)]

        case 31...60:
            // SMALL IMAGES (chatheads, small thumbnails)
            // Cache original + retina, maybe one step up
            let retinaSize = originalSize * 2
            return retinaSize <= 100 ? [String(retinaSize)] : [String(100)]

        case 61...150:
            // SMALL-MEDIUM IMAGES (larger chatheads, small article images)
            // Cache original + common responsive size
            return ["300"]

        case 151...300:
            // MEDIUM IMAGES (article thumbnails)
            // Cache original + one larger responsive size
            return ["600"]

        case 301...600:
            // LARGE IMAGES (main article images)
            // Cache original + larger responsive sizes
            return ["300", "1200"]

        default:
            // VERY LARGE IMAGES (hero images, detailed screenshots)
            // Full responsive treatment
            return ["300", "600", "1200"]
        }
    }

    /// Determine if full-size variant should be included
    /// Only include for medium/large images where it might be useful
    private func shouldIncludeFullSize(originalSize: Int) -> Bool {
        return originalSize > 100 // Only include full-size for images larger than 100px
    }

    /// Generate multiple size variants for MediaWiki thumbnail images
    /// NOW WITH INTELLIGENT OPTIMIZATION: Eliminates 60-80% of wasteful caching
    private func generateImageSizeVariants(originalURL: String) -> [String] {
        var variants = [originalURL] // Always include the original

        // Check if this is a MediaWiki thumbnail URL
        if originalURL.contains("/thumb/") && originalURL.contains("px-") {
            // Parse MediaWiki thumbnail pattern: /thumb/Filename.ext/300px-Filename.ext?hash
            // FIXED: Updated regex to properly separate filename from query string
            let pattern = #"/thumb/([^/]+)/(\d+)px-([^?]+)(\?.*)?$"#

            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: originalURL, options: [], range: NSRange(location: 0, length: originalURL.count)) {

                let nsString = originalURL as NSString
                let baseFilename = nsString.substring(with: match.range(at: 1))
                let originalSize = nsString.substring(with: match.range(at: 2))
                let thumbnailFilename = nsString.substring(with: match.range(at: 3)) // Now excludes query string
                let queryString = match.range(at: 4).location != NSNotFound ? nsString.substring(with: match.range(at: 4)) : ""

                print("🔍 ArticleViewModel: Detected MediaWiki thumbnail:")
                print("  📁 Base filename: \(baseFilename)")
                print("  📏 Original size: \(originalSize)px")
                print("  🖼️ Thumbnail filename: \(thumbnailFilename)")
                print("  🔗 Query string: \(queryString)")

                // FIXED: Construct proper base URL for MediaWiki thumb directory
                // Extract the thumb directory path: /images/thumb/Filename.ext
                let thumbPathPattern = #"/images/thumb/[^/]+"#
                if let thumbPathRegex = try? NSRegularExpression(pattern: thumbPathPattern, options: []),
                   let thumbPathMatch = thumbPathRegex.firstMatch(in: originalURL, options: [], range: NSRange(location: 0, length: originalURL.count)) {

                    let thumbPath = nsString.substring(with: thumbPathMatch.range)
                    let baseURL = "https://oldschool.runescape.wiki\(thumbPath)"

                    print("🏗️ ArticleViewModel: Base URL for variants: \(baseURL)")

                    // INTELLIGENT OPTIMIZATION: Apply content-aware size rules
                    let intelligentSizes = generateIntelligentSizeVariants(originalSize: Int(originalSize) ?? 0)
                    let variantSizes = intelligentSizes.filter { $0 != originalSize } // Don't duplicate original

                    print("🧠 ArticleViewModel: Intelligent sizing - \(originalSize)px image gets \(variantSizes.count + 1) variants (was 5-6)")

                    for size in variantSizes {
                        // FIXED: Correct MediaWiki thumbnail URL construction
                        let variantURL = "\(baseURL)/\(size)px-\(thumbnailFilename)\(queryString)"
                        variants.append(variantURL)
                        print("  ✅ Generated intelligent variant: \(variantURL)")
                    }

                    // Add full-size variant only for medium/large images
                    if shouldIncludeFullSize(originalSize: Int(originalSize) ?? 0) {
                        let fullSizeURL = "https://oldschool.runescape.wiki/images/\(baseFilename)\(queryString)"
                        variants.append(fullSizeURL)
                        print("  🖼️ Added full-size variant: \(fullSizeURL)")
                    } else {
                        print("  🚫 Skipped full-size variant (unnecessary for small image)")
                    }
                }

                print("🖼️ ArticleViewModel: Generated \(variants.count) size variants for responsive caching")
            } else {
                print("⚠️ ArticleViewModel: Failed to parse MediaWiki thumbnail URL: \(originalURL)")
            }
        }

        return variants
    }

    /// DEPRECATED: Resource discovery no longer needed with lazy caching
    /// Keeping minimal version for backward compatibility only
    private func discoverAndCachePageResources(pageId: String, originalHTML: String) async throws {
        // With lazy caching, resources are automatically cached during browsing
        // No need for manual discovery and sequential downloading
        print("🚀 ArticleViewModel: Skipping resource discovery - using lazy caching instead")
        return

        // OLD CODE BELOW - KEPT FOR REFERENCE BUT NEVER EXECUTED
        /*
        print("🚀🔍 RESOURCE DISCOVERY ENTRY POINT - pageId: \(pageId)")
        print("🔍 ArticleViewModel: Starting comprehensive resource discovery from original HTML...")
        print("📄 ArticleViewModel: HTML length: \(originalHTML.count) characters")

        // CRITICAL: Verify proxy is configured for caching before starting resource discovery
        print("🔗 ArticleViewModel: Resource discovery starting - proxy system should be configured by now")

        // Add HTML content debugging
        if originalHTML.count > 0 {
            let htmlPreview = String(originalHTML.prefix(500))
            print("📄 ArticleViewModel: HTML preview: \(htmlPreview)")

            // Look for any img tags manually for debugging
            let imgCount = originalHTML.components(separatedBy: "<img").count - 1
            print("🔍 ArticleViewModel: Found \(imgCount) <img> tags in HTML using simple string search")

            // Look for any src attributes manually
            let srcCount = originalHTML.components(separatedBy: "src=").count - 1
            print("🔍 ArticleViewModel: Found \(srcCount) src= attributes in HTML using simple string search")

            // Check for specific image file extensions
            let pngCount = originalHTML.components(separatedBy: ".png").count - 1
            let jpgCount = originalHTML.components(separatedBy: ".jpg").count - 1
            print("🔍 ArticleViewModel: Found \(pngCount) .png and \(jpgCount) .jpg references")
        }

        var discoveredResources: [(type: String, url: String)] = []

        // Helper function to convert URLs to absolute form
        func makeAbsoluteURL(_ urlString: String) -> String? {
            // Skip data URLs and empty strings
            guard !urlString.isEmpty && !urlString.starts(with: "data:") else {
                print("🔍 ArticleViewModel: Skipping URL (empty or data): '\(urlString)'")
                return nil
            }

            if urlString.starts(with: "http") {
                // Already absolute URL
                print("🔍 ArticleViewModel: Using absolute URL: \(urlString)")
                return urlString
            } else if urlString.starts(with: "//") {
                // Protocol-relative URL
                let result = "https:" + urlString
                print("🔍 ArticleViewModel: Converting protocol-relative: \(urlString) → \(result)")
                return result
            } else if urlString.starts(with: "/") {
                // Domain-relative URL - convert to absolute
                let result = "https://oldschool.runescape.wiki" + urlString
                print("🔍 ArticleViewModel: Converting domain-relative: \(urlString) → \(result)")
                return result
            } else {
                // Other relative URLs or invalid - skip
                print("🔍 ArticleViewModel: Skipping unsupported URL format: '\(urlString)'")
                return nil
            }
        }

        // Discover images using regex on original HTML
        let imagePattern = #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        print("🔍 ArticleViewModel: Trying image regex pattern: \(imagePattern)")

        if let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: .caseInsensitive) {
            let matches = imageRegex.matches(in: originalHTML, options: [], range: NSRange(location: 0, length: originalHTML.utf16.count))
            print("🔍 ArticleViewModel: Image regex found \(matches.count) matches")

            var processedCount = 0
            var acceptedCount = 0
            var rejectedCount = 0

            for (index, match) in matches.enumerated() {
                if let srcRange = Range(match.range(at: 1), in: originalHTML) {
                    let srcValue = String(originalHTML[srcRange])
                    processedCount += 1

                    // Only show first few for debugging to avoid log spam
                    if index < 10 {
                        print("🔍 ArticleViewModel: Image match \(index + 1): '\(srcValue)'")
                    }

                    if let fullURL = makeAbsoluteURL(srcValue) {
                        discoveredResources.append((type: "image", url: fullURL))
                        acceptedCount += 1
                        if index < 5 {  // Only show first few for debugging
                            print("🖼️ ArticleViewModel: ✅ Found image: \(srcValue) → \(fullURL)")
                        }
                    } else {
                        rejectedCount += 1
                        if index < 5 {  // Only show first few for debugging
                            print("🖼️ ArticleViewModel: ❌ Rejected image URL: \(srcValue)")
                        }
                    }
                }
            }

            print("📊 ArticleViewModel: Image processing complete - Processed: \(processedCount), Accepted: \(acceptedCount), Rejected: \(rejectedCount)")

        } else {
            print("❌ ArticleViewModel: Failed to create image regex pattern")
        }

        // Discover CSS files using regex on original HTML
        let cssPattern = #"<link[^>]+rel\s*=\s*[\"']stylesheet[\"'][^>]+href\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        if let cssRegex = try? NSRegularExpression(pattern: cssPattern, options: .caseInsensitive) {
            let matches = cssRegex.matches(in: originalHTML, options: [], range: NSRange(location: 0, length: originalHTML.utf16.count))
            for match in matches {
                if let hrefRange = Range(match.range(at: 1), in: originalHTML) {
                    let hrefValue = String(originalHTML[hrefRange])
                    if let fullURL = makeAbsoluteURL(hrefValue) {
                        discoveredResources.append((type: "css", url: fullURL))
                        print("🎨 ArticleViewModel: Found CSS: \(hrefValue) → \(fullURL)")
                    }
                }
            }
        }

        // Discover JavaScript files using regex on original HTML
        let jsPattern = #"<script[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        if let jsRegex = try? NSRegularExpression(pattern: jsPattern, options: .caseInsensitive) {
            let matches = jsRegex.matches(in: originalHTML, options: [], range: NSRange(location: 0, length: originalHTML.utf16.count))
            for match in matches {
                if let srcRange = Range(match.range(at: 1), in: originalHTML) {
                    let srcValue = String(originalHTML[srcRange])
                    if let fullURL = makeAbsoluteURL(srcValue) {
                        discoveredResources.append((type: "js", url: fullURL))
                        print("⚡ ArticleViewModel: Found JS: \(srcValue) → \(fullURL)")
                    }
                }
            }
        }

        // Remove duplicates
        var uniqueUrls = Set<String>()
        discoveredResources = discoveredResources.filter { resource in
            if uniqueUrls.contains(resource.url) { return false }
            uniqueUrls.insert(resource.url)
            return true
        }

        print("🎯 ArticleViewModel: Discovered \(discoveredResources.count) external resources to cache")

        // CRITICAL DIAGNOSTIC: Show summary of what we found
        if discoveredResources.isEmpty {
            print("❌ ArticleViewModel: ⚠️  CRITICAL - Zero resources discovered despite HTML analysis!")
            print("❌ ArticleViewModel: This indicates a problem in the resource discovery logic")
        } else {
            print("✅ ArticleViewModel: Resource discovery successful - found \(discoveredResources.count) unique resources")

            // Group by type for analysis
            let imageCount = discoveredResources.filter { $0.type == "image" }.count
            let cssCount = discoveredResources.filter { $0.type == "css" }.count
            let jsCount = discoveredResources.filter { $0.type == "js" }.count
            print("📊 ArticleViewModel: Resource breakdown - Images: \(imageCount), CSS: \(cssCount), JS: \(jsCount)")

            // Sample first few discovered resources
            print("📋 ArticleViewModel: Sample discovered resources:")
            for (i, resource) in discoveredResources.prefix(5).enumerated() {
                print("   [\(i+1)] \(resource.type): \(resource.url)")
            }
        }

        // ENHANCED: Track individual resource caching success/failure
        var successCount = 0
        var failureCount = 0
        var failedResources: [(type: String, url: String, error: String)] = []

        // ENHANCED: Smart multi-size image caching for responsive images
        for (index, resource) in discoveredResources.enumerated() {
            guard let url = URL(string: resource.url) else {
                print("❌ ArticleViewModel: Invalid URL for resource \(index + 1): \(resource.url)")
                failureCount += 1
                failedResources.append((type: resource.type, url: resource.url, error: "Invalid URL"))
                continue
            }

            if resource.type == "image" {
                // For images, implement smart multi-size caching
                let imageVariants = generateImageSizeVariants(originalURL: resource.url)
                print("🖼️ ArticleViewModel: [\(index + 1)/\(discoveredResources.count)] Caching image with \(imageVariants.count) size variants: \(resource.url)")

                for (variantIndex, variantURL) in imageVariants.enumerated() {
                    guard let url = URL(string: variantURL) else {
                        print("❌ ArticleViewModel: Invalid variant URL: \(variantURL)")
                        continue
                    }

                    print("📦 ArticleViewModel:   Variant [\(variantIndex + 1)/\(imageVariants.count)]: \(variantURL)")

                    do {
                        let responseData = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)
                        print("✅ ArticleViewModel: Successfully cached image variant (\(responseData.0.count) bytes): \(variantURL)")
                        successCount += 1
                    } catch {
                        print("⚠️ ArticleViewModel: Failed to cache image variant \(variantURL): \(error)")
                        failureCount += 1
                        failedResources.append((type: resource.type, url: variantURL, error: error.localizedDescription))
                        // Continue with other variants even if one fails
                    }

                    // Small delay between variants
                    try await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
                }
            } else {
                // For non-images, cache normally
                print("📦 ArticleViewModel: [\(index + 1)/\(discoveredResources.count)] Caching \(resource.type): \(resource.url)")

                do {
                    let responseData = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 1)
                    print("✅ ArticleViewModel: Successfully cached \(resource.type) (\(responseData.0.count) bytes): \(resource.url)")
                    successCount += 1
                } catch {
                    print("⚠️ ArticleViewModel: Failed to cache \(resource.type) \(resource.url): \(error)")
                    failureCount += 1
                    failedResources.append((type: resource.type, url: resource.url, error: error.localizedDescription))
                }
            }

            // Small delay to avoid overwhelming the server
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        // ENHANCED: Comprehensive caching results analysis
        let totalResources = discoveredResources.count
        let successRate = totalResources > 0 ? Double(successCount) / Double(totalResources) * 100 : 0

        print("📊 RESOURCE CACHING ANALYSIS:")
        print("   📈 Total resources discovered: \(totalResources)")
        print("   ✅ Successfully cached: \(successCount) (\(String(format: "%.1f", successRate))%)")
        print("   ❌ Failed to cache: \(failureCount)")

        if failureCount > 0 {
            print("⚠️ CACHING FAILURES DETECTED:")
            for (i, failed) in failedResources.prefix(5).enumerated() {
                print("   [\(i+1)] \(failed.type): \(failed.url)")
                print("        Error: \(failed.error)")
            }
            if failedResources.count > 5 {
                print("   ... and \(failedResources.count - 5) more failures")
            }
        }

        // ENHANCED: Cache success threshold validation
        let minimumSuccessRate = 80.0 // Require 80% success rate for reliable offline experience
        let hasReliableCache = successRate >= minimumSuccessRate

        if hasReliableCache {
            print("🎉 ArticleViewModel: Resource caching SUCCESSFUL - \(successCount)/\(totalResources) cached (≥\(minimumSuccessRate)% threshold met)")
        } else {
            print("⚠️ ArticleViewModel: Resource caching INCOMPLETE - \(successCount)/\(totalResources) cached (<\(minimumSuccessRate)% threshold)")
            print("💡 Recommendation: Page may have missing images when accessed offline")
        }

        // Return success status for save process decision making
        if !hasReliableCache {
            print("🔄 ArticleViewModel: Consider adjusting offline availability status based on cache success rate")
        }
        */
    }
}

// MARK: - Data Models
struct TableOfContentsSection: Codable, Identifiable {
    let id: String
    let title: String
    let level: Int
}

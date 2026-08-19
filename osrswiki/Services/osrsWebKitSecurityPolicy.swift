//
//  osrsWebKitSecurityPolicy.swift
//  osrswiki
//

import Foundation
import WebKit

struct osrsWebKitUserScriptPolicy {
    let name: String
    let isForMainFrameOnly: Bool
}

enum osrsWebKitSecurityPolicy {
    static let diagnosticModeUserDefaultsKey = "osrsWebKitDiagnosticsEnabled"

    static let productionHandlerNames: Set<String> = [
        "clipboardBridge",
        "linkHandler",
        "mapBridge",
        "osrsYouTube",
        "renderTimeline"
    ]

    static let diagnosticHandlerNames: Set<String> = [
        "safariDebugger"
    ]

    static let productionUserScripts: [osrsWebKitUserScriptPolicy] = [
        osrsWebKitUserScriptPolicy(name: "clipboardBridge", isForMainFrameOnly: true),
        osrsWebKitUserScriptPolicy(name: "internalLinkRouting", isForMainFrameOnly: true),
        osrsWebKitUserScriptPolicy(name: "renderTimeline", isForMainFrameOnly: true),
        osrsWebKitUserScriptPolicy(name: "mobileOptimization", isForMainFrameOnly: true)
    ]

    static var isDiagnosticModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: diagnosticModeUserDefaultsKey)
    }

    static var isWebViewInspectionEnabled: Bool {
        isDiagnosticModeEnabled
    }

    static var enabledHandlerNames: [String] {
        let base = productionHandlerNames
        guard isDiagnosticModeEnabled else {
            return base.sorted()
        }
        return base.union(diagnosticHandlerNames).sorted()
    }

    static func isTrustedWikiHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedHost == "oldschool.runescape.wiki" || normalizedHost == "runescape.wiki"
    }

    static func isTrustedArticleNavigationURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return isTrustedWikiHost(url.host)
    }

    static func isTrustedMessageOrigin(_ origin: WKSecurityOrigin) -> Bool {
        let originProtocol = origin.protocol.lowercased()
        let host = origin.host.lowercased()

        if originProtocol == "https" {
            return isTrustedWikiHost(host)
        }

        if originProtocol == "app-assets" {
            return host == "localhost" || host == "saved-pages"
        }

        if originProtocol == "applewebdata" {
            return true
        }

        // Offline web archives are loaded from app-owned file URLs selected by ArticleViewModel.
        if originProtocol == "file" {
            return true
        }

        return false
    }

    static func canAcceptScriptMessage(name: String, frameInfo: WKFrameInfo) -> Bool {
        guard frameInfo.isMainFrame else { return false }
        if name == "linkHandler" {
            return true
        }
        guard isTrustedMessageOrigin(frameInfo.securityOrigin) else { return false }

        if productionHandlerNames.contains(name) {
            return true
        }

        if diagnosticHandlerNames.contains(name) {
            return isDiagnosticModeEnabled
        }

        return false
    }

    static func isUserScriptMainFrameOnly(name: String) -> Bool {
        if let script = productionUserScripts.first(where: { $0.name == name }) {
            return script.isForMainFrameOnly
        }
        return true
    }
}

enum osrsYouTubeEmbed {
    static let wikiOrigin = "https://oldschool.runescape.wiki"

    static func videoID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed) ?? URL(string: trimmed, relativeTo: URL(string: wikiOrigin)) else {
            return nil
        }
        let host = (url.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        if host == "youtu.be" {
            let id = url.path.split(separator: "/").first.map(String.init)
            return validVideoID(id)
        }
        if host == "youtube.com" || host == "youtube-nocookie.com" || host == "m.youtube.com" {
            if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value {
                return validVideoID(queryID)
            }
            let parts = url.path.split(separator: "/").map(String.init)
            if let embedIndex = parts.firstIndex(of: "embed"), parts.indices.contains(embedIndex + 1) {
                return validVideoID(parts[embedIndex + 1])
            }
            if let shortsIndex = parts.firstIndex(of: "shorts"), parts.indices.contains(shortsIndex + 1) {
                return validVideoID(parts[shortsIndex + 1])
            }
        }
        return validVideoID(trimmed)
    }

    static func playerURL(videoID: String) -> URL? {
        guard let id = validVideoID(videoID) else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/embed/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "origin", value: wikiOrigin)
        ]
        return components?.url
    }

    static func playerRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(wikiOrigin + "/", forHTTPHeaderField: "Referer")
        request.setValue(wikiOrigin, forHTTPHeaderField: "Origin")
        return request
    }

    private static func validVideoID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let id = raw.split(separator: "?").first.map(String.init) ?? raw
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard id.count >= 8, id.count <= 20, id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return id
    }
}

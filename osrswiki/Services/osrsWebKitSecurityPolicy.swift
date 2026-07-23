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

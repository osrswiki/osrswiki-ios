//
//  osrsArticleLinkRouter.swift
//  osrswiki
//

import Foundation

enum osrsArticleLinkRouter {
    static func appArticleURL(for url: URL) -> URL? {
        if url.scheme?.lowercased() == "https",
           osrsWebKitSecurityPolicy.isTrustedWikiHost(url.host),
           isArticlePath(url.path) {
            return url
        }

        if url.scheme?.lowercased() == "app-assets",
           url.host?.lowercased() == "localhost",
           isArticlePath(url.path) {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "oldschool.runescape.wiki"
            components.path = url.path
            components.query = url.query
            components.fragment = url.fragment
            return components.url
        }

        return nil
    }

    static func externalWikiURLForNonArticleAppAssetURL(_ url: URL) -> URL? {
        guard isAppAssetURL(url),
              isExcludedWikiNamespacePath(url.path) else {
            return nil
        }

        return trustedWikiURL(fromAppAssetURL: url)
    }

    private static func isArticlePath(_ path: String) -> Bool {
        guard path.hasPrefix("/w/") else { return false }

        let pageName = String(path.dropFirst(3))
        guard !pageName.isEmpty else { return false }

        return !isExcludedWikiNamespacePageName(pageName)
    }

    private static func isExcludedWikiNamespacePath(_ path: String) -> Bool {
        guard path.hasPrefix("/w/") else { return false }

        let pageName = String(path.dropFirst(3))
        guard !pageName.isEmpty else { return false }

        return isExcludedWikiNamespacePageName(pageName)
    }

    private static func isExcludedWikiNamespacePageName(_ pageName: String) -> Bool {
        let decodedPageName = (pageName.removingPercentEncoding ?? pageName).lowercased()
        let excludedPrefixes = [
            "file:",
            "media:",
            "special:"
        ]

        return excludedPrefixes.contains { decodedPageName.hasPrefix($0) }
    }

    private static func isAppAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "app-assets" && url.host?.lowercased() == "localhost"
    }

    private static func trustedWikiURL(fromAppAssetURL url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "oldschool.runescape.wiki"
        components.path = url.path
        components.query = url.query
        components.fragment = url.fragment
        return components.url
    }
}

import Foundation

enum osrsWikiWebViewUrl {
    static let wikiHost = "oldschool.runescape.wiki"
    static let wikiOrigin = "https://oldschool.runescape.wiki"
    static let localAssetHost = "localhost"

    static func shouldProxy(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path
        let isLocal = host == localAssetHost || host == "appassets.androidplatform.net"
        guard isLocal else { return false }
        return path == "/api.php" ||
            path.hasSuffix("/api.php") ||
            path.hasPrefix("/cors/") ||
            path == "/load.php" ||
            path.hasSuffix("/load.php")
    }

    static func rewriteToWiki(_ url: URL) -> URL {
        guard shouldProxy(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        components.host = wikiHost
        return components.url ?? url
    }

    static func rewriteToWiki(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return rewriteToWiki(url).absoluteString
    }

    static func isCalculatorNamespaceTitle(_ title: String) -> Bool {
        title.hasPrefix("Calculator:")
    }

    static func isUserFacingCalculator(_ title: String) -> Bool {
        guard isCalculatorNamespaceTitle(title) else { return false }
        if title.lowercased().contains("sandbox") { return false }
        let rest = String(title.dropFirst("Calculator:".count))
        return rest.split(separator: "/").allSatisfy { part in
            let loweredPart = part.lowercased()
            return !loweredPart.hasPrefix("template") &&
                loweredPart != "doc" &&
                loweredPart != "sandbox" &&
                loweredPart != "module"
        }
    }

    static func isIncludedInDefaultSearch(_ title: String) -> Bool {
        !isCalculatorNamespaceTitle(title) || isUserFacingCalculator(title)
    }

    static func mediaWikiPageConfig(canonicalTitle: String, displayTitle: String) -> (namespaceNumber: Int, canonicalNamespace: String, pageName: String, title: String) {
        let source = canonicalTitle.isEmpty ? displayTitle : canonicalTitle
        if isCalculatorNamespaceTitle(source) {
            return (
                116,
                "Calculator",
                source.replacingOccurrences(of: " ", with: "_"),
                String(source.dropFirst("Calculator:".count))
            )
        }
        let display = displayTitle.isEmpty ? source : displayTitle
        return (
            0,
            "",
            display.replacingOccurrences(of: " ", with: "_"),
            display
        )
    }
}

enum osrsResourceLoaderScript {
    static let brokenOojsTrailer = "window.OO=module.exports;"
    static let safeOojsTrailer =
        "window.OO=(typeof module!=='undefined'&&module.exports)?module.exports:window.OO;"

    static func sanitize(_ source: String) -> String {
        source.replacingOccurrences(of: brokenOojsTrailer, with: safeOojsTrailer)
    }

    static func sanitize(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let sanitized = sanitize(text)
        return Data(sanitized.utf8)
    }
}

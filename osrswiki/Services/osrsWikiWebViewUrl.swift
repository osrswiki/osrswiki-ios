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

    static let rejectedGadgetLoadJS = "/* osrs: MediaWiki gadgets are not loaded */\n"

    static func isMediaWikiGadgetModule(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("ext.gadget.")
    }

    static func withoutMediaWikiGadgets(_ modules: [String]) -> [String] {
        modules.filter { !isMediaWikiGadgetModule($0) }
    }

    static func loadPhpModuleNames(_ url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let modules = components.queryItems?.first(where: { $0.name == "modules" })?.value else {
            return []
        }
        return modules
            .split { $0 == "|" || $0 == "," }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func loadPhpModuleNames(_ urlString: String) -> [String] {
        guard let url = URL(string: urlString) else { return [] }
        return loadPhpModuleNames(url)
    }

    static func isRejectedMediaWikiGadgetLoad(_ url: URL) -> Bool {
        guard url.path == "/load.php" || url.path.hasSuffix("/load.php") else { return false }
        let modules = loadPhpModuleNames(url)
        return !modules.isEmpty && modules.allSatisfy { isMediaWikiGadgetModule($0) }
    }

    static func isRejectedMediaWikiGadgetLoad(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return isRejectedMediaWikiGadgetLoad(url)
    }

    /// Drop `ext.gadget.*` from a load.php URL. Returns nil when nothing FLOSS remains.
    static func withoutMediaWikiGadgetLoadModules(_ url: URL) -> URL? {
        guard url.path == "/load.php" || url.path.hasSuffix("/load.php") else { return url }
        let modules = loadPhpModuleNames(url)
        guard !modules.isEmpty else { return url }
        let kept = withoutMediaWikiGadgets(modules)
        if kept.count == modules.count { return url }
        if kept.isEmpty { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []).map { item in
            if item.name == "modules" {
                return URLQueryItem(name: "modules", value: kept.joined(separator: "|"))
            }
            return item
        }
        return components.url
    }

    static func withoutMediaWikiGadgetLoadModules(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return urlString }
        return withoutMediaWikiGadgetLoadModules(url)?.absoluteString
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

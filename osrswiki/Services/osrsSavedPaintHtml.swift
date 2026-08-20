import Foundation

struct osrsSavedPaintHtml {
    static func isFullDocument(_ html: String) -> Bool {
        let start = html.trimmingCharacters(in: .whitespacesAndNewlines)
        return start.lowercased().hasPrefix("<!doctype") || start.lowercased().hasPrefix("<html")
    }

    static func extractBodyForToc(_ html: String) -> String {
        guard isFullDocument(html),
              let bodyOpen = html.range(of: "<body", options: .caseInsensitive),
              let bodyClose = html.range(of: "</body>", options: [.caseInsensitive, .backwards]),
              bodyOpen.lowerBound < bodyClose.lowerBound,
              let contentStart = html[bodyOpen.lowerBound...].firstIndex(of: ">")
        else {
            return html
        }
        let body = String(html[html.index(after: contentStart)..<bodyClose.lowerBound])
        return body.replacingOccurrences(
            of: #"<h1\s+class=["']page-header["'][^>]*>.*?</h1>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    static func applyingLivePreferences(
        _ html: String,
        isDark: Bool,
        wrapEnabled: Bool,
        scaleCssValue: String,
        chromeClearancePx: Int,
        bottomChromePx: Int,
        safeAreaTopPx: Int,
        safeAreaBottomPx: Int
    ) -> String {
        var next = applyingNamedClass(html, tag: "html", className: "theme-osrs-dark", enabled: isDark)
        next = applyingNamedClass(next, tag: "body", className: "theme-osrs-dark", enabled: isDark)
        next = applyingNamedClass(next, tag: "html", className: "osrs-table-cells-wrap", enabled: wrapEnabled)
        next = applyingNamedClass(next, tag: "body", className: "osrs-table-cells-wrap", enabled: wrapEnabled)
        next = next.replacingOccurrences(
            of: #"--osrs-article-user-text-scale:\s*[0-9.]+"#,
            with: "--osrs-article-user-text-scale: \(scaleCssValue)",
            options: .regularExpression
        )
        return withLiveChrome(
            next,
            chromeClearancePx: chromeClearancePx,
            bottomChromePx: bottomChromePx,
            safeAreaTopPx: safeAreaTopPx,
            safeAreaBottomPx: safeAreaBottomPx
        )
    }

    static func inlineLinkedFirstPaintCss(
        _ html: String,
        loadCss: (String) -> String?
    ) -> String {
        let pattern = #"<link\s+rel=["']stylesheet["']\s+href=["'][^"']+://localhost/([^"']+)["']\s*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }
        var result = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let assetPath = result.substring(with: match.range(at: 1))
            guard let css = loadCss(assetPath), !css.isEmpty else { continue }
            let replacement = "<style data-osrs-inline-css=\"\(assetPath)\">\(css)</style>"
            result = result.replacingCharacters(in: match.range, with: replacement) as NSString
        }
        return result as String
    }

    static func withLiveChrome(
        _ html: String,
        chromeClearancePx: Int,
        bottomChromePx: Int,
        safeAreaTopPx: Int,
        safeAreaBottomPx: Int
    ) -> String {
        let style = """
        <style id="osrs-article-live-chrome">
        html:root {
            --osrs-article-safe-area-top: \(safeAreaTopPx)px;
            --osrs-article-safe-area-bottom: \(safeAreaBottomPx)px;
            --osrs-article-chrome-clearance: \(chromeClearancePx)px;
            --osrs-article-bottom-chrome: \(bottomChromePx)px;
        }
        html {
            padding-top: calc(var(--osrs-article-safe-area-top) + var(--osrs-article-chrome-clearance)) !important;
            padding-bottom: calc(var(--osrs-article-safe-area-bottom) + var(--osrs-article-bottom-chrome)) !important;
        }
        </style>
        """
        if let regex = try? NSRegularExpression(
            pattern: #"<style id=["']osrs-article-live-chrome["']>[\s\S]*?</style>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(html.startIndex..., in: html)
            if regex.firstMatch(in: html, range: range) != nil {
                return regex.stringByReplacingMatches(in: html, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: style))
            }
        }
        if let headClose = html.range(of: "</head>", options: .caseInsensitive) {
            return html.replacingCharacters(in: headClose, with: style + "</head>")
        }
        return style + html
    }

    private static func applyingNamedClass(
        _ html: String,
        tag: String,
        className: String,
        enabled: Bool
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(tag)\\b([^>]*)>",
            options: [.caseInsensitive]
        ) else {
            return html
        }
        let nsHtml = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHtml.length)),
              match.numberOfRanges > 1,
              let attrsRange = Range(match.range(at: 1), in: html),
              let fullRange = Range(match.range, in: html)
        else {
            return html
        }
        let attrs = String(html[attrsRange])
        let classRegex = try? NSRegularExpression(pattern: #"\bclass=["']([^"']*)["']"#, options: [.caseInsensitive])
        var classes: [String] = []
        var attrsWithoutClass = attrs
        if let classRegex,
           let classMatch = classRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
           classMatch.numberOfRanges > 1,
           let classValueRange = Range(classMatch.range(at: 1), in: attrs),
           let classAttrRange = Range(classMatch.range, in: attrs) {
            classes = attrs[classValueRange].split(whereSeparator: \.isWhitespace).map(String.init)
            attrsWithoutClass.removeSubrange(classAttrRange)
        }
        if enabled {
            if !classes.contains(className) {
                classes.append(className)
            }
        } else {
            classes.removeAll { $0 == className }
        }
        let classAttr = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        let trimmed = attrsWithoutClass.trimmingCharacters(in: .whitespaces)
        let spacer = trimmed.isEmpty ? "" : " "
        let replacement = "<\(tag)\(spacer)\(trimmed)\(classAttr)>"
        return html.replacingCharacters(in: fullRange, with: replacement)
    }
}

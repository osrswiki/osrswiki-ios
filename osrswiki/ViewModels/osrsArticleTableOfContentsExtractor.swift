import Foundation

/// Visible heading text for the native table of contents. Wiki floor-number
/// markup always contains both GB and US variants plus [UK]/[US] help marks;
/// CSS hides one dialect, but `textContent` would still concatenate both.
enum osrsArticleSectionTitle {
    static func visible(
        fromHTML html: String,
        convention: osrsArticleFloorConvention = .current()
    ) -> String {
        var cleaned = html
        cleaned = cleaned.replacingOccurrences(
            of: #"<span[^>]*class="[^"]*\b\#(convention.hiddenDialectClass)\b[^"]*"[^>]*>[\s\S]*?</span>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Wiki help marks use <sup class="floornumber-help">, not <span>.
        cleaned = cleaned.replacingOccurrences(
            of: #"<(span|sup)[^>]*class="[^"]*\bfloornumber-help\b[^"]*"[^>]*>[\s\S]*?</\1>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Unwrap remaining markup without inserting spaces so 1<sup>st</sup> stays "1st".
        cleaned = cleaned.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&#160;", with: " ")
        cleaned = cleaned.replacingOccurrences(
            of: #"\[(?:UK|US)\]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum osrsArticleTableOfContentsExtractor {
    static func extract(
        displayTitle: String,
        html: String,
        convention: osrsArticleFloorConvention = .current()
    ) -> [TableOfContentsSection] {
        let lead = osrsArticleSectionTitle.visible(fromHTML: displayTitle, convention: convention)
            .ifEmpty("Top of page")
        var sections = [TableOfContentsSection(id: "", title: lead, level: 1)]
        var seen = Set<String>()
        let pattern = #"<h([23])\b([^>]*)>([\s\S]*?)</h\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return sections
        }
        let ns = html as NSString
        regex.enumerateMatches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let attrs = ns.substring(with: match.range(at: 2))
            let inner = ns.substring(with: match.range(at: 3))
            let level = Int(ns.substring(with: match.range(at: 1))) ?? 2
            let id = headingId(attributes: attrs, innerHTML: inner)
            let title = osrsArticleSectionTitle.visible(fromHTML: inner, convention: convention)
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { return }
            sections.append(TableOfContentsSection(id: id, title: title, level: level))
        }
        return sections
    }

    private static func headingId(attributes: String, innerHTML: String) -> String {
        if let id = htmlAttribute(attributes, name: "id"), !id.isEmpty {
            return id
        }
        if let id = htmlAttribute(innerHTML, name: "id"), !id.isEmpty {
            return id
        }
        return ""
    }

    private static func htmlAttribute(_ source: String, name: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: (source as NSString).length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return (source as NSString).substring(with: match.range(at: 1))
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

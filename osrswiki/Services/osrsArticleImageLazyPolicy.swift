import Foundation

enum osrsArticleImageLazyPolicy {
    static let placeholder =
        "data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='1'%20height='1'%3E%3C/svg%3E"

    static func apply(_ html: String) -> String {
        guard osrsLoadPerformancePrefs.lazyOffscreenArticleImages else { return html }
        var out = applySizes(to: html)
        let defaultIndex = authoredDefaultIndex(from: out)
        out = deferNonDefaultSwitcherPool(in: out, defaultIndex: defaultIndex)
        out = deferAfterFirstHeading(in: out)
        return out
    }

    static func authoredDefaultIndex(from html: String) -> String {
        if let match = firstCapture(#"data-default-version=["']([^"']+)["']"#, in: html) {
            return match
        }
        if let match = firstCapture(#"class=["'][^"']*button-selected[^"']*["'][^>]*data-switch-index=["']([^"']+)["']"#, in: html)
            ?? firstCapture(#"data-switch-index=["']([^"']+)["'][^>]*class=["'][^"']*button-selected"#, in: html) {
            return match
        }
        return firstCapture(#"data-switch-index=["']([^"']+)["']"#, in: html) ?? "0"
    }

    private static func applySizes(to html: String) -> String {
        rewriteImgTags(in: html) { tag in
            guard tag.range(of: #"srcset\s*="#, options: [.regularExpression, .caseInsensitive]) != nil else {
                return tag
            }
            if tag.range(of: #"\bsizes\s*="#, options: [.regularExpression, .caseInsensitive]) != nil {
                return tag
            }
            guard let width = firstCapture(#"\bwidth=["'](\d+)["']"#, in: tag),
                  let widthValue = Int(width), widthValue > 0 else {
                return tag
            }
            return tag.replacingOccurrences(of: "<img", with: "<img sizes=\"\(widthValue)px\"", options: [.caseInsensitive])
        }
    }

    private static func deferNonDefaultSwitcherPool(in html: String, defaultIndex: String) -> String {
        let pattern = #"<div[^>]*data-attr-index=["']([^"']+)["'][^>]*>[\s\S]*?</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }
        let nsRange = NSRange(html.startIndex..., in: html)
        var result = html
        let matches = regex.matches(in: html, range: nsRange).reversed()
        for match in matches {
            guard match.numberOfRanges > 1,
                  let blockRange = Range(match.range, in: result),
                  let indexRange = Range(match.range(at: 1), in: html) else { continue }
            let index = String(html[indexRange])
            if index == defaultIndex { continue }
            let block = String(result[blockRange])
            let deferred = rewriteImgTags(in: block, transform: deferImgTag)
            result.replaceSubrange(blockRange, with: deferred)
        }
        return result
    }

    private static func deferAfterFirstHeading(in html: String) -> String {
        let pattern = #"(?i)<h2\b|<[^>]*class=["'][^"']*mw-heading"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else {
            return html
        }
        let prefix = String(html[..<range.lowerBound])
        let suffix = String(html[range.lowerBound...])
        return prefix + rewriteImgTags(in: suffix, transform: deferImgTag)
    }

    private static func deferImgTag(_ tag: String) -> String {
        if tag.range(of: "data-osrs-deferred-src", options: .caseInsensitive) != nil {
            return insertAttribute(tag, name: "loading", value: "lazy")
        }
        let width = Int(firstCapture(#"\bwidth=["'](\d+)["']"#, in: tag) ?? "") ?? 0
        let height = Int(firstCapture(#"\bheight=["'](\d+)["']"#, in: tag) ?? "") ?? 0
        if width <= 0 && height <= 0 {
            return insertAttribute(insertAttribute(tag, name: "loading", value: "lazy"), name: "decoding", value: "async")
        }
        var out = tag
        if let src = firstCapture(#"\bsrc=["']([^"']+)["']"#, in: out),
           !src.lowercased().hasPrefix("data:") {
            out = replaceAttribute(out, name: "src", value: placeholder)
            out = insertAttribute(out, name: "data-osrs-deferred-src", value: src)
        }
        if let srcset = firstCapture(#"\bsrcset=["']([^"']+)["']"#, in: out) {
            out = removeAttribute(out, name: "srcset")
            out = insertAttribute(out, name: "data-osrs-deferred-srcset", value: srcset)
        }
        if let sizes = firstCapture(#"\bsizes=["']([^"']+)["']"#, in: out) {
            out = removeAttribute(out, name: "sizes")
            out = insertAttribute(out, name: "data-osrs-deferred-sizes", value: sizes)
        }
        if out.range(of: "osrs-deferred-offscreen-image") == nil {
            if let classValue = firstCapture(#"\bclass=["']([^"']*)["']"#, in: out) {
                out = replaceAttribute(out, name: "class", value: classValue + " osrs-deferred-offscreen-image")
            } else {
                out = insertAttribute(out, name: "class", value: "osrs-deferred-offscreen-image")
            }
        }
        out = insertAttribute(out, name: "loading", value: "lazy")
        out = insertAttribute(out, name: "decoding", value: "async")
        return out
    }

    private static func rewriteImgTags(in html: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive]) else {
            return html
        }
        let nsRange = NSRange(html.startIndex..., in: html)
        var result = html
        for match in regex.matches(in: html, range: nsRange).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let tag = String(result[range])
            result.replaceSubrange(range, with: transform(tag))
        }
        return result
    }

    private static func firstCapture(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static func insertAttribute(_ tag: String, name: String, value: String) -> String {
        if tag.range(of: #"\b\#(name)\s*="#, options: [.regularExpression, .caseInsensitive]) != nil {
            return tag
        }
        return tag.replacingOccurrences(of: "<img", with: "<img \(name)=\"\(value)\"", options: [.caseInsensitive])
    }

    private static func replaceAttribute(_ tag: String, name: String, value: String) -> String {
        let pattern = #"\b\#(name)\s*=\s*["'][^"']*["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range, in: tag) else {
            return insertAttribute(tag, name: name, value: value)
        }
        var out = tag
        out.replaceSubrange(range, with: "\(name)=\"\(value)\"")
        return out
    }

    private static func removeAttribute(_ tag: String, name: String) -> String {
        let pattern = #"\s\#(name)\s*=\s*["'][^"']*["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return tag
        }
        return regex.stringByReplacingMatches(
            in: tag,
            options: [],
            range: NSRange(tag.startIndex..., in: tag),
            withTemplate: ""
        )
    }
}

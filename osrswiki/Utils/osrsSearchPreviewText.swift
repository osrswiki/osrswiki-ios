import Foundation

/// Preview text for Search rows when Cirrus snippets and intro extracts are empty.
/// Update pages often start with templates or a verbatim copyright line, so
/// `exintro` is blank even though the parse HTML always has readable copy.
enum osrsSearchPreviewText {
    static let maxChars = 160

    static func fromPlainExtract(_ extract: String?) -> String? {
        firstUsableChunk(extract ?? "")
    }

    static func fromCandidates(_ values: String?...) -> String? {
        for value in values {
            if let preview = fromPlainExtract(value) {
                return preview
            }
        }
        return nil
    }

    static func fromHtml(_ html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        let withoutChrome = stripDocumentChrome(html)
        let blocks = withoutChrome.replacingOccurrences(
            of: "</(?:p|div|h[1-6]|li|section)>",
            with: "\u{1e}",
            options: [.regularExpression, .caseInsensitive]
        ).components(separatedBy: "\u{1e}")
        var fallback: String?
        for block in blocks {
            guard let preview = preview(from: stripTags(block)) else { continue }
            if looksLikeSentence(preview) {
                return preview
            }
            if fallback == nil {
                fallback = preview
            }
        }
        return fallback ?? firstUsableChunk(stripTags(withoutChrome))
    }

    static func preview(from raw: String) -> String? {
        var text = decodeEntities(stripTags(raw))
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if isBoilerplate(text) { return nil }
        if text.count <= maxChars { return text }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        var clipped = String(text[..<end])
        if let lastSpace = clipped.lastIndex(of: " "), lastSpace > clipped.startIndex {
            clipped = String(clipped[..<lastSpace])
        }
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstUsableChunk(_ raw: String) -> String? {
        if let preview = preview(from: raw) {
            return preview
        }
        let chunks = raw.components(separatedBy: CharacterSet.newlines)
            + raw.replacingOccurrences(
                of: "(?<=[.!?])\\s+",
                with: "\n",
                options: .regularExpression
            ).components(separatedBy: "\n")
        for chunk in chunks {
            if let preview = preview(from: chunk) {
                return preview
            }
        }
        return nil
    }

    private static func isBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("copied verbatim")
            || lower.contains("this official news post")
            || lower.contains("if you can't see the")
            || lower.contains("if you can’t see the")
            || lower.contains("click here to show")
            || lower.contains("it was added on")
            || lower.contains("snapshots of the web page")
            || lower.contains("horizontal_line")
            || lower == "contents"
            || lower == "changelog"
            || lower.hasPrefix("file:")
            || lower.hasPrefix("category:") {
            return true
        }
        if lower.range(of: "^[0-9]+px-", options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"^\d+\s+\S+.+\d+\s+\S+"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\d+\.\d+\s+\S+.+\d+\.\d+\s+\S+"#, options: .regularExpression) != nil {
            return true
        }
        return text.contains("_") && !text.contains(" ")
    }

    private static func looksLikeSentence(_ text: String) -> Bool {
        text.count >= 40 && text.range(of: #"[A-Za-z][.!?](?:\s|$)"#, options: .regularExpression) != nil
    }

    private static func stripDocumentChrome(_ html: String) -> String {
        html.replacingOccurrences(
            of: "<script[\\s\\S]*?</script>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(
            of: "<style[\\s\\S]*?</style>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(
            of: "<(?:div|nav|ol|ul)[^>]*(?:id|class)=['\"][^'\"]*\\btoc\\b[^'\"]*['\"][^>]*>[\\s\\S]*?</(?:div|nav|ol|ul)>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(
            of: "<div[^>]*id=['\"]mw-panel-toc['\"][^>]*>[\\s\\S]*?</div>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = decoded as NSString
            let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length)).reversed()
            var mutable = decoded
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let digits = ns.substring(with: match.range(at: 1))
                if let value = Int(digits), let scalar = UnicodeScalar(value) {
                    let range = Range(match.range, in: mutable)!
                    mutable.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
            decoded = mutable
        }
        return decoded
    }
}

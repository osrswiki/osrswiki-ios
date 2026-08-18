import Foundation

enum SearchQueryPolicy {
    struct HighlightRange: Hashable {
        let startInclusive: Int
        let endExclusive: Int
    }

    private static let officialHosts = Set(["oldschool.runescape.wiki", "www.oldschool.runescape.wiki"])

    static func apiQuery(_ rawQuery: String) -> String {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           officialHosts.contains(host) {
            let encodedTitle: String? = if url.path.hasPrefix("/w/") {
                String(url.path.dropFirst(3))
            } else if url.path.hasSuffix("/index.php"),
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.queryItems?.first(where: { $0.name == "title" })?.value
            } else {
                nil
            }
            if let encodedTitle, !encodedTitle.isEmpty {
                return encodedTitle.removingPercentEncoding?
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
            }
        }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: #"(?i)^(?:how\s+to\s+get|where\s+to\s+find|where\s+is|what\s+is)\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\s+(?:osrs|old\s+school\s+runescape|wiki)(?:\s+(?:page|article))?\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func merge(
        prefix: [WikiGeneratedSearchPage],
        fulltext: [WikiGeneratedSearchPage],
        for rawQuery: String
    ) -> [WikiGeneratedSearchPage] {
        var byPageId: [Int: WikiGeneratedSearchPage] = [:]
        var order: [Int] = []
        for page in prefix + fulltext {
            if let existing = byPageId[page.pageid] {
                byPageId[page.pageid] = existing.enriched(with: page)
            } else {
                byPageId[page.pageid] = page.withPreviewFallback()
                order.append(page.pageid)
            }
        }
        let combined = order.compactMap { byPageId[$0] }
        return rank(combined, for: rawQuery)
    }

    static func rank(_ results: [WikiGeneratedSearchPage], for rawQuery: String) -> [WikiGeneratedSearchPage] {
        let query = normalize(apiQuery(rawQuery))
        guard !query.isEmpty else { return results.sorted { $0.index < $1.index } }
        let queryTokens = tokens(query)

        return results.enumerated().sorted { left, right in
            let leftScore = score(query: query, queryTokens: queryTokens, title: normalize(left.element.title))
            let rightScore = score(query: query, queryTokens: queryTokens, title: normalize(right.element.title))
            if leftScore != rightScore { return leftScore > rightScore }
            if left.element.index != right.element.index { return left.element.index < right.element.index }
            return left.offset < right.offset
        }.map(\.element)
    }

    static func highlightTerms(_ rawQuery: String) -> [String] {
        var seen = Set<String>()
        return tokens(normalize(apiQuery(rawQuery))).filter { $0.count >= 2 && seen.insert($0).inserted }
    }

    /// Titles may use the complete contiguous query prefix, including a one-character
    /// final word. This makes `barbarian v` visibly match `Barbarian V` without
    /// highlighting every incidental `v` in result previews.
    static func titleHighlightRanges(_ displayText: String, query rawQuery: String) -> [HighlightRange] {
        let decodedText = osrsStringUtils.decodeHTMLEntitiesFixedPoint(displayText)
        let decodedQuery = osrsStringUtils.decodeHTMLEntitiesFixedPoint(apiQuery(rawQuery))
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !decodedQuery.isEmpty,
           let prefixRange = decodedText.range(
               of: decodedQuery,
               options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
               range: decodedText.startIndex..<decodedText.endIndex,
               locale: .current
           ),
           prefixRange.lowerBound == decodedText.startIndex {
            let range = NSRange(prefixRange, in: decodedText)
            return [HighlightRange(startInclusive: range.location, endExclusive: range.location + range.length)]
        }

        return matchingRanges(in: decodedText, terms: highlightTerms(rawQuery))
    }

    /// Preview text deliberately excludes one-character terms to avoid noisy matches.
    static func snippetHighlightRanges(_ displayText: String, query rawQuery: String) -> [HighlightRange] {
        matchingRanges(
            in: osrsStringUtils.decodeHTMLEntitiesFixedPoint(displayText),
            terms: highlightTerms(rawQuery)
        )
    }

    /// Prefix expansion improves recall for partial words without adding a second network trip.
    static func networkQuery(_ rawQuery: String) -> String {
        let canonical = apiQuery(rawQuery)
        let range = NSRange(canonical.startIndex..<canonical.endIndex, in: canonical)
        let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
        let terms = regex?.matches(in: canonical, range: range).compactMap { match -> String? in
            guard let range = Range(match.range, in: canonical) else { return nil }
            return String(canonical[range])
        } ?? []
        guard !terms.isEmpty else { return canonical }
        return terms.map { $0.count >= 3 ? "\($0)*" : $0 }.joined(separator: " ")
    }

    private static func score(query: String, queryTokens: [String], title: String) -> Int {
        if title == query { return 100_000 }
        if title.hasPrefix(query) { return 90_000 - max(0, title.count - query.count) }
        let titleTokens = tokens(title)
        let genericTrailingTokens = Set(["guide", "page", "article", "wiki"])
        if !titleTokens.isEmpty,
           queryTokens.count > titleTokens.count,
           Array(queryTokens.prefix(titleTokens.count)) == titleTokens,
           queryTokens.dropFirst(titleTokens.count).allSatisfy({ genericTrailingTokens.contains($0) }) {
            return 89_000 - max(0, query.count - title.count)
        }
        if !queryTokens.isEmpty && queryTokens.allSatisfy({ queryToken in
            titleTokens.contains(where: { $0.hasPrefix(queryToken) })
        }) {
            return 88_000 - abs(title.count - query.count)
        }
        if query.count >= 4, editDistance(query, title, limit: 2) { return 85_000 }
        // A short title that merely begins a longer query must not outrank a title covering
        // every query token ("Amulet" versus "Amulet of glory" for "amulet glo").
        if !title.isEmpty, query.hasPrefix(title) { return 65_000 - max(0, query.count - title.count) }
        if queryTokens.count == 1, titleTokens.contains(where: { $0.hasPrefix(queryTokens[0]) }) {
            return 60_000 - abs(title.count - query.count)
        }
        return 0
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func tokens(_ value: String) -> [String] { value.split(separator: " ").map(String.init) }

    private static func matchingRanges(in text: String, terms: [String]) -> [HighlightRange] {
        let source = text as NSString
        var ranges: [HighlightRange] = []

        for term in terms {
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let match = source.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: searchRange
                )
                guard match.location != NSNotFound, match.length > 0 else { break }
                ranges.append(
                    HighlightRange(
                        startInclusive: match.location,
                        endExclusive: match.location + match.length
                    )
                )
                let nextLocation = match.location + match.length
                searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
            }
        }

        return Array(Set(ranges))
            .sorted { lhs, rhs in
                lhs.startInclusive == rhs.startInclusive
                    ? lhs.endExclusive < rhs.endExclusive
                    : lhs.startInclusive < rhs.startInclusive
            }
    }

    private static func editDistance(_ left: String, _ right: String, limit: Int) -> Bool {
        let lhs = Array(left), rhs = Array(right)
        guard abs(lhs.count - rhs.count) <= limit else { return false }
        var previous = Array(0...rhs.count)
        for i in lhs.indices {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = i + 1
            var rowMinimum = current[0]
            for j in rhs.indices {
                current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (lhs[i] == rhs[j] ? 0 : 1))
                rowMinimum = min(rowMinimum, current[j + 1])
            }
            if rowMinimum > limit { return false }
            previous = current
        }
        return previous[rhs.count] <= limit
    }
}

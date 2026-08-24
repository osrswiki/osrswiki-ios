import Foundation

/// Canonical View more / empty-query updates order: reverse chronological
/// (most recent first). Both platforms must apply this same key.
///
/// Sort key:
///  1. MediaWiki generator index ascending. `generator=recentchanges` with
///     `grcdir=older` numbers the newest change index=1.
///  2. ISO-8601 `timestamp` descending when index is missing.
///  3. `pageid` descending (new pages receive increasing ids).
enum osrsUpdatesBrowseOrder {
    static func sort(_ pages: [WikiGeneratedSearchPage]) -> [WikiGeneratedSearchPage] {
        pages.sorted { lhs, rhs in
            let leftIndex = lhs.index > 0 ? lhs.index : Int.max
            let rightIndex = rhs.index > 0 ? rhs.index : Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            let leftStamp = lhs.timestamp ?? ""
            let rightStamp = rhs.timestamp ?? ""
            if leftStamp != rightStamp { return leftStamp > rightStamp }
            return lhs.pageid > rhs.pageid
        }
    }

    static func sort(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { lhs, rhs in
            let leftIndex = (lhs.index ?? 0) > 0 ? (lhs.index ?? Int.max) : Int.max
            let rightIndex = (rhs.index ?? 0) > 0 ? (rhs.index ?? Int.max) : Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            let leftStamp = lhs.timestamp ?? ""
            let rightStamp = rhs.timestamp ?? ""
            if leftStamp != rightStamp { return leftStamp > rightStamp }
            let leftId = Int(lhs.id) ?? 0
            let rightId = Int(rhs.id) ?? 0
            return leftId > rightId
        }
    }
}

enum osrsSearchResultSnippetReserve {
    /// Two subheadline lines plus the 4pt title-to-snippet gap. Always reserved
    /// so preview enrich cannot grow a View more row after first paint.
    static let height: CGFloat = 36
}

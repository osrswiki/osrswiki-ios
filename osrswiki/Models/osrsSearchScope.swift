import Foundation

/// Reusable Search destination filter. Home "View more" is one call site:
/// Update: namespace (112), reverse-chronological when the query is empty
/// (`osrsUpdatesBrowseOrder`: generator index, then timestamp, then pageid).
struct osrsSearchScope: Hashable, Sendable {
    var namespace: Int?
    var emptyQueryBrowsesNewest: Bool
    var placeholder: String

    static let all = osrsSearchScope(
        namespace: nil,
        emptyQueryBrowsesNewest: false,
        placeholder: "Search OSRS Wiki"
    )

    static let updates = osrsSearchScope(
        namespace: osrsMediaWikiNamespace.updates,
        emptyQueryBrowsesNewest: true,
        placeholder: "Search updates"
    )

    var restrictsNamespace: Bool { namespace != nil }
}

enum osrsMediaWikiNamespace {
    static let main = 0
    static let updates = 112
    static let calculator = 116
    /// Default Home search: main articles plus user-facing Calculator: pages.
    static let defaultSearch = "\(main)|\(calculator)"
}

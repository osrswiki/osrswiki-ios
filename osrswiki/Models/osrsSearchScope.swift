import Foundation

/// Reusable Search destination filter. Home "View more" is one call site:
/// Update: namespace (112), newest-first when the query is empty.
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
}

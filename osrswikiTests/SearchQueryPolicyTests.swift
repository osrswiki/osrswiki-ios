import XCTest
@testable import osrswiki

final class SearchQueryPolicyTests: XCTestCase {
    private var noisyServerOrder: [WikiGeneratedSearchPage] {
        [
            page("Locations", 1),
            page("Herblore", 2),
            page("Demonic Pacts", 3),
            page("Font", 4),
            page("Barbarian Village", 5),
            page("Barbarian", 6)
        ]
    }

    func testPartialMultiTokenQueryPromotesExpectedTitle() {
        XCTAssertEqual(SearchQueryPolicy.rank(noisyServerOrder, for: "barbarian v").first?.title, "Barbarian Village")
    }

    func testTypoAndOverspecifiedQueriesPromoteExpectedTitle() {
        XCTAssertEqual(SearchQueryPolicy.rank(noisyServerOrder, for: "barbarian vilage").first?.title, "Barbarian Village")
        XCTAssertEqual(SearchQueryPolicy.rank(noisyServerOrder, for: "barbarian village osrs").first?.title, "Barbarian Village")
    }

    func testOfficialArticleURLUsesReadableArticleTitle() {
        let url = "https://oldschool.runescape.wiki/w/Amulet_of_glory"
        XCTAssertEqual(SearchQueryPolicy.apiQuery(url), "Amulet of glory")
        XCTAssertEqual(
            SearchQueryPolicy.rank([page("Minigames", 1), page("Amulet of glory", 9)], for: url).first?.title,
            "Amulet of glory"
        )
        XCTAssertEqual(
            SearchQueryPolicy.apiQuery("https://oldschool.runescape.wiki/index.php?title=Barbarian_Village&oldid=1"),
            "Barbarian Village"
        )
    }

    func testCommonOverspecificationIsRemovedBeforeNetworkRequest() {
        XCTAssertEqual(SearchQueryPolicy.apiQuery("barbarian village osrs"), "barbarian village")
        XCTAssertEqual(SearchQueryPolicy.apiQuery("how to get Amulet of glory"), "Amulet of glory")
        XCTAssertEqual(SearchQueryPolicy.apiQuery("where is Ancient Cavern wiki page"), "Ancient Cavern")
        XCTAssertEqual(SearchQueryPolicy.networkQuery("falador gen store"), "falador* gen* store*")
        XCTAssertEqual(SearchQueryPolicy.apiQuery("Amulet_of_glory"), "Amulet of glory")
        XCTAssertEqual(SearchQueryPolicy.networkQuery("Amulet_of_glory"), "Amulet* of glory*")
    }

    func testPunctuationOnlyServerTitlesCannotOutrankRealMatches() {
        XCTAssertEqual(
            SearchQueryPolicy.rank([page("? ? ? ?", 1), page("Recipe for Disaster", 2)], for: "recipe disaster").first?.title,
            "Recipe for Disaster"
        )
    }

    func testTitlePrefixPagesSurfaceEvenWhenFulltextRanksUnrelatedRunes() {
        let prefix = [page("Earth rune", 1), page("Earth rune pack", 2)]
        let fulltext = [page("Nature rune", 1), page("Law rune", 2), page("Death rune", 3)]
        XCTAssertEqual(
            SearchQueryPolicy.merge(prefix: prefix, fulltext: fulltext, for: "earth ru").first?.title,
            "Earth rune"
        )
        XCTAssertEqual(
            SearchQueryPolicy.rank(prefix + fulltext, for: "earth rune").first?.title,
            "Earth rune"
        )
    }

    func testFullTokenCoverageOutranksShortTitlePrefix() {
        let results = [page("Amulet", 1), page("Amulet of glory", 2)]
        XCTAssertEqual(SearchQueryPolicy.rank(results, for: "amulet glo").first?.title, "Amulet of glory")
        XCTAssertEqual(
            SearchQueryPolicy.rank([page("Ironman Guide/Sailing", 1), page("Sailing", 2)], for: "sailing guide").first?.title,
            "Sailing"
        )
    }

    func testUnrelatedResultsRetainStableServerOrder() {
        XCTAssertEqual(
            SearchQueryPolicy.rank(noisyServerOrder, for: "unmatched phrase").map(\.pageid),
            noisyServerOrder.map(\.pageid)
        )
    }

    func testHighlightingUsesMeaningfulTerms() {
        XCTAssertEqual(SearchQueryPolicy.highlightTerms("Barbarian V"), ["barbarian"])
        XCTAssertTrue(SearchQueryPolicy.highlightTerms("a").isEmpty)
    }

    func testTitleHighlightIncludesContiguousOneLetterTrailingPrefix() {
        XCTAssertEqual(
            SearchQueryPolicy.titleHighlightRanges("Barbarian Village", query: "barbarian v"),
            [SearchQueryPolicy.HighlightRange(startInclusive: 0, endExclusive: 11)]
        )
    }

    func testPrefixHitsKeepFulltextSnippetsWhenTheTitleMatchHasNoPreview() {
        let prefix = [
            page("Glory", 10, snippet: nil),
            page("Amulet of glory", 20, snippet: nil)
        ]
        let fulltext = [
            page("Glory", 10, snippet: "A quest item used in..."),
            page("Amulet of glory", 20, snippet: "A dragonstone amulet...")
        ]
        let merged = SearchQueryPolicy.merge(prefix: prefix, fulltext: fulltext, for: "glory")
        XCTAssertEqual(merged.first { $0.title == "Glory" }?.snippet, "A quest item used in...")
        XCTAssertEqual(merged.first { $0.title == "Amulet of glory" }?.snippet, "A dragonstone amulet...")
    }

    func testSnippetHighlightDoesNotPromoteOneLetterTrailingToken() {
        XCTAssertEqual(
            SearchQueryPolicy.snippetHighlightRanges("Barbarian values are common", query: "barbarian v"),
            [SearchQueryPolicy.HighlightRange(startInclusive: 0, endExclusive: 9)]
        )
    }

    func testRepresentativeQueryCorpusPromotesNaturalTitleMatches() {
        let cases = [
            ("barbarian v", "Barbarian Village"),
            ("barbarian vilage", "Barbarian Village"),
            ("BARBARIAN-VILLAGE", "Barbarian Village"),
            ("where to find Barbarian Village", "Barbarian Village"),
            ("amulet glo", "Amulet of glory"),
            ("amulet glory", "Amulet of glory"),
            ("amulet of glroy", "Amulet of glory"),
            ("Amulet_of_glory", "Amulet of glory"),
            ("amulet of glory (4)", "Amulet of glory"),
            ("low level alch", "Low Level Alchemy"),
            ("dragon scim", "Dragon scimitar"),
            ("recipe disaster", "Recipe for Disaster"),
            ("varrok teleport", "Varrock Teleport"),
            ("ancient cav", "Ancient Cavern"),
            ("falador gen store", "Falador General Store"),
            ("zulrah", "Zulrah"),
            ("agility training guide", "Agility training"),
            ("ironman money making", "Ironman money making guide"),
            ("sailing guide", "Sailing"),
            ("https://oldschool.runescape.wiki/w/Barbarian_Village", "Barbarian Village")
        ]
        let distractors = ["Locations", "Herblore", "Demonic Pacts", "Font"]
        for (index, entry) in cases.enumerated() {
            let results = (distractors + [entry.1]).enumerated().map { page($0.element, $0.offset + 1) }
            XCTAssertEqual(SearchQueryPolicy.rank(results, for: entry.0).first?.title, entry.1, "case \(index): \(entry.0)")
        }
    }

    private func page(_ title: String, _ index: Int, snippet: String? = nil) -> WikiGeneratedSearchPage {
        WikiGeneratedSearchPage(
            ns: 0,
            pageid: index,
            title: title,
            index: index,
            snippet: snippet,
            size: nil,
            wordcount: nil,
            timestamp: nil,
            thumbnail: nil
        )
    }
}

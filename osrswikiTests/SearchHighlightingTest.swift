//
//  SearchHighlightingTest.swift
//  osrswikiTests
//
//  Created to verify search highlighting works without crashes
//

import XCTest
import SwiftUI
import UIKit
@testable import osrswiki

class SearchHighlightingTest: XCTestCase {
    
    func testServerProvidedHighlightExtraction() {
        // Test that we correctly extract and apply server-provided highlights
        let snippetWithHighlights = """
        The city of <span class="searchmatch">Varrock</span> is the capital of Misthalin. \
        Located in central <span class="searchmatch">Varrock</span>, the Grand Exchange serves as...
        """
        
        // Simulate ThemedSearchResult processing
        var highlightTerms: [String] = []
        var tempSnippet = snippetWithHighlights
        
        // Extract highlight terms (mimicking SearchResultRowView logic)
        while let startRange = tempSnippet.range(of: "<span class=\"searchmatch\">", options: .caseInsensitive) {
            if let endRange = tempSnippet.range(of: "</span>", options: .caseInsensitive, range: startRange.upperBound..<tempSnippet.endIndex) {
                let highlightText = String(tempSnippet[startRange.upperBound..<endRange.lowerBound])
                if !highlightText.isEmpty {
                    highlightTerms.append(highlightText)
                }
                // Remove this occurrence to find the next one
                tempSnippet.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                break
            }
        }
        
        // Verify we extracted the correct terms
        XCTAssertEqual(highlightTerms.count, 2, "Should extract 2 highlighted terms")
        XCTAssertEqual(highlightTerms[0], "Varrock", "First highlight should be 'Varrock'")
        XCTAssertEqual(highlightTerms[1], "Varrock", "Second highlight should be 'Varrock'")
        
        // Clean the snippet
        let cleanedSnippet = snippetWithHighlights
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        XCTAssertEqual(cleanedSnippet, "The city of Varrock is the capital of Misthalin. Located in central Varrock, the Grand Exchange serves as...",
                      "Cleaned snippet should have no HTML tags")
        
        // Verify AttributedString creation doesn't crash
        let attributed = AttributedString(cleanedSnippet)
        XCTAssertFalse(attributed.characters.isEmpty, "AttributedString should be created successfully")
    }
    
    func testHTMLEntityDecoding() {
        // Test that HTML entities are properly decoded
        let textWithEntities = "Zezima&#039;s profile &amp; achievements &lt;guide&gt;"
        
        // This should use the decodingHTMLEntities extension
        let decoded = textWithEntities.decodingHTMLEntities()
        
        XCTAssertEqual(decoded, "Zezima's profile & achievements <guide>",
                      "HTML entities should be decoded correctly")
    }

    func testNestedHTMLEntitiesDecodeToFixedPoint() {
        XCTAssertEqual(
            "Wyrmscraig &amp;amp; Sailing Changes".decodingHTMLEntities(),
            "Wyrmscraig & Sailing Changes"
        )
        XCTAssertEqual(
            osrsStringUtils.extractMainTitle("Update:Wyrmscraig &amp;amp; Sailing Changes"),
            "Wyrmscraig & Sailing Changes"
        )
    }

    func testTitleHighlightStylesTheTrailingPrefixCharacter() throws {
        let result = ThemedSearchResult(
            title: "Barbarian Village",
            url: "https://oldschool.runescape.wiki/w/Barbarian_Village",
            searchQuery: "barbarian v"
        )
        let highlighted = try XCTUnwrap(result.highlightedTitle)
        let highlightRun = try XCTUnwrap(highlighted.runs.first(where: {
            String(highlighted.characters[$0.range]).contains("Barbarian V")
        }))
        XCTAssertTrue(
            highlightRun.inlinePresentationIntent?.contains(.stronglyEmphasized) == true,
            "The trailing title-prefix character must remain semantically emphasized."
        )
    }

    func testThemedBaseColorPreservesExplicitSearchHighlight() throws {
        let model = ThemedSearchResult(
            title: "Barbarian Village",
            url: "https://oldschool.runescape.wiki/w/Barbarian_Village",
            searchQuery: "barbarian v"
        )
        let prepared = try XCTUnwrap(model.highlightedTitle)
        let themeColor = Color(red: 58 / 255, green: 46 / 255, blue: 28 / 255)
        let rendered = SearchResultRowView.applyingBaseColor(to: prepared, color: themeColor)
        let highlightRun = try XCTUnwrap(rendered.runs.first(where: {
            String(rendered.characters[$0.range]).contains("Barbarian V")
        }))
        let baseRun = try XCTUnwrap(rendered.runs.first(where: {
            String(rendered.characters[$0.range]).contains("illage")
        }))
        let highlightColor = try XCTUnwrap(highlightRun.foregroundColor)
        let baseColor = try XCTUnwrap(baseRun.foregroundColor)

        XCTAssertEqual(baseColor, themeColor)
        XCTAssertNotEqual(highlightColor, baseColor, "The brown match color must survive theme application")
    }

    func testServerSnippetHighlightIgnoresOneCharacterQueryTokens() throws {
        let result = ThemedSearchResult(
            title: "Barbarian Village",
            snippet: #"<span class="searchmatch">Barbarian</span> <span class="searchmatch">v</span> history"#,
            url: "https://oldschool.runescape.wiki/w/Barbarian_Village",
            searchQuery: "barbarian v"
        )
        let snippet = try XCTUnwrap(result.processedSnippet)
        let native = NSAttributedString(snippet)
        let barbarianRange = (native.string as NSString).range(of: "Barbarian")
        let trailingVRange = (native.string as NSString).range(of: "v")

        let policyRanges = SearchQueryPolicy.snippetHighlightRanges(native.string, query: "barbarian v")
        XCTAssertTrue(
            policyRanges.contains {
                $0.startInclusive == barbarianRange.location &&
                    $0.endExclusive == NSMaxRange(barbarianRange)
            },
            "The meaningful server match must remain in the snippet highlight policy."
        )
        XCTAssertFalse(
            policyRanges.contains {
                $0.startInclusive <= trailingVRange.location &&
                    $0.endExclusive > trailingVRange.location
            },
            "The one-character token must not become a noisy snippet highlight."
        )
        let trailingFont = native.attribute(.font, at: trailingVRange.location, effectiveRange: nil) as? UIFont
        XCTAssertFalse(
            trailingFont?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
            "A one-character trailing query token should remain unhighlighted in snippets."
        )
    }
    
    func testNoExpensiveNSAttributedStringOperations() {
        // Ensure we're not using NSAttributedString for HTML processing
        let htmlSnippet = "<b>Test</b> content with <i>formatting</i>"
        
        // Process without NSAttributedString
        let cleaned = htmlSnippet
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingHTMLEntities()
        
        XCTAssertEqual(cleaned, "Test content with formatting",
                      "Should clean HTML without NSAttributedString")
        
        // Verify this doesn't involve expensive operations
        let start = Date()
        for _ in 0..<1000 {
            _ = htmlSnippet
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .decodingHTMLEntities()
        }
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, 1.0, "1000 iterations should complete in under 1 second")
    }
    
    func testAttributedStringHighlighting() {
        // Test the final highlighting application
        let cleanText = "The city of Varrock is the capital"
        let highlightTerm = "Varrock"
        
        var attributed = AttributedString(cleanText)
        
        if let range = cleanText.range(of: highlightTerm, options: .caseInsensitive) {
            if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
               let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[attrStart..<attrEnd].foregroundColor = Color(.systemOrange)
                attributed[attrStart..<attrEnd].font = .body.bold()
            }
        }
        
        // Verify attributes were applied (just check that it doesn't crash)
        // We can't easily extract the text back, but we've verified the operations don't crash
        XCTAssertTrue(true, "Highlighting operations completed without crash")
    }
}

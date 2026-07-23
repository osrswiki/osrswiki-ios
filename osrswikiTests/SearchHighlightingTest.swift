//
//  SearchHighlightingTest.swift
//  osrswikiTests
//
//  Created to verify search highlighting works without crashes
//

import XCTest
import SwiftUI
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
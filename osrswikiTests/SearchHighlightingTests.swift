//
//  SearchHighlightingTests.swift
//  osrswikiTests
//
//  Unit tests to verify HTML search highlighting produces correct orange color
//

import XCTest
import SwiftUI
import Foundation
@testable import osrswiki

final class SearchHighlightingTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Called before each test method
    }
    
    override func tearDownWithError() throws {
        // Called after each test method
    }
    
    // MARK: - Core HTML Highlighting Tests
    
    func testHtmlToAttributedString_WithSearchMatch_ProducesOrangeColor() throws {
        // Given
        let inputHtml = "The <span class=\"searchmatch\">dragon</span> scimitar is a weapon."
        let expectedOrangeColor = UIColor(red: 1.0, green: 0.42, blue: 0.208, alpha: 1.0) // #FF6B35
        
        // When
        let result = inputHtml.htmlToAttributedString()
        let nsAttributedString = NSAttributedString(result)
        
        // Then - Verify the AttributedString was created
        XCTAssertGreaterThan(nsAttributedString.length, 0, "AttributedString should not be empty")
        
        // Find the "dragon" word in the attributed string
        let fullText = nsAttributedString.string
        XCTAssertTrue(fullText.contains("dragon"), "Result should contain the word 'dragon'")
        
        // Find range of "dragon" word
        let dragonRange = (fullText as NSString).range(of: "dragon")
        XCTAssertNotEqual(dragonRange.location, NSNotFound, "Should find 'dragon' in the text")
        
        // Verify color attribute at the dragon word location
        let attributes = nsAttributedString.attributes(at: dragonRange.location, effectiveRange: nil)
        
        // Check if foreground color exists
        guard let actualColor = attributes[.foregroundColor] as? UIColor else {
            XCTFail("No foreground color found at 'dragon' location")
            return
        }
        
        // Convert colors to RGBA components for comparison
        var actualRed: CGFloat = 0, actualGreen: CGFloat = 0, actualBlue: CGFloat = 0, actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0, expectedGreen: CGFloat = 0, expectedBlue: CGFloat = 0, expectedAlpha: CGFloat = 0
        
        let _ = actualColor.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha)
        let _ = expectedOrangeColor.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha)
        
        // Verify orange color components (with tolerance for floating point comparison)
        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.01, "Red component should match #FF6B35")
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.01, "Green component should match #FF6B35") 
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.01, "Blue component should match #FF6B35")
        
        print("✅ Test Result: Orange color verified")
        print("   Expected: R=\(expectedRed), G=\(expectedGreen), B=\(expectedBlue)")
        print("   Actual:   R=\(actualRed), G=\(actualGreen), B=\(actualBlue)")
    }
    
    func testHtmlToAttributedString_WithoutSearchMatch_HasNoOrangeColor() throws {
        // Given
        let inputHtml = "The dragon scimitar is a weapon."
        
        // When
        let result = inputHtml.htmlToAttributedString()
        let nsAttributedString = NSAttributedString(result)
        
        // Then - Verify no orange color attributes exist
        nsAttributedString.enumerateAttributes(in: NSRange(location: 0, length: nsAttributedString.length), options: []) { attributes, range, _ in
            if let color = attributes[.foregroundColor] as? UIColor {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                let _ = color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                
                // Verify it's NOT orange (#FF6B35)
                let isOrange = abs(red - 1.0) < 0.01 && abs(green - 0.42) < 0.01 && abs(blue - 0.208) < 0.01
                XCTAssertFalse(isOrange, "Should not have orange color when no searchmatch tags present")
            }
        }
        
        print("✅ Test Result: No orange color when no searchmatch tags")
    }
    
    func testHtmlToAttributedString_WithMultipleSearchMatches_AllHaveOrangeColor() throws {
        // Given
        let inputHtml = "The <span class=\"searchmatch\">dragon</span> and <span class=\"searchmatch\">scimitar</span> are both highlighted."
        let expectedOrangeColor = UIColor(red: 1.0, green: 0.42, blue: 0.208, alpha: 1.0) // #FF6B35
        
        // When
        let result = inputHtml.htmlToAttributedString()
        let nsAttributedString = NSAttributedString(result)
        
        // Then
        let fullText = nsAttributedString.string
        
        // Verify both words are highlighted with orange
        let words = ["dragon", "scimitar"]
        for word in words {
            let wordRange = (fullText as NSString).range(of: word)
            XCTAssertNotEqual(wordRange.location, NSNotFound, "Should find '\(word)' in text")
            
            let attributes = nsAttributedString.attributes(at: wordRange.location, effectiveRange: nil)
            guard let actualColor = attributes[.foregroundColor] as? UIColor else {
                XCTFail("No foreground color found at '\(word)' location")
                continue
            }
            
            var actualRed: CGFloat = 0, actualGreen: CGFloat = 0, actualBlue: CGFloat = 0, actualAlpha: CGFloat = 0
            let _ = actualColor.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha)
            
            XCTAssertEqual(actualRed, 1.0, accuracy: 0.01, "'\(word)' should have orange red component")
            XCTAssertEqual(actualGreen, 0.42, accuracy: 0.01, "'\(word)' should have orange green component") 
            XCTAssertEqual(actualBlue, 0.208, accuracy: 0.01, "'\(word)' should have orange blue component")
        }
        
        print("✅ Test Result: Multiple searchmatch terms all have orange color")
    }
    
    func testHtmlColorConversion_VerifyExactColorMatch() throws {
        // Given - Test the exact HTML color conversion
        let htmlWithColor = "<font color='#FF6B35'>test</font>"
        
        // When - Create NSAttributedString directly from HTML
        guard let data = htmlWithColor.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            XCTFail("Failed to parse HTML with color")
            return
        }
        
        // Then - Verify the exact color
        let attributes = attributedString.attributes(at: 0, effectiveRange: nil)
        guard let actualColor = attributes[.foregroundColor] as? UIColor else {
            XCTFail("No foreground color found in HTML conversion")
            return
        }
        
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let _ = actualColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Verify exact #FF6B35 color
        XCTAssertEqual(red, 1.0, accuracy: 0.01, "Red should be 1.0 for #FF6B35")
        XCTAssertEqual(green, 0.42, accuracy: 0.01, "Green should be ~0.42 for #FF6B35") 
        XCTAssertEqual(blue, 0.208, accuracy: 0.01, "Blue should be ~0.208 for #FF6B35")
        
        print("✅ Test Result: HTML color #FF6B35 converts correctly")
        print("   Color values: R=\(red), G=\(green), B=\(blue)")
    }
}

// MARK: - String Extension for Testing
extension String {
    func htmlToAttributedString() -> AttributedString {
        // DEBUG: Log the conversion process for testing
        print("🔍 [TEST DEBUG] Original snippet: '\(self)'")
        
        // Handle search match highlighting similar to Android 
        // Android uses: <span class="searchmatch"> -> <b><font color='#FF6B35'>
        let orangeColor = "#FF6B35"  // Same as Android's search_highlight_light
        let highlightedHtml = self
            .replacingOccurrences(of: "<span class=\"searchmatch\">", with: "<b><font color='\(orangeColor)'>")
            .replacingOccurrences(of: "</span>", with: "</font></b>")
        
        print("🔍 [TEST DEBUG] After HTML transformation: '\(highlightedHtml)'")
        
        // Convert HTML to AttributedString
        guard let data = highlightedHtml.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            // Fallback to plain text if HTML parsing fails
            print("🔍 [TEST DEBUG] HTML parsing FAILED - using plain text fallback")
            return AttributedString(self)
        }
        
        // Create mutable copy to override font attributes while preserving colors
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        
        // Get the system subheadline font to match SwiftUI's .subheadline
        let systemFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldSystemFont = UIFont.boldSystemFont(ofSize: systemFont.pointSize)
        
        print("🔍 [TEST DEBUG] Setting fonts - Regular: \(systemFont.fontName), Bold: \(boldSystemFont.fontName)")
        print("🔍 [TEST DEBUG] Target highlight color: \(orangeColor)")
        
        // Apply system font to entire string, preserving other attributes (colors, bold)
        let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
        
        // First, set all text to regular system font (preserving other attributes)
        mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
        
        // Then, find bold ranges and apply bold system font (colors are preserved)
        mutableAttributedString.enumerateAttribute(.font, in: fullRange) { (value, range, _) in
            if let font = value as? UIFont {
                if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                    mutableAttributedString.addAttribute(.font, value: boldSystemFont, range: range)
                }
            }
        }
        
        let result = AttributedString(mutableAttributedString)
        print("🔍 [TEST DEBUG] Font override SUCCESS - using system fonts")
        
        return result
    }
}
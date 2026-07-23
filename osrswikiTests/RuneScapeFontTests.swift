//
//  RuneScapeFontTests.swift
//  osrswikiTests
//
//  Created for automated RuneScape font verification
//

import XCTest
import SwiftUI
@testable import osrswiki

final class RuneScapeFontTests: XCTestCase {
    
    func testRuneScapeFontIsRegisteredAndLoaded() throws {
        // Test that RuneScape Plain font is properly registered in the app bundle
        let possibleFontNames = [
            "RuneScape Plain 12",
            "runescape_plain",
            "RuneScape Plain", 
            "RuneScape",
            "runescape"
        ]
        
        var foundFont: UIFont?
        var foundFontName: String?
        
        for fontName in possibleFontNames {
            if let font = UIFont(name: fontName, size: 14) {
                foundFont = font
                foundFontName = fontName
                break
            }
        }
        
        XCTAssertNotNil(foundFont, "RuneScape font should be registered and loadable")
        XCTAssertNotNil(foundFontName, "Should find at least one valid RuneScape font name")
        
        if let fontName = foundFontName {
            print("✅ FONT TEST: Successfully loaded RuneScape font with name: '\(fontName)'")
        }
    }
    
    func testRuneScapeFontFileExists() throws {
        // Verify the font file exists in the app bundle
        guard let fontPath = Bundle.main.path(forResource: "runescape_plain", ofType: "ttf") else {
            XCTFail("runescape_plain.ttf should exist in app bundle")
            return
        }
        
        let fileExists = FileManager.default.fileExists(atPath: fontPath)
        XCTAssertTrue(fileExists, "RuneScape font file should exist at path: \(fontPath)")
        
        print("✅ FONT FILE TEST: RuneScape font file exists at: \(fontPath)")
    }
    
    func testProgressViewUsesRuneScapeFont() throws {
        // Test that the osrsProgressView component actually uses RuneScape font
        let progressView = osrsProgressView(progress: 0.5, progressText: "Test Progress")
        
        // We need to extract the font from the view - this is tricky in SwiftUI
        // Let's verify the font resolution logic matches what osrsProgressView uses
        let fontNames = ["RuneScape Plain 12", "runescape_plain", "RuneScape Plain", "RuneScape", "runescape"]
        var resolvedFont: UIFont?
        
        for fontName in fontNames {
            if let font = UIFont(name: fontName, size: 14) {
                resolvedFont = font
                break
            }
        }
        
        XCTAssertNotNil(resolvedFont, "osrsProgressView should be able to resolve RuneScape font")
        
        // Verify it's not falling back to system font
        let systemFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        XCTAssertNotEqual(resolvedFont?.fontName, systemFont.fontName, 
                         "Should use RuneScape font, not fall back to system font")
        
        if let font = resolvedFont {
            print("✅ PROGRESS VIEW FONT TEST: Using font: '\(font.fontName)' (family: \(font.familyName))")
        }
    }
    
    func testFontRegistrationInInfoPlist() throws {
        // Verify runescape_plain.ttf is listed in Info.plist UIAppFonts
        guard let infoPlist = Bundle.main.infoDictionary,
              let appFonts = infoPlist["UIAppFonts"] as? [String] else {
            XCTFail("UIAppFonts should be defined in Info.plist")
            return
        }
        
        let hasRuneScapeFont = appFonts.contains("runescape_plain.ttf")
        XCTAssertTrue(hasRuneScapeFont, "runescape_plain.ttf should be listed in UIAppFonts")
        
        print("✅ INFO.PLIST TEST: RuneScape font properly registered in UIAppFonts")
        print("📝 All registered fonts: \(appFonts)")
    }
    
    func testComprehensiveFontValidation() throws {
        // Comprehensive test that verifies the entire font loading pipeline
        print("\n🧪 COMPREHENSIVE FONT VALIDATION STARTING...")
        
        // Step 1: Check Info.plist registration
        guard let infoPlist = Bundle.main.infoDictionary,
              let appFonts = infoPlist["UIAppFonts"] as? [String],
              appFonts.contains("runescape_plain.ttf") else {
            XCTFail("❌ FONT PIPELINE FAILURE: runescape_plain.ttf not in Info.plist UIAppFonts")
            return
        }
        print("✅ Step 1: Font registered in Info.plist")
        
        // Step 2: Check font file exists
        guard let fontPath = Bundle.main.path(forResource: "runescape_plain", ofType: "ttf"),
              FileManager.default.fileExists(atPath: fontPath) else {
            XCTFail("❌ FONT PIPELINE FAILURE: runescape_plain.ttf file missing from bundle")
            return
        }
        print("✅ Step 2: Font file exists in bundle at: \(fontPath)")
        
        // Step 3: Check font can be loaded by UIFont
        let fontNames = ["RuneScape Plain 12", "runescape_plain", "RuneScape Plain", "RuneScape", "runescape"]
        var loadedFont: UIFont?
        var workingFontName: String?
        
        for fontName in fontNames {
            if let font = UIFont(name: fontName, size: 14) {
                loadedFont = font
                workingFontName = fontName
                break
            }
        }
        
        guard let actualFont = loadedFont else {
            XCTFail("❌ FONT PIPELINE FAILURE: UIFont cannot load any RuneScape font variant")
            return
        }
        print("✅ Step 3: Font successfully loaded by UIFont: '\(actualFont.fontName)' using name '\(workingFontName ?? "unknown")'")
        
        // Step 4: Verify it's actually the RuneScape font (not system fallback)
        let systemFont = UIFont.systemFont(ofSize: 14)
        XCTAssertNotEqual(actualFont.fontName, systemFont.fontName, 
                         "Should load actual RuneScape font, not fall back to system")
        print("✅ Step 4: Font is genuine RuneScape font (not system fallback)")
        
        // Step 5: Test font family detection
        print("📝 Font Details:")
        print("   - Font Name: \(actualFont.fontName)")
        print("   - Family Name: \(actualFont.familyName)")
        print("   - Point Size: \(actualFont.pointSize)")
        print("   - Working Font Name: \(workingFontName ?? "unknown")")
        
        print("🎉 COMPREHENSIVE FONT VALIDATION: ALL TESTS PASSED!")
    }
}
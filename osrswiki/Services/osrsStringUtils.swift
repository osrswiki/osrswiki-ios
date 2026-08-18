//
//  osrsStringUtils.swift
//  OSRS Wiki
//
//  Created on title cleaning consistency session
//

import Foundation

/// Utility class for string manipulation, mirroring Android's StringUtil functionality
class osrsStringUtils {
    
    // CRASH FIX: Cache processed titles to avoid expensive HTML processing on main thread
    private static var titleCache = NSCache<NSString, NSString>()
    private static var plainHTMLCache = NSCache<NSString, NSString>()
    private static let cacheQueue = DispatchQueue(label: "osrsStringUtils.cache", attributes: .concurrent)
    
    /// Extracts the main title from a MediaWiki displayTitle, removing namespace prefixes.
    /// Handles both HTML-formatted titles (with mw-page-title-main spans) and plain text titles.
    /// Matches Android's StringUtil.extractMainTitle() functionality exactly.
    /// 
    /// CRASH FIX: Uses caching to avoid expensive HTML processing on main thread during cell rendering
    ///
    /// - Parameter displayTitle: The display title which may contain HTML or plain text
    /// - Returns: The cleaned main title without namespace prefix or Update: prefixes
    static func extractMainTitle(_ displayTitle: String) -> String {
        let cacheKey = displayTitle as NSString
        
        // CRASH FIX: Check cache first to avoid expensive HTML processing
        if let cached = titleCache.object(forKey: cacheKey) {
            return cached as String
        }
        
        let processedTitle = extractMainTitleUncached(displayTitle)
        
        // Store in cache for future use
        titleCache.setObject(processedTitle as NSString, forKey: cacheKey)
        
        return processedTitle
    }
    
    /// Internal uncached version of extractMainTitle for actual processing
    private static func extractMainTitleUncached(_ displayTitle: String) -> String {
        var extractedTitle: String?

        // Check if it contains MediaWiki title HTML structure
        if displayTitle.contains("mw-page-title-main") {
            // Extract content between <span class="mw-page-title-main"> and </span>
            let pattern = #"<span[^>]*class="mw-page-title-main"[^>]*>([^<]+)</span>"#
            
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(location: 0, length: displayTitle.utf16.count)
                
                if let match = regex.firstMatch(in: displayTitle, options: [], range: range) {
                    if let swiftRange = Range(match.range(at: 1), in: displayTitle) {
                        extractedTitle = String(displayTitle[swiftRange])
                    }
                }
            } catch {
                print("Error parsing MediaWiki title HTML: \(error)")
            }
        }
        
        // Normalize at the presentation boundary as well as at persistence. MediaWiki feed
        // records can be entity encoded more than once (for example `&amp;amp;`).
        let cleanTitle = decodeHTMLEntitiesFixedPoint(stripHTML(extractedTitle ?? displayTitle))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove "Update:" prefixes (with and without space)
        if cleanTitle.hasPrefix("Update: ") {
            return String(cleanTitle.dropFirst("Update: ".count))
        } else if cleanTitle.hasPrefix("Update:") {
            return String(cleanTitle.dropFirst("Update:".count))
        }
        
        return cleanTitle
    }
    
    /// Strips HTML tags from a string
    /// CRASH FIX: Optimized to avoid expensive NSAttributedString processing when possible
    /// - Parameter htmlString: The HTML string to clean
    /// - Returns: Plain text without HTML tags
    private static func stripHTML(_ htmlString: String) -> String {
        htmlString.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
    }

    /// Produces non-interactive list-row copy from HTML without creating attributed links.
    /// Rows whose whole surface is already a button must not embed a second interactive
    /// attributed-text graph; that combination can form an accessibility layout cycle.
    static func plainText(fromHTML htmlString: String) -> String {
        let cacheKey = htmlString as NSString
        if let cached = plainHTMLCache.object(forKey: cacheKey) {
            return cached as String
        }

        let separated = htmlString.replacingOccurrences(
            of: #"</?(?:p|div|li|br|h[1-6]|tr|td|th|ul|ol|blockquote)\b[^>]*>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let value = decodeHTMLEntitiesFixedPoint(stripHTML(separated))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        plainHTMLCache.setObject(value as NSString, forKey: cacheKey)
        return value
    }

    /// Bounded fixed-point decoding keeps entity text out of every list surface without
    /// invoking the expensive HTML attributed-string parser during row rendering.
    static func decodeHTMLEntitiesFixedPoint(_ value: String) -> String {
        var decoded = value
        for _ in 0..<8 {
            let next = decodeHTMLEntitiesSinglePass(decoded)
            if next == decoded { break }
            decoded = next
        }
        return decoded
    }

    private static func decodeHTMLEntitiesSinglePass(_ value: String) -> String {
        let namedEntities = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#039;", "'"),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&ldquo;", "\""),
            ("&rdquo;", "\""),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™")
        ]

        var result = value
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        result = replacingNumericEntities(in: result, pattern: #"&#(\d+);"#, radix: 10)
        return replacingNumericEntities(in: result, pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
    }

    private static func replacingNumericEntities(in value: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        var result = value
        let matches = regex.matches(
            in: result,
            range: NSRange(location: 0, length: (result as NSString).length)
        )
        for match in matches.reversed() {
            guard let numberRange = Range(match.range(at: 1), in: result),
                  let codePoint = UInt32(result[numberRange], radix: radix),
                  let scalar = UnicodeScalar(codePoint),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}

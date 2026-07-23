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
        // Check if it contains MediaWiki title HTML structure
        if displayTitle.contains("mw-page-title-main") {
            // Extract content between <span class="mw-page-title-main"> and </span>
            let pattern = #"<span[^>]*class="mw-page-title-main"[^>]*>([^<]+)</span>"#
            
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(location: 0, length: displayTitle.utf16.count)
                
                if let match = regex.firstMatch(in: displayTitle, options: [], range: range) {
                    if let swiftRange = Range(match.range(at: 1), in: displayTitle) {
                        return String(displayTitle[swiftRange])
                    }
                }
            } catch {
                print("Error parsing MediaWiki title HTML: \(error)")
            }
        }
        
        // Fallback to regular HTML cleaning and Update: prefix removal
        let cleanTitle = stripHTML(displayTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        // CRASH FIX: If string doesn't contain HTML tags, return as-is to avoid processing
        guard htmlString.contains("<") && htmlString.contains(">") else {
            return htmlString
        }
        
        // CRASH FIX: For simple HTML, use regex instead of expensive NSAttributedString
        // Only use NSAttributedString for complex HTML with entities
        if !htmlString.contains("&") && !htmlString.contains("style=") && !htmlString.contains("class=") {
            return htmlString.replacingOccurrences(
                of: "<[^>]+>", 
                with: "", 
                options: .regularExpression, 
                range: nil
            )
        }
        
        // Only use expensive NSAttributedString for complex HTML
        guard let data = htmlString.data(using: .utf8) else { return htmlString }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        do {
            // CRASH FIX: This is the expensive operation that was causing the crash
            let attributedString = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            return attributedString.string
        } catch {
            // Fallback: use regex to remove HTML tags
            return htmlString.replacingOccurrences(
                of: "<[^>]+>", 
                with: "", 
                options: .regularExpression, 
                range: nil
            )
        }
    }
}
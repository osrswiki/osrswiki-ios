//
//  SearchResultRowView.swift
//  OSRS Wiki
//
//  Created on iOS theming fixes session
//

import SwiftUI
import Foundation

struct SearchResultRowView: View {
    @Environment(\.osrsTheme) var osrsTheme
    let result: ThemedSearchResult
    let onTap: () -> Void
    
    // CRASH FIX: Static font to avoid repeated font lookup during rendering
    private static let alegreyaFont: UIFont = {
        let fontNames = ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya Regular"]
        for fontName in fontNames {
            if let font = UIFont(name: fontName, size: 20) {
                return font
            }
        }
        return UIFont.preferredFont(forTextStyle: .headline)
    }()
    
    // FUNCTIONALITY RESTORE: Use pre-processed highlighted data with proper theming
    private var displayTitle: AttributedString {
        // Use pre-processed highlighted title if available
        if let highlightedTitle = result.highlightedTitle {
            // Apply primary text color to non-highlighted parts while preserving highlights
            var attributed = highlightedTitle
            // The highlights already have secondary color, just ensure base text uses primary
            return attributed
        } else {
            // Fallback for no search query
            var attributed = AttributedString(result.processedTitle)
            attributed.font = Font(Self.alegreyaFont)
            attributed.foregroundColor = Color(osrsTheme.primaryTextColor)
            return attributed
        }
    }
    
    private var displaySnippet: AttributedString {
        // FUNCTIONALITY RESTORE: Use pre-processed snippet with HTML entity decoding and highlighting
        guard let processedSnippet = result.processedSnippet else {
            return AttributedString("")
        }
        
        // The snippet should have secondary text as base color
        var attributed = processedSnippet
        // Note: The highlighting already sets colors, we just return it
        return attributed
    }
    
    var body: some View {
        Button(action: {
            onTap()
        }) {
            HStack(spacing: 12) {
                // Main content section (title and snippet)
                VStack(alignment: .leading, spacing: 4) {
                    // CRASH FIX: Use pre-processed display properties - no expensive operations
                    Text(displayTitle)
                        .font(.osrsListTitle) // Ensure AttributedString font attributes are respected
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        // NO .foregroundStyle() - let AttributedString colors show through
                    
                    if result.processedSnippet != nil {
                        Text(displaySnippet)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                // Thumbnail positioned on the right (matching Android layout) - only show if URL exists
                if let thumbnailUrl = result.thumbnailUrl {
                    AsyncImage(url: thumbnailUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())                            .tint(.osrsPrimaryColor)
                            .frame(width: 60, height: 60)
                    }
                    .frame(width: 60, height: 60)
                    .background(.clear)
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(osrsTheme.surface)
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(osrsTheme.divider)
    }
}

// MARK: - ThemedSearchResult Model
struct ThemedSearchResult: Identifiable, Hashable {
    // CRASH FIX: Use consistent ID based on content hash instead of random UUID
    // This ensures stable identity for SwiftUI List cell dequeuing
    let id: String
    let title: String
    let snippet: String?
    let description: String?
    let url: String
    let thumbnailUrl: URL?
    let pageId: Int?
    
    // CRASH FIX: Pre-processed strings to avoid expensive operations during rendering
    let processedTitle: String
    let processedSnippet: AttributedString?
    // FUNCTIONALITY RESTORE: Pre-processed highlighted versions
    let highlightedTitle: AttributedString?
    let searchQuery: String?
    
    init(title: String, snippet: String? = nil, description: String? = nil, url: String, thumbnailUrl: URL? = nil, pageId: Int? = nil, searchQuery: String? = nil) {
        self.title = title
        self.snippet = snippet
        self.description = description
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.pageId = pageId
        self.searchQuery = searchQuery
        
        // CRASH FIX: Create stable ID based on content
        self.id = "\(url.hashValue)-\(title.hashValue)"
        
        // CRASH FIX: Pre-process expensive operations ONCE during creation, not during rendering
        // Use the title directly for highlighting, not the extracted/processed version
        let titleForHighlighting = title
            .replacingOccurrences(of: "_", with: " ")
            .decodingHTMLEntities()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.processedTitle = titleForHighlighting // Don't use extractMainTitle as it may remove search terms
        
        // FUNCTIONALITY RESTORE: Pre-process title highlighting during creation
        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            // Get the Alegreya font for highlighting
            let fontNames = ["Alegreya-Medium", "alegreya_medium", "Alegreya Medium", "Alegreya-Regular", "Alegreya Regular"]
            var alegreyaFont = UIFont.preferredFont(forTextStyle: .headline)
            for fontName in fontNames {
                if let font = UIFont(name: fontName, size: 20) {
                    alegreyaFont = font
                    break
                }
            }
            
            // Use the existing highlightMatches extension that works properly
            // Match Android: use brown (#8B7355) for ALL highlights
            // Note: Using hardcoded brown since we don't have theme context here
            let brownHighlightColor = Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x55/255.0) // #8B7355
            self.highlightedTitle = titleForHighlighting.highlightMatches(
                query: searchQuery,
                baseColor: Color.primary,      // Title base text (will be overridden by Text modifier)
                highlightColor: brownHighlightColor, // Brown highlight to match Android
                baseFont: alegreyaFont
            )
        } else {
            self.highlightedTitle = nil
        }
        
        // CRASH FIX: Process HTML safely without expensive NSAttributedString during creation
        if let snippet = snippet, !snippet.isEmpty {
            // Check if HTML contains search highlights
            let htmlString = snippet.lowercased()
            let hasSearchMatch = htmlString.contains("<span class=\"searchmatch\">") || htmlString.contains("searchmatch")
            
            if hasSearchMatch {
                // FUNCTIONALITY FIX: Preserve searchmatch highlights from server
                // Extract the terms that should be highlighted
                var highlightTerms: [String] = []
                var tempSnippet = snippet
                
                // Find all text within searchmatch tags - INFINITE LOOP FIX
                var safetyCounter = 0
                let maxIterations = 20 // Safety limit to prevent infinite loops
                while let startRange = tempSnippet.range(of: "<span class=\"searchmatch\">", options: .caseInsensitive), safetyCounter < maxIterations {
                    safetyCounter += 1
                    if let endRange = tempSnippet.range(of: "</span>", options: .caseInsensitive, range: startRange.upperBound..<tempSnippet.endIndex) {
                        let highlightText = String(tempSnippet[startRange.upperBound..<endRange.lowerBound])
                        if !highlightText.isEmpty {
                            highlightTerms.append(highlightText)
                        }
                        let originalLength = tempSnippet.count
                        tempSnippet.removeSubrange(startRange.lowerBound..<endRange.upperBound)
                        // INFINITE LOOP PROTECTION: If string didn't get shorter, break
                        if tempSnippet.count >= originalLength {
                            break
                        }
                    } else {
                        // No closing tag found, break to prevent infinite loop
                        break
                    }
                }
                
                // Now clean the snippet
                let cleanedSnippet = snippet
                    .replacingOccurrences(of: "<span class=\"searchmatch\">", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "</span>", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .decodingHTMLEntities()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Create AttributedString and highlight the extracted terms
                var attributed = AttributedString(cleanedSnippet)
                
                // Highlight each term that was marked by the server
                for term in highlightTerms {
                    if let range = cleanedSnippet.range(of: term, options: .caseInsensitive) {
                        if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
                           let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                            // Match Android: use brown (#8B7355) for server-provided highlights
                            let brownHighlightColor = Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x55/255.0)
                            attributed[attrStart..<attrEnd].foregroundColor = brownHighlightColor
                            // Just make it bold without changing the base font size
                            attributed[attrStart..<attrEnd].font = .subheadline.bold()
                        }
                    }
                }
                
                self.processedSnippet = attributed
            } else {
                // Simple processing without HTML complexity
                let cleaned = snippet
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .decodingHTMLEntities() // RESTORE: Decode &#039; etc.
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Apply manual highlighting to snippet if we have a search query
                if let searchQuery = searchQuery, !searchQuery.isEmpty {
                    // Match Android: use brown (#8B7355) for highlights, primary for base text
                    let brownHighlightColor = Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x55/255.0) // #8B7355
                    self.processedSnippet = cleaned.highlightMatches(
                        query: searchQuery,
                        baseColor: Color.primary,  // Snippet base text should match title (primary color)
                        highlightColor: brownHighlightColor // Brown for highlights
                    )
                } else {
                    var attributed = AttributedString(cleaned)
                    attributed.foregroundColor = Color.primary // Use primary color for non-highlighted snippets too
                    self.processedSnippet = attributed
                }
            }
        } else {
            self.processedSnippet = nil
        }
    }
}

#Preview {
    SearchResultRowView(
        result: ThemedSearchResult(
            title: "Dragon Scimitar",
            snippet: "A powerful melee weapon requiring Attack level 60... <span class=\"searchmatch\">dragon</span> scimitar &#039;s special attack...",
            description: "Article",
            url: "https://example.com",
            thumbnailUrl: nil,
            pageId: 123,
            searchQuery: "dragon" // FUNCTIONALITY RESTORE: Test highlighting
        )
    ) {
    }
    .environmentObject(osrsThemeManager.preview)
    .environment(\.osrsTheme, osrsLightTheme())
}

// MARK: - HTML Processing Extension
extension String {
    func htmlToAttributedStringSafe(baseColor: Color = .primary) -> AttributedString {
        // First decode HTML entities manually to ensure they're properly handled
        let decodedString = self.decodingHTMLEntities()
        
        // Handle search match highlighting with unified brown color
        // Use same brown as osrs_text_secondary_light (#8B7355) to match Android
        let brownColor = "#8B7355"  // Unified highlight color across platforms
        let highlightedHtml = decodedString
            .replacingOccurrences(of: "<span class=\"searchmatch\">", with: "<b><font color='\(brownColor)'>")
            .replacingOccurrences(of: "</span>", with: "</font></b>")
        
        // Convert HTML to AttributedString
        guard let data = highlightedHtml.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            // Fallback to plain text if HTML parsing fails
            return AttributedString(decodedString)
        }
        
        // Create mutable copy to override font attributes while preserving colors
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        
        // Get the system subheadline font to match SwiftUI's .subheadline
        let systemFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldSystemFont = UIFont.boldSystemFont(ofSize: systemFont.pointSize)
        
        
        // Apply system font to entire string, preserving existing colors
        let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
        
        // Store existing color attributes BEFORE making font changes
        var colorRanges: [(NSRange, UIColor)] = []
        mutableAttributedString.enumerateAttribute(.foregroundColor, in: fullRange) { (value, range, _) in
            if let color = value as? UIColor {
                colorRanges.append((range, color))
            }
        }
        
        // Apply system font to entire string
        mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
        
        // Apply bold system font to bold ranges
        mutableAttributedString.enumerateAttribute(.font, in: fullRange) { (value, range, _) in
            if let font = value as? UIFont {
                if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                    mutableAttributedString.addAttribute(.font, value: boldSystemFont, range: range)
                }
            }
        }
        
        // Apply colors: use base color for ranges without existing colors, preserve highlights
        mutableAttributedString.addAttribute(.foregroundColor, value: UIColor(baseColor), range: fullRange)
        
        // Restore specific highlight colors (they should be orange from HTML processing)
        for (range, color) in colorRanges {
            // Check if this is likely a highlight color (not black/default)
            let colorComponents = color.cgColor.components
            let isLikelyHighlight = colorComponents?.count ?? 0 >= 3 && 
                                   (colorComponents?[0] ?? 0) > 0.3 && // Some red component
                                   (colorComponents?[1] ?? 0) > 0.2 && // Some green component  
                                   color != UIColor.black && color != UIColor.label
            
            if isLikelyHighlight {
                mutableAttributedString.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        
        let result = AttributedString(mutableAttributedString)
        
        return result
    }
}

// MARK: - Manual Text Highlighting Extension
extension String {
    func highlightMatches(query: String, baseColor: Color, highlightColor: Color, baseFont: UIFont? = nil) -> AttributedString {
        let attributedString = NSMutableAttributedString(string: self)
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        // Set base color and font
        let font = baseFont ?? UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = baseFont?.withTraits(.traitBold) ?? UIFont.boldSystemFont(ofSize: font.pointSize)
        attributedString.addAttribute(.font, value: font, range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: UIColor(baseColor), range: fullRange)
        
        // Find and highlight matches (case insensitive) - INFINITE LOOP FIX
        let searchString = self.lowercased()
        let queryLowercased = query.lowercased()
        
        var searchIndex = 0
        var safetyCounter = 0
        let maxHighlights = 50 // Safety limit to prevent infinite loops
        
        while searchIndex < searchString.count && safetyCounter < maxHighlights {
            safetyCounter += 1
            let startIndex = searchString.index(searchString.startIndex, offsetBy: searchIndex)
            if let range = searchString.range(of: queryLowercased, range: startIndex..<searchString.endIndex) {
                let nsRange = NSRange(range, in: self)
                
                // Apply highlight color and bold
                attributedString.addAttribute(.foregroundColor, value: UIColor(highlightColor), range: nsRange)
                attributedString.addAttribute(.font, value: boldFont, range: nsRange)
                
                let newSearchIndex = self.distance(from: self.startIndex, to: range.upperBound)
                
                // INFINITE LOOP PROTECTION: Ensure we're making progress
                if newSearchIndex <= searchIndex {
                    break
                }
                
                searchIndex = newSearchIndex
            } else {
                break
            }
        }

        return AttributedString(attributedString)
    }
}

// MARK: - UIFont Extension for Bold Traits
extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return descriptor.map { UIFont(descriptor: $0, size: 0) }
    }
}

// MARK: - HTML Entity Decoding Extension
extension String {
    func decodingHTMLEntities() -> String {
        // Common HTML entities that appear in search results
        let entities = [
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
        
        var result = self
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Handle numeric character references (e.g., &#8217; for right single quote)
        let pattern = "&#(\\d+);"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = result as NSString
        let matches = regex?.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            if let codeRange = Range(match.range(at: 1), in: result),
               let code = Int(result[codeRange]),
               let scalar = UnicodeScalar(code) {
                let character = String(Character(scalar))
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: character)
            }
        }
        
        // Handle hexadecimal character references (e.g., &#x27; for apostrophe)
        let hexPattern = "&#x([0-9a-fA-F]+);"
        let hexRegex = try? NSRegularExpression(pattern: hexPattern, options: [])
        let hexMatches = hexRegex?.matches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length)) ?? []
        
        for match in hexMatches.reversed() {
            if let codeRange = Range(match.range(at: 1), in: result),
               let code = Int(result[codeRange], radix: 16),
               let scalar = UnicodeScalar(code) {
                let character = String(Character(scalar))
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: character)
            }
        }
        
        return result
    }
}

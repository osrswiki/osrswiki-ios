//
//  SearchResultRowView.swift
//  OSRS Wiki
//
//  Created on iOS theming fixes session
//

import SwiftUI
import Foundation
import ImageIO

struct SearchResultRowView: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            return Self.applyingBaseColor(
                to: highlightedTitle,
                color: Color(osrsTheme.primaryTextColor)
            )
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
        
        return Self.applyingBaseColor(
            to: processedSnippet,
            color: Color(osrsTheme.primaryTextColor)
        )
    }

    /// Highlight attributes are prepared without a platform label color so the rendered row can
    /// supply the active OSRS light/dark theme. Explicit brown match runs remain untouched.
    static func applyingBaseColor(to value: AttributedString, color: Color) -> AttributedString {
        var result = value
        let uncoloredRanges = result.runs.compactMap { run in
            run.foregroundColor == nil ? run.range : nil
        }
        for range in uncoloredRanges {
            result[range].foregroundColor = color
        }
        return result
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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .multilineTextAlignment(.leading)
                        // NO .foregroundStyle() - let AttributedString colors show through
                    
                    if result.processedSnippet != nil {
                        Text(displaySnippet)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                
                Spacer()
                
                // Thumbnail positioned on the right (matching Android layout) - only show if URL exists
                if let thumbnailUrl = result.thumbnailUrl {
                    osrsAnimatedThumbnailView(url: thumbnailUrl)
                    .frame(width: 60, height: 60)
                    .background(.osrsSearchBoxBackgroundColor)
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: 76,
                maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : 84
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 84)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("search_result_row_\(result.title)")
        .accessibilityLabel(result.title)
        .accessibilityAddTraits(.isButton)
        .listRowBackground(osrsTheme.surface)
        .listRowSeparator(.hidden)
        .osrsPrewarmArticleWhenVisible(
            pageURL: URL(string: result.url),
            pageTitle: result.title,
            retainWhileAppeared: result.searchQuery.map {
                $0.compare(result.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            } ?? false
        )
    }
}

/// A small UIKit-backed image view because SwiftUI's AsyncImage intentionally
/// displays only the first frame of animated GIFs. Search, history, and saved
/// lists share this component so their media behavior stays identical.
struct osrsAnimatedThumbnailView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let refreshToken: String?
    private static let cache = NSCache<NSString, UIImage>()

    init(url: URL?, refreshToken: String? = nil) {
        self.url = url
        self.refreshToken = refreshToken
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        // UIImageView otherwise advertises the downloaded bitmap's pixel size as
        // its intrinsic content size. That allowed a 240x160 Wiki thumbnail to
        // expand a nominally 60x60 SwiftUI list cell.
        let view = osrsThumbnailImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.image = UIImage(systemName: "doc.text.fill")
        view.tintColor = .secondaryLabel
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Article thumbnail"
        view.accessibilityValue = "loading"
        return view
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let identity = thumbnailIdentity
        guard context.coordinator.loadedIdentity != identity ||
                context.coordinator.loadedReduceMotion != reduceMotion else { return }
        context.coordinator.task?.cancel()
        context.coordinator.loadedIdentity = identity
        context.coordinator.loadedReduceMotion = reduceMotion
        imageView.stopAnimating()
        imageView.image = UIImage(systemName: "doc.text.fill")
        imageView.accessibilityValue = url == nil ? "unavailable" : "loading"
        guard let url else { return }

        let cacheKey = identity as NSString
        if let cached = Self.cache.object(forKey: cacheKey) {
            apply(cached, to: imageView)
            return
        }

        let cachePolicy: URLRequest.CachePolicy = refreshToken == nil
            ? .returnCacheDataElseLoad
            : .reloadRevalidatingCacheData
        let request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 20)
        context.coordinator.task = URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let image = Self.decodeImage(data: data) else { return }
            Self.cache.setObject(image, forKey: cacheKey)
            DispatchQueue.main.async {
                guard context.coordinator.loadedIdentity == identity else { return }
                apply(image, to: imageView)
            }
        }
        context.coordinator.task?.resume()
    }

    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        uiView.stopAnimating()
    }

    private func apply(_ image: UIImage, to imageView: UIImageView) {
        let animated = image.images?.isEmpty == false
        if reduceMotion, let firstFrame = image.images?.first {
            imageView.image = firstFrame
            imageView.accessibilityValue = "static"
        } else {
            imageView.image = image
            imageView.startAnimating()
            imageView.accessibilityValue = animated ? "animated" : "static"
        }
    }

    private static func decodeImage(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else { return UIImage(data: data) }

        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1)) ?? frames[0]
    }

    final class Coordinator {
        var loadedIdentity = ""
        var loadedReduceMotion = false
        var task: URLSessionDataTask?
    }

    private var thumbnailIdentity: String {
        guard let url else { return "unavailable" }
        return "\(url.absoluteString)#\(refreshToken ?? "cached")"
    }
}

private final class osrsThumbnailImageView: UIImageView {
    override var intrinsicContentSize: CGSize { .zero }
}

// MARK: - ThemedSearchResult Model
struct ThemedSearchResult: Identifiable, Hashable {
    private static let searchHighlightColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xFF/255.0, green: 0x8A/255.0, blue: 0x65/255.0, alpha: 1)
            : UIColor(red: 0xB5/255.0, green: 0x36/255.0, blue: 0x16/255.0, alpha: 1)
    })
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
        let titleForHighlighting = osrsStringUtils.extractMainTitle(
            title.replacingOccurrences(of: "_", with: " ")
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.processedTitle = titleForHighlighting
        
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
            let brownHighlightColor = Self.searchHighlightColor
            self.highlightedTitle = titleForHighlighting.highlightMatches(
                ranges: SearchQueryPolicy.titleHighlightRanges(titleForHighlighting, query: searchQuery),
                baseColor: nil,
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
                if let searchQuery {
                    highlightTerms.append(contentsOf: SearchQueryPolicy.highlightTerms(searchQuery))
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
                let meaningfulHighlightTerms = Set(
                    highlightTerms
                        .map(osrsStringUtils.decodeHTMLEntitiesFixedPoint)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.count >= 2 }
                )
                for term in meaningfulHighlightTerms {
                    var searchStart = cleanedSnippet.startIndex
                    while searchStart < cleanedSnippet.endIndex,
                          let range = cleanedSnippet.range(of: term, options: .caseInsensitive, range: searchStart..<cleanedSnippet.endIndex) {
                        if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
                           let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                            // Match Android: use brown (#8B7355) for server-provided highlights
                            let brownHighlightColor = Self.searchHighlightColor
                            attributed[attrStart..<attrEnd].foregroundColor = brownHighlightColor
                            // Just make it bold without changing the base font size
                            attributed[attrStart..<attrEnd].font = .subheadline.bold()
                        }
                        searchStart = range.upperBound
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
                    let brownHighlightColor = Self.searchHighlightColor
                    self.processedSnippet = cleaned.highlightMatches(
                        ranges: SearchQueryPolicy.snippetHighlightRanges(cleaned, query: searchQuery),
                        baseColor: nil,
                        highlightColor: brownHighlightColor // Brown for highlights
                    )
                } else {
                    self.processedSnippet = AttributedString(cleaned)
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
    func highlightMatches(
        ranges: [SearchQueryPolicy.HighlightRange],
        baseColor: Color?,
        highlightColor: Color,
        baseFont: UIFont? = nil
    ) -> AttributedString {
        var attributedString = AttributedString(self)

        // Build the presentation with native AttributedString attributes. Bridging a
        // dynamic UIColor through NSMutableAttributedString can lose the SwiftUI
        // foreground-color scope, allowing a later theme pass to overwrite matches.
        let font = baseFont ?? UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = baseFont?.withTraits(.traitBold) ?? UIFont.boldSystemFont(ofSize: font.pointSize)
        attributedString.font = Font(font)
        if let baseColor {
            attributedString.foregroundColor = baseColor
        }

        for range in ranges {
            let nsRange = NSRange(
                location: range.startInclusive,
                length: range.endExclusive - range.startInclusive
            )
            guard nsRange.location >= 0,
                  nsRange.length > 0,
                  let stringRange = Range(nsRange, in: self),
                  let start = AttributedString.Index(stringRange.lowerBound, within: attributedString),
                  let end = AttributedString.Index(stringRange.upperBound, within: attributedString) else {
                continue
            }
            attributedString[start..<end].foregroundColor = highlightColor
            attributedString[start..<end].font = Font(boldFont)
            attributedString[start..<end].inlinePresentationIntent = .stronglyEmphasized
        }

        return attributedString
    }

    func highlightMatches(
        query: String,
        baseColor: Color?,
        highlightColor: Color,
        baseFont: UIFont? = nil
    ) -> AttributedString {
        highlightMatches(
            ranges: SearchQueryPolicy.snippetHighlightRanges(self, query: query),
            baseColor: baseColor,
            highlightColor: highlightColor,
            baseFont: baseFont
        )
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
        osrsStringUtils.decodeHTMLEntitiesFixedPoint(self)
    }
}

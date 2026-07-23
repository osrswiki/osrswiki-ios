//
//  SimpleResourceDiscoveryTest.swift
//  osrswikiTests
//
//  Simple test to analyze HTML resource discovery patterns
//

import XCTest

@MainActor
class SimpleResourceDiscoveryTest: XCTestCase {
    
    func testVarrockPageResourceDiscovery() async throws {
        print("🧪 Testing Varrock page resource discovery...")
        
        // Fetch real MediaWiki content
        let varrockHTML = try await fetchMediaWikiContent(page: "Varrock")
        
        // Analyze HTML structure
        analyzeHTMLForResources(html: varrockHTML, pageName: "Varrock")
    }
    
    func testUpdatePageResourceDiscovery() async throws {
        print("🧪 Testing Update page resource discovery...")
        
        // Fetch real MediaWiki content  
        let updateHTML = try await fetchMediaWikiContent(page: "Update:Summer_Sweep_Up_Slayer_%26_More")
        
        // Analyze HTML structure
        analyzeHTMLForResources(html: updateHTML, pageName: "Update")
    }
    
    // MARK: - Helper Methods
    
    private func fetchMediaWikiContent(page: String) async throws -> String {
        let apiURL = URL(string: "https://oldschool.runescape.wiki/api.php?action=parse&format=json&prop=text&disablelimitreport=1&wrapoutputclass=mw-parser-output&page=\(page)")!
        
        print("📡 Fetching: \(apiURL.absoluteString)")
        
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let response = try JSONDecoder().decode(MediaWikiResponse.self, from: data)
        
        return response.parse.text.content
    }
    
    private func analyzeHTMLForResources(html: String, pageName: String) {
        print("\n📊 [\(pageName)] HTML Analysis Results:")
        print("═══════════════════════════════════════")
        
        // Basic stats
        print("📄 HTML length: \(html.count) characters")
        
        // Count different resource types manually
        let imgCount = html.components(separatedBy: "<img").count - 1
        let srcCount = html.components(separatedBy: "src=").count - 1
        let linkCount = html.components(separatedBy: "<link").count - 1
        let scriptCount = html.components(separatedBy: "<script").count - 1
        
        print("🔢 Manual counts:")
        print("   - <img> tags: \(imgCount)")
        print("   - src= attributes: \(srcCount)")
        print("   - <link> tags: \(linkCount)")  
        print("   - <script> tags: \(scriptCount)")
        
        // Test regex patterns (like ArticleViewModel uses)
        print("\n🎯 Regex pattern testing:")
        testRegexPattern(html: html, pattern: #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#, name: "Images")
        testRegexPattern(html: html, pattern: #"<link[^>]+href\s*=\s*[\"']([^\"']+\.css[^\"']*)[\"'][^>]*>"#, name: "CSS")
        testRegexPattern(html: html, pattern: #"<script[^>]+src\s*=\s*[\"']([^\"']+\.js[^\"']*)[\"'][^>]*>"#, name: "JavaScript")
        
        // Sample image URLs and test URL conversion
        print("\n🔄 URL conversion analysis:")
        sampleImageURLsAndTestConversion(html: html, pageName: pageName)
        
        print("═══════════════════════════════════════")
        print("[\(pageName)] Analysis complete\n")
    }
    
    private func testRegexPattern(html: String, pattern: String, name: String) {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            
            print("   - \(name): \(matches.count) regex matches")
            
            // Show first few matches
            let sampleCount = min(3, matches.count)
            for i in 0..<sampleCount {
                let match = matches[i]
                if match.numberOfRanges > 1 {
                    let range = Range(match.range(at: 1), in: html)!
                    let url = String(html[range])
                    print("     [\(i+1)] \(url)")
                }
            }
        } catch {
            print("   - \(name): REGEX ERROR - \(error)")
        }
    }
    
    private func sampleImageURLsAndTestConversion(html: String, pageName: String) {
        do {
            let imageRegex = try NSRegularExpression(pattern: #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#, options: [.caseInsensitive])
            let matches = imageRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            
            print("   Found \(matches.count) total image URLs")
            
            // Analyze URL patterns
            var urlPatterns: [String: Int] = [:]
            var sampleURLs: [String] = []
            
            for match in matches.prefix(10) { // Sample first 10
                if match.numberOfRanges > 1 {
                    let range = Range(match.range(at: 1), in: html)!
                    let url = String(html[range])
                    sampleURLs.append(url)
                    
                    // Categorize URL pattern
                    if url.starts(with: "http") {
                        urlPatterns["absolute"] = (urlPatterns["absolute"] ?? 0) + 1
                    } else if url.starts(with: "//") {
                        urlPatterns["protocol-relative"] = (urlPatterns["protocol-relative"] ?? 0) + 1
                    } else if url.starts(with: "/") {
                        urlPatterns["domain-relative"] = (urlPatterns["domain-relative"] ?? 0) + 1
                    } else {
                        urlPatterns["relative"] = (urlPatterns["relative"] ?? 0) + 1
                    }
                }
            }
            
            // Show URL pattern distribution
            print("   URL patterns found:")
            for (pattern, count) in urlPatterns.sorted(by: { $0.value > $1.value }) {
                print("     - \(pattern): \(count)")
            }
            
            // Test conversion logic on samples
            print("   Sample URL conversions:")
            for (i, url) in sampleURLs.prefix(5).enumerated() {
                let shouldHandle = shouldHandleURL(url)
                let converted = convertToAbsoluteURL(url)
                print("     [\(i+1)] \(url)")
                print("         Handle: \(shouldHandle), Converted: \(converted ?? "FAILED")")
            }
            
        } catch {
            print("   - Image URL analysis ERROR: \(error)")
        }
    }
    
    private func shouldHandleURL(_ url: String) -> Bool {
        // Test the filtering logic from ArticleViewModel
        return url.starts(with: "http") || url.starts(with: "//") || url.starts(with: "/")
    }
    
    private func convertToAbsoluteURL(_ url: String) -> String? {
        // Test the conversion logic from ArticleViewModel
        if url.starts(with: "http") {
            return url // Already absolute
        } else if url.starts(with: "//") {
            return "https:" + url // Protocol-relative
        } else if url.starts(with: "/") {
            return "https://oldschool.runescape.wiki" + url // Domain-relative  
        } else {
            return nil // Skip relative paths
        }
    }
}

// MARK: - Supporting Types

private struct MediaWikiResponse: Codable {
    let parse: ParseData
    
    struct ParseData: Codable {
        let text: TextWrapper
        
        struct TextWrapper: Codable {
            let content: String
            
            enum CodingKeys: String, CodingKey {
                case content = "*"
            }
        }
    }
}
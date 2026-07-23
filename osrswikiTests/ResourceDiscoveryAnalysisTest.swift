//
//  ResourceDiscoveryAnalysisTest.swift - SIMPLIFIED VERSION
//  osrswikiTests
//

import XCTest

@MainActor
class ResourceDiscoveryAnalysisTest: XCTestCase {
    
    func testVarrockResourceDiscovery() async throws {
        print("🧪 RESOURCE DISCOVERY ANALYSIS")
        
        // Fetch Varrock HTML
        let html = try await fetchHTML(page: "Varrock")
        
        // Count resources
        let imgCount = countPattern(html: html, pattern: #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#)
        let cssCount = countPattern(html: html, pattern: #"<link[^>]+href\s*=\s*[\"']([^\"']+\.css[^\"']*)[\"'][^>]*>"#)
        let jsCount = countPattern(html: html, pattern: #"<script[^>]+src\s*=\s*[\"']([^\"']+\.js[^\"']*)[\"'][^>]*>"#)
        
        // Analyze URLs
        let urls = extractImageURLs(html: html)
        let absoluteCount = urls.filter { $0.starts(with: "http") }.count
        let protocolRelativeCount = urls.filter { $0.starts(with: "//") }.count  
        let domainRelativeCount = urls.filter { $0.starts(with: "/") && !$0.starts(with: "//") }.count
        let relativeCount = urls.filter { !$0.starts(with: "http") && !$0.starts(with: "//") && !$0.starts(with: "/") }.count
        
        print("📊 RESULTS:")
        print("HTML: \(html.count) chars")
        print("Images: \(imgCount)")
        print("CSS: \(cssCount)")
        print("JS: \(jsCount)")
        print("URL Types:")
        print("  Absolute: \(absoluteCount)")
        print("  Protocol-relative: \(protocolRelativeCount)")
        print("  Domain-relative: \(domainRelativeCount)")  
        print("  Relative: \(relativeCount)")
        print("  Total URLs: \(urls.count)")
        
        // Sample URLs
        print("Sample URLs:")
        for (i, url) in urls.prefix(5).enumerated() {
            print("  \(i+1). \(url)")
        }
    }
    
    private func fetchHTML(page: String) async throws -> String {
        let url = URL(string: "https://oldschool.runescape.wiki/api.php?action=parse&format=json&prop=text&page=\(page)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(MediaWikiResponse.self, from: data)
        return response.parse.text.content
    }
    
    private func countPattern(html: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return regex.numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html))
    }
    
    private func extractImageURLs(html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#, options: [.caseInsensitive]) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }
}

private struct MediaWikiResponse: Codable {
    let parse: ParseData
    struct ParseData: Codable {
        let text: TextWrapper
        struct TextWrapper: Codable {
            let content: String
            enum CodingKeys: String, CodingKey { case content = "*" }
        }
    }
}
//
//  SaveProcessDiagnosticTest.swift
//  osrswikiTests
//

import XCTest

final class SaveProcessDiagnosticTest: XCTestCase {
    func testImageResourceDiscoveryConvertsWikiImageSourcesToAbsoluteURLs() throws {
        let html = """
        <figure>
            <img src="//oldschool.runescape.wiki/images/thumb/Varrock.png/300px-Varrock.png?620c5"
                 srcset="/images/thumb/Varrock.png/300px-Varrock.png?620c5 1x,
                         https://oldschool.runescape.wiki/images/thumb/Varrock.png/600px-Varrock.png?620c5 2x">
            <img src="/images/Misthalin_Area_Badge.png?d6e6d">
            <img src="https://oldschool.runescape.wiki/images/Varrock_East_bank.png?732e4">
        </figure>
        """

        let urls = Set(extractImageURLs(from: html).compactMap(makeAbsoluteWikiURL).map(\.absoluteString))

        XCTAssertEqual(
            urls,
            [
                "https://oldschool.runescape.wiki/images/thumb/Varrock.png/300px-Varrock.png?620c5",
                "https://oldschool.runescape.wiki/images/thumb/Varrock.png/600px-Varrock.png?620c5",
                "https://oldschool.runescape.wiki/images/Misthalin_Area_Badge.png?d6e6d",
                "https://oldschool.runescape.wiki/images/Varrock_East_bank.png?732e4"
            ],
            "Save resource discovery should normalize src and srcset wiki image URLs before caching"
        )
    }

    func testImageResourceDiscoveryIgnoresUnsupportedInlineAndRelativeSources() throws {
        let html = """
        <figure>
            <img src="data:image/png;base64,abc123">
            <img src="relative/local-only.png">
            <img src="">
            <img src="/images/Supported.png?12345">
        </figure>
        """

        let urls = extractImageURLs(from: html).compactMap(makeAbsoluteWikiURL).map(\.absoluteString)

        XCTAssertEqual(
            urls,
            ["https://oldschool.runescape.wiki/images/Supported.png?12345"],
            "Only absolute, protocol-relative, or wiki-root image URLs should enter the offline cache request set"
        )
    }

    private func extractImageURLs(from html: String) -> [String] {
        var urls = Set<String>()

        collectMatches(
            pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#,
            in: html
        ) { source in
            urls.insert(source)
        }

        collectMatches(
            pattern: #"<img[^>]+srcset\s*=\s*["']([^"']+)["'][^>]*>"#,
            in: html
        ) { srcset in
            for candidate in srcset.split(separator: ",") {
                guard let source = candidate
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .first
                else {
                    continue
                }
                urls.insert(String(source))
            }
        }

        return Array(urls).sorted()
    }

    private func collectMatches(
        pattern: String,
        in html: String,
        handle: (String) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            XCTFail("Regex should compile: \(pattern)")
            return
        }

        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                  let sourceRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            handle(String(html[sourceRange]))
        }
    }

    private func makeAbsoluteWikiURL(from resourcePath: String) -> URL? {
        guard !resourcePath.isEmpty, !resourcePath.hasPrefix("data:") else {
            return nil
        }

        if resourcePath.hasPrefix("https://oldschool.runescape.wiki/") {
            return URL(string: resourcePath)
        }

        if resourcePath.hasPrefix("//oldschool.runescape.wiki/") {
            return URL(string: "https:" + resourcePath)
        }

        if resourcePath.hasPrefix("/") {
            return URL(string: "https://oldschool.runescape.wiki" + resourcePath)
        }

        return nil
    }
}

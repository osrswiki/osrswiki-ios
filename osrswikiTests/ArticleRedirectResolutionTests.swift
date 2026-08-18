//
//  ArticleRedirectResolutionTests.swift
//  osrswikiTests
//
//  Regression coverage for MediaWiki redirect resolution in article loads.
//

import XCTest
@testable import osrswiki

@MainActor
final class ArticleRedirectResolutionTests: XCTestCase {
    func testParseRequestURLFollowsRedirectsForDirectArticleLoads() throws {
        let url = try XCTUnwrap(ArticleViewModel.makeParseRequestURL(pageTitle: "List of quests"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []

        XCTAssertEqual(queryItems.first(named: "action")?.value, "parse")
        XCTAssertEqual(queryItems.first(named: "page")?.value, "List of quests")
        XCTAssertEqual(queryItems.first(named: "redirects")?.value, "1")
        XCTAssertEqual(queryItems.first(named: "formatversion")?.value, "2")
        XCTAssertEqual(queryItems.first(named: "disableeditsection")?.value, "1")
        XCTAssertEqual(queryItems.first(named: "disablelimitreport")?.value, "1")
    }

    func testRedirectedParsePayloadUsesResolvedTitleAndRealContent() throws {
        let json = """
        {
            "parse": {
            "title": "Quests/List",
            "pageid": 1390,
            "displaytitle": "<span class=\\"mw-page-title-main\\">Quests/List</span>",
            "revid": 123456,
            "text": {
              "*": "<div class=\\"mw-parser-output\\"><p>This page lists all quests and miniquests.</p><table><tr><th>Quest</th></tr><tr><td>Cook's Assistant</td></tr></table></div>"
            }
          }
        }
        """

        let payload = try ArticleViewModel.decodeParsePayload(Data(json.utf8))

        XCTAssertEqual(payload.resolvedTitle, "Quests/List")
        XCTAssertTrue(payload.htmlContent.contains("Cook's Assistant"))
        XCTAssertFalse(payload.htmlContent.contains("Redirect to:"))
    }

    func testFormatVersion2StringTextDecodesWithoutNestedWrapper() throws {
        let json = """
        {
          "parse": {
            "title": "Varrock",
            "pageid": 42,
            "displaytitle": "Varrock",
            "revid": 9,
            "text": "<p>The capital of Misthalin.</p>"
          }
        }
        """

        let payload = try ArticleViewModel.decodeParsePayload(Data(json.utf8))
        XCTAssertEqual(payload.title, "Varrock")
        XCTAssertEqual(payload.htmlContent, "<p>The capital of Misthalin.</p>")
    }

    func testMissingTitleErrorStaysDistinctFromRedirectResolution() throws {
        let json = """
        {
          "error": {
            "code": "missingtitle",
            "info": "The page you specified doesn't exist."
          }
        }
        """

        XCTAssertThrowsError(try ArticleViewModel.decodeParsePayload(Data(json.utf8))) { error in
            guard case NetworkError.pageNotFound = error else {
                return XCTFail("Expected pageNotFound, got \\(error)")
            }
        }
    }
}

private extension Array where Element == URLQueryItem {
    func first(named name: String) -> URLQueryItem? {
        first { $0.name == name }
    }
}

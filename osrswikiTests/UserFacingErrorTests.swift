import XCTest
@testable import osrswiki

final class UserFacingErrorTests: XCTestCase {
    func testBackendAndSerializationDetailsNeverReachUsers() {
        let raw = NSError(
            domain: "decoder",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Field 'query' is required for type with serial name 'GeneratedSearchApiResponse'"]
        )
        let shown = UserFacingError.message(for: raw)
        XCTAssertEqual(shown, "Something went wrong. Please try again.")
        XCTAssertFalse(shown.localizedCaseInsensitiveContains("serial name"))
        XCTAssertFalse(shown.localizedCaseInsensitiveContains("query"))
    }

    func testNetworkFailuresUseActionableNontechnicalCopy() {
        XCTAssertEqual(
            UserFacingError.message(for: URLError(.notConnectedToInternet)),
            "Please check your internet connection and try again."
        )
        XCTAssertEqual(UserFacingError.message(for: URLError(.timedOut)), "That took too long. Please try again.")
    }

    func testRepositoryErrorsDoNotExposeTransportOrSchemaVocabulary() {
        let shown = [
            SearchError.invalidURL.localizedDescription,
            SearchError.invalidResponse.localizedDescription,
            SearchError.serverError.localizedDescription,
            NetworkError.serverError(503).localizedDescription,
            NetworkError.invalidData.localizedDescription,
            osrsFeedbackError.httpError(422).localizedDescription
        ]
        for message in shown {
            XCTAssertFalse(message.localizedCaseInsensitiveContains("http"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("invalid"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("schema"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("serial"))
        }
    }
}

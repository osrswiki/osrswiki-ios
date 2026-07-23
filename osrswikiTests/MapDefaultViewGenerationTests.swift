import XCTest

final class MapDefaultViewGenerationTests: XCTestCase {
    func testMainMapDefaultUsesGeneratedLumbridgeSpawnCoordinate() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let defaultViewSource = repoRoot
            .appendingPathComponent("osrswiki/Models/osrsMapDefaultView.swift")
        let mainMapSource = repoRoot
            .appendingPathComponent("osrswiki/Views/OSRSMapLibreView.swift")
        let backgroundPreloaderSource = repoRoot
            .appendingPathComponent("osrswiki/Services/osrsBackgroundMapPreloader.swift")
        let tilePrewarmerSource = repoRoot
            .appendingPathComponent("osrswiki/Services/osrsMapTilePrewarmingService.swift")

        let generated = try String(contentsOf: defaultViewSource)
        XCTAssertTrue(generated.contains("static let gameX = 3222.0"))
        XCTAssertTrue(generated.contains("static let gameY = 3218.0"))
        XCTAssertTrue(generated.contains("static let gameMinX = 960.0"))
        XCTAssertTrue(generated.contains("static let gameMaxX = 4224.0"))
        XCTAssertTrue(generated.contains("static let sourceImageWidth = 13056.0"))
        XCTAssertTrue(generated.contains("static let longitude = -130.2978515625"))
        XCTAssertTrue(generated.contains("static func mapCoordinate(gameX: Double, gameY: Double)"))

        for sourceURL in [mainMapSource, backgroundPreloaderSource, tilePrewarmerSource] {
            let source = try String(contentsOf: sourceURL)
            XCTAssertTrue(source.contains("osrsMapDefaultView"), "\(sourceURL.lastPathComponent) should use the generated map default view")
            XCTAssertFalse(source.contains("-25.2023457171692"), "\(sourceURL.lastPathComponent) should not use the stale iOS default latitude")
            XCTAssertFalse(source.contains("-131.44071698586012"), "\(sourceURL.lastPathComponent) should not use the stale iOS default longitude")
            XCTAssertFalse(source.contains("12800.0"), "\(sourceURL.lastPathComponent) should not hardcode the stale source image width")
        }
    }
}

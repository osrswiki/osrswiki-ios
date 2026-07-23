import XCTest

final class StaticSettingsPreviewSourceGuardTest: XCTestCase {
    func testNormalSettingsPreviewUiDoesNotInvokeDynamicPreviewGeneration() throws {
        let root = try repositoryRoot()

        let mainTab = try source(root, "platforms/ios/osrswiki/Views/MainTabView.swift")
        let customMainTab = try source(root, "platforms/ios/osrswiki/Views/CustomMainTabView.swift")
        let appearance = try source(root, "platforms/ios/osrswiki/Views/Settings/AppearanceSettingsView.swift")

        XCTAssertFalse(mainTab.contains("preGenerateAllPreviews"))
        XCTAssertFalse(customMainTab.contains("preGenerateAllPreviews"))
        XCTAssertFalse(appearance.contains("osrsBackgroundPreviewManager.shared"))
        XCTAssertFalse(appearance.contains("generatePreview(for:"))
        XCTAssertFalse(appearance.contains("generateTablePreview("))
    }

    func testSettingsPreviewAssetsAreGeneratedFromSimulatorAppRendering() throws {
        let root = try repositoryRoot()

        let generator = try source(root, "tools/settings-preview-assets/generate-settings-preview-assets.swift")
        let iosScript = try source(root, "scripts/ios/generate-settings-preview-assets.sh")
        let generatorTest = try source(root, "platforms/ios/osrswikiTests/SettingsPreviewAssetGenerationTest.swift")
        let exportView = try source(root, "platforms/ios/osrswiki/Views/Settings/osrsSettingsPreviewExportView.swift")

        XCTAssertFalse(generator.contains("import AppKit"), "Preview generator must not use host-side AppKit drawing.")
        XCTAssertFalse(generator.contains("NSBezierPath"), "Preview generator must not hand-draw generic preview shapes.")
        XCTAssertFalse(generator.contains("drawThemePreview("), "Theme assets must come from app-rendered previews.")
        XCTAssertFalse(generator.contains("drawTablePreview("), "Table assets must come from app-rendered previews.")

        XCTAssertTrue(iosScript.contains("SettingsPreviewAssetGenerationTest"))
        XCTAssertTrue(iosScript.contains("simctl get_app_container"))
        XCTAssertTrue(iosScript.contains("simctl io"))
        XCTAssertTrue(iosScript.contains("-settingsPreviewExport"))
        XCTAssertTrue(generatorTest.contains("osrsThemePreviewRenderer.shared"))
        XCTAssertTrue(exportView.contains("WKWebView"))
        XCTAssertTrue(exportView.contains("osrsPageHtmlBuilder"))
        XCTAssertTrue(exportView.contains("settings_preview_capture_ready"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("platforms/ios/osrswiki.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate repository root from \(#filePath)")
    }

    private func source(_ root: URL, _ path: String) throws -> String {
        let fileURL = root.appendingPathComponent(path)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

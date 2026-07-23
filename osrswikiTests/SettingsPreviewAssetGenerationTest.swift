import XCTest
import SwiftUI
import UIKit
@testable import osrswiki

@MainActor
final class SettingsPreviewAssetGenerationTest: XCTestCase {
    private let exportDirectoryName = "settings_preview_exports"
    private let logicalPreviewSize = CGSize(width: 82, height: 120)
    private let sourceScale: CGFloat = 4

    func testExportSettingsPreviewSourceImages() async throws {
        let root = try repositoryRoot()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".settings-preview-export-enabled").path) else {
            throw XCTSkip("Run scripts/ios/generate-settings-preview-assets.sh to export settings preview assets.")
        }

        let exportRoot = try resetExportRoot()
        let rawRoot = exportRoot.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawRoot, withIntermediateDirectories: true)

        let targetPixelSize = CGSize(
            width: logicalPreviewSize.width * sourceScale,
            height: logicalPreviewSize.height * sourceScale
        )

        let themeRenderer = osrsThemePreviewRenderer.shared
        themeRenderer.clearCache()

        let exports: [(name: String, source: UIImage, renderer: String)] = [
            (
                "settings_preview_theme_light",
                await themeRenderer.generatePreview(for: .osrsLight, colorScheme: .light),
                "osrsThemePreviewRenderer.shared"
            ),
            (
                "settings_preview_theme_dark",
                await themeRenderer.generatePreview(for: .osrsDark, colorScheme: .dark),
                "osrsThemePreviewRenderer.shared"
            ),
            (
                "settings_preview_theme_auto",
                await themeRenderer.generatePreview(for: .automatic),
                "osrsThemePreviewRenderer.shared"
            )
        ]

        var metadata: [[String: Any]] = []

        for export in exports {
            let framedImage = composeIntoStaticPreviewFrame(export.source, targetPixelSize: targetPixelSize)
            XCTAssertEqual(framedImage.cgImage?.width, Int(targetPixelSize.width), "\(export.name) width")
            XCTAssertEqual(framedImage.cgImage?.height, Int(targetPixelSize.height), "\(export.name) height")

            guard let data = framedImage.pngData() else {
                XCTFail("Could not encode \(export.name)")
                continue
            }

            let outputURL = rawRoot.appendingPathComponent("\(export.name).png")
            try data.write(to: outputURL, options: .atomic)

            metadata.append([
                "name": export.name,
                "renderer": export.renderer,
                "source_points": [
                    "width": export.source.size.width,
                    "height": export.source.size.height
                ],
                "export_pixels": [
                    "width": Int(targetPixelSize.width),
                    "height": Int(targetPixelSize.height)
                ]
            ])

            print("Exported app-rendered settings preview source: \(outputURL.path)")
        }

        let metadataData = try JSONSerialization.data(
            withJSONObject: [
                "logical_size_points": [
                    "width": Int(logicalPreviewSize.width),
                    "height": Int(logicalPreviewSize.height)
                ],
                "source_scale": Int(sourceScale),
                "exports": metadata
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try metadataData.write(to: exportRoot.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func resetExportRoot() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let exportRoot = documents.appendingPathComponent(exportDirectoryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: exportRoot.path) {
            try FileManager.default.removeItem(at: exportRoot)
        }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        return exportRoot
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

    private func composeIntoStaticPreviewFrame(_ source: UIImage, targetPixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: targetPixelSize, format: format).image { _ in
            let scale = min(
                targetPixelSize.width / source.size.width,
                targetPixelSize.height / source.size.height
            )
            let drawSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let drawOrigin = CGPoint(
                x: (targetPixelSize.width - drawSize.width) / 2,
                y: (targetPixelSize.height - drawSize.height) / 2
            )
            source.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}

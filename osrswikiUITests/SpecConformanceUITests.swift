//
//  SpecConformanceUITests.swift
//  osrswikiUITests
//
//  Contract-driven iOS UI conformance gate for top-level app screens.
//

import XCTest
import UIKit

final class SpecConformanceUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 12
    private var outputDirectory: URL!
    private var contractURL: URL!
    private var report = ConformanceReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        contractPath: "",
        screens: []
    )

    override func setUpWithError() throws {
        continueAfterFailure = true
        outputDirectory = try makeOutputDirectory()
        contractURL = try resolveContractURL()
        report.contractPath = contractURL.path
    }

    func testContractedScreensMatchSpec() throws {
        let contract = try loadContract()
        var failureSummaries: [String] = []

        for screen in contract.screens {
            let result = try evaluate(screen)
            report.screens.append(result)
            try writeReport()

            if !result.passed {
                failureSummaries.append(result.failureSummary)
            }
        }

        if !failureSummaries.isEmpty {
            XCTFail(failureSummaries.joined(separator: "\n\n"))
        }
    }

    private func evaluate(_ screen: ScreenContract) throws -> ScreenResult {
        let start = Date()
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading"
        ] + screen.launchArguments
        app.launch()

        var missingIdentifiers: [String] = []
        var missingLabels: [String] = []
        var scrollIssues: [String] = []

        guard app.wait(for: .runningForeground, timeout: launchTimeout) else {
            app.terminate()
            return ScreenResult(
                screenId: screen.id,
                name: screen.name,
                passed: false,
                elapsedSeconds: Date().timeIntervalSince(start),
                screenshotPath: nil,
                accessibilityTreePath: nil,
                visualAnalysisPath: nil,
                missingIdentifiers: screen.requiredIdentifiers,
                missingLabels: screen.requiredLabels,
                visualIssues: [],
                scrollIssues: ["App did not reach running foreground state within \(launchTimeout)s."]
            )
        }

        waitForInitialScreen(screen, in: app)

        let screenshot = captureScreenshot(for: screen, app: app)
        let screenshotURL = outputDirectory.appendingPathComponent("spec-\(fileStem(for: screen)).png")
        try screenshot.pngRepresentation.write(to: screenshotURL)
        attach(screenshot, named: "spec-\(screen.id)")

        let accessibilityTreeURL = outputDirectory.appendingPathComponent("accessibility-tree-\(fileStem(for: screen)).txt")
        let accessibilityTree = app.debugDescription

        let visualAnalysis = analyzeScreenshot(screenshot.pngRepresentation, for: screen)
        let visualAnalysisURL = outputDirectory.appendingPathComponent("visual-analysis-\(fileStem(for: screen)).json")
        try writeJSON(visualAnalysis, to: visualAnalysisURL)

        scrollIssues = scrollConformanceIssues(for: screen, in: app)

        var contractAccessibilityTree = accessibilityTree
        if shouldCaptureScrolledAccessibilityTree(for: screen, in: accessibilityTree) {
            scrollDown(in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            contractAccessibilityTree += "\n\n--- after scroll ---\n\n\(app.debugDescription)"
        }

        try contractAccessibilityTree.write(to: accessibilityTreeURL, atomically: true, encoding: .utf8)

        missingIdentifiers = missingRequiredIdentifiers(screen.requiredIdentifiers, in: contractAccessibilityTree)
        missingLabels = missingRequiredLabels(screen.requiredLabels, in: contractAccessibilityTree)

        app.terminate()

        let visualIssues = visualAnalysis.issues
        let passed = missingIdentifiers.isEmpty && missingLabels.isEmpty && visualIssues.isEmpty && scrollIssues.isEmpty

        return ScreenResult(
            screenId: screen.id,
            name: screen.name,
            passed: passed,
            elapsedSeconds: Date().timeIntervalSince(start),
            screenshotPath: screenshotURL.path,
            accessibilityTreePath: accessibilityTreeURL.path,
            visualAnalysisPath: visualAnalysisURL.path,
            missingIdentifiers: missingIdentifiers,
            missingLabels: missingLabels,
            visualIssues: visualIssues,
            scrollIssues: scrollIssues
        )
    }

    private func waitForInitialScreen(_ screen: ScreenContract, in app: XCUIApplication) {
        if let firstIdentifier = screen.requiredIdentifiers.first {
            let firstElement = screen.id == "SCREEN-APPEARANCE-001"
                ? app.otherElements[firstIdentifier]
                : app.descendants(matching: .any)[firstIdentifier]
            _ = firstElement.waitForExistence(timeout: launchTimeout)
        } else if let firstLabel = screen.requiredLabels.first {
            let predicate = NSPredicate(format: "label == %@", firstLabel)
            _ = app.descendants(matching: .any).matching(predicate).firstMatch.waitForExistence(timeout: launchTimeout)
        }

        let settleDelay: TimeInterval = screen.id == "SCREEN-MAP-001" ? 4.0 : 1.0
        RunLoop.current.run(until: Date().addingTimeInterval(settleDelay))
    }

    private func missingRequiredIdentifiers(_ identifiers: [String], in accessibilityTree: String) -> [String] {
        identifiers.filter { identifier in
            !accessibilityTree.contains("identifier: '\(identifier)'") &&
            !accessibilityTree.contains("identifier: \"\(identifier)\"")
        }
    }

    private func missingRequiredLabels(_ labels: [String], in accessibilityTree: String) -> [String] {
        labels.filter { label in
            !accessibilityTree.contains("label: '\(label)'") &&
            !accessibilityTree.contains("label: \"\(label)\"") &&
            !accessibilityTree.contains("placeholderValue: '\(label)'") &&
            !accessibilityTree.contains("placeholderValue: \"\(label)\"")
        }
    }

    private func shouldCaptureScrolledAccessibilityTree(for screen: ScreenContract, in accessibilityTree: String) -> Bool {
        !missingRequiredIdentifiers(screen.requiredIdentifiers, in: accessibilityTree).isEmpty ||
        !missingRequiredLabels(screen.requiredLabels, in: accessibilityTree).isEmpty
    }

    private func scrollConformanceIssues(for screen: ScreenContract, in app: XCUIApplication) -> [String] {
        guard screen.scrollExpectations?.mustScroll == true else {
            return []
        }

        let before = app.screenshot().pngRepresentation
        scrollDown(in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let after = app.screenshot().pngRepresentation
        let changedRatio = screenshotDifferenceRatio(before, after)

        if changedRatio < 0.01 {
            return ["Spec expects scrollable content, but screenshot changed by only \(String(format: "%.3f", changedRatio))."]
        }

        return []
    }

    private func scrollDown(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        start.press(forDuration: 0.02, thenDragTo: end)
    }

    private func analyzeScreenshot(_ pngData: Data, for screen: ScreenContract) -> VisualAnalysis {
        guard let image = UIImage(data: pngData),
              let cgImage = image.cgImage,
              let pixelBuffer = PixelBuffer(cgImage: cgImage) else {
            return VisualAnalysis(
                screenId: screen.id,
                width: 0,
                height: 0,
                maxBlankVerticalRatio: 1,
                distinctSampledColors: 0,
                contentCoverageRatio: 0,
                issues: ["Screenshot could not be decoded for visual analysis."]
            )
        }

        let width = pixelBuffer.width
        let height = pixelBuffer.height
        let yStart = Int(Double(height) * 0.14)
        let yEnd = Int(Double(height) * 0.88)
        let xStart = Int(Double(width) * 0.08)
        let xEnd = Int(Double(width) * 0.92)
        let rowStep = max(4, height / 180)
        let columnStep = max(4, width / 90)

        var allColors: [Int: Int] = [:]
        var distinctColors = Set<Int>()
        var sampledPixelCount = 0

        for y in stride(from: yStart, to: yEnd, by: rowStep) {
            for x in stride(from: xStart, to: xEnd, by: columnStep) {
                let color = pixelBuffer.quantizedColor(x: x, y: y)
                distinctColors.insert(color)
                allColors[color, default: 0] += 1
                sampledPixelCount += 1
            }
        }

        let dominantCount = allColors.values.max() ?? 0
        let contentCoverageRatio = sampledPixelCount == 0 ? 0 : 1.0 - Double(dominantCount) / Double(sampledPixelCount)

        var longestBlankRun = 0
        var currentBlankRun = 0
        var blankRunStart: Int?
        var bestBlankRunStart: Int?

        for y in stride(from: yStart, to: yEnd, by: rowStep) {
            var rowColors: [Int: Int] = [:]
            var rowSamples = 0

            for x in stride(from: xStart, to: xEnd, by: columnStep) {
                rowColors[pixelBuffer.quantizedColor(x: x, y: y), default: 0] += 1
                rowSamples += 1
            }

            let rowDominantCount = rowColors.values.max() ?? 0
            let dominantFraction = rowSamples == 0 ? 1 : Double(rowDominantCount) / Double(rowSamples)
            let isBlankLike = rowColors.count <= 3 && dominantFraction >= 0.78

            if isBlankLike {
                if currentBlankRun == 0 {
                    blankRunStart = y
                }
                currentBlankRun += rowStep
                if currentBlankRun > longestBlankRun {
                    longestBlankRun = currentBlankRun
                    bestBlankRunStart = blankRunStart
                }
            } else {
                currentBlankRun = 0
                blankRunStart = nil
            }
        }

        let contentHeight = max(1, yEnd - yStart)
        let maxBlankVerticalRatio = Double(longestBlankRun) / Double(contentHeight)
        let rules = screen.visualAnomalyBudget
        var issues: [String] = []

        if maxBlankVerticalRatio > rules.maxBlankVerticalRatio {
            issues.append("Spec expected meaningful content bands, product showed a blank-like vertical run of \(String(format: "%.2f", maxBlankVerticalRatio)) of the analyzed area; budget \(rules.maxBlankVerticalRatio).")
        }

        if distinctColors.count < rules.minDistinctSampledColors {
            issues.append("Spec expected a nonblank screen, product showed only \(distinctColors.count) sampled color groups; minimum \(rules.minDistinctSampledColors).")
        }

        if contentCoverageRatio < rules.minContentCoverageRatio {
            issues.append("Spec expected visible content beyond the dominant background, product content coverage was \(String(format: "%.2f", contentCoverageRatio)); minimum \(rules.minContentCoverageRatio).")
        }

        if screen.requiredIdentifiers.count > 1 &&
            distinctColors.count < rules.minDistinctSampledColors &&
            contentCoverageRatio < rules.minContentCoverageRatio {
            issues.append("Screen-shell-only render suspected: required contract has content regions but screenshot is visually low-content.")
        }

        return VisualAnalysis(
            screenId: screen.id,
            width: width,
            height: height,
            maxBlankVerticalRatio: maxBlankVerticalRatio,
            distinctSampledColors: distinctColors.count,
            contentCoverageRatio: contentCoverageRatio,
            longestBlankRunStartY: bestBlankRunStart,
            longestBlankRunEndY: bestBlankRunStart.map { $0 + longestBlankRun },
            issues: issues
        )
    }

    private func screenshotDifferenceRatio(_ leftPNG: Data, _ rightPNG: Data) -> Double {
        guard let leftImage = UIImage(data: leftPNG)?.cgImage,
              let rightImage = UIImage(data: rightPNG)?.cgImage,
              let left = PixelBuffer(cgImage: leftImage),
              let right = PixelBuffer(cgImage: rightImage),
              left.width == right.width,
              left.height == right.height else {
            return 0
        }

        let xStep = max(8, left.width / 80)
        let yStep = max(8, left.height / 120)
        var changed = 0
        var total = 0

        for y in stride(from: 0, to: left.height, by: yStep) {
            for x in stride(from: 0, to: left.width, by: xStep) {
                total += 1
                if left.colorDistance(to: right, x: x, y: y) > 18 {
                    changed += 1
                }
            }
        }

        return total == 0 ? 0 : Double(changed) / Double(total)
    }

    private func makeOutputDirectory() throws -> URL {
        let environmentPath = ProcessInfo.processInfo.environment["OSRS_SPEC_CONFORMANCE_OUTPUT_DIR"]
        let path = environmentPath ?? NSTemporaryDirectory().appending("osrswiki-ios-spec-conformance-\(UUID().uuidString)")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func resolveContractURL() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["OSRS_SCREEN_CONTRACT_PATH"] {
            return URL(fileURLWithPath: path)
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = directory.appendingPathComponent("docs/internal/ui-screen-contracts.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        throw XCTSkip("Could not locate docs/internal/ui-screen-contracts.json")
    }

    private func loadContract() throws -> UIScreenContracts {
        let data = try Data(contentsOf: contractURL)
        return try JSONDecoder().decode(UIScreenContracts.self, from: data)
    }

    private func writeReport() throws {
        try writeJSON(report, to: outputDirectory.appendingPathComponent("spec-conformance-report.json"))
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureScreenshot(for screen: ScreenContract, app: XCUIApplication) -> XCUIScreenshot {
        if screen.id == "SCREEN-APPEARANCE-001" {
            return XCUIScreen.main.screenshot()
        }

        return app.screenshot()
    }

    private func fileStem(for screen: ScreenContract) -> String {
        screen.id.lowercased().replacingOccurrences(of: "_", with: "-")
    }
}

private struct UIScreenContracts: Codable {
    let version: Int
    let sourceSpec: String
    let platform: String
    let screens: [ScreenContract]
}

private struct ScreenContract: Codable {
    let id: String
    let name: String
    let featureId: String
    let launchArguments: [String]
    let requiredIdentifiers: [String]
    let requiredLabels: [String]
    let contentRegions: [String]
    let optionalRegions: [String]
    let scrollExpectations: ScrollExpectations?
    let visualAnomalyBudget: VisualAnomalyBudget
}

private struct ScrollExpectations: Codable {
    let mustScroll: Bool
    let requiresMeaningfulContentBelow: String?
}

private struct VisualAnomalyBudget: Codable {
    let maxBlankVerticalRatio: Double
    let minDistinctSampledColors: Int
    let minContentCoverageRatio: Double
}

private struct ConformanceReport: Codable {
    let generatedAt: String
    var contractPath: String
    var screens: [ScreenResult]
}

private struct ScreenResult: Codable {
    let screenId: String
    let name: String
    let passed: Bool
    let elapsedSeconds: TimeInterval
    let screenshotPath: String?
    let accessibilityTreePath: String?
    let visualAnalysisPath: String?
    let missingIdentifiers: [String]
    let missingLabels: [String]
    let visualIssues: [String]
    let scrollIssues: [String]

    var failureSummary: String {
        var parts: [String] = ["\(screenId) \(name) failed spec conformance."]
        if !missingIdentifiers.isEmpty {
            parts.append("Missing identifiers: \(missingIdentifiers.joined(separator: ", ")).")
        }
        if !missingLabels.isEmpty {
            parts.append("Missing labels: \(missingLabels.joined(separator: ", ")).")
        }
        if !visualIssues.isEmpty {
            parts.append("Visual issues: \(visualIssues.joined(separator: " ")).")
        }
        if !scrollIssues.isEmpty {
            parts.append("Scroll issues: \(scrollIssues.joined(separator: " ")).")
        }
        return parts.joined(separator: " ")
    }
}

private struct VisualAnalysis: Codable {
    let screenId: String
    let width: Int
    let height: Int
    let maxBlankVerticalRatio: Double
    let distinctSampledColors: Int
    let contentCoverageRatio: Double
    var longestBlankRunStartY: Int?
    var longestBlankRunEndY: Int?
    let issues: [String]

    init(
        screenId: String,
        width: Int,
        height: Int,
        maxBlankVerticalRatio: Double,
        distinctSampledColors: Int,
        contentCoverageRatio: Double,
        longestBlankRunStartY: Int? = nil,
        longestBlankRunEndY: Int? = nil,
        issues: [String]
    ) {
        self.screenId = screenId
        self.width = width
        self.height = height
        self.maxBlankVerticalRatio = maxBlankVerticalRatio
        self.distinctSampledColors = distinctSampledColors
        self.contentCoverageRatio = contentCoverageRatio
        self.longestBlankRunStartY = longestBlankRunStartY
        self.longestBlankRunEndY = longestBlankRunEndY
        self.issues = issues
    }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    private static let bytesPerPixel = 4
    private let pixels: [UInt8]

    init?(cgImage: CGImage) {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        width = imageWidth
        height = imageHeight
        var buffer = [UInt8](repeating: 0, count: imageWidth * imageHeight * Self.bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = buffer.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(
                data: pointer.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageWidth * Self.bytesPerPixel,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }

        guard didDraw else {
            return nil
        }

        pixels = buffer
    }

    func quantizedColor(x: Int, y: Int) -> Int {
        let offset = ((y * width) + x) * Self.bytesPerPixel
        let red = Int(pixels[offset]) / 24
        let green = Int(pixels[offset + 1]) / 24
        let blue = Int(pixels[offset + 2]) / 24
        return (red << 16) | (green << 8) | blue
    }

    func colorDistance(to other: PixelBuffer, x: Int, y: Int) -> Int {
        let offset = ((y * width) + x) * Self.bytesPerPixel
        let red = Int(pixels[offset]) - Int(other.pixels[offset])
        let green = Int(pixels[offset + 1]) - Int(other.pixels[offset + 1])
        let blue = Int(pixels[offset + 2]) - Int(other.pixels[offset + 2])
        return abs(red) + abs(green) + abs(blue)
    }
}

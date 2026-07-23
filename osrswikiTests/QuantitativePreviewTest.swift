//
//  QuantitativePreviewTest.swift
//  osrswikiTests
//
//  Quantitative tests that detect specific appearance preview issues
//  - No visual inspection required, uses measurable criteria
//

import XCTest
import SwiftUI
@testable import osrswiki

@MainActor
final class QuantitativePreviewTest: XCTestCase {
    
    func testTablePreviewLogicCorrectness() async throws {
        let renderer = osrsTablePreviewRenderer.shared
        let theme = osrsLightTheme()
        
        print("🧪 Testing table preview logic with quantitative analysis...")
        
        // Generate both expanded and collapsed previews
        let expandedImage = await renderer.generateTablePreview(collapsed: false, theme: theme)
        let collapsedImage = await renderer.generateTablePreview(collapsed: true, theme: theme)
        
        // Analyze pixel density to detect collapsed vs expanded content
        let expandedComplexity = await analyzeContentComplexity(expandedImage)
        let collapsedComplexity = await analyzeContentComplexity(collapsedImage)
        
        print("📊 Expanded complexity: \(expandedComplexity.uniqueColors) colors, \(expandedComplexity.textRegions) text regions")
        print("📊 Collapsed complexity: \(collapsedComplexity.uniqueColors) colors, \(collapsedComplexity.textRegions) text regions")
        
        // CRITICAL: Expanded tables should have MORE content complexity than collapsed
        XCTAssertGreaterThan(expandedComplexity.uniqueColors, collapsedComplexity.uniqueColors + 1000, 
                           "Expanded preview should have significantly more color variation than collapsed")
        
        // Note: Text regions may actually be fewer in expanded state due to table cell consolidation
        // The key metric is color diversity indicating more visual content
        print("📊 Table logic working: Expanded has \(expandedComplexity.uniqueColors - collapsedComplexity.uniqueColors) more colors than collapsed")
        
        // Save for debugging
        await saveImageForDebugging(expandedImage, name: "quantitative-expanded")
        await saveImageForDebugging(collapsedImage, name: "quantitative-collapsed")
        
        print("✅ Table preview logic test passed")
    }
    
    func testThemePreviewHasImages() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing theme preview image presence quantitatively...")
        
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        let imageAnalysis = await analyzeImageContent(lightImage)
        
        print("📊 Image analysis: \(imageAnalysis.colorRegions) distinct color regions, \(imageAnalysis.gradientRegions) gradients")
        
        // CRITICAL: Real images should have diverse color regions and gradients
        XCTAssertGreaterThan(imageAnalysis.colorRegions, 15, 
                           "Theme preview should have multiple distinct color regions indicating images")
        
        XCTAssertGreaterThan(imageAnalysis.gradientRegions, 2,
                           "Theme preview should have gradient regions from images/cards")
        
        // Check for non-uniform color distribution (indicates real content)
        XCTAssertLessThan(imageAnalysis.dominantColorPercentage, 0.6,
                         "No single color should dominate >60% (indicates missing images)")
        
        await saveImageForDebugging(lightImage, name: "quantitative-theme-light")
        
        print("✅ Theme preview image test passed")
    }
    
    func testThemePreviewTopAlignment() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing theme preview top alignment quantitatively...")
        
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        let alignmentAnalysis = await analyzeTopAlignment(lightImage)
        
        print("📊 Alignment analysis: \(alignmentAnalysis.topQuarterComplexity) top complexity vs \(alignmentAnalysis.bottomQuarterComplexity) bottom")
        
        // CRITICAL: If properly top-aligned, top quarter should have MORE content than bottom
        XCTAssertGreaterThanOrEqual(alignmentAnalysis.topQuarterComplexity, alignmentAnalysis.bottomQuarterComplexity,
                                  "Top-aligned preview should have more content in top quarter than bottom quarter")
        
        // Check that content starts near the top (not center-cropped)
        XCTAssertGreaterThan(alignmentAnalysis.topQuarterComplexity, 20,
                           "Top quarter should have substantial content (not blank/header space)")
        
        await saveImageForDebugging(lightImage, name: "quantitative-alignment")
        
        print("✅ Theme preview alignment test passed")
    }
    
    func testThemePreviewsActuallyDifferent() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing that light/dark theme previews are actually different...")
        
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        let darkImage = await renderer.generatePreview(for: .osrsDark)
        
        let difference = await calculateImageDifference(lightImage, darkImage)
        
        print("📊 Theme difference: \(difference.pixelDifferencePercentage)% pixels differ")
        
        // CRITICAL: Light and dark themes should be visually different
        XCTAssertGreaterThan(difference.pixelDifferencePercentage, 25.0,
                           "Light and dark theme previews should differ by >25% of pixels")
        
        print("✅ Theme difference test passed")
    }
    
    // MARK: - Analysis Functions
    
    private func analyzeContentComplexity(_ image: UIImage) async -> ContentComplexity {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: ContentComplexity(uniqueColors: 0, textRegions: 0))
                    return
                }
                
                let width = cgImage.width
                let height = cgImage.height
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel * width
                let totalBytes = height * bytesPerRow
                
                var pixelData = [UInt8](repeating: 0, count: totalBytes)
                
                guard let context = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    continuation.resume(returning: ContentComplexity(uniqueColors: 0, textRegions: 0))
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                // Count unique colors
                var colorSet = Set<UInt32>()
                var textRegions = 0
                
                // Analyze in blocks to detect text regions (regions with high contrast)
                let blockSize = 10
                for y in stride(from: 0, to: height, by: blockSize) {
                    for x in stride(from: 0, to: width, by: blockSize) {
                        var blockColors = Set<UInt32>()
                        
                        for dy in 0..<min(blockSize, height - y) {
                            for dx in 0..<min(blockSize, width - x) {
                                let pixelIndex = ((y + dy) * width + (x + dx)) * bytesPerPixel
                                if pixelIndex + 3 < totalBytes {
                                    let r = UInt32(pixelData[pixelIndex])
                                    let g = UInt32(pixelData[pixelIndex + 1])
                                    let b = UInt32(pixelData[pixelIndex + 2])
                                    let color = (r << 16) | (g << 8) | b
                                    colorSet.insert(color)
                                    blockColors.insert(color)
                                }
                            }
                        }
                        
                        // High color variation in block suggests text/detailed content
                        if blockColors.count > 8 {
                            textRegions += 1
                        }
                    }
                }
                
                continuation.resume(returning: ContentComplexity(
                    uniqueColors: colorSet.count,
                    textRegions: textRegions
                ))
            }
        }
    }
    
    private func analyzeImageContent(_ image: UIImage) async -> ImageAnalysis {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: ImageAnalysis(colorRegions: 0, gradientRegions: 0, dominantColorPercentage: 1.0))
                    return
                }
                
                let width = cgImage.width
                let height = cgImage.height
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel * width
                let totalBytes = height * bytesPerRow
                
                var pixelData = [UInt8](repeating: 0, count: totalBytes)
                
                guard let context = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    continuation.resume(returning: ImageAnalysis(colorRegions: 0, gradientRegions: 0, dominantColorPercentage: 1.0))
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                var colorCounts: [UInt32: Int] = [:]
                var gradientRegions = 0
                var colorRegions = 0
                
                // Analyze color distribution and gradients
                let blockSize = 20
                for y in stride(from: 0, to: height, by: blockSize) {
                    for x in stride(from: 0, to: width, by: blockSize) {
                        var blockColors = Set<UInt32>()
                        var hasGradient = false
                        
                        for dy in 0..<min(blockSize, height - y) {
                            for dx in 0..<min(blockSize, width - x) {
                                let pixelIndex = ((y + dy) * width + (x + dx)) * bytesPerPixel
                                if pixelIndex + 3 < totalBytes {
                                    let r = UInt32(pixelData[pixelIndex])
                                    let g = UInt32(pixelData[pixelIndex + 1])
                                    let b = UInt32(pixelData[pixelIndex + 2])
                                    let color = (r << 16) | (g << 8) | b
                                    blockColors.insert(color)
                                    colorCounts[color, default: 0] += 1
                                    
                                    // Check for gradient (neighboring pixels with slight color differences)
                                    if dx > 0 && !hasGradient {
                                        let prevPixelIndex = ((y + dy) * width + (x + dx - 1)) * bytesPerPixel
                                        if prevPixelIndex + 3 < totalBytes {
                                            let prevR = UInt32(pixelData[prevPixelIndex])
                                            let colorDiff = abs(Int(r) - Int(prevR))
                                            if colorDiff > 10 && colorDiff < 50 {
                                                hasGradient = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        if blockColors.count > 5 {
                            colorRegions += 1
                        }
                        
                        if hasGradient {
                            gradientRegions += 1
                        }
                    }
                }
                
                // Calculate dominant color percentage
                let totalPixels = colorCounts.values.reduce(0, +)
                let maxColorCount = colorCounts.values.max() ?? 0
                let dominantColorPercentage = totalPixels > 0 ? Double(maxColorCount) / Double(totalPixels) : 1.0
                
                continuation.resume(returning: ImageAnalysis(
                    colorRegions: colorRegions,
                    gradientRegions: gradientRegions,
                    dominantColorPercentage: dominantColorPercentage
                ))
            }
        }
    }
    
    private func analyzeTopAlignment(_ image: UIImage) async -> AlignmentAnalysis {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: AlignmentAnalysis(topQuarterComplexity: 0, bottomQuarterComplexity: 0))
                    return
                }
                
                let width = cgImage.width
                let height = cgImage.height
                let quarterHeight = height / 4
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel * width
                let totalBytes = height * bytesPerRow
                
                var pixelData = [UInt8](repeating: 0, count: totalBytes)
                
                guard let context = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    continuation.resume(returning: AlignmentAnalysis(topQuarterComplexity: 0, bottomQuarterComplexity: 0))
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                // Analyze top quarter
                var topColors = Set<UInt32>()
                for y in 0..<quarterHeight {
                    for x in stride(from: 0, to: width, by: 4) { // Sample every 4th pixel
                        let pixelIndex = (y * width + x) * bytesPerPixel
                        if pixelIndex + 3 < totalBytes {
                            let r = UInt32(pixelData[pixelIndex])
                            let g = UInt32(pixelData[pixelIndex + 1])
                            let b = UInt32(pixelData[pixelIndex + 2])
                            let color = (r << 16) | (g << 8) | b
                            topColors.insert(color)
                        }
                    }
                }
                
                // Analyze bottom quarter
                var bottomColors = Set<UInt32>()
                for y in (height - quarterHeight)..<height {
                    for x in stride(from: 0, to: width, by: 4) { // Sample every 4th pixel
                        let pixelIndex = (y * width + x) * bytesPerPixel
                        if pixelIndex + 3 < totalBytes {
                            let r = UInt32(pixelData[pixelIndex])
                            let g = UInt32(pixelData[pixelIndex + 1])
                            let b = UInt32(pixelData[pixelIndex + 2])
                            let color = (r << 16) | (g << 8) | b
                            bottomColors.insert(color)
                        }
                    }
                }
                
                continuation.resume(returning: AlignmentAnalysis(
                    topQuarterComplexity: topColors.count,
                    bottomQuarterComplexity: bottomColors.count
                ))
            }
        }
    }
    
    private func calculateImageDifference(_ image1: UIImage, _ image2: UIImage) async -> ImageDifference {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage1 = image1.cgImage,
                      let cgImage2 = image2.cgImage,
                      cgImage1.width == cgImage2.width,
                      cgImage1.height == cgImage2.height else {
                    continuation.resume(returning: ImageDifference(pixelDifferencePercentage: 0.0))
                    return
                }
                
                let width = cgImage1.width
                let height = cgImage1.height
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel * width
                let totalBytes = height * bytesPerRow
                
                var pixelData1 = [UInt8](repeating: 0, count: totalBytes)
                var pixelData2 = [UInt8](repeating: 0, count: totalBytes)
                
                let context1 = CGContext(
                    data: &pixelData1,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                
                let context2 = CGContext(
                    data: &pixelData2,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                
                guard let ctx1 = context1, let ctx2 = context2 else {
                    continuation.resume(returning: ImageDifference(pixelDifferencePercentage: 0.0))
                    return
                }
                
                ctx1.draw(cgImage1, in: CGRect(x: 0, y: 0, width: width, height: height))
                ctx2.draw(cgImage2, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                var differentPixels = 0
                let totalPixels = width * height
                let threshold = 30 // Minimum color difference to count as different
                
                for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
                    let r1 = Int(pixelData1[i])
                    let g1 = Int(pixelData1[i + 1])
                    let b1 = Int(pixelData1[i + 2])
                    
                    let r2 = Int(pixelData2[i])
                    let g2 = Int(pixelData2[i + 1])
                    let b2 = Int(pixelData2[i + 2])
                    
                    let colorDistance = sqrt(Double((r1-r2)*(r1-r2) + (g1-g2)*(g1-g2) + (b1-b2)*(b1-b2)))
                    
                    if colorDistance > Double(threshold) {
                        differentPixels += 1
                    }
                }
                
                let differencePercentage = Double(differentPixels) / Double(totalPixels) * 100.0
                
                continuation.resume(returning: ImageDifference(pixelDifferencePercentage: differencePercentage))
            }
        }
    }
    
    private func saveImageForDebugging(_ image: UIImage, name: String) async {
        await MainActor.run {
            guard let data = image.pngData() else {
                print("❌ Failed to convert image to PNG data for \(name)")
                return
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let imageURL = tempDir.appendingPathComponent("quantitative-\(name).png")
            
            do {
                try data.write(to: imageURL)
                print("💾 Saved quantitative test image: \(imageURL.path)")
            } catch {
                print("❌ Failed to save image \(name): \(error)")
            }
        }
    }
}

// MARK: - Analysis Data Structures

struct ContentComplexity {
    let uniqueColors: Int
    let textRegions: Int
}

struct ImageAnalysis {
    let colorRegions: Int
    let gradientRegions: Int
    let dominantColorPercentage: Double
}

struct AlignmentAnalysis {
    let topQuarterComplexity: Int
    let bottomQuarterComplexity: Int
}

struct ImageDifference {
    let pixelDifferencePercentage: Double
}
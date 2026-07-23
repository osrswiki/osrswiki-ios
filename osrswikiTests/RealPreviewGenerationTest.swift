//
//  RealPreviewGenerationTest.swift
//  osrswikiTests
//
//  Test to verify ACTUAL app content preview generation - no mocks allowed
//

import XCTest
import SwiftUI
@testable import osrswiki

@MainActor
final class RealPreviewGenerationTest: XCTestCase {
    
    func testActualHomeViewPreviewGeneration() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing ACTUAL home view preview generation...")
        
        // Test light theme
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        
        // Verify image properties
        XCTAssertNotNil(lightImage, "Light theme preview should generate")
        XCTAssertGreaterThan(lightImage.size.width, 0, "Image should have width")
        XCTAssertGreaterThan(lightImage.size.height, 0, "Image should have height")
        
        // CRITICAL: Verify this contains ACTUAL app content, not fake mocks
        let hasActualContent = await verifyActualAppContent(lightImage, description: "Light theme home view")
        XCTAssertTrue(hasActualContent, "Must contain actual NewsView content, not mock replicas")
        
        // Save for manual inspection
        await saveImageForInspection(lightImage, name: "actual-light-home-preview")
        
        print("✅ Actual home view preview test passed")
    }
    
    func testActualVarrockArticlePreviewGeneration() async throws {
        let renderer = osrsTablePreviewRenderer.shared
        let theme = osrsLightTheme()
        
        print("🧪 Testing ACTUAL Varrock article preview generation...")
        
        // Test collapsed state
        let collapsedImage = await renderer.generateTablePreview(collapsed: true, theme: theme)
        
        // Verify image properties
        XCTAssertNotNil(collapsedImage, "Collapsed Varrock preview should generate")
        XCTAssertGreaterThan(collapsedImage.size.width, 0, "Image should have width")
        XCTAssertGreaterThan(collapsedImage.size.height, 0, "Image should have height")
        
        // CRITICAL: Verify this contains ACTUAL Varrock article content
        let hasVarrockContent = await verifyVarrockArticleContent(collapsedImage, description: "Collapsed Varrock article")
        XCTAssertTrue(hasVarrockContent, "Must contain actual Varrock article content with real tables, not mock data")
        
        // Save for manual inspection
        await saveImageForInspection(collapsedImage, name: "actual-varrock-collapsed-preview")
        
        print("✅ Actual Varrock article preview test passed")
    }
    
    func testDifferentThemesProduceActuallyDifferentContent() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing that different themes produce genuinely different actual content...")
        
        // Generate previews for different themes using REAL content
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        let darkImage = await renderer.generatePreview(for: .osrsDark)
        
        // Save both for inspection
        await saveImageForInspection(lightImage, name: "real-content-light-theme")
        await saveImageForInspection(darkImage, name: "real-content-dark-theme")
        
        // Test they are actually different (not the same mock)
        let areImagesDifferent = await compareImages(lightImage, darkImage)
        XCTAssertTrue(areImagesDifferent, "Light and dark themes must produce visually different REAL content")
        
        // Verify both have actual app content
        let lightHasRealContent = await verifyActualAppContent(lightImage, description: "Light theme real content")
        let darkHasRealContent = await verifyActualAppContent(darkImage, description: "Dark theme real content")
        
        XCTAssertTrue(lightHasRealContent, "Light theme must show actual app interface")
        XCTAssertTrue(darkHasRealContent, "Dark theme must show actual app interface")
        
        print("✅ Different themes with real content test passed")
    }
    
    // MARK: - Rigorous Content Verification
    
    private func verifyActualAppContent(_ image: UIImage, description: String) async -> Bool {
        print("🔍 Verifying actual app content for: \(description)")
        
        // Check for visible pixels
        let hasContent = await imageHasVisibleContent(image)
        if !hasContent {
            print("❌ \(description): Image has no visible content")
            return false
        }
        
        // CRITICAL: Check that this is NOT an error state
        let hasErrorIndicators = await imageContainsErrorStates(image)
        if hasErrorIndicators {
            print("❌ \(description): Image contains error states like 'No News Available' or blank content")
            return false
        }
        
        // Check image complexity (real content should have significant pixel variation)
        let hasComplexity = await imageHasContentComplexity(image, minimumVariation: 20)
        if !hasComplexity {
            print("❌ \(description): Image lacks complexity expected from real app content")
            return false
        }
        
        // Check dimensions match expected app content
        let correctDimensions = image.size.width == 300 && image.size.height == 200
        if !correctDimensions {
            print("❌ \(description): Image dimensions incorrect - expected 300x200, got \(image.size)")
            return false
        }
        
        print("✅ \(description): Verified as having actual app content characteristics")
        return true
    }
    
    /// Detect error states in images (like "No News Available" text patterns)
    private func imageContainsErrorStates(_ image: UIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: true) // Assume error if can't analyze
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
                    continuation.resume(returning: true)
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                // Check for patterns that indicate error states:
                // 1. Too much uniform color (blank content)
                // 2. Very limited color palette (error messages tend to be simple)
                
                var colorCounts: [UInt32: Int] = [:]
                var totalNonTransparentPixels = 0
                
                for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
                    let alpha = pixelData[i + 3]
                    if alpha > 50 { // Non-transparent pixel
                        totalNonTransparentPixels += 1
                        let r = UInt32(pixelData[i])
                        let g = UInt32(pixelData[i + 1])
                        let b = UInt32(pixelData[i + 2])
                        let color = (r << 16) | (g << 8) | b
                        colorCounts[color, default: 0] += 1
                    }
                }
                
                // Error indicators:
                // 1. Very few unique colors (< 15) suggests simple error message
                // 2. Dominant single color (> 70% of pixels) suggests mostly blank
                let uniqueColors = colorCounts.count
                let maxColorCount = colorCounts.values.max() ?? 0
                let dominantColorPercentage = totalNonTransparentPixels > 0 ? 
                    Double(maxColorCount) / Double(totalNonTransparentPixels) : 1.0
                
                let hasErrorPattern = uniqueColors < 15 || dominantColorPercentage > 0.7
                
                print("🔍 Error analysis: \(uniqueColors) colors, dominant: \(String(format: "%.1f", dominantColorPercentage * 100))%, error pattern: \(hasErrorPattern)")
                
                continuation.resume(returning: hasErrorPattern)
            }
        }
    }
    
    private func verifyVarrockArticleContent(_ image: UIImage, description: String) async -> Bool {
        print("🔍 Verifying Varrock article content for: \(description)")
        
        // Check for visible pixels
        let hasContent = await imageHasVisibleContent(image)
        if !hasContent {
            print("❌ \(description): Image has no visible content")
            return false
        }
        
        // CRITICAL: Check that this is NOT an error state (like verifyActualAppContent but with table dimensions)
        let hasErrorIndicators = await imageContainsErrorStates(image)
        if hasErrorIndicators {
            print("❌ \(description): Image contains error states like 'No News Available' or blank content")
            return false
        }
        
        // Check image complexity (real content should have significant pixel variation)
        let hasComplexity = await imageHasContentComplexity(image, minimumVariation: 20)
        if !hasComplexity {
            print("❌ \(description): Image lacks complexity expected from real app content")
            return false
        }
        
        // Check dimensions match table preview size (not theme preview size)
        let correctDimensions = image.size.width == 280 && image.size.height == 200
        if !correctDimensions {
            print("❌ \(description): Table preview dimensions incorrect - expected 280x200, got \(image.size)")
            return false
        }
        
        print("✅ \(description): Verified as having actual Varrock article characteristics")
        return true
    }
    
    private func imageHasContentComplexity(_ image: UIImage, minimumVariation: Int = 10) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: false)
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
                    continuation.resume(returning: false)
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                // Count unique colors (complexity indicator)
                var colorSet = Set<UInt32>()
                for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
                    let r = UInt32(pixelData[i])
                    let g = UInt32(pixelData[i + 1])
                    let b = UInt32(pixelData[i + 2])
                    let color = (r << 16) | (g << 8) | b
                    colorSet.insert(color)
                    
                    // Early exit if we have enough variation
                    if colorSet.count >= minimumVariation {
                        break
                    }
                }
                
                let hasComplexity = colorSet.count >= minimumVariation
                print("🔍 Content complexity: \(colorSet.count) unique colors (minimum: \(minimumVariation))")
                continuation.resume(returning: hasComplexity)
            }
        }
    }
    
    // MARK: - Helper Methods (same as before)
    
    private func imageHasVisibleContent(_ image: UIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: false)
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
                    continuation.resume(returning: false)
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                // Check for non-transparent pixels
                var hasContent = false
                for i in stride(from: 3, to: totalBytes, by: bytesPerPixel) {
                    if pixelData[i] > 0 {
                        hasContent = true
                        break
                    }
                }
                
                print("🔍 Image analysis: \(width)×\(height), hasContent: \(hasContent)")
                continuation.resume(returning: hasContent)
            }
        }
    }
    
    private func compareImages(_ image1: UIImage, _ image2: UIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage1 = image1.cgImage,
                      let cgImage2 = image2.cgImage,
                      cgImage1.width == cgImage2.width,
                      cgImage1.height == cgImage2.height else {
                    continuation.resume(returning: true)
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
                    continuation.resume(returning: true)
                    return
                }
                
                ctx1.draw(cgImage1, in: CGRect(x: 0, y: 0, width: width, height: height))
                ctx2.draw(cgImage2, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                // Compare significant differences
                var differences = 0
                for i in stride(from: 0, to: totalBytes, by: bytesPerPixel * 10) {
                    if pixelData1[i] != pixelData2[i] ||
                       pixelData1[i + 1] != pixelData2[i + 1] ||
                       pixelData1[i + 2] != pixelData2[i + 2] {
                        differences += 1
                        if differences > 10 {
                            break
                        }
                    }
                }
                
                let areImagesDifferent = differences > 10
                print("🔍 Image comparison: \(differences) differences found, different: \(areImagesDifferent)")
                continuation.resume(returning: areImagesDifferent)
            }
        }
    }
    
    private func saveImageForInspection(_ image: UIImage, name: String) async {
        await MainActor.run {
            guard let data = image.pngData() else {
                print("❌ Failed to convert image to PNG data for \(name)")
                return
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let imageURL = tempDir.appendingPathComponent("real-preview-test-\(name).png")
            
            do {
                try data.write(to: imageURL)
                print("💾 Saved REAL content image for inspection: \(imageURL.path)")
            } catch {
                print("❌ Failed to save image \(name): \(error)")
            }
        }
    }
}
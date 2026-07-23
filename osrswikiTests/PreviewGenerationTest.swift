//
//  PreviewGenerationTest.swift
//  osrswikiTests
//
//  Test to objectively verify theme and table preview generation and content
//

import XCTest
import SwiftUI
@testable import osrswiki

@MainActor
final class PreviewGenerationTest: XCTestCase {
    
    func testThemePreviewGeneration() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing theme preview generation...")
        
        // Test light theme specifically first
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        print("🖼️ Light theme image: \(lightImage)")
        print("🖼️ Light theme size: \(lightImage.size)")
        
        // Basic verification
        XCTAssertNotNil(lightImage, "Light theme preview should generate")
        XCTAssertGreaterThan(lightImage.size.width, 0, "Image should have width")
        XCTAssertGreaterThan(lightImage.size.height, 0, "Image should have height")
        
        // Test that image is not completely transparent
        let hasVisibleContent = await imageHasVisibleContent(lightImage)
        XCTAssertTrue(hasVisibleContent, "Light theme preview should have visible content")
        
        // Save image for manual inspection
        await saveImageForInspection(lightImage, name: "light-theme-preview")
        
        print("✅ Theme preview generation test passed")
    }
    
    func testTablePreviewGeneration() async throws {
        let renderer = osrsTablePreviewRenderer.shared
        let theme = osrsLightTheme()
        
        print("🧪 Testing table preview generation...")
        
        // Test collapsed state
        let collapsedImage = await renderer.generateTablePreview(collapsed: true, theme: theme)
        print("📊 Collapsed table image: \(collapsedImage)")
        print("📊 Collapsed table size: \(collapsedImage.size)")
        
        // Basic verification
        XCTAssertNotNil(collapsedImage, "Collapsed table preview should generate")
        XCTAssertGreaterThan(collapsedImage.size.width, 0, "Image should have width")
        XCTAssertGreaterThan(collapsedImage.size.height, 0, "Image should have height")
        
        // Test that image is not completely transparent
        let hasVisibleContent = await imageHasVisibleContent(collapsedImage)
        XCTAssertTrue(hasVisibleContent, "Collapsed table preview should have visible content")
        
        // Save image for manual inspection
        await saveImageForInspection(collapsedImage, name: "collapsed-table-preview")
        
        print("✅ Table preview generation test passed")
    }
    
    func testDifferentThemesProduceDifferentImages() async throws {
        let renderer = osrsThemePreviewRenderer.shared
        
        print("🧪 Testing that different themes produce different images...")
        
        // Generate previews for different themes
        let lightImage = await renderer.generatePreview(for: .osrsLight)
        let darkImage = await renderer.generatePreview(for: .osrsDark)
        
        // Save both for inspection
        await saveImageForInspection(lightImage, name: "light-vs-dark-light")
        await saveImageForInspection(darkImage, name: "light-vs-dark-dark")
        
        // Test they are different
        let areImagesDifferent = await compareImages(lightImage, darkImage)
        XCTAssertTrue(areImagesDifferent, "Light and dark theme previews should be visually different")
        
        print("✅ Different themes produce different images test passed")
    }
    
    // MARK: - Helper Methods
    
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
                
                // Check for non-transparent pixels (any alpha > 0)
                var hasContent = false
                for i in stride(from: 3, to: totalBytes, by: bytesPerPixel) { // Alpha channel
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
                    continuation.resume(returning: true) // Different if can't compare
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
                
                // Compare pixel data (sample every 10th pixel for performance)
                var differences = 0
                for i in stride(from: 0, to: totalBytes, by: bytesPerPixel * 10) {
                    if pixelData1[i] != pixelData2[i] ||
                       pixelData1[i + 1] != pixelData2[i + 1] ||
                       pixelData1[i + 2] != pixelData2[i + 2] ||
                       pixelData1[i + 3] != pixelData2[i + 3] {
                        differences += 1
                        if differences > 5 { // Early exit if clearly different
                            break
                        }
                    }
                }
                
                let areImagesDifferent = differences > 5
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
            
            // Save to temporary directory for inspection
            let tempDir = FileManager.default.temporaryDirectory
            let imageURL = tempDir.appendingPathComponent("preview-test-\(name).png")
            
            do {
                try data.write(to: imageURL)
                print("💾 Saved image for inspection: \(imageURL.path)")
            } catch {
                print("❌ Failed to save image \(name): \(error)")
            }
        }
    }
}
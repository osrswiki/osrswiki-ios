import CoreImage
import UIKit
import XCTest
@testable import osrswiki

final class osrsWebViewThemePaintLuminanceTests: XCTestCase {
    func testNilAndEmptyImagesAreUniformWithoutCrashing() {
        XCTAssertNil(osrsWebViewThemePaint.luminanceStats(nil))
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(nil))
        XCTAssertTrue(osrsWebViewThemePaint.isUnpaintedSystemFill(nil))
        XCTAssertEqual(osrsWebViewThemePaint.luminanceRange(nil), 0)

        let empty = UIImage()
        XCTAssertNil(osrsWebViewThemePaint.luminanceStats(empty))
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(empty))
    }

    func testSolidAndContrastingEightBitImagesStillClassify() {
        XCTAssertTrue(
            osrsWebViewThemePaint.isUniformFill(
                solidImage(color: UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1))
            )
        )
        XCTAssertFalse(osrsWebViewThemePaint.isUniformFill(contrastingImage()))
        XCTAssertTrue(osrsWebViewThemePaint.isUnpaintedSystemFill(solidImage(color: .white)))
        XCTAssertGreaterThan(osrsWebViewThemePaint.luminanceRange(contrastingImage()), 16)
    }

    func testSixteenBitAndGrayscaleSourcesDoNotRedrawOrCrash() throws {
        let gray = try XCTUnwrap(grayImage(value: 128, width: 32, height: 18))
        XCTAssertNotNil(osrsWebViewThemePaint.luminanceStats(gray))
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(gray))

        guard let hdr = sixteenBitImage(width: 8, height: 8) else {
            throw XCTSkip("16-bit CGImage unavailable on this OS")
        }
        XCTAssertNil(
            osrsWebViewThemePaint.luminanceStats(hdr),
            "Non-8-bit snapshots must be skipped instead of UIImage.draw → vImage permute"
        )
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(hdr))
    }

    func testCIImageBackedSnapshotDoesNotForceADraw() {
        let ciImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = UIImage(ciImage: ciImage)
        if image.cgImage == nil {
            XCTAssertNil(osrsWebViewThemePaint.luminanceStats(image))
            XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(image))
        } else if let stats = osrsWebViewThemePaint.luminanceStats(image) {
            XCTAssertGreaterThanOrEqual(stats.mean, 220)
        }
    }

    func testDirectPixelSamplingHonorsBytesPerRowPadding() throws {
        let padded = try XCTUnwrap(paddedRowImage(width: 3, height: 3, fill: 40, contrastAt: (1, 1), contrast: 200))
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(padded),
            "Sampling must use bytesPerRow so padded rows still see contrast"
        )
        XCTAssertGreaterThan(osrsWebViewThemePaint.luminanceRange(padded), 16)
    }

    private func contrastingImage() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
    }

    private func solidImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func grayImage(value: UInt8, width: Int, height: Int) -> UIImage? {
        var pixels = [UInt8](repeating: value, count: width * height)
        let data = Data(bytes: &pixels, count: pixels.count)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func sixteenBitImage(width: Int, height: Int) -> UIImage? {
        var pixels = [UInt16](repeating: 0xFFFF, count: width * height * 4)
        let data = Data(bytes: &pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 64,
                bytesPerRow: width * 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func paddedRowImage(
        width: Int,
        height: Int,
        fill: UInt8,
        contrastAt: (Int, Int),
        contrast: UInt8
    ) -> UIImage? {
        let bytesPerPixel = 4
        let bytesPerRow = ((width * bytesPerPixel) + 15) & ~15
        var pixels = [UInt8](repeating: fill, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = fill
                pixels[offset + 1] = fill
                pixels[offset + 2] = fill
                pixels[offset + 3] = 255
            }
        }
        let contrastOffset = contrastAt.1 * bytesPerRow + contrastAt.0 * bytesPerPixel
        pixels[contrastOffset] = contrast
        pixels[contrastOffset + 1] = contrast
        pixels[contrastOffset + 2] = contrast
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

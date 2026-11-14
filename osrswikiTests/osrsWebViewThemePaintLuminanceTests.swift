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
        let stats = try XCTUnwrap(
            osrsWebViewThemePaint.luminanceStats(hdr),
            "16-bit integer snapshots must be measured from dataProvider.data, not skipped or redrawn"
        )
        XCTAssertEqual(stats.min, stats.max)
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

    func testEightBitImageStillClassifies() throws {
        let gray = try XCTUnwrap(grayImage(value: 180, width: 24, height: 24))
        let grayCG = try XCTUnwrap(gray.cgImage)
        XCTAssertEqual(grayCG.bitsPerComponent, 8)
        let grayStats = try XCTUnwrap(osrsWebViewThemePaint.luminanceStats(grayCG))
        XCTAssertEqual(grayStats.min, grayStats.max)
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(gray))

        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = 1
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let solid = renderer.image { context in
            osrsParchmentColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let cgImage = try XCTUnwrap(solid.cgImage)
        XCTAssertNotNil(osrsWebViewThemePaint.luminanceStats(cgImage))
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(solid))
        XCTAssertFalse(osrsWebViewThemePaint.isUniformFill(contrastingEightBitImage()))
    }

    func testDefaultRendererHalfFloatImageIsMeasured() throws {
        let size = CGSize(width: 48, height: 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            osrsParchmentColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            osrsDarkInkColor.setFill()
            context.fill(CGRect(x: 4, y: 22, width: 40, height: 2))
        }
        let rendered = try XCTUnwrap(image.cgImage)
        XCTAssertNotNil(
            osrsWebViewThemePaint.luminanceStats(rendered),
            "Default UIGraphicsImageRenderer output must be measured even when it is 16-bit half-float"
        )
        XCTAssertFalse(osrsWebViewThemePaint.isUniformFill(image))

        let synthetic = try XCTUnwrap(
            halfFloatImage(
                width: 32,
                height: 32,
                fill: (226 / 255, 219 / 255, 200 / 255),
                darkLineY: 16
            )
        )
        XCTAssertEqual(synthetic.bitsPerComponent, 16)
        XCTAssertTrue(synthetic.bitmapInfo.contains(.floatComponents))
        let syntheticStats = try XCTUnwrap(osrsWebViewThemePaint.luminanceStats(synthetic))
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(
                minLuminance: syntheticStats.min,
                maxLuminance: syntheticStats.max
            )
        )
    }

    func testUniformFillStaysUniformAcrossBitDepths() throws {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let fill = renderer.image { context in
            osrsParchmentColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(fill))

        let halfFloat = try XCTUnwrap(
            halfFloatImage(width: 24, height: 24, fill: (226 / 255, 219 / 255, 200 / 255), darkLineY: nil)
        )
        let stats = try XCTUnwrap(osrsWebViewThemePaint.luminanceStats(halfFloat))
        XCTAssertEqual(stats.min, stats.max)
        XCTAssertTrue(osrsWebViewThemePaint.isUniformFill(minLuminance: stats.min, maxLuminance: stats.max))
    }

    func testThinDarkTextOnParchmentIsNotUniformFill() throws {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        let textLine = renderer.image { context in
            osrsParchmentColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            osrsDarkInkColor.setFill()
            context.fill(CGRect(x: 6, y: 30, width: 52, height: 2))
        }
        XCTAssertFalse(
            osrsWebViewThemePaint.isUniformFill(textLine),
            "A thin dark text line on parchment must not classify as a uniform compositor fill"
        )
        XCTAssertGreaterThan(osrsWebViewThemePaint.luminanceRange(textLine), 16)
    }

    private var osrsParchmentColor: UIColor {
        UIColor(red: 226 / 255, green: 219 / 255, blue: 200 / 255, alpha: 1)
    }

    private var osrsDarkInkColor: UIColor {
        UIColor(red: 40 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
    }

    private func contrastingEightBitImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = 1
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            osrsDarkInkColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
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

    private func halfFloatImage(
        width: Int,
        height: Int,
        fill: (Float, Float, Float),
        darkLineY: Int?
    ) -> CGImage? {
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        func halfBits(_ value: Float) -> UInt16 {
            Float16(min(max(value, 0), 1)).bitPattern
        }
        for y in 0..<height {
            for x in 0..<width {
                let dark = darkLineY == y
                let index = (y * width + x) * 4
                pixels[index] = halfBits(dark ? 0 : fill.0)
                pixels[index + 1] = halfBits(dark ? 0 : fill.1)
                pixels[index + 2] = halfBits(dark ? 0 : fill.2)
                pixels[index + 3] = halfBits(1)
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue
                | CGBitmapInfo.floatComponents.rawValue
        )
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: width * 8,
            space: space,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
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

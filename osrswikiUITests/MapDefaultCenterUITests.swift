import XCTest
import UIKit

final class MapDefaultCenterUITests: XCTestCase {
    func testMapLaunchExposesLumbridgeDefaultCamera() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["map_screen"].waitForExistence(timeout: 10), "Map screen should open directly")

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10), "Native map view should be visible")

        let cameraText = waitForCameraSnapshot(on: mapView)
        XCTAssertTrue(cameraText.contains("ready=true"), "Map camera snapshot should report ready=true: \(cameraText)")

        let centerLat = try XCTUnwrap(cameraValue("centerLat", in: cameraText))
        let centerLon = try XCTUnwrap(cameraValue("centerLon", in: cameraText))
        let zoom = try XCTUnwrap(cameraValue("zoom", in: cameraText))

        XCTAssertEqual(centerLat, -25.44327461230575, accuracy: 0.00000001)
        XCTAssertEqual(centerLon, -130.2978515625, accuracy: 0.00000001)
        XCTAssertEqual(zoom, 7.3414426741929, accuracy: 0.0000001)
    }

    func testFloorSelectionChangesRenderedMapPixels() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-startTab",
            "map",
            "-exposeMapCameraForUITests",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["map_screen"].waitForExistence(timeout: 10), "Map screen should open directly")

        let mapView = app.otherElements["map_view"].firstMatch
        XCTAssertTrue(mapView.waitForExistence(timeout: 10), "Native map view should be visible")
        XCTAssertTrue(waitForCameraSnapshot(on: mapView).contains("ready=true"), "Map should finish rendering before floor comparison")

        let beforeScreenshot = XCUIScreen.main.screenshot()
        let beforePixels = try mapComparisonPixels(from: beforeScreenshot)

        let floorUp = app.buttons["Increase map floor"]
        XCTAssertTrue(floorUp.waitForExistence(timeout: 5), "Floor up control should exist")
        XCTAssertTrue(floorUp.isHittable, "Floor up control should be hittable")
        floorUp.tap()

        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 2), "Floor label should update to 1")
        XCTAssertTrue(
            waitForCameraSnapshot(on: mapView, containing: "floor=1").contains("floor=1"),
            "Native map should receive selected floor 1 before rendering comparison"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let afterScreenshot = XCUIScreen.main.screenshot()
        let afterPixels = try mapComparisonPixels(from: afterScreenshot)
        let changedRatio = changedPixelRatio(beforePixels, afterPixels, tolerance: 2)

        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "floor-0-before"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
        afterAttachment.name = "floor-1-after"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)

        XCTAssertGreaterThan(
            changedRatio,
            0.005,
            "Selecting floor 1 should change visible map pixels, not only the floor label. Changed ratio: \(changedRatio)"
        )
    }

    private func waitForCameraSnapshot(on element: XCUIElement) -> String {
        waitForCameraSnapshot(on: element, containing: "ready=true")
    }

    private func waitForCameraSnapshot(on element: XCUIElement, containing requiredText: String) -> String {
        let deadline = Date().addingTimeInterval(10)
        var latest = cameraSnapshotText(from: element)

        while Date() < deadline {
            latest = cameraSnapshotText(from: element)
            if latest.contains("ready=true") && latest.contains(requiredText) {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return latest
    }

    private func cameraSnapshotText(from element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return [element.label, value].filter { !$0.isEmpty }.joined(separator: ";")
    }

    private func cameraValue(_ key: String, in snapshot: String) -> Double? {
        snapshot
            .split(separator: ";")
            .compactMap { component -> Double? in
                let pieces = component.split(separator: "=", maxSplits: 1)
                guard pieces.count == 2, pieces[0] == key else { return nil }
                return Double(pieces[1])
            }
            .first
    }

    private func mapComparisonPixels(from screenshot: XCUIScreenshot) throws -> PixelBuffer {
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation)?.cgImage)
        let width = image.width
        let height = image.height

        let cropRect = CGRect(
            x: Double(width) * 0.22,
            y: Double(height) * 0.13,
            width: Double(width) * 0.73,
            height: Double(height) * 0.69
        ).integral

        let cropped = try XCTUnwrap(image.cropping(to: cropRect))
        let cropWidth = cropped.width
        let cropHeight = cropped.height
        var pixels = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: cropWidth,
            height: cropHeight,
            bitsPerComponent: 8,
            bytesPerRow: cropWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))

        return PixelBuffer(width: cropWidth, height: cropHeight, rgba: pixels)
    }

    private func changedPixelRatio(_ before: PixelBuffer, _ after: PixelBuffer, tolerance: UInt8) -> Double {
        XCTAssertEqual(before.width, after.width)
        XCTAssertEqual(before.height, after.height)
        XCTAssertEqual(before.rgba.count, after.rgba.count)

        var changedPixels = 0
        let pixelCount = before.width * before.height

        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * 4
            let redChanged = abs(Int(before.rgba[offset]) - Int(after.rgba[offset])) > Int(tolerance)
            let greenChanged = abs(Int(before.rgba[offset + 1]) - Int(after.rgba[offset + 1])) > Int(tolerance)
            let blueChanged = abs(Int(before.rgba[offset + 2]) - Int(after.rgba[offset + 2])) > Int(tolerance)
            if redChanged || greenChanged || blueChanged {
                changedPixels += 1
            }
        }

        return Double(changedPixels) / Double(pixelCount)
    }

    private struct PixelBuffer {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }
}

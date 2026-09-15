import XCTest
import UIKit
@testable import osrswiki

final class osrsListThumbnailScaleTests: XCTestCase {
    func testSearchHistoryAndSavedThumbsUseAspectFitToMatchAndroidFitCenter() {
        XCTAssertEqual(
            osrsAnimatedThumbnailView.osrsListContentMode,
            .scaleAspectFit,
            "makeUIView and updateUIView both write this constant; crop would hide mixed Wiki sprites."
        )

        let imageView = osrsAnimatedThumbnailView.makeConfiguredImageView()

        XCTAssertEqual(
            imageView.contentMode,
            osrsAnimatedThumbnailView.osrsListContentMode,
            "List thumbnails must aspect-fit (Android ImageView.ScaleType.FIT_CENTER) so mixed Wiki sprites, maps, and portraits stay recognizable instead of center-cropping."
        )
        XCTAssertTrue(
            imageView.clipsToBounds,
            "The 60pt list cell still clips to its frame when the bitmap is letterboxed."
        )
        XCTAssertEqual(
            imageView.intrinsicContentSize,
            .zero,
            "Wiki bitmaps must not advertise pixel size as intrinsic size or they expand the 60pt SwiftUI cell."
        )
    }

    func testConfiguredListThumbCanvasIsClearAndUnrounded() {
        let imageView = osrsAnimatedThumbnailView.makeConfiguredImageView()

        XCTAssertEqual(
            imageView.backgroundColor,
            UIColor.clear,
            "Letterboxing must show the search-row surface, not a UIImageView fill."
        )
        XCTAssertFalse(
            imageView.isOpaque,
            "An opaque image view can paint a solid canvas behind aspect-fit sprites."
        )
        XCTAssertEqual(
            imageView.layer.cornerRadius,
            0,
            "Android item_search_result ImageViews do not round-clip; iOS must not invent a plate."
        )
        XCTAssertEqual(
            osrsAnimatedThumbnailView.osrsListThumbCornerRadius,
            0
        )
        XCTAssertEqual(
            osrsAnimatedThumbnailView.osrsListThumbSize,
            60
        )
    }

    func testListThumbClearsGenericHostingSuperviewButNotTableCells() {
        let imageView = osrsAnimatedThumbnailView.makeConfiguredImageView()
        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        wrapper.backgroundColor = .red
        wrapper.isOpaque = true
        wrapper.addSubview(imageView)

        XCTAssertEqual(
            wrapper.backgroundColor,
            UIColor.clear,
            "SwiftUI UIViewRepresentable wrappers can stay opaque; letterboxing must punch through to the row surface."
        )
        XCTAssertFalse(wrapper.isOpaque)

        let cell = UITableViewCell(style: .default, reuseIdentifier: "list-thumb")
        cell.backgroundColor = .blue
        let thumbInCell = osrsAnimatedThumbnailView.makeConfiguredImageView()
        cell.addSubview(thumbInCell)

        XCTAssertEqual(
            cell.backgroundColor,
            UIColor.blue,
            "Clearing hosting wrappers must not wipe UITableViewCell / list-row surface color."
        )
    }

    func testListThumbCallSitesSharePlateFreeChrome() throws {
        let root = try repositoryRoot()
        let files = [
            "platforms/ios/osrswiki/Views/Components/SearchResultRowView.swift",
            "platforms/ios/osrswiki/Views/HistoryView.swift",
            "platforms/ios/osrswiki/Views/SavedPagesView.swift",
            "platforms/ios/osrswiki/Views/Components/HistoryRowView.swift",
        ]

        for path in files {
            let src = try source(root, path)
            XCTAssertTrue(
                src.contains(".osrsListThumbnailChrome()"),
                "\(path) must share transparent 60pt list-thumb chrome so search/history/saved match Android (no plate)."
            )
            XCTAssertFalse(
                src.contains(".osrsSearchBoxBackgroundColor"),
                "\(path) must not paint search-box fill behind thumbs; that overlay is a contrasting rounded canvas on parchment."
            )
            XCTAssertFalse(
                src.contains(".cornerRadius(8)"),
                "\(path) must not round-clip list thumbs; Android ImageViews have no corner radius."
            )
        }
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

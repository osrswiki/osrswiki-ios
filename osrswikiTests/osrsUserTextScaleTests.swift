import XCTest
@testable import osrswiki
import SwiftUI

final class osrsUserTextScaleTests: XCTestCase {
    func testDefaultScaleKeepsSystemDynamicTypeIncludingAccessibility() {
        XCTAssertEqual(DynamicTypeSize.large.osrsApplyingUserScale(1.0), .large)
        XCTAssertEqual(DynamicTypeSize.accessibility3.osrsApplyingUserScale(1.0), .accessibility3)
        XCTAssertEqual(DynamicTypeSize.small.osrsApplyingUserScale(1.00), .small)
    }

    func testSliderGrowsAndShrinksFromTheSystemSize() {
        XCTAssertEqual(DynamicTypeSize.large.osrsApplyingUserScale(0.85), .medium)
        XCTAssertEqual(DynamicTypeSize.large.osrsApplyingUserScale(1.15), .xLarge)
        XCTAssertEqual(DynamicTypeSize.large.osrsApplyingUserScale(1.25), .xxLarge)
        XCTAssertEqual(DynamicTypeSize.large.osrsApplyingUserScale(1.40), .xxxLarge)
        XCTAssertEqual(DynamicTypeSize.xSmall.osrsApplyingUserScale(0.85), .xSmall)
        XCTAssertEqual(DynamicTypeSize.accessibility5.osrsApplyingUserScale(1.40), .accessibility5)
    }

    func testMappedUIKitCategoryFollowsDynamicTypeIncludingSliderSteps() {
        XCTAssertEqual(DynamicTypeSize.large.osrsUIContentSizeCategory, .large)
        XCTAssertEqual(DynamicTypeSize.xxxLarge.osrsUIContentSizeCategory, .extraExtraExtraLarge)
        XCTAssertEqual(DynamicTypeSize.accessibility1.osrsUIContentSizeCategory, .accessibilityMedium)
        let scaled = DynamicTypeSize.large.osrsApplyingUserScale(1.40).osrsPreferredFont(forTextStyle: .body)
        let baseline = DynamicTypeSize.large.osrsPreferredFont(forTextStyle: .body)
        XCTAssertGreaterThan(scaled.pointSize, baseline.pointSize)
    }
}

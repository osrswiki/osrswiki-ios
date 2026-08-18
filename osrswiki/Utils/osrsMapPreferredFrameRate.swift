import MapLibre
import UIKit

/// One ProMotion-aware frame-rate contract for maps and custom `CADisplayLink`
/// animation. MapLibre's `PreferredFramesPerSecondMaximum` is documented as ~60 FPS,
/// so every `MLNMapView` requests the screen maximum instead of that cap.
/// UIKit, SwiftUI, WKWebView scrolling, and interactive-pop inherit ProMotion from
/// `CADisableMinimumFrameDurationOnPhone` in Info.plist. This SDK's `UIView` has no
/// `preferredFrameRateRange` (confirmed against iPhoneSimulator 26.5 / iOS 18.5).
enum osrsMapPreferredFrameRate {
    static var framesPerSecond: MLNMapViewPreferredFramesPerSecond {
        MLNMapViewPreferredFramesPerSecond(rawValue: UIScreen.main.maximumFramesPerSecond)
    }

    static var viewRange: CAFrameRateRange {
        let maximum = Float(max(UIScreen.main.maximumFramesPerSecond, 60))
        return CAFrameRateRange(
            minimum: min(24, maximum),
            maximum: maximum,
            preferred: maximum
        )
    }

    static func apply(to mapView: MLNMapView) {
        mapView.preferredFramesPerSecond = framesPerSecond
    }
}

import MapLibre
import UIKit

/// One ProMotion-aware frame-rate contract for maps and custom `CADisplayLink`
/// animation. MapLibre's `PreferredFramesPerSecondMaximum` is documented as ~60 FPS,
/// so every `MLNMapView` requests the screen maximum instead of that cap.
/// UIKit, SwiftUI, WKWebView scrolling, and interactive-pop inherit ProMotion from
/// `CADisableMinimumFrameDurationOnPhone` in Info.plist. This SDK's `UIView` has no
/// `preferredFrameRateRange` (confirmed against iPhoneSimulator 26.5 / iOS 18.5).
/// Frame-rate comes from the window scene when one is attached; `UIScreen.main`
/// remains last-resort only.
enum osrsMapPreferredFrameRate {
    static var framesPerSecond: MLNMapViewPreferredFramesPerSecond {
        framesPerSecond(from: nil)
    }

    static func framesPerSecond(from view: UIView?) -> MLNMapViewPreferredFramesPerSecond {
        MLNMapViewPreferredFramesPerSecond(
            rawValue: osrsWindowSceneGeometry.maximumFramesPerSecond(from: view)
        )
    }

    static var viewRange: CAFrameRateRange {
        viewRange(from: nil)
    }

    static func viewRange(from view: UIView?) -> CAFrameRateRange {
        let maximum = Float(max(osrsWindowSceneGeometry.maximumFramesPerSecond(from: view), 60))
        return CAFrameRateRange(
            minimum: min(24, maximum),
            maximum: maximum,
            preferred: maximum
        )
    }

    static func apply(to mapView: MLNMapView) {
        mapView.preferredFramesPerSecond = framesPerSecond(from: mapView)
    }
}

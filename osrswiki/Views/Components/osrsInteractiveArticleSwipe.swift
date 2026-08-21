//
//  osrsInteractiveArticleSwipe.swift
//  osrswiki
//
//  Live, finger-tracking chrome for article back and contents swipes.
//  Uses the existing UIKit pan on WKWebView (vertical scrolls never begin the
//  recognizer) and UINavigationController's previous page for the back peek.
//

import SwiftUI
import UIKit
import WebKit

enum osrsInteractiveArticleSwipeAxis {
    case back
    case contents
}

enum osrsInteractiveArticleSwipeFinish {
    case commitBack
    case commitContents
    case commitContentsDismiss
    case cancel
}

/// Tracks one article pan and keeps the destination visible while the finger moves.
final class osrsInteractiveArticleSwipe {
    static let contentsDrawerWidth: CGFloat = 280
    static let contentsDrawerTrailingInset: CGFloat = 12
    /// Extra travel past the trailing inset so liquid-glass bleed cannot rest on-screen.
    static let contentsDrawerParkBleed: CGFloat = 80
    static var contentsDrawerTravelDistance: CGFloat {
        contentsDrawerWidth + contentsDrawerTrailingInset + contentsDrawerParkBleed
    }

    static func contentsParkedOffset(panelWidth: CGFloat) -> CGFloat {
        panelWidth + contentsDrawerTrailingInset + contentsDrawerParkBleed
    }
    static let lockDistance: CGFloat = 12
    static let horizontalDominance: CGFloat = 1.75
    static let commitProgress: CGFloat = 0.35
    static let commitVelocity: CGFloat = 500

    private static var backPreviewStack: [UIImage] = []

    static func captureVisibleBackPreview() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { captureVisibleBackPreview() }
            return
        }
        guard let window = keyWindow(),
              window.bounds.width > 1,
              window.bounds.height > 1 else { return }
        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        if isUniformBlackFlash(image) {
            if let last = backPreviewStack.last {
                backPreviewStack.append(last)
            }
            return
        }
        backPreviewStack.append(image)
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// Active article/page background. Dark mode must not peek light parchment.
    var chromeColor: UIColor = osrsInteractiveArticleSwipe.parchmentColor()

    static func parchmentColor(theme: (any osrsThemeProtocol)? = nil) -> UIColor {
        if let theme {
            return UIColor(theme.background)
        }
        return UIColor(red: 0.87, green: 0.84, blue: 0.77, alpha: 1)
    }

    /// True only for a featureless black frame, not a dark-theme article.
    static func isUniformBlackFlash(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0
        var minLuma = 255
        var maxLuma = 0
        let count = width * height
        for index in 0..<count {
            let offset = index * 4
            let luma = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            total += luma
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
        }
        return (total / count) < 16 && (maxLuma - minLuma) < 10
    }

    static func popCapturedBackPreview() {
        if !backPreviewStack.isEmpty {
            backPreviewStack.removeLast()
        }
    }

    static func currentBackPreviewImage() -> UIImage? {
        backPreviewStack.last
    }

    private(set) var axis: osrsInteractiveArticleSwipeAxis?
    private(set) var isTracking = false
    private(set) var contentsProgress: CGFloat = 0
    private(set) var backProgress: CGFloat = 0
    private(set) var contentsOpenAtStart = false

    private(set) var lastAxis: osrsInteractiveArticleSwipeAxis?
    private var isCommitSettling = false
    private var chromeHost: UIView?
    private var slidingSnapshot: UIView?
    private var hiddenSlidingView: UIView?

    private weak var slidingView: UIView?
    private var previousSnapshot: UIView?
    private var dimmingView: UIView?

    func begin(from view: UIView, contentsOpen: Bool = false) {
        isCommitSettling = false
        cleanup(resetTransform: true)
        axis = nil
        isTracking = false
        lastAxis = nil
        contentsProgress = contentsOpen ? 1 : 0
        backProgress = 0
        contentsOpenAtStart = contentsOpen
        slidingView = Self.slidingView(from: view)
        Self.navigationController(from: view)?.interactivePopGestureRecognizer?.isEnabled = false
    }

    static func lockAxis(
        translation: CGPoint,
        contentsOpenAtStart: Bool
    ) -> osrsInteractiveArticleSwipeAxis? {
        let dx = translation.x
        let dy = translation.y
        guard hypot(dx, dy) >= lockDistance else { return nil }
        guard abs(dx) >= abs(dy) * horizontalDominance else { return nil }
        if contentsOpenAtStart {
            return .contents
        }
        return dx > 0 ? .back : .contents
    }

    static func contentsProgress(translationX: CGFloat, contentsOpenAtStart: Bool) -> CGFloat {
        if contentsOpenAtStart {
            return min(1, max(0, 1 - translationX / contentsDrawerWidth))
        }
        return min(1, max(0, -translationX / contentsDrawerWidth))
    }

    static func shouldCommitContents(
        progress: CGFloat,
        velocityX: CGFloat,
        contentsOpenAtStart: Bool
    ) -> Bool {
        if contentsOpenAtStart {
            return progress <= (1 - commitProgress) || velocityX >= commitVelocity
        }
        return progress >= commitProgress || velocityX <= -commitVelocity
    }

    func update(translation: CGPoint, from view: UIView) {
        if axis == nil {
            guard let locked = Self.lockAxis(
                translation: translation,
                contentsOpenAtStart: contentsOpenAtStart
            ) else {
                if hypot(translation.x, translation.y) >= Self.lockDistance {
                    isTracking = false
                    axis = nil
                }
                return
            }
            axis = locked
            isTracking = true
            lastAxis = locked
            if axis == .back {
                installBackPreview(from: view)
            }
        }

        guard isTracking, let axis else { return }
        switch axis {
        case .back:
            let width = max(slidingView?.bounds.width ?? UIScreen.main.bounds.width, 1)
            let x = max(0, translation.x)
            backProgress = min(1, x / width)
            let moving = slidingSnapshot ?? slidingView
            moving?.transform = CGAffineTransform(translationX: x, y: 0)
            previousSnapshot?.transform = CGAffineTransform(
                translationX: (x - width) * Self.backPreviewParallax,
                y: 0
            )
            dimmingView?.alpha = 0.22 * (1 - backProgress)
        case .contents:
            contentsProgress = Self.contentsProgress(
                translationX: translation.x,
                contentsOpenAtStart: contentsOpenAtStart
            )
        }
    }

    static let settleCoastPointsPerSecond: CGFloat = 280
    static let settleMinDuration: TimeInterval = 0.12
    static let settleMaxDuration: TimeInterval = 0.80
    /// Keep the destination snapshot aligned with the real previous page. Any
    /// parallax here draws a second, offset copy the user can tell apart.
    static let backPreviewParallax: CGFloat = 0

    static func remainingDistance(from: CGFloat, to: CGFloat, distance: CGFloat) -> CGFloat {
        abs(to - from) * max(distance, 1)
    }

    static func remainingDistance(progress: CGFloat, distance: CGFloat) -> CGFloat {
        remainingDistance(from: progress, to: 1, distance: distance)
    }

    static func remainingCommitDuration(
        from: CGFloat,
        to: CGFloat,
        velocity: CGFloat,
        distance: CGFloat
    ) -> TimeInterval {
        let remaining = remainingDistance(from: from, to: to, distance: distance)
        let speed = max(abs(velocity), settleCoastPointsPerSecond)
        return min(settleMaxDuration, max(settleMinDuration, TimeInterval(remaining / speed)))
    }

    static func remainingCommitDuration(
        progress: CGFloat,
        velocity: CGFloat,
        distance: CGFloat
    ) -> TimeInterval {
        remainingCommitDuration(from: progress, to: 1, velocity: velocity, distance: distance)
    }

    static func settleSpring(
        from: CGFloat,
        to: CGFloat,
        velocity: CGFloat,
        distance: CGFloat
    ) -> UISpringTimingParameters {
        let remaining = remainingDistance(from: from, to: to, distance: distance)
        let initial = remaining > 1 ? abs(velocity) / remaining : 0
        return UISpringTimingParameters(
            dampingRatio: 0.92,
            initialVelocity: CGVector(dx: initial, dy: 0)
        )
    }

    static func settleSpring(progress: CGFloat, velocity: CGFloat, distance: CGFloat) -> UISpringTimingParameters {
        settleSpring(from: progress, to: 1, velocity: velocity, distance: distance)
    }

    static func settleAnimation(
        from: CGFloat,
        to: CGFloat,
        velocity: CGFloat,
        distance: CGFloat
    ) -> Animation {
        let remaining = remainingDistance(from: from, to: to, distance: distance)
        let speed = max(abs(velocity), settleCoastPointsPerSecond)
        let initial = remaining > 1 ? Double(speed / remaining) : 0
        return .interpolatingSpring(stiffness: 170, damping: 26, initialVelocity: initial)
    }

    static func settleAnimation(progress: CGFloat, velocity: CGFloat, distance: CGFloat) -> Animation {
        settleAnimation(from: progress, to: 1, velocity: velocity, distance: distance)
    }

    func finish(translation _: CGPoint, velocity: CGPoint) -> osrsInteractiveArticleSwipeFinish {
        guard isTracking, let axis else {
            cleanup(resetTransform: true)
            return .cancel
        }

        switch axis {
        case .back:
            if backProgress >= Self.commitProgress || velocity.x >= Self.commitVelocity {
                isTracking = false
                lastAxis = .back
                return .commitBack
            }
            cancel(animated: true)
            return .cancel
        case .contents:
            lastAxis = .contents
            isTracking = false
            self.axis = nil
            if Self.shouldCommitContents(
                progress: contentsProgress,
                velocityX: velocity.x,
                contentsOpenAtStart: contentsOpenAtStart
            ) {
                return contentsOpenAtStart ? .commitContentsDismiss : .commitContents
            }
            return .cancel
        }
    }

    func completeCommit(velocity: CGPoint, completion: @escaping () -> Void) {
        commitBackImmediately(velocity: velocity, pop: completion)
    }

    /// Keep a window-level snapshot of the previous page under a snapshot of the
    /// outgoing page, then pop immediately. NavigationStack can go black during
    /// an incomplete push; the window chrome stays stable until the settle ends.
    func commitBackImmediately(velocity: CGPoint, pop: @escaping () -> Void) {
        guard slidingView != nil || slidingSnapshot != nil else {
            pop()
            return
        }
        if chromeHost == nil, let sliding = slidingView, let window = sliding.window ?? Self.keyWindow() {
            let overlay = slidingSnapshot ?? sliding.snapshotView(afterScreenUpdates: false) ?? {
                let fallback = UIView(frame: sliding.bounds)
                fallback.backgroundColor = sliding.backgroundColor ?? chromeColor
                return fallback
            }()
            var restFrame = sliding.convert(sliding.bounds, to: window)
            restFrame.origin.x -= sliding.transform.tx
            restFrame.origin.y -= sliding.transform.ty
            overlay.frame = restFrame
            overlay.transform = sliding.transform
            overlay.isUserInteractionEnabled = false
            if overlay.superview == nil {
                window.addSubview(overlay)
            }
            slidingSnapshot = overlay
        }
        guard let overlay = slidingSnapshot else {
            pop()
            cleanup(resetTransform: true)
            return
        }
        isCommitSettling = true
        let progress = backProgress
        axis = nil
        backProgress = 1
        isTracking = false
        pop()
        hiddenSlidingView = nil
        let width = overlay.superview?.bounds.width ?? overlay.bounds.width
        let duration = Self.remainingCommitDuration(
            from: progress,
            to: 1,
            velocity: velocity.x,
            distance: width
        )
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: Self.settleSpring(
                from: progress,
                to: 1,
                velocity: velocity.x,
                distance: width
            )
        )
        animator.addAnimations {
            overlay.transform = CGAffineTransform(translationX: width, y: 0)
            self.dimmingView?.alpha = 0
        }
        animator.addCompletion { _ in
            DispatchQueue.main.async {
                self.isCommitSettling = false
                overlay.removeFromSuperview()
                if self.slidingSnapshot === overlay {
                    self.slidingSnapshot = nil
                }
                self.removePreviewViews()
            }
        }
        animator.startAnimation()
    }

    func cancel(animated: Bool) {
        lastAxis = lastAxis ?? axis
        let moving = slidingSnapshot ?? slidingView
        let snapshot = previousSnapshot
        let dimming = dimmingView
        let reset = {
            moving?.transform = .identity
            snapshot?.transform = .identity
            dimming?.alpha = 0
        }
        if animated, let moving {
            let width = max(moving.bounds.width, 1)
            let progress = backProgress
            let duration = Self.remainingCommitDuration(
                from: progress,
                to: 0,
                velocity: 0,
                distance: width
            )
            let animator = UIViewPropertyAnimator(
                duration: duration,
                timingParameters: Self.settleSpring(
                    from: progress,
                    to: 0,
                    velocity: 0,
                    distance: width
                )
            )
            animator.addAnimations {
                reset()
            }
            animator.addCompletion { _ in
                self.hiddenSlidingView?.alpha = 1
                self.cleanup(resetTransform: false)
            }
            animator.startAnimation()
        } else if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                reset()
            } completion: { _ in
                self.hiddenSlidingView?.alpha = 1
                self.cleanup(resetTransform: false)
            }
        } else {
            reset()
            hiddenSlidingView?.alpha = 1
            cleanup(resetTransform: false)
        }
        contentsProgress = contentsOpenAtStart ? 1 : 0
        backProgress = 0
        isTracking = false
        axis = nil
    }

    func cleanup(resetTransform: Bool) {
        if isCommitSettling {
            return
        }
        if resetTransform {
            slidingView?.transform = .identity
            slidingSnapshot?.transform = .identity
        }
        hiddenSlidingView?.alpha = 1
        removePreviewViews()
        isTracking = false
        axis = nil
        contentsProgress = 0
        backProgress = 0
        contentsOpenAtStart = false
    }

    private func removePreviewViews() {
        slidingSnapshot?.removeFromSuperview()
        previousSnapshot?.removeFromSuperview()
        dimmingView?.removeFromSuperview()
        chromeHost?.removeFromSuperview()
        slidingSnapshot = nil
        previousSnapshot = nil
        dimmingView = nil
        chromeHost = nil
        hiddenSlidingView = nil
    }

    private func installBackPreview(from view: UIView) {
        guard chromeHost == nil,
              let sliding = slidingView,
              let window = sliding.window ?? Self.keyWindow() else { return }

        let chrome = UIView(frame: window.bounds)
        chrome.isUserInteractionEnabled = false
        chrome.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        chrome.backgroundColor = chromeColor
        chrome.isOpaque = true
        chrome.accessibilityIdentifier = "article_back_swipe_chrome"

        let destination = makeDestinationPreview(in: window.bounds)

        let dimming = UIView(frame: window.bounds)
        dimming.backgroundColor = .black
        dimming.alpha = 0.22
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.isUserInteractionEnabled = false

        // Snapshot the article page only. The live overlay bottom bar translates
        // with the swipe; a window snapshot cannot capture iOS 26 Liquid Glass
        // and hiding that bar made it vanish on the first pixel of movement.
        var currentFrame = sliding.convert(sliding.bounds, to: window)
        currentFrame.origin.x -= sliding.transform.tx
        currentFrame.origin.y -= sliding.transform.ty
        let current = sliding.snapshotView(afterScreenUpdates: false) ?? {
            let fallback = UIView(frame: currentFrame)
            fallback.backgroundColor = sliding.backgroundColor ?? chromeColor
            return fallback
        }()
        current.frame = currentFrame
        current.isUserInteractionEnabled = false

        chrome.addSubview(destination)
        chrome.addSubview(dimming)
        chrome.addSubview(current)
        window.addSubview(chrome)

        sliding.alpha = 0
        hiddenSlidingView = sliding
        chromeHost = chrome
        previousSnapshot = destination
        dimmingView = dimming
        slidingSnapshot = current
    }

    private func makeDestinationPreview(in bounds: CGRect) -> UIView {
        if let image = Self.currentBackPreviewImage(), !Self.isUniformBlackFlash(image) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleToFill
            imageView.frame = bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.isUserInteractionEnabled = false
            return imageView
        }
        let fallback = UIView(frame: bounds)
        fallback.backgroundColor = chromeColor
        fallback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fallback.isUserInteractionEnabled = false
        return fallback
    }

    static func slidingView(from view: UIView) -> UIView? {
        if let nav = navigationController(from: view),
           let top = nav.topViewController?.view {
            return top
        }
        return view
    }

    static func navigationController(from view: UIView) -> UINavigationController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let navigationController = current as? UINavigationController {
                return navigationController
            }
            if let viewController = current as? UIViewController {
                if let navigationController = viewController.navigationController {
                    return navigationController
                }
            }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Reusable full-width back swipe for pushed non-list destinations

/// Anchors a UIKit pan on the destination canvas so overlays, settings pages,
/// and other non-webview hosts get the same interactive-back chrome as articles.
final class osrsInteractiveBackSwipeAnchorView: UIView {
    var installOnSuperview: ((UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = false
        if let superview {
            installOnSuperview?(superview)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

struct osrsInteractiveBackSwipeHost: UIViewRepresentable {
    var enabled: Bool
    var chromeColor: UIColor
    var onBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> osrsInteractiveBackSwipeAnchorView {
        let view = osrsInteractiveBackSwipeAnchorView()
        view.backgroundColor = .clear
        context.coordinator.parent = self
        view.installOnSuperview = { [weak coordinator = context.coordinator] host in
            coordinator?.install(on: host)
        }
        return view
    }

    func updateUIView(_ uiView: osrsInteractiveBackSwipeAnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.swipe.chromeColor = chromeColor
        context.coordinator.pan.isEnabled = enabled
        if let superview = uiView.superview {
            context.coordinator.install(on: superview)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: osrsInteractiveBackSwipeHost?
        let swipe = osrsInteractiveArticleSwipe()
        let pan = UIPanGestureRecognizer()
        private weak var installedOn: UIView?

        override init() {
            super.init()
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.maximumNumberOfTouches = 1
        }

        deinit {
            installedOn?.removeGestureRecognizer(pan)
        }

        func install(on view: UIView) {
            let canvas = Self.destinationCanvas(from: view)
            if installedOn === canvas {
                pan.isEnabled = parent?.enabled ?? false
                return
            }
            installedOn?.removeGestureRecognizer(pan)
            canvas.addGestureRecognizer(pan)
            installedOn = canvas
            pan.isEnabled = parent?.enabled ?? false
            if parent?.enabled == true {
                osrsInteractiveArticleSwipe.navigationController(from: canvas)?
                    .interactivePopGestureRecognizer?.isEnabled = false
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent?.enabled == true,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else {
                return false
            }
            let velocity = pan.velocity(in: view)
            if velocity == .zero {
                return true
            }
            return osrsArticleWebPanPolicy.isPrimarilyHorizontal(velocity: velocity) && velocity.x >= 0
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view, parent?.enabled == true else { return }
            swipe.chromeColor = parent?.chromeColor ?? osrsInteractiveArticleSwipe.parchmentColor()
            switch recognizer.state {
            case .began:
                swipe.begin(from: view, contentsOpen: false)
            case .changed:
                swipe.update(
                    translation: recognizer.translation(in: view.window ?? view),
                    from: view
                )
                if swipe.axis == .contents {
                    swipe.cancel(animated: false)
                }
            case .ended, .cancelled, .failed:
                let translation = recognizer.translation(in: view.window ?? view)
                let velocity = recognizer.velocity(in: view.window ?? view)
                swipe.update(translation: translation, from: view)
                if swipe.axis == .back,
                   swipe.finish(translation: translation, velocity: velocity) == .commitBack {
                    swipe.cleanup(resetTransform: false)
                    parent?.onBack()
                } else {
                    swipe.cancel(animated: true)
                }
            default:
                break
            }
        }

        private static func destinationCanvas(from view: UIView) -> UIView {
            var responder: UIResponder? = view
            var lastViewControllerView: UIView = view
            while let current = responder {
                if let viewController = current as? UIViewController,
                   !(viewController is UINavigationController),
                   !(viewController is UITabBarController),
                   !(viewController is UISplitViewController) {
                    lastViewControllerView = viewController.view
                }
                responder = current.next
            }
            return lastViewControllerView
        }
    }
}

struct osrsInteractiveBackSwipeModifier: ViewModifier {
    @EnvironmentObject private var themeManager: osrsThemeManager
    @Environment(\.dismiss) private var dismiss
    var isEnabled: Bool
    var onBack: (() -> Void)?

    func body(content: Content) -> some View {
        content.background(
            osrsInteractiveBackSwipeHost(
                enabled: isEnabled && themeManager.swipeRightToGoBackEnabled,
                chromeColor: UIColor(themeManager.currentTheme.background),
                onBack: { onBack?() ?? dismiss() }
            )
        )
    }
}

extension View {
    func osrsInteractiveBackSwipe(
        enabled: Bool = true,
        onBack: (() -> Void)? = nil
    ) -> some View {
        modifier(osrsInteractiveBackSwipeModifier(isEnabled: enabled, onBack: onBack))
    }
}

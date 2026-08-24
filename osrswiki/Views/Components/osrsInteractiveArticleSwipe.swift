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
    private var chromeHost: osrsLiveBackChromeView?
    private var slidingSnapshot: UIView?
    private var hiddenSlidingView: UIView?
    private var slidingRestMinX: CGFloat = 0

    private weak var slidingView: UIView?
    private var previousSnapshot: UIView?
    private var dimmingView: UIView?
    private weak var livePreviousView: UIView?
    private weak var livePreviousOriginalSuperview: UIView?
    private var livePreviousOriginalFrame: CGRect = .zero
    private var livePreviousOriginalIndex: Int?

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
            chromeHost?.slidingMinX = slidingRestMinX + x
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

    /// Translate the live article while the finger is down. Snapshot only at
    /// commit so the outgoing page can keep moving after the VC pops.
    /// `snapshotView` of a heavy WKWebView during tracking is the 20 Hz hitch.
    func commitBackImmediately(velocity: CGPoint, pop: @escaping () -> Void) {
        guard slidingView != nil || slidingSnapshot != nil else {
            pop()
            return
        }
        if slidingSnapshot == nil, let sliding = slidingView {
            let window = sliding.window ?? Self.keyWindow()
            let overlay = sliding.snapshotView(afterScreenUpdates: false) ?? {
                let fallback = UIView(frame: sliding.bounds)
                fallback.backgroundColor = sliding.backgroundColor ?? chromeColor
                return fallback
            }()
            var restFrame = sliding.convert(sliding.bounds, to: window ?? sliding.superview ?? sliding)
            restFrame.origin.x -= sliding.transform.tx
            restFrame.origin.y -= sliding.transform.ty
            overlay.frame = restFrame
            overlay.transform = sliding.transform
            overlay.isUserInteractionEnabled = false
            if overlay.superview == nil {
                (window ?? sliding.superview)?.addSubview(overlay)
            }
            slidingSnapshot = overlay
            sliding.alpha = 0
            hiddenSlidingView = sliding
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
            self.chromeHost?.slidingMinX = self.slidingRestMinX + width
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
            self.chromeHost?.slidingMinX = self.slidingRestMinX
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
            Self.resetStuckTranslationTransforms(from: slidingView)
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
        restoreLivePreviousPage()
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

    /// Keep the previous navigation destination mounted as a live view behind the
    /// outgoing snapshot. Bitmaps of the destination go stale after a theme change.
    static func livePreviousPageView(from view: UIView) -> UIView? {
        guard let navigationController = navigationController(from: view),
              navigationController.viewControllers.count >= 2,
              let sliding = slidingView(from: view) else {
            return nil
        }
        guard view === sliding || view.isDescendant(of: sliding) else {
            return nil
        }
        let previous = navigationController.viewControllers[navigationController.viewControllers.count - 2]
        previous.loadViewIfNeeded()
        let live = previous.view
        if live === sliding {
            return nil
        }
        return live
    }

    private func restoreLivePreviousPage() {
        guard let live = livePreviousView else { return }
        if let originalSuperview = livePreviousOriginalSuperview {
            let insertionIndex = min(
                livePreviousOriginalIndex ?? originalSuperview.subviews.count,
                originalSuperview.subviews.count
            )
            originalSuperview.insertSubview(live, at: insertionIndex)
            live.frame = livePreviousOriginalFrame
        } else if live.superview === chromeHost {
            live.removeFromSuperview()
        }
        livePreviousView = nil
        livePreviousOriginalSuperview = nil
        livePreviousOriginalIndex = nil
    }

    private func installBackPreview(from view: UIView) {
        guard chromeHost == nil,
              let sliding = slidingView,
              let host = sliding.superview else { return }

        let chrome = osrsLiveBackChromeView(frame: host.bounds)
        chrome.isUserInteractionEnabled = true
        chrome.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        chrome.backgroundColor = .clear
        chrome.isOpaque = false
        chrome.accessibilityIdentifier = "article_back_swipe_chrome"

        if let live = Self.livePreviousPageView(from: sliding) {
            livePreviousOriginalSuperview = live.superview
            livePreviousOriginalIndex = live.superview?.subviews.firstIndex(of: live)
            livePreviousOriginalFrame = live.frame
            live.isHidden = false
            live.alpha = 1
            chrome.addSubview(live)
            live.frame = chrome.bounds
            live.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            livePreviousView = live
        }

        let dimming = UIView(frame: chrome.bounds)
        dimming.backgroundColor = .black
        dimming.alpha = 0.22
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.isUserInteractionEnabled = false

        var currentFrame = sliding.convert(sliding.bounds, to: host)
        currentFrame.origin.x -= sliding.transform.tx
        currentFrame.origin.y -= sliding.transform.ty

        chrome.slidingMinX = currentFrame.minX
        chrome.addSubview(dimming)
        host.insertSubview(chrome, belowSubview: sliding)

        chromeHost = chrome
        previousSnapshot = nil
        dimmingView = dimming
        slidingSnapshot = nil
        hiddenSlidingView = nil
        slidingRestMinX = currentFrame.minX
    }

    static func slidingView(from view: UIView) -> UIView? {
        destinationCanvas(from: view)
    }

    /// Prefer the pushed navigation destination, never a surviving tab/root
    /// host. Walking to the last ancestor VC translated the entire app and
    /// stacked a leftover gutter on every More swipe-back.
    static func destinationCanvas(from view: UIView) -> UIView {
        if let nav = navigationController(from: view),
           let top = nav.topViewController?.view {
            return top
        }
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController,
               !(viewController is UINavigationController),
               !(viewController is UITabBarController),
               !(viewController is UISplitViewController) {
                return viewController.view
            }
            responder = current.next
        }
        return view
    }

    static func resetStuckTranslationTransforms(from view: UIView?) {
        var current = view
        while let node = current {
            let transform = node.transform
            if transform.ty == 0,
               abs(transform.tx) > 0.5,
               transform.a == 1,
               transform.d == 1,
               transform.b == 0,
               transform.c == 0 {
                node.transform = .identity
            }
            if node is UIWindow {
                break
            }
            current = node.superview
        }
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

private final class osrsLiveBackChromeView: UIView {
    var slidingMinX: CGFloat = 0

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.x < slidingMinX {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Reusable full-width back swipe for pushed destinations

enum osrsInteractiveBackSwipeTouchPolicy {
    /// Full-width back swipe must not steal slider/switch drags or a horizontal
    /// scroller that owns the start point. Missing hits fail closed, matching
    /// article pan policy (viewport coords, 4cf528b0).
    static func allowsBackSwipe(from touchView: UIView?) -> Bool {
        guard let touchView else { return false }
        var view: UIView? = touchView
        while let current = view {
            if current is UIControl {
                return false
            }
            let name = NSStringFromClass(type(of: current))
            if name.range(of: "slider", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return false
            }
            if isHorizontalScroller(current) {
                return false
            }
            view = current.superview
        }
        return true
    }

    static func allowsSimultaneousRecognition(with other: UIGestureRecognizer) -> Bool {
        allowsBackSwipe(from: other.view)
    }

    /// Hit-test in window / viewport space so a UIScrollView whose bounds origin
    /// equals contentOffset cannot mis-classify the start point.
    static func hitView(for touch: UITouch, in host: UIView?) -> UIView? {
        if let window = host?.window ?? touch.window {
            let point = touch.location(in: window)
            return window.hitTest(point, with: nil)
        }
        if let host {
            return host.hitTest(touch.location(in: host), with: nil) ?? touch.view
        }
        return touch.view
    }

    static func isHorizontalScroller(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        if name.range(of: "WKScroll", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }
        guard let scroll = view as? UIScrollView else { return false }
        let insetWidth = scroll.adjustedContentInset.left + scroll.adjustedContentInset.right
        let extraWidth = scroll.contentSize.width - scroll.bounds.width + insetWidth
        if extraWidth > 1 {
            return true
        }
        if scroll.alwaysBounceHorizontal && !scroll.alwaysBounceVertical {
            return true
        }
        if scroll.isPagingEnabled && scroll.alwaysBounceHorizontal {
            return true
        }
        return false
    }
}

/// Anchors a UIKit pan on the destination canvas so overlays, settings pages,
/// list destinations, and other non-webview hosts get the same interactive-back chrome as articles.
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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let hit = osrsInteractiveBackSwipeTouchPolicy.hitView(for: touch, in: gestureRecognizer.view)
            return osrsInteractiveBackSwipeTouchPolicy.allowsBackSwipe(from: hit)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            osrsInteractiveBackSwipeTouchPolicy.allowsSimultaneousRecognition(with: otherGestureRecognizer)
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
                    let canvas = view
                    let navView = osrsInteractiveArticleSwipe.navigationController(from: view)?.view
                    swipe.completeCommit(velocity: velocity) {
                        self.parent?.onBack()
                        osrsInteractiveArticleSwipe.resetStuckTranslationTransforms(from: canvas)
                        osrsInteractiveArticleSwipe.resetStuckTranslationTransforms(from: navView)
                    }
                } else {
                    swipe.cancel(animated: true)
                }
            default:
                break
            }
        }

        private static func destinationCanvas(from view: UIView) -> UIView {
            osrsInteractiveArticleSwipe.destinationCanvas(from: view)
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

import SwiftUI
import UIKit
import WebKit

/// Attaches a vertical pan discriminator to the native-calc chrome host.
/// Taps still hit UIKit controls. A pan past slop cancels the control and
/// scrolls `WKWebView.scrollView` without feeding article back-swipe.
struct osrsNativeCalcControlPanBridge: UIViewRepresentable {
    var webView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "native-calc-control-pan-bridge"
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.webView = webView
        DispatchQueue.main.async {
            context.coordinator.attach(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var webView: WKWebView?
        private weak var host: UIView?
        private var pan: UIPanGestureRecognizer?
        private var startOffset: CGPoint = .zero

        func attach(from anchor: UIView) {
            var candidate = anchor.superview
            while let current = candidate, current.bounds.height < 80, let parent = current.superview {
                candidate = parent
            }
            guard let host = candidate else { return }
            if self.host === host, pan != nil { return }
            detach()
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            host.addGestureRecognizer(recognizer)
            self.host = host
            self.pan = recognizer
        }

        func detach() {
            if let pan, let host {
                host.removeGestureRecognizer(pan)
            }
            pan = nil
            host = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else {
                return false
            }
            return osrsNativeCalcSlotGeometry.shouldBeginVerticalArticlePan(
                translation: pan.translation(in: view)
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if otherGestureRecognizer.view === webView?.scrollView ||
                otherGestureRecognizer.view === webView {
                return false
            }
            if let scroll = otherGestureRecognizer.view as? UIScrollView,
               scroll.contentSize.width > scroll.bounds.width + 1,
               scroll.contentSize.height <= scroll.bounds.height + 1 {
                return false
            }
            return false
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let webView, let view = pan.view else { return }
            let scroll = webView.scrollView
            switch pan.state {
            case .began:
                startOffset = scroll.contentOffset
                apply(pan, in: view, scroll: scroll)
            case .changed:
                apply(pan, in: view, scroll: scroll)
            default:
                break
            }
        }

        private func apply(_ pan: UIPanGestureRecognizer, in view: UIView, scroll: UIScrollView) {
            let offset = osrsNativeCalcSlotGeometry.articleScrollOffset(
                startOffset: startOffset,
                translationY: pan.translation(in: view).y,
                contentSize: scroll.contentSize,
                boundsHeight: scroll.bounds.height,
                adjustedInsetTop: scroll.adjustedContentInset.top,
                adjustedInsetBottom: scroll.adjustedContentInset.bottom
            )
            if scroll.contentOffset != offset {
                scroll.setContentOffset(offset, animated: false)
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }
}

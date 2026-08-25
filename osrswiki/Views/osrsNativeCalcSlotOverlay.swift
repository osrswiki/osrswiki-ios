import SwiftUI
import UIKit
import WebKit

struct osrsNativeCalcSlotOverlay: View {
    @ObservedObject var session: osrsNativeCalcSession
    var webView: WKWebView?
    @State private var slotY: CGFloat = 0
    @State private var formHeight: CGFloat = 420
    @State private var collapsed = false

    var body: some View {
        GeometryReader { page in
            let top = osrsNativeCalcSlotGeometry.formTopY(
                slotDocumentY: slotY,
                contentOffsetY: 0
            )
            osrsNativeCalcChrome(
                session: session,
                collapsed: $collapsed,
                onHeightChange: { formHeight = $0 }
            )
            .offset(y: top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(top + formHeight > 0 && top < page.size.height)
        }
        .clipped()
        .background(
            osrsNativeCalcSlotProbe(
                session: session,
                webView: webView,
                slotY: $slotY,
                formHeight: formHeight,
                collapsed: collapsed
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
    }
}

private struct osrsNativeCalcSlotProbe: UIViewRepresentable {
    @ObservedObject var session: osrsNativeCalcSession
    var webView: WKWebView?
    @Binding var slotY: CGFloat
    var formHeight: CGFloat
    var collapsed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(slotY: $slotY)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.session = session
        context.coordinator.webView = webView
        context.coordinator.slotY = $slotY
        context.coordinator.collapsed = collapsed
        context.coordinator.sync(formHeight: formHeight)
    }

    @MainActor
    final class Coordinator {
        var session: osrsNativeCalcSession?
        weak var webView: WKWebView?
        var slotY: Binding<CGFloat>
        var collapsed = false
        private var offsetObservation: NSKeyValueObservation?
        private var observedScrollView: UIScrollView?
        private var slotDocumentY: CGFloat = 0
        private var lastInjectedHTML: String?
        private var lastSlotKey: String = ""
        private var installWorkItem: DispatchWorkItem?
        private var retries = 0

        init(slotY: Binding<CGFloat>) {
            self.slotY = slotY
        }

        func sync(formHeight: CGFloat) {
            observeScrollView()
            publishViewportY()
            guard let webView, let session else { return }
            switch session.phase {
            case .native, .submitting:
                installSlot(webView: webView, session: session, formHeight: formHeight)
                injectResultIfNeeded(webView: webView, session: session)
                webView.evaluateJavaScript(
                    "window.osrsNativeCalcSetCollapsed && window.osrsNativeCalcSetCollapsed(\(collapsed ? "true" : "false"))",
                    completionHandler: nil
                )
            default:
                lastSlotKey = ""
                lastInjectedHTML = nil
                retries = 0
                webView.evaluateJavaScript(osrsNativeCalcDefinition.uninstallSlotJavaScript(), completionHandler: nil)
            }
        }

        private func observeScrollView() {
            guard let scroll = webView?.scrollView, observedScrollView !== scroll else { return }
            observedScrollView = scroll
            offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.publishViewportY()
                }
            }
        }

        private func publishViewportY() {
            let offsetY = webView?.scrollView.contentOffset.y ?? 0
            let next = osrsNativeCalcSlotGeometry.formTopY(
                slotDocumentY: slotDocumentY,
                contentOffsetY: offsetY
            )
            if abs(slotY.wrappedValue - next) > 0.5 {
                slotY.wrappedValue = next
            }
        }

        private func installSlot(webView: WKWebView, session: osrsNativeCalcSession, formHeight: CGFloat) {
            let formId = session.definition?.ui.formId ?? ""
            let resultId = session.definition?.ui.resultId ?? ""
            let height = max(Int(ceil(formHeight > 1 ? formHeight : 420)), 1)
            let key = "\(formId)|\(resultId)|\(height)|\(collapsed)"
            if lastSlotKey == key { return }
            lastSlotKey = key
            let script = osrsNativeCalcDefinition.installSlotJavaScript(
                formId: formId,
                resultId: resultId,
                height: height
            )
            installWorkItem?.cancel()
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.applySlotResult(result)
                    self.publishViewportY()
                    guard self.slotDocumentY <= 0, self.retries < 12,
                          let webView, let session = self.session else { return }
                    self.retries += 1
                    self.lastSlotKey = ""
                    let retry = DispatchWorkItem { [weak self] in
                        Task { @MainActor in
                            self?.installSlot(webView: webView, session: session, formHeight: formHeight)
                        }
                    }
                    self.installWorkItem = retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: retry)
                }
            }
        }

        private func applySlotResult(_ result: Any?) {
            if let number = result as? NSNumber {
                slotDocumentY = CGFloat(truncating: number)
                return
            }
            guard let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            if let top = json["top"] as? Double {
                slotDocumentY = CGFloat(top)
            } else if let top = json["top"] as? NSNumber {
                slotDocumentY = CGFloat(truncating: top)
            }
        }

        private func injectResultIfNeeded(webView: WKWebView, session: osrsNativeCalcSession) {
            let html = session.resultHTML
            guard html != lastInjectedHTML, !html.isEmpty else { return }
            lastInjectedHTML = html
            let resultId = session.definition?.ui.resultId ?? ""
            webView.evaluateJavaScript(
                osrsNativeCalcDefinition.setResultJavaScript(resultId: resultId, html: html),
                completionHandler: nil
            )
        }
    }
}

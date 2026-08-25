import SwiftUI
import UIKit
import WebKit

struct osrsNativeCalcSlotOverlay: View {
    @ObservedObject var session: osrsNativeCalcSession
    var webView: WKWebView?
    @State private var slotY: CGFloat = 0
    @State private var slotX: CGFloat = 0
    @State private var slotWidth: CGFloat = 0
    @State private var slotResolved = false
    @State private var formHeight: CGFloat = 420
    @State private var collapsed = false

    var body: some View {
        GeometryReader { page in
            let top = osrsNativeCalcSlotGeometry.formTopY(
                slotDocumentY: slotY,
                contentOffsetY: 0
            )
            let width = slotWidth > 1 ? slotWidth : page.size.width
            if osrsNativeCalcSlotGeometry.overlayMayShow(slotResolved: slotResolved, collapsed: collapsed) {
                osrsNativeCalcChrome(
                    session: session,
                    onHeightChange: { formHeight = $0 }
                )
                .frame(width: width, alignment: .top)
                .frame(maxHeight: formHeight, alignment: .top)
                .offset(x: slotX, y: top)
                .allowsHitTesting(top + formHeight > 0 && top < page.size.height)
            }
        }
        .clipped()
        .background(
            osrsNativeCalcSlotProbe(
                session: session,
                webView: webView,
                slotY: $slotY,
                slotX: $slotX,
                slotWidth: $slotWidth,
                slotResolved: $slotResolved,
                formHeight: formHeight,
                collapsed: $collapsed
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
    @Binding var slotX: CGFloat
    @Binding var slotWidth: CGFloat
    @Binding var slotResolved: Bool
    var formHeight: CGFloat
    @Binding var collapsed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(slotY: $slotY, slotX: $slotX, slotWidth: $slotWidth, slotResolved: $slotResolved, collapsed: $collapsed)
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
        context.coordinator.slotX = $slotX
        context.coordinator.slotWidth = $slotWidth
        context.coordinator.slotResolved = $slotResolved
        context.coordinator.collapsed = $collapsed
        context.coordinator.sync(formHeight: formHeight)
    }

    @MainActor
    final class Coordinator {
        var session: osrsNativeCalcSession?
        weak var webView: WKWebView?
        var slotY: Binding<CGFloat>
        var slotX: Binding<CGFloat>
        var slotWidth: Binding<CGFloat>
        var slotResolved: Binding<Bool>
        var collapsed: Binding<Bool>
        private var offsetObservation: NSKeyValueObservation?
        private var observedScrollView: UIScrollView?
        private var slotDocumentY: CGFloat = 0
        private var lastInjectedHTML: String?
        private var lastSlotKey: String = ""
        private var installWorkItem: DispatchWorkItem?
        private var retries = 0

        init(
            slotY: Binding<CGFloat>,
            slotX: Binding<CGFloat>,
            slotWidth: Binding<CGFloat>,
            slotResolved: Binding<Bool>,
            collapsed: Binding<Bool>
        ) {
            self.slotY = slotY
            self.slotX = slotX
            self.slotWidth = slotWidth
            self.slotResolved = slotResolved
            self.collapsed = collapsed
        }

        func sync(formHeight: CGFloat) {
            observeScrollView()
            publishViewportY()
            guard let webView, let session else { return }
            switch session.phase {
            case .native, .submitting:
                installSlot(webView: webView, session: session, formHeight: formHeight)
                injectResultIfNeeded(webView: webView, session: session)
                probeDisclosure(webView: webView)
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
            let key = "\(formId)|\(resultId)|\(height)"
            if lastSlotKey == key {
                probeDisclosure(webView: webView)
                return
            }
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
                slotResolved.wrappedValue = slotDocumentY > 0
                return
            }
            guard let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            if json["waiting"] as? Bool == true || json["missing"] as? Bool == true {
                slotResolved.wrappedValue = false
                return
            }
            if let top = json["top"] as? Double {
                slotDocumentY = CGFloat(top)
                slotResolved.wrappedValue = true
            } else if let top = json["top"] as? NSNumber {
                slotDocumentY = CGFloat(truncating: top)
                slotResolved.wrappedValue = true
            }
            applyGeometry(json)
        }

        private func probeDisclosure(webView: WKWebView) {
            webView.evaluateJavaScript(
                """
                (function(){
                  var s=document.getElementById('osrs-native-calc-slot');
                  if(!s)return null;
                  var box=s.closest('.collapsible-calculator');
                  var r=s.getBoundingClientRect();
                  return JSON.stringify({
                    top:r.top+(window.scrollY||document.documentElement.scrollTop||0),
                    left:r.left+(window.scrollX||document.documentElement.scrollLeft||0),
                    width:r.width,
                    collapsed:!!(box&&box.classList.contains('collapsed'))
                  });
                })()
                """
            ) { [weak self] result, _ in
                Task { @MainActor in
                    self?.applySlotResult(result)
                    self?.publishViewportY()
                }
            }
        }

        private func applyGeometry(_ json: [String: Any]) {
            if let collapsed = json["collapsed"] as? Bool {
                self.collapsed.wrappedValue = collapsed
            }
            if let left = json["left"] as? Double {
                slotX.wrappedValue = CGFloat(left)
            } else if let left = json["left"] as? NSNumber {
                slotX.wrappedValue = CGFloat(truncating: left)
            }
            if let width = json["width"] as? Double, width > 1 {
                slotWidth.wrappedValue = CGFloat(width)
            } else if let width = json["width"] as? NSNumber, CGFloat(truncating: width) > 1 {
                slotWidth.wrappedValue = CGFloat(truncating: width)
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

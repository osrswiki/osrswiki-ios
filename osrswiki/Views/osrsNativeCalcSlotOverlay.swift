import SwiftUI
import UIKit
import WebKit

/// Dump SPI (job ios-calc-flash-ip): per-probe geometry log naming the
/// oscillator behind the TF 43 Agility chrome seizure. Gated by the
/// `-osrsCalcProbeLog` launch argument; inert otherwise. Appends
/// pipe-separated lines to Documents/osrs-calc-probe-log.txt with an
/// 8 MB rotation (one .1 backup) so a probe storm cannot fill the disk.
@MainActor
enum osrsNativeCalcProbeLog {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-osrsCalcProbeLog")
    private static var buffer: [String] = []
    private static var counters: [String: Int] = [:]
    private static var lastFlush = Date()
    private static var lastSummary = Date()
    private static let start = Date()

    private static var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("osrs-calc-probe-log.txt")
    }

    static func log(_ site: String, _ detail: String) {
        guard enabled else { return }
        counters[site, default: 0] += 1
        let t = Date().timeIntervalSince(start)
        buffer.append(String(format: "t=%010.3f|site=%@|%@", t, site, detail))
        let now = Date()
        if now.timeIntervalSince(lastSummary) >= 1.0 {
            let summary = counters
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            buffer.append(String(format: "t=%010.3f|site=SUMMARY|rates1s=%@", t, summary))
            counters.removeAll()
            lastSummary = now
        }
        if buffer.count >= 200 || now.timeIntervalSince(lastFlush) >= 1.0 {
            flush()
            lastFlush = now
        }
    }

    private static func flush() {
        guard !buffer.isEmpty else { return }
        let chunk = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll()
        let url = logURL
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 8_000_000 {
            let backup = url.deletingLastPathComponent().appendingPathComponent("osrs-calc-probe-log.1.txt")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: url, to: backup)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(chunk.utf8))
        }
    }

    private static var lastBodyGeom = ""

    /// Change-gated dump of the geometry the SwiftUI body actually used for
    /// the chrome frame this render. Also feeds the pan probe the window
    /// point of the chrome so its rendered-chain hitTest aims correctly.
    static func logBodyGeometry(
        top: CGFloat,
        width: CGFloat,
        visibleHeight: CGFloat,
        formHeight: CGFloat,
        boxHeight: CGFloat,
        slotX: CGFloat,
        pageSize: CGSize,
        pageGlobal: CGRect
    ) {
        guard enabled else { return }
        let line = String(
            format: "top=%.1f|w=%.1f|visH=%.1f|formH=%.1f|boxH=%.1f|slotX=%.1f|page=%.0fx%.0f|pageG=%.0f,%.0f",
            top, width, visibleHeight, formHeight, boxHeight, slotX,
            pageSize.width, pageSize.height,
            pageGlobal.origin.x, pageGlobal.origin.y
        )
        osrsCalcPanProbe.shared.chromeCenterInWindow = CGPoint(
            x: pageGlobal.origin.x + slotX + width / 2,
            y: pageGlobal.origin.y + top + min(max(visibleHeight, 1), 120) / 2
        )
        guard line != lastBodyGeom else { return }
        lastBodyGeom = line
        log("bodyGeom", line)
    }
}

/// Pan/hitTest dump SPI (job calc-clip-pan-ip): names which view actually
/// receives an in-calc pan and reconstructs the rendered view chain (frames
/// + clipsToBounds) under the chrome. Gated by the same `-osrsCalcProbeLog`
/// launch argument; never installed otherwise. The window pan recognizer is
/// observe-only: cancelsTouchesInView=false and simultaneous with everything.
@MainActor
final class osrsCalcPanProbe: NSObject, UIGestureRecognizerDelegate {
    static let shared = osrsCalcPanProbe()
    weak var webView: WKWebView?
    var chromeCenterInWindow: CGPoint = .zero
    private weak var installedWindow: UIWindow?
    private var lastMoveLog = Date.distantPast
    private var lastChromeDump = Date.distantPast

    func install(on window: UIWindow) {
        guard osrsNativeCalcProbeLog.enabled, installedWindow !== window else { return }
        installedWindow = window
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        osrsNativeCalcProbeLog.log("panProbeInstall", "window=\(pointer(window))")
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = installedWindow else { return }
        let location = gesture.location(in: window)
        let translation = gesture.translation(in: window)
        switch gesture.state {
        case .began:
            osrsNativeCalcProbeLog.log(
                "panBegan",
                String(format: "loc=%.1f,%.1f|artOff=%.1f", location.x, location.y, webView?.scrollView.contentOffset.y ?? -1)
            )
            dumpHitChain(at: location, window: window, site: "panHit")
            dumpHitChain(at: chromeCenterInWindow, window: window, site: "panChromeChain")
            dumpScrollViews(window: window, site: "panScrollsBegan")
            dumpHostingChildren(window: window, site: "panHostTree")
        case .changed:
            let now = Date()
            if now.timeIntervalSince(lastMoveLog) >= 0.15 {
                lastMoveLog = now
                osrsNativeCalcProbeLog.log(
                    "panMove",
                    String(
                        format: "loc=%.1f,%.1f|tx=%.1f|ty=%.1f|artOff=%.1f|artPanSt=%d",
                        location.x, location.y, translation.x, translation.y,
                        webView?.scrollView.contentOffset.y ?? -1,
                        webView?.scrollView.panGestureRecognizer.state.rawValue ?? -1
                    )
                )
            }
        case .ended, .cancelled, .failed:
            osrsNativeCalcProbeLog.log(
                "panEnd",
                String(
                    format: "state=%d|loc=%.1f,%.1f|tx=%.1f|ty=%.1f|artOff=%.1f",
                    gesture.state.rawValue, location.x, location.y,
                    translation.x, translation.y,
                    webView?.scrollView.contentOffset.y ?? -1
                )
            )
            dumpScrollViews(window: window, site: "panScrollsEnd")
        default:
            break
        }
    }

    /// 1 Hz rendered-chain dump at the chrome center, driven off the existing
    /// disclosure poll so it needs no extra timer.
    func dumpChromeChainIfDue() {
        guard osrsNativeCalcProbeLog.enabled, let window = installedWindow,
              chromeCenterInWindow != .zero else { return }
        let now = Date()
        guard now.timeIntervalSince(lastChromeDump) >= 1.0 else { return }
        lastChromeDump = now
        dumpHitChain(at: chromeCenterInWindow, window: window, site: "chromeChain")
    }

    private func dumpHitChain(at point: CGPoint, window: UIWindow, site: String) {
        guard let hit = window.hitTest(point, with: nil) else {
            osrsNativeCalcProbeLog.log(site, String(format: "pt=%.1f,%.1f|hit=nil", point.x, point.y))
            return
        }
        var lines: [String] = []
        var view: UIView? = hit
        var depth = 0
        while let current = view, depth < 24 {
            lines.append(describe(current, in: window))
            view = current.superview
            depth += 1
        }
        let inWeb = webView.map { hit.isDescendant(of: $0) } ?? false
        osrsNativeCalcProbeLog.log(
            site,
            String(format: "pt=%.1f,%.1f|inWeb=%d|chain=%@", point.x, point.y, inWeb ? 1 : 0, lines.joined(separator: " << "))
        )
    }

    /// Dumps the UIKit children of the hosting view that owns the article
    /// WebView, three levels deep. With the inner ScrollView torn down this
    /// names whichever UIKit-backed chrome views (if any) still exist above
    /// the WebView platform host and could absorb pans.
    private func dumpHostingChildren(window: UIWindow, site: String) {
        guard let webView else { return }
        var host: UIView? = webView.superview
        while let current = host, !String(describing: type(of: current)).contains("HostingView") {
            host = current.superview
        }
        guard let hostingView = host else {
            osrsNativeCalcProbeLog.log(site, "host=notFound")
            return
        }
        var lines: [String] = []
        appendSubtree(hostingView, into: &lines, window: window, depth: 0, maxDepth: 3)
        osrsNativeCalcProbeLog.log(site, lines.joined(separator: " >> "))
    }

    private func appendSubtree(_ view: UIView, into lines: inout [String], window: UIWindow, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth, lines.count < 40 else { return }
        lines.append(String(repeating: "-", count: depth) + describe(view, in: window))
        // The WebView's own internals are census'd elsewhere; skip its subtree.
        if view is WKWebView { return }
        for subview in view.subviews {
            appendSubtree(subview, into: &lines, window: window, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private func dumpScrollViews(window: UIWindow, site: String) {
        var found: [String] = []
        collectScrollViews(window, into: &found, window: window, depth: 0)
        osrsNativeCalcProbeLog.log(site, found.isEmpty ? "none" : found.joined(separator: " || "))
    }

    private func collectScrollViews(_ view: UIView, into result: inout [String], window: UIWindow, depth: Int) {
        guard depth < 24, result.count < 40 else { return }
        if let scroll = view as? UIScrollView {
            result.append(describe(scroll, in: window))
        }
        for subview in view.subviews {
            collectScrollViews(subview, into: &result, window: window, depth: depth + 1)
        }
    }

    private func describe(_ view: UIView, in window: UIWindow) -> String {
        let frame = view.convert(view.bounds, to: window)
        var out = String(
            format: "%@(%@)f=%.0f,%.0f,%.0fx%.0f|clip=%d",
            String(describing: type(of: view)), pointer(view),
            frame.origin.x, frame.origin.y, frame.width, frame.height,
            view.clipsToBounds ? 1 : 0
        )
        if let scroll = view as? UIScrollView {
            let role: String
            if scroll === webView?.scrollView {
                role = "article"
            } else if String(describing: type(of: scroll)).contains("WKChild") {
                role = "wkchild"
            } else {
                role = "other"
            }
            out += String(
                format: "|role=%@|en=%d|cs=%.0fx%.0f|off=%.1f,%.1f|panSt=%d",
                role, scroll.isScrollEnabled ? 1 : 0,
                scroll.contentSize.width, scroll.contentSize.height,
                scroll.contentOffset.x, scroll.contentOffset.y,
                scroll.panGestureRecognizer.state.rawValue
            )
        }
        let recognizers = view.gestureRecognizers ?? []
        if !recognizers.isEmpty {
            let names = recognizers.prefix(8).map { recognizer in
                "\(String(describing: type(of: recognizer)))\(recognizer.isEnabled ? "" : "(off)")"
            }
            out += "|gr=" + names.joined(separator: "+") + (recognizers.count > 8 ? "+…\(recognizers.count)" : "")
        }
        return out
    }

    private func pointer(_ object: AnyObject) -> String {
        String(describing: Unmanaged.passUnretained(object).toOpaque())
    }
}

/// Zero-size probe host. Its only extra job over a plain UIView is telling
/// the pan probe when a window exists to hang the observe-only recognizer on.
private final class osrsCalcProbeAnchorView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard osrsNativeCalcProbeLog.enabled, let window else { return }
        osrsCalcPanProbe.shared.install(on: window)
    }
}

struct osrsNativeCalcSlotOverlay: View {
    @ObservedObject var session: osrsNativeCalcSession
    var webView: WKWebView?
    @State private var slotY: CGFloat = 0
    @State private var slotX: CGFloat = 0
    @State private var slotWidth: CGFloat = 0
    @State private var contentColumnWidth: CGFloat = 0
    @State private var boxHeight: CGFloat = 0
    @State private var slotResolved = false
    @State private var formHeight: CGFloat = 420
    @State private var collapsed = false

    var body: some View {
        GeometryReader { page in
            let top = osrsNativeCalcSlotGeometry.formTopY(
                slotDocumentY: slotY,
                contentOffsetY: 0
            )
            let width = osrsNativeCalcSlotGeometry.overlayClipWidth(
                slotWidth: slotWidth,
                contentColumnWidth: contentColumnWidth,
                viewportWidth: page.size.width
            )
            let visibleHeight = osrsNativeCalcSlotGeometry.overlayVisibleHeight(
                formHeight: formHeight,
                viewportHeight: page.size.height,
                formTopY: top,
                boxHeight: boxHeight
            )
            let _ = osrsNativeCalcProbeLog.logBodyGeometry(
                top: top,
                width: width,
                visibleHeight: visibleHeight,
                formHeight: formHeight,
                boxHeight: boxHeight,
                slotX: slotX,
                pageSize: page.size,
                pageGlobal: page.frame(in: .global)
            )
            // Article owns vertical scrolling: the chrome is always intrinsic
            // (full formHeight) and scrolls with the page like an on-wiki
            // calculator. visibleHeight only gates painting before the slot
            // and collapsible body exist.
            if osrsNativeCalcSlotGeometry.overlayMayShow(slotResolved: slotResolved, collapsed: collapsed),
               visibleHeight > 1 {
                osrsNativeCalcChrome(
                    session: session,
                    onHeightChange: { newHeight in
                        let line = String(format: "old=%.1f|new=%.1f|width=%.1f", formHeight, newHeight, width)
                        Task { @MainActor in
                            osrsNativeCalcProbeLog.log("chromeHeight", line)
                        }
                        formHeight = newHeight
                    }
                )
                .frame(width: width, height: max(formHeight, 1), alignment: .top)
                .clipped()
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
                contentColumnWidth: $contentColumnWidth,
                boxHeight: $boxHeight,
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
    @Binding var contentColumnWidth: CGFloat
    @Binding var boxHeight: CGFloat
    @Binding var slotResolved: Bool
    var formHeight: CGFloat
    @Binding var collapsed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(slotY: $slotY, slotX: $slotX, slotWidth: $slotWidth, contentColumnWidth: $contentColumnWidth, boxHeight: $boxHeight, slotResolved: $slotResolved, collapsed: $collapsed)
    }

    func makeUIView(context: Context) -> UIView {
        let view = osrsCalcProbeAnchorView(frame: .zero)
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
        context.coordinator.contentColumnWidth = $contentColumnWidth
        context.coordinator.boxHeight = $boxHeight
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
        var contentColumnWidth: Binding<CGFloat>
        var boxHeight: Binding<CGFloat>
        var slotResolved: Binding<Bool>
        var collapsed: Binding<Bool>
        private var offsetObservation: NSKeyValueObservation?
        private var observedScrollView: UIScrollView?
        private var slotDocumentY: CGFloat = 0
        private var lastInjectedHTML: String?
        private var lastSlotKey: String = ""
        private var installWorkItem: DispatchWorkItem?
        private var pollWorkItem: DispatchWorkItem?
        private var collapsedObserver: NSObjectProtocol?
        private var retries = 0
        /// Matches Android `installNativeCalcSlot` postDelayed loop: a WebView
        /// article-header click never calls SwiftUI `updateUIView`, so collapsed
        /// must be probed on a timer or the overlay stays painted.

        init(
            slotY: Binding<CGFloat>,
            slotX: Binding<CGFloat>,
            slotWidth: Binding<CGFloat>,
            contentColumnWidth: Binding<CGFloat>,
            boxHeight: Binding<CGFloat>,
            slotResolved: Binding<Bool>,
            collapsed: Binding<Bool>
        ) {
            self.slotY = slotY
            self.slotX = slotX
            self.slotWidth = slotWidth
            self.contentColumnWidth = contentColumnWidth
            self.boxHeight = boxHeight
            self.slotResolved = slotResolved
            self.collapsed = collapsed
        }

        func sync(formHeight: CGFloat) {
            osrsCalcPanProbe.shared.webView = webView
            osrsNativeCalcProbeLog.log(
                "sync",
                String(
                    format: "phase=%@|formH=%.1f|slotDocY=%.1f|slotX=%.1f|slotW=%.1f|colW=%.1f|resolved=%d|collapsed=%d|key=%@",
                    String(describing: session?.phase),
                    formHeight,
                    slotDocumentY,
                    slotX.wrappedValue,
                    slotWidth.wrappedValue,
                    contentColumnWidth.wrappedValue,
                    slotResolved.wrappedValue ? 1 : 0,
                    collapsed.wrappedValue ? 1 : 0,
                    lastSlotKey
                )
            )
            observeScrollView()
            publishViewportY()
            guard let webView, let session else { return }
            switch session.phase {
            case .native, .submitting:
                observeCollapsedNotifications()
                installSlot(webView: webView, session: session, formHeight: formHeight)
                injectResultIfNeeded(webView: webView, session: session)
                probeDisclosure(webView: webView)
                startDisclosurePollIfNeeded()
            default:
                stopDisclosurePoll()
                lastSlotKey = ""
                lastInjectedHTML = nil
                retries = 0
                webView.evaluateJavaScript(osrsNativeCalcDefinition.uninstallSlotJavaScript(), completionHandler: nil)
            }
        }

        private func observeCollapsedNotifications() {
            guard collapsedObserver == nil else { return }
            collapsedObserver = NotificationCenter.default.addObserver(
                forName: .osrsNativeCalcCollapsed,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let collapsed = (note.userInfo?["collapsed"] as? Bool) ?? false
                Task { @MainActor in
                    self?.collapsed.wrappedValue = collapsed
                }
            }
        }

        private func startDisclosurePollIfNeeded() {
            guard pollWorkItem == nil else { return }
            scheduleDisclosurePoll()
        }

        private func stopDisclosurePoll() {
            pollWorkItem?.cancel()
            pollWorkItem = nil
        }

        private func scheduleDisclosurePoll() {
            pollWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.pollDisclosureIfNeeded()
                }
            }
            pollWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + osrsNativeCalcSlotGeometry.disclosurePollInterval,
                execute: work
            )
        }

        private func pollDisclosureIfNeeded() {
            guard let webView else {
                stopDisclosurePoll()
                return
            }
            switch session?.phase {
            case .native, .submitting:
                osrsNativeCalcProbeLog.log("pollFire", "")
                osrsCalcPanProbe.shared.dumpChromeChainIfDue()
                probeDisclosure(webView: webView)
                scheduleDisclosurePoll()
            default:
                stopDisclosurePoll()
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
            // Stamp the slot with the full form height so the collapsible
            // body contains the whole chrome and the article scrolls through
            // it, exactly like an on-wiki calculator in flow.
            let height = max(Int(ceil(formHeight > 1 ? formHeight : 420)), 1)
            let key = "\(formId)|\(resultId)|\(height)"
            if lastSlotKey == key {
                probeDisclosure(webView: webView)
                return
            }
            osrsNativeCalcProbeLog.log("installKeyChange", "old=\(lastSlotKey)|new=\(key)")
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
                    osrsNativeCalcProbeLog.log(
                        "installCB",
                        "raw=\((result as? String) ?? String(describing: result))"
                    )
                    self.applySlotResult(result)
                    self.publishViewportY()
                    guard self.slotDocumentY <= 0, self.retries < 12,
                          let webView, let session = self.session else { return }
                    self.retries += 1
                    osrsNativeCalcProbeLog.log("installRetry", "retries=\(self.retries)")
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
            // Passive, capture-phase touch counters prove whether WebKit ever
            // receives the finger at all. Probe-log builds only.
            let touchProbeInstall = osrsNativeCalcProbeLog.enabled ? """
                  if(!window.__osrsTouchProbe){window.__osrsTouchProbe={s:0,m:0,e:0,lastY:-1};(function(tp){
                    document.addEventListener('touchstart',function(ev){tp.s++;tp.lastY=ev.touches[0]?Math.round(ev.touches[0].clientY):-1;},{passive:true,capture:true});
                    document.addEventListener('touchmove',function(){tp.m++;},{passive:true,capture:true});
                    document.addEventListener('touchend',function(){tp.e++;},{passive:true,capture:true});
                  })(window.__osrsTouchProbe);}
            """ : ""
            let touchProbeField = osrsNativeCalcProbeLog.enabled
                ? "touch:window.__osrsTouchProbe.s+'/'+window.__osrsTouchProbe.m+'/'+window.__osrsTouchProbe.e+'@'+window.__osrsTouchProbe.lastY,"
                : ""
            webView.evaluateJavaScript(
                """
                (function(){
                  \(touchProbeInstall)
                  var s=document.getElementById('osrs-native-calc-slot');
                  if(!s)return null;
                  var box=s.closest('.collapsible-calculator');
                  var r=s.getBoundingClientRect();
                  var boxR=box?box.getBoundingClientRect():null;
                  var body=box&&box.querySelector(':scope > .collapsible-content > .osrs-disclosure-body');
                  var bodyR=body?body.getBoundingClientRect():null;
                  var column=window.osrsNativeCalcContentColumnWidth?window.osrsNativeCalcContentColumnWidth(box):0;
                  var sib=document.querySelector('.mw-parser-output > .collapsible-container:not(.collapsible-calculator)')||document.querySelector('.collapsible-container:not(.collapsible-calculator)');
                  var stop=document.querySelector('.mw-parser-output')||document.body;
                  var mutated=[];
                  var p=box?box.parentElement:null;
                  while(p&&p!==stop&&p!==document.body){mutated.push(p);p=p.parentElement;}
                  var sibInChain=!!(sib&&mutated.some(function(m){return m.contains(sib);}));
                  var sibInBox=!!(sib&&box&&box.contains(sib));
                  var colSrc=sib&&sib.offsetWidth>1?('sib:'+(sib.className||'?')+':w'+sib.offsetWidth+':chain'+(sibInChain?1:0)+':box'+(sibInBox?1:0)):'fallback';
                  if(window.osrsNativeCalcApplyContentColumnWidth&&box)window.osrsNativeCalcApplyContentColumnWidth(box);
                  return JSON.stringify({
                    \(touchProbeField)
                    colSrc:colSrc,
                    boxRect:boxR?Math.round(boxR.left)+','+Math.round(boxR.width):'-',
                    bodyRect:bodyR?Math.round(bodyR.left)+','+Math.round(bodyR.width):'-',
                    slotW:Math.round(r.width),
                    top:r.top+(window.scrollY||document.documentElement.scrollTop||0),
                    left:r.left+(window.scrollX||document.documentElement.scrollLeft||0),
                    bodyW:bodyR&&bodyR.width>1?bodyR.width:0,
                    width:(bodyR&&bodyR.width>1?bodyR.width:r.width),
                    boxHeight:bodyR?bodyR.height:(boxR?boxR.height:0),
                    contentColumn:column,
                    clientWidth:document.documentElement.clientWidth||window.innerWidth||0,
                    collapsed:!!(box&&box.classList.contains('collapsed'))
                  });
                })()
                """
            ) { [weak self] result, _ in
                Task { @MainActor in
                    osrsNativeCalcProbeLog.log(
                        "probeCB",
                        "raw=\((result as? String) ?? String(describing: result))"
                    )
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
            if let column = json["contentColumn"] as? Double, column > 1 {
                contentColumnWidth.wrappedValue = CGFloat(column)
            } else if let column = json["contentColumn"] as? NSNumber, CGFloat(truncating: column) > 1 {
                contentColumnWidth.wrappedValue = CGFloat(truncating: column)
            }
            if let height = json["boxHeight"] as? Double, height > 1 {
                boxHeight.wrappedValue = CGFloat(height)
            } else if let height = json["boxHeight"] as? NSNumber, CGFloat(truncating: height) > 1 {
                boxHeight.wrappedValue = CGFloat(truncating: height)
            }
            // The disclosure body's interior is the authoritative chrome
            // width: the box's outer width paired with the slot's interior
            // left pushed the overlay 12pt past the box edge. The runtime's
            // install payload has no bodyW; the 5/s probe supplies it.
            let probedWidth: CGFloat
            if let bodyW = json["bodyW"] as? Double, bodyW > 1 {
                probedWidth = CGFloat(bodyW)
            } else if let bodyW = json["bodyW"] as? NSNumber, CGFloat(truncating: bodyW) > 1 {
                probedWidth = CGFloat(truncating: bodyW)
            } else if let width = json["width"] as? Double, width > 1 {
                probedWidth = CGFloat(width)
            } else if let width = json["width"] as? NSNumber, CGFloat(truncating: width) > 1 {
                probedWidth = CGFloat(truncating: width)
            } else {
                probedWidth = slotWidth.wrappedValue
            }
            let chosen = osrsNativeCalcSlotGeometry.overlayClipWidth(
                slotWidth: probedWidth,
                contentColumnWidth: contentColumnWidth.wrappedValue,
                viewportWidth: webView?.bounds.width ?? probedWidth
            )
            osrsNativeCalcProbeLog.log(
                "applyGeom",
                String(
                    format: "probedW=%.1f|colW=%.1f|vw=%.1f|chosen=%.1f|prevW=%.1f|slotX=%.1f|slotDocY=%.1f|collapsed=%d|colSrc=%@",
                    probedWidth,
                    contentColumnWidth.wrappedValue,
                    webView?.bounds.width ?? -1,
                    chosen,
                    slotWidth.wrappedValue,
                    slotX.wrappedValue,
                    slotDocumentY,
                    (json["collapsed"] as? Bool) == true ? 1 : 0,
                    (json["colSrc"] as? String) ?? "-"
                )
            )
            slotWidth.wrappedValue = chosen
        }

        private func injectResultIfNeeded(webView: WKWebView, session: osrsNativeCalcSession) {
            let html = session.resultHTML
            guard html != lastInjectedHTML, !html.isEmpty else { return }
            osrsNativeCalcProbeLog.log("resultInject", "len=\(html.count)")
            lastInjectedHTML = html
            let resultId = session.definition?.ui.resultId ?? ""
            webView.evaluateJavaScript(
                osrsNativeCalcDefinition.setResultJavaScript(resultId: resultId, html: html),
                completionHandler: nil
            )
        }
    }
}

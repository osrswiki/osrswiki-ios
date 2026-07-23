//
//  osrsSettingsPreviewExportView.swift
//  OSRS Wiki
//
//  DEBUG-only simulator renderer for static settings preview assets.
//

#if DEBUG
import SwiftUI
import WebKit

struct osrsSettingsPreviewExportRequest: Equatable {
    let name: String
    let themeName: String
    let collapsed: Bool

    var theme: any osrsThemeProtocol {
        themeName == "dark" ? osrsDarkTheme() : osrsLightTheme()
    }

    var themeSelection: osrsThemeSelection {
        themeName == "dark" ? .osrsDark : .osrsLight
    }

    static var current: osrsSettingsPreviewExportRequest? {
        let arguments = ProcessInfo.processInfo.arguments
        guard value(after: "-settingsPreviewExport", in: arguments) == "table",
              let name = value(after: "-settingsPreviewExportName", in: arguments),
              let themeName = value(after: "-settingsPreviewExportTheme", in: arguments),
              let collapsedValue = value(after: "-settingsPreviewExportCollapsed", in: arguments) else {
            return nil
        }

        return osrsSettingsPreviewExportRequest(
            name: name,
            themeName: themeName,
            collapsed: collapsedValue == "true"
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

struct osrsSettingsPreviewTableExportView: View {
    let request: osrsSettingsPreviewExportRequest

    @EnvironmentObject private var themeManager: osrsThemeManager

    var body: some View {
        osrsSettingsPreviewTableWebView(request: request)
            .background(Color(request.theme.background))
            .statusBarHidden(true)
            .onAppear {
                themeManager.setTheme(request.themeSelection)
            }
    }
}

private struct osrsSettingsPreviewTableWebView: UIViewRepresentable {
    let request: osrsSettingsPreviewExportRequest

    func makeCoordinator() -> Coordinator {
        Coordinator(request: request)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(request.theme.background)
        webView.scrollView.backgroundColor = UIColor(request.theme.background)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.setContentOffset(.zero, animated: false)

        context.coordinator.webView = webView
        webView.loadHTMLString(
            osrsSettingsPreviewExportContent.html(collapsed: request.collapsed, theme: request.theme),
            baseURL: Bundle.main.resourceURL
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            context.coordinator.applyFinalStateAndMarkReady()
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let request: osrsSettingsPreviewExportRequest
        weak var webView: WKWebView?
        private var didMarkReady = false

        init(request: osrsSettingsPreviewExportRequest) {
            self.request = request
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.applyFinalStateAndMarkReady()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Settings preview export navigation failed: \(error.localizedDescription)")
            self.webView = webView
            applyFinalStateAndMarkReady()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Settings preview export provisional navigation failed: \(error.localizedDescription)")
            self.webView = webView
            applyFinalStateAndMarkReady()
        }

        func applyFinalStateAndMarkReady() {
            guard !didMarkReady, let webView else { return }

            let collapsedLiteral = request.collapsed ? "true" : "false"
            let script = """
            (function() {
                var shouldCollapse = \(collapsedLiteral);
                document.querySelectorAll('.collapsible-container').forEach(function(container) {
                    var content = container.querySelector('.collapsible-content');
                    var title = container.querySelector('.title-wrapper');
                    if (shouldCollapse) {
                        container.classList.add('collapsed');
                        if (content) { content.style.height = '0px'; }
                        if (title) { title.innerHTML = 'Varrock facilities<span style="font-weight: normal;">: Tap to expand</span>'; }
                    } else {
                        container.classList.remove('collapsed');
                        if (content) { content.style.height = 'auto'; }
                        if (title) { title.innerHTML = 'Varrock facilities<span style="font-weight: normal;">: Tap to collapse</span>'; }
                    }
                });
                document.body.style.visibility = 'visible';
                document.body.classList.add('js-transforms-complete');
                window.scrollTo(0, 0);
                return document.querySelectorAll('.collapsible-container').length;
            })();
            """

            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    print("Settings preview export state script failed: \(error.localizedDescription)")
                } else {
                    print("Settings preview export state applied for \(self.request.name): \(String(describing: result))")
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.writeReadyMetadata(webView: webView)
                }
            }
        }

        private func writeReadyMetadata(webView: WKWebView) {
            guard !didMarkReady else { return }
            didMarkReady = true

            do {
                let documents = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let readyRoot = documents.appendingPathComponent("settings_preview_capture_ready", isDirectory: true)
                try FileManager.default.createDirectory(at: readyRoot, withIntermediateDirectories: true)

                webView.setContentOffsetToTop()
                webView.layoutIfNeeded()

                let captureRect = webView.convert(webView.bounds, to: nil)
                let screenBounds = UIScreen.main.bounds
                let payload: [String: Any] = [
                    "name": request.name,
                    "renderer": "osrsSettingsPreviewTableExportView.simulator.WKWebView",
                    "theme": request.themeName,
                    "collapsed": request.collapsed,
                    "screen_scale": UIScreen.main.scale,
                    "screen_points": [
                        "width": screenBounds.width,
                        "height": screenBounds.height
                    ],
                    "crop_points": [
                        "x": captureRect.origin.x,
                        "y": captureRect.origin.y,
                        "width": captureRect.width,
                        "height": captureRect.height
                    ]
                ]

                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                let outputURL = readyRoot.appendingPathComponent("\(request.name).json")
                try data.write(to: outputURL, options: .atomic)
                print("Settings preview export ready: \(outputURL.path)")
            } catch {
                print("Settings preview export failed to write ready metadata: \(error)")
            }
        }
    }
}

private enum osrsSettingsPreviewExportContent {
    static func html(collapsed: Bool, theme: any osrsThemeProtocol) -> String {
        var html = osrsPageHtmlBuilder().buildFullHtmlDocument(
            title: "Varrock",
            bodyContent: tableFixture,
            theme: theme,
            collapseTablesEnabled: collapsed,
            includeAssetLinks: false
        )

        html = html.replacingOccurrences(
            of: "<!-- CSS assets injected via WKUserScript -->",
            with: "<style>\(inlineCSS())</style>"
        )
        html = html.replacingOccurrences(
            of: "<!-- MediaWiki scripts injected via WKUserScript -->",
            with: ""
        )
        html = html.replacingOccurrences(
            of: "<!-- JS assets injected via WKUserScript -->",
            with: "<script>\(bridgeShim)</script><script>\(inlineJavaScript())</script><script>\(visibilityScript)</script>"
        )

        return html
    }

    private static func inlineCSS() -> String {
        [
            "styles/themes.css",
            "styles/base.css",
            "styles/components.css",
            "styles/wiki-integration.css",
            "web/collapsible_tables.css",
            "styles/fixes.css"
        ].compactMap(assetText).joined(separator: "\n")
    }

    private static func inlineJavaScript() -> String {
        [
            "web/collapsible_content.js",
            "js/tablesort.min.js",
            "js/tablesort_init.js"
        ].compactMap(assetText).joined(separator: "\n")
    }

    private static func assetText(_ relativePath: String) -> String? {
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("Assets").appendingPathComponent(relativePath)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        let sourceURL = URL(fileURLWithPath: relativePath)
        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        if let flattenedURL = Bundle.main.url(forResource: basename, withExtension: fileExtension) {
            return try? String(contentsOf: flattenedURL, encoding: .utf8)
        }

        print("Settings preview export missing bundled asset: \(relativePath)")
        return nil
    }

    private static var bridgeShim: String {
        """
        window.OsrsWikiBridge = window.OsrsWikiBridge || {
            onMapPlaceholderMeasured: function() {},
            onCollapsibleToggled: function() {},
            setHorizontalScroll: function() {},
            log: function() {}
        };
        window.RenderTimeline = window.RenderTimeline || { log: function() {} };
        window.__osrsArticleLoadGeneration = 'settings-preview-export';
        """
    }

    private static var visibilityScript: String {
        """
        requestAnimationFrame(function() {
            document.body.style.visibility = 'visible';
            window.scrollTo(0, 0);
        });
        """
    }

    private static var tableFixture: String {
        """
        <div class="mw-parser-output">
          <p><b>Varrock</b> is one of the largest cities in Misthalin and a common early destination for Old School RuneScape players.</p>
          <h2><span class="mw-headline" id="Facilities">Facilities</span></h2>
          <div class="collapsible-container collapsible-wikitable primary-collapsible">
            <div class="collapsible-header">
              <div class="title-wrapper">Varrock facilities<span style="font-weight: normal;">: Tap to collapse</span></div>
              <span class="icon"></span>
            </div>
            <div class="collapsible-content" style="height: auto;">
              <table class="wikitable sortable">
                <caption>Varrock facilities</caption>
                <tbody>
                  <tr><th>Facility</th><th>Location</th><th>Use</th></tr>
                  <tr><td>Grand Exchange</td><td>North-west</td><td>Trading items with other players</td></tr>
                  <tr><td>Varrock east bank</td><td>East</td><td>Banking near shops and mines</td></tr>
                  <tr><td>Aubury's Rune Shop</td><td>South-east</td><td>Buying runes and teleporting to the rune essence mine</td></tr>
                  <tr><td>Cooking range</td><td>South-west</td><td>Cooking fish and other food</td></tr>
                </tbody>
              </table>
            </div>
          </div>
          <p>The app renders this fixture through the same article HTML, theme, table, and collapsible CSS used by normal pages.</p>
        </div>
        """
    }
}

private extension WKWebView {
    func setContentOffsetToTop() {
        scrollView.setContentOffset(.zero, animated: false)
    }
}
#endif

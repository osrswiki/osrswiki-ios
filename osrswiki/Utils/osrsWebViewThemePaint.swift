import UIKit
import WebKit

enum osrsWebViewThemePaint {
    @MainActor
    static func apply(to webView: WKWebView, theme: any osrsThemeProtocol) {
        let pageColor = UIColor(theme.background)
        webView.underPageBackgroundColor = pageColor
        webView.backgroundColor = pageColor
        webView.scrollView.backgroundColor = pageColor
    }

    @MainActor
    static func apply(to webView: WKWebView, usesDarkTheme: Bool) {
        apply(to: webView, theme: usesDarkTheme ? osrsDarkTheme() : osrsLightTheme())
    }
}

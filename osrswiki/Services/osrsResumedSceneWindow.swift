//
//  osrsResumedSceneWindow.swift
//  osrswiki
//
//  iOS 26 WindowGroup UIHostingView can stop compositing UIKit children
//  (WKWebView, Liquid Glass) after a scene resume. The live view tree is
//  still there; the framebuffer is the SwiftUI theme fill. Tweaking layers
//  inside that host does not reconnect them. Moving the WindowGroup
//  UIHostingController empties SwiftUI. Remounting CustomMainTabView onto a
//  second UIWindow still lands in a UIHostingView whose layer.contents is
//  an opaque parchment snapshot.
//
//  After a real background, osrsSceneDelegate replaces the scene's one
//  UIWindow. This type is the UIKit article root for that replacement
//  window. Do not stack a second UIWindow on a frozen SwiftUI host.
//

import SwiftUI
import UIKit
import WebKit

final class osrsResumedSceneWindow: UIWindow {
    static func bindRuntime(appState: AppState, themeManager: osrsThemeManager) {
        _ = appState
        _ = themeManager
    }

    static func reconnectAfterBackground() {
        // SceneDelegate replaces the primary window. Stacking another UIWindow
        // on a frozen host becomes key without reaching the LCD.
        print("🪟 osrsResumedSceneWindow resume: deferred to osrsSceneDelegate.replacePrimaryWindow")
    }
}

/// UIKit article chrome that does not nest WKWebView inside a SwiftUI host.
final class osrsResumedArticleViewController: UIViewController, UISearchBarDelegate, WKNavigationDelegate {
    private let appState: AppState
    private let themeManager: osrsThemeManager
    private let articleURL: URL?
    private var webView: WKWebView
    private let searchBar = UISearchBar()
    private let bottomBar = UIStackView()
    private let adoptedExisting: Bool

    init(
        appState: AppState,
        themeManager: osrsThemeManager,
        articleURL: URL? = nil,
        webView: WKWebView?
    ) {
        self.appState = appState
        self.themeManager = themeManager
        let resolvedURL = articleURL ?? appState.resumableArticleURL
        self.articleURL = resolvedURL
        self.adoptedExisting = webView != nil
        if let webView {
            self.webView = webView
        } else if let resolvedURL {
            self.webView = WKWebView(
                frame: .zero,
                configuration: osrsPreparedArticleWebViewStore.makeConfiguration(sourceArticleURL: resolvedURL)
            )
        } else {
            self.webView = WKWebView(frame: .zero)
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = themeManager.currentTheme
        view.backgroundColor = UIColor(theme.background)

        searchBar.delegate = self
        searchBar.placeholder = "Search OSRS Wiki"
        searchBar.searchBarStyle = .default
        searchBar.barTintColor = UIColor(theme.surface)
        searchBar.backgroundColor = UIColor(theme.surface)
        searchBar.tintColor = UIColor(theme.primary)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.accessibilityIdentifier = "article_search_bar"

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = UIColor(theme.background)
        webView.isOpaque = true
        webView.navigationDelegate = self
        webView.removeFromSuperview()

        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillEqually
        bottomBar.alignment = .fill
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor(theme.surface)
        bottomBar.layer.cornerRadius = 22
        bottomBar.accessibilityIdentifier = "article_bottom_bar"
        for title in ["Save", "Find", "Appearance", "Contents"] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.tintColor = UIColor(theme.primary)
            button.setTitleColor(UIColor(theme.primary), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            bottomBar.addArrangedSubview(button)
        }

        view.addSubview(searchBar)
        view.addSubview(webView)
        view.addSubview(bottomBar)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: guide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 52),

            webView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -osrsOverlayChromeMetrics.screenEdgeGap),
            bottomBar.heightAnchor.constraint(equalToConstant: osrsOverlayChromeMetrics.floatingBarHeight)
        ])

        if !adoptedExisting, let url = articleURL ?? appState.resumableArticleURL {
            print("🪟 osrsResumedArticleViewController load \(url.absoluteString)")
            NSLog("osrsResumedArticleViewController load %@", url.absoluteString)
            webView.load(URLRequest(url: url))
        } else {
            print("🪟 osrsResumedArticleViewController no article URL")
            NSLog("osrsResumedArticleViewController no article URL")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layer.contents = nil
        print(
            "🪟 osrsResumedArticleViewController appear adopted=\(adoptedExisting) view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) web=\(Int(webView.frame.width))x\(Int(webView.frame.height)) url=\(webView.url?.absoluteString ?? "nil")"
        )
        NSLog(
            "osrsResumedArticleViewController appear view=%dx%d web=%dx%d url=%@",
            Int(view.bounds.width),
            Int(view.bounds.height),
            Int(webView.frame.width),
            Int(webView.frame.height),
            webView.url?.absoluteString ?? "nil"
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🪟 osrsResumedArticleViewController didFinish \(webView.url?.absoluteString ?? "nil")")
        NSLog("osrsResumedArticleViewController didFinish %@", webView.url?.absoluteString ?? "nil")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("🪟 osrsResumedArticleViewController didFail \(error.localizedDescription)")
        NSLog("osrsResumedArticleViewController didFail %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("🪟 osrsResumedArticleViewController didFailProvisional \(error.localizedDescription)")
        NSLog("osrsResumedArticleViewController didFailProvisional %@", error.localizedDescription)
    }
}

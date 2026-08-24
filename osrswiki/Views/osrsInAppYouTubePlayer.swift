//
//  osrsInAppYouTubePlayer.swift
//  osrswiki
//
//  Top-level HTTPS YouTube embeds. Article documents use app-assets://, so
//  in-page iframes fail with error 153; this player is a real https origin.
//  See docs/internal/ios-youtube-in-webview.md.
//

import SwiftUI
import WebKit

enum osrsYouTubePlayerLayout {
    static let aspectRatio: CGFloat = 16.0 / 9.0

    static func fittedSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let heightIfFullWidth = container.width / aspectRatio
        if heightIfFullWidth <= container.height {
            return CGSize(width: container.width, height: heightIfFullWidth)
        }
        return CGSize(width: container.height * aspectRatio, height: container.height)
    }
}

struct osrsYouTubePlayerItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct osrsInAppYouTubePlayer: UIViewRepresentable {
    let url: URL
    var backgroundColor: UIColor = .clear

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(osrsYouTubeEmbed.playerRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.backgroundColor = backgroundColor
        uiView.scrollView.backgroundColor = backgroundColor
        if uiView.url != url {
            uiView.load(osrsYouTubeEmbed.playerRequest(url: url))
        }
    }
}

struct osrsYouTubePlayerPage: View {
    let url: URL
    let onDone: () -> Void
    @Environment(\.osrsTheme) private var osrsTheme

    var body: some View {
        GeometryReader { geo in
            let size = osrsYouTubePlayerLayout.fittedSize(in: geo.size)
            ZStack {
                Color(osrsTheme.background)
                osrsInAppYouTubePlayer(
                    url: url,
                    backgroundColor: UIColor(osrsTheme.background)
                )
                .aspectRatio(osrsYouTubePlayerLayout.aspectRatio, contentMode: .fit)
                .frame(width: size.width, height: size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(osrsTheme.background))
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done", action: onDone)
            }
        }
    }
}

struct osrsYouTubePlayerSheetModifier: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content.sheet(item: playerItem) { item in
            NavigationStack {
                osrsYouTubePlayerPage(url: item.url) {
                    url = nil
                }
            }
            .osrsYouTubePlayerChrome()
        }
    }

    private var playerItem: Binding<osrsYouTubePlayerItem?> {
        Binding(
            get: { url.map(osrsYouTubePlayerItem.init) },
            set: { url = $0?.url }
        )
    }
}

private struct osrsYouTubePlayerChromeModifier: ViewModifier {
    @EnvironmentObject private var themeManager: osrsThemeManager
    @Environment(\.osrsTheme) private var osrsTheme

    func body(content: Content) -> some View {
        content
            .tint(Color(osrsTheme.primary))
            .preferredColorScheme(themeManager.currentColorScheme)
            .toolbarColorScheme(themeManager.currentColorScheme, for: .navigationBar)
            .toolbarBackground(Color(osrsTheme.surface), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .presentationBackground(Color(osrsTheme.background))
            .background(Color(osrsTheme.background))
            .onAppear(perform: applyLiveTheme)
            .onChange(of: themeManager.selectedTheme) { _, _ in
                applyLiveTheme()
            }
    }

    private func applyLiveTheme() {
        osrsLiveThemeApplier.apply(
            themeManager.currentTheme,
            colorScheme: themeManager.currentColorScheme
        )
    }
}

private extension View {
    func osrsYouTubePlayerChrome() -> some View {
        modifier(osrsYouTubePlayerChromeModifier())
    }
}

extension View {
    func osrsYouTubePlayerSheet(url: Binding<URL?>) -> some View {
        modifier(osrsYouTubePlayerSheetModifier(url: url))
    }
}

struct osrsArticleSceneRestoreModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var needsRecovery: Bool
    let onLeaveForeground: () -> Void
    let onEnterForeground: () -> Void
    let onRecover: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    onLeaveForeground()
                } else if phase == .active {
                    onEnterForeground()
                }
            }
            .onChange(of: needsRecovery) { _, needsRecovery in
                guard needsRecovery else { return }
                onRecover()
            }
    }
}

extension View {
    func osrsArticleSceneRestore(
        needsRecovery: Binding<Bool>,
        onLeaveForeground: @escaping () -> Void,
        onEnterForeground: @escaping () -> Void,
        onRecover: @escaping () -> Void
    ) -> some View {
        modifier(
            osrsArticleSceneRestoreModifier(
                needsRecovery: needsRecovery,
                onLeaveForeground: onLeaveForeground,
                onEnterForeground: onEnterForeground,
                onRecover: onRecover
            )
        )
    }
}

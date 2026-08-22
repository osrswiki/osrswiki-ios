//
//  osrsInAppYouTubePlayer.swift
//  osrswiki
//
//  Top-level HTTPS YouTube embeds. Article documents use a custom scheme, so
//  in-page iframes fail with error 153; this player is a real https origin.
//

import SwiftUI
import WebKit

struct osrsYouTubePlayerItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct osrsInAppYouTubePlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.bounces = false
        webView.load(osrsYouTubeEmbed.playerRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(osrsYouTubeEmbed.playerRequest(url: url))
        }
    }
}

struct osrsYouTubePlayerSheetModifier: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content.sheet(item: playerItem) { item in
            NavigationStack {
                osrsInAppYouTubePlayer(url: item.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Video")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                url = nil
                            }
                        }
                    }
            }
        }
    }

    private var playerItem: Binding<osrsYouTubePlayerItem?> {
        Binding(
            get: { url.map(osrsYouTubePlayerItem.init) },
            set: { url = $0?.url }
        )
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

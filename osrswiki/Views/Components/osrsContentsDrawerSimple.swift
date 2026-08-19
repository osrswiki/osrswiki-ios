//
//  osrsContentsDrawerSimple.swift
//  osrswiki
//
//  Floating table-of-contents panel. Matches map realm-selector chrome:
//  liquid glass, inset from the article bars, not a full-height opaque slab.
//  Open and dismiss progress still follow the finger.
//

import SwiftUI
import WebKit

struct osrsContentsDrawerSimple: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var isPresented: Bool
    @Binding var interactiveProgress: CGFloat
    let sections: [TableOfContentsSection]
    let onSectionSelected: (String) -> Void

    private let drawerWidth: CGFloat = osrsInteractiveArticleSwipe.contentsDrawerWidth
    @State private var isDismissTracking = false

    private var revealProgress: CGFloat {
        min(1, max(0, interactiveProgress))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.18 * revealProgress)
                    .ignoresSafeArea()
                    .allowsHitTesting(revealProgress > 0.15)
                    .gesture(dismissDrag)
                    .onTapGesture {
                        dismissContents()
                    }
                    .accessibilityIdentifier("contents_drawer_backdrop")

                panel
                    .frame(width: min(drawerWidth, max(240, geometry.size.width - 24)))
                    .frame(maxHeight: panelMaxHeight(in: geometry.size))
                    .padding(.trailing, 12)
                    .padding(.top, topClearance)
                    .padding(.bottom, bottomClearance)
                    .offset(x: (1 - revealProgress) * drawerWidth)
                    .allowsHitTesting(isPresented || revealProgress > 0.02)
                    .accessibilityHidden(revealProgress <= 0)
                    .simultaneousGesture(dismissDrag)
            }
        }
        .allowsHitTesting(osrsContentsReveal.allowsOverlayHitTesting(
            isPresented: isPresented,
            interactiveProgress: revealProgress
        ))
    }

    private var topClearance: CGFloat {
        osrsOverlayChromeMetrics.topInset
            + osrsSearchControlGeometry.height(for: dynamicTypeSize)
            + osrsOverlayChromeMetrics.pairedEdgeGap
    }

    private var bottomClearance: CGFloat {
        osrsOverlayChromeMetrics.screenEdgeGap
            + osrsOverlayChromeMetrics.floatingBarHeight
            + 8
    }

    private func panelMaxHeight(in size: CGSize) -> CGFloat {
        let available = size.height - topClearance - bottomClearance
        return max(220, min(size.height * 0.72, available))
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let fallback = Color(osrsTheme.surface)
        let content = VStack(spacing: 0) {
            HStack {
                Text("Contents")
                    .font(.headline)
                    .foregroundColor(osrsTheme.onSurface)
                    .accessibilityIdentifier("contents_drawer_title")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sections) { section in
                            Button(action: {
                                onSectionSelected(section.id)
                                dismissContents()
                            }) {
                                HStack {
                                    Text(section.title)
                                        .font(fontForSection(section))
                                        .foregroundColor(osrsTheme.onSurface)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: .infinity, alignment: .trailing)

                                    Spacer().frame(width: 16)

                                    Circle()
                                        .frame(width: 8, height: 8)
                                        .foregroundColor(osrsTheme.onSurfaceVariant)

                                    Spacer().frame(width: 20)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
                .scrollDisabled(isDismissTracking)

                osrsDottedRail()
                    .frame(width: 2)
                    .offset(x: -39)
            }
        }

        return osrsDrawerChrome(content, shape: shape, fallback: fallback)
            .contentTransition(.identity)
            .accessibilityIdentifier("contents_drawer")
    }

    /// Glass is a rest-state material. Keep it while the drawer is still
    /// presented so a dismiss drag does not tear down `.glassEffect` on the
    /// first pixel of motion. Opening finger-follow keeps `isPresented` false
    /// until settle completes, so that path stays solid.
    @ViewBuilder
    private func osrsDrawerChrome<Content: View>(
        _ content: Content,
        shape: RoundedRectangle,
        fallback: Color
    ) -> some View {
        if isPresented {
            content.osrsFloatingGlass(in: shape, fallback: fallback)
        } else {
            content
                .background(fallback, in: shape)
                .clipShape(shape)
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard osrsContentsReveal.isVisuallyOpen(
                    isPresented: isPresented,
                    interactiveProgress: revealProgress
                ) else { return }
                if !isDismissTracking {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    isDismissTracking = true
                }
                let next = min(1, max(0, 1 - max(0, value.translation.width) / drawerWidth))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    interactiveProgress = next
                    if next > 0 {
                        isPresented = true
                    }
                }
            }
            .onEnded { value in
                defer { isDismissTracking = false }
                guard osrsContentsReveal.isVisuallyOpen(
                    isPresented: isPresented,
                    interactiveProgress: revealProgress
                ) else { return }
                let progress = min(1, max(0, 1 - max(0, value.translation.width) / drawerWidth))
                let shouldDismiss = osrsInteractiveArticleSwipe.shouldCommitContents(
                    progress: progress,
                    velocityX: value.velocity.width,
                    contentsOpenAtStart: true
                )
                settleDrawer(to: shouldDismiss ? 0 : 1, velocity: value.velocity.width)
            }
    }

    private func settleDrawer(to target: CGFloat, velocity: CGFloat) {
        let clamped = min(1, max(0, target))
        let animation = osrsContentsReveal.settleAnimation(
            from: interactiveProgress,
            to: clamped,
            velocity: velocity
        )
        withAnimation(animation) {
            interactiveProgress = clamped
            if clamped >= 1 {
                isPresented = true
            }
        } completion: {
            if clamped < 1 {
                isPresented = false
            } else {
                isPresented = true
            }
            interactiveProgress = clamped
        }
    }

    private func dismissContents() {
        settleDrawer(to: 0, velocity: 0)
    }

    private func fontForSection(_ section: TableOfContentsSection) -> Font {
        switch section.level {
        case 1:
            return .custom("Alegreya-Bold", size: 26).weight(.bold)
        case 2:
            return .custom("Alegreya-Bold", size: 20).weight(.bold)
        default:
            return .custom("Alegreya", size: 16).weight(.medium)
        }
    }
}

/// Vertical dotted rail replicating Android DottedLineView
struct osrsDottedRail: View {
    @Environment(\.osrsTheme) var osrsTheme

    var body: some View {
        GeometryReader { geometry in
            let dotRadius: CGFloat = 1
            let dotGap: CGFloat = 6
            let totalDotSpacing = (dotRadius * 2) + dotGap
            let numberOfDots = Int(geometry.size.height / totalDotSpacing)

            VStack(spacing: dotGap) {
                ForEach(0..<numberOfDots, id: \.self) { _ in
                    Circle()
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .foregroundColor(osrsTheme.onSurfaceVariant)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true

    return osrsContentsDrawerSimple(
        isPresented: $isPresented,
        interactiveProgress: .constant(1),
        sections: [
            TableOfContentsSection(id: "gameplay", title: "Gameplay", level: 1),
            TableOfContentsSection(id: "contents", title: "Contents", level: 2),
            TableOfContentsSection(id: "history", title: "History", level: 2)
        ],
        onSectionSelected: { _ in }
    )
}

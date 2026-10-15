import SwiftUI
import UIKit

/// iOS 27.1 Duo system-bar helpers.
///
/// Verified against Xcode 27.1 SDK interface names from SwiftUI / SwiftUICore
/// / UIKit (`toolbarVerticalBehavior`, `axisBehavior`, `toolbarVerticalEdge`,
/// `GeometryProxy.reservedRegions(kind:)`). Those symbols are not in the
/// iOS 27.0 SDK; this project links `iphoneos27.1` so they compile.
///
/// Runtime `#available(iOS 27.1, *)` keeps iOS 18–27.0 layout identical.
/// Non-Duo devices never get a vertical bar (`toolbarVerticalEdge` is nil),
/// so the modifiers are no-ops there even on 27.1.
enum osrsDuoSystemBars {
    /// Search / Random stay in `osrsTabSearchWithTrailingControl`, which is a
    /// `safeAreaInset` accessory, not `ToolbarContent`. SwiftUI's
    /// `axisBehavior(_:)` is a `ToolbarItem` / `ToolbarContent` modifier, so it
    /// cannot mark those accessories. Keeping them out of the system bar is
    /// what keeps them on the horizontal axis.
    static let searchRandomStayHorizontalReason = """
        Search/Random are osrsTabSearchWithTrailingControl accessories, not ToolbarItems; \
        axisBehavior(.horizontalOnly) does not apply. Do not move them into a system vertical bar.
        """
}

extension View {
    /// Opt system `TabView` / `NavigationStack` bars into the 27.1 vertical
    /// side rail. Default is already `.automatic`; calling it documents the
    /// SDK-tier opt-in. Pre-27.1 and non-Duo keep today's horizontal bars.
    @ViewBuilder
    func osrsSystemVerticalBarsEnabled() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.automatic)
        } else {
            self
        }
    }

    /// Keep bars horizontal. Apple's examples: video player, calculator-like
    /// UIs, and a sheet whose only item is Close/Done.
    @ViewBuilder
    func osrsSystemVerticalBarsDisabled() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }

    /// Extra overlay padding from active edge-hugging reserved regions.
    /// Interior fold divisions do not displace the overlay. Typical phone/iPad
    /// (no regions) add nothing.
    func osrsReservedRegionOverlayPadding(
        alreadyAccounted: UIEdgeInsets = .zero
    ) -> some View {
        modifier(
            osrsReservedRegionOverlayPaddingModifier(alreadyAccounted: alreadyAccounted)
        )
    }
}

/// Title-only / wide toolbar items stay on the remaining horizontal axis
/// instead of migrating into the vertical side rail. Non-Duo has no vertical
/// bar, so this does not change their appearance.
struct osrsHorizontalOnlyToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content

    init(
        placement: ToolbarItemPlacement,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarItem(placement: placement) {
                content
            }
            .axisBehavior(.horizontalOnly)
        } else {
            ToolbarItem(placement: placement) {
                content
            }
        }
    }
}

private struct osrsReservedRegionOverlayPaddingModifier: ViewModifier {
    let alreadyAccounted: UIEdgeInsets

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            osrsReservedRegionOverlayPaddingAvailable(
                alreadyAccounted: alreadyAccounted,
                content: content
            )
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct osrsReservedRegionOverlayPaddingAvailable<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    let alreadyAccounted: UIEdgeInsets
    let content: Content
    @State private var extraInsets = EdgeInsets()

    var body: some View {
        content
            .padding(extraInsets)
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                edgeInsets(from: proxy)
            } action: { extraInsets = $0 }
    }

    private func edgeInsets(from proxy: GeometryProxy) -> EdgeInsets {
        var accounted = alreadyAccounted
        // `toolbarVerticalEdge` is HorizontalEdge? in 27.1: `.leading`,
        // `.trailing`, or nil where the system never places a vertical bar.
        if let edge = toolbarVerticalEdge {
            switch edge {
            case .leading:
                accounted.left = max(accounted.left, 1)
            case .trailing:
                accounted.right = max(accounted.right, 1)
            @unknown default:
                break
            }
        }
        let ui = osrsWindowSceneGeometry.overlayEdgeInsetsAvoidingReservedRegions(
            containerSize: proxy.size,
            regions: snapshots(from: proxy),
            alreadyAccounted: accounted
        )
        return EdgeInsets(
            top: ui.top,
            leading: ui.left,
            bottom: ui.bottom,
            trailing: ui.right
        )
    }

    private func snapshots(
        from proxy: GeometryProxy
    ) -> [osrsWindowSceneGeometry.osrsReservedRegionSnapshot] {
        func snapshot(_ region: ReservedRegion) -> osrsWindowSceneGeometry.osrsReservedRegionSnapshot {
            osrsWindowSceneGeometry.osrsReservedRegionSnapshot(
                frame: region.frame,
                margins: UIEdgeInsets(
                    top: region.margins.top,
                    left: region.margins.leading,
                    bottom: region.margins.bottom,
                    right: region.margins.trailing
                ),
                isActive: region.isActive
            )
        }
        return Array(proxy.reservedRegions(kind: .division).map(snapshot))
            + Array(proxy.reservedRegions(kind: .occlusion).map(snapshot))
    }
}

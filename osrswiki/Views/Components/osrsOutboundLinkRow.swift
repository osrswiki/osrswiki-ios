import SwiftUI

/// Colored text-and-arrow affordance for outbound More links.
///
/// The link is the hit target. Surrounding copy and inset cards are not.
struct osrsOutboundLinkRow: View {
    @Environment(\.osrsTheme) private var osrsTheme
    let title: String
    var systemImage: String = "arrow.up.right"
    var alignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: systemImage)
            }
            .font(.osrsBody)
            .foregroundStyle(Color(osrsTheme.primary))
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}

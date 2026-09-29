import SwiftUI

/// Unified empty state. Two layouts:
/// - `.expanded`: centered icon + optional title + message, fills the region
///   (module lists, Disk Analyzer, History, management sheets).
/// - `.inline`: compact leading-aligned placeholder inside a card
///   (dashboard sections before a scan has run).
struct EmptyStateView: View {
    enum Layout {
        case expanded
        case inline
    }

    let icon: String
    var title: String? = nil
    let message: String
    var layout: Layout = .expanded
    var maxTextWidth: CGFloat = 400
    var tint: Color = AppTheme.accentText
    var actionTitle: String? = nil
    var actionIcon: String = "arrow.right"
    var action: (() -> Void)? = nil

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        switch layout {
        case .expanded:
            expanded
        case .inline:
            inline
        }
    }

    private var expanded: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.16), .clear], center: .center, startRadius: 4, endRadius: scale.space(70)))
                    .frame(width: scale.space(140), height: scale.space(140))
                Circle()
                    .fill(AppTheme.cardFill)
                    .overlay(Circle().strokeBorder(AppTheme.Hairline.standard, lineWidth: 1))
                    .frame(width: scale.space(72), height: scale.space(72))
                    .shadow(color: AppTheme.Shadow.card, radius: 12, y: 6)
                Image(systemName: icon)
                    .font(scale.font(28, weight: .medium))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(height: scale.space(100))
            .accessibilityHidden(true)

            if let title {
                Text(title)
                    .font(scale.font(17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(message)
                .font(title == nil ? scale.body : scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxTextWidth)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                SecondaryActionButton(title: actionTitle, systemImage: actionIcon, role: .accent, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title ?? message, systemImage: icon)
                .font(scale.font(14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            if title != nil {
                Text(message)
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.cardCompact)
        .background(
            AppTheme.Fill.subtle,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }
}

#if DEBUG
struct EmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No cleanup history",
                message: "Run a Quick Clean or Deep Clean to create a history record."
            )
            .frame(width: 480, height: 260)
            .background(AppTheme.base)
            .previewDisplayName("Expanded")

            EmptyStateView(
                icon: "shippingbox",
                message: "No formulae match the current filters"
            )
            .frame(width: 480, height: 200)
            .background(AppTheme.base)
            .previewDisplayName("Expanded — no title")

            EmptyStateView(
                icon: "tray",
                title: "No scan results yet",
                message: "Start a scan to browse reclaimable storage by category.",
                layout: .inline
            )
            .padding(24)
            .background(AppTheme.base)
            .previewDisplayName("Inline")
        }
    }
}
#endif

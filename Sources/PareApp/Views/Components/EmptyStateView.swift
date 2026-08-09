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
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(scale.font(36, weight: .light))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.45))

            if let title {
                Text(title)
                    .font(scale.font(16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(message)
                .font(title == nil ? scale.body : scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxTextWidth)
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

#Preview("Expanded") {
    EmptyStateView(
        icon: "clock.arrow.circlepath",
        title: "No cleanup history",
        message: "Run a Quick Clean or Deep Clean to create a history record."
    )
    .frame(width: 480, height: 260)
    .background(AppTheme.base)
}

#Preview("Expanded — no title") {
    EmptyStateView(
        icon: "shippingbox",
        message: "No formulae match the current filters"
    )
    .frame(width: 480, height: 200)
    .background(AppTheme.base)
}

#Preview("Inline") {
    EmptyStateView(
        icon: "tray",
        title: "No scan results yet",
        message: "Start a scan to browse reclaimable storage by category.",
        layout: .inline
    )
    .padding(24)
    .background(AppTheme.base)
}

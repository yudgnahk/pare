import SwiftUI

/// Unified status banner for operation lifecycle feedback
/// (cleaning / cleaned / undoing / undone / error / inline warnings).
///
/// - `.card` style renders inside a `GlassCard` (dashboard cleanup states).
/// - `.inline` style is a compact tinted strip inside an existing card.
struct StatusBanner<Accessory: View>: View {
    enum Kind {
        /// Indeterminate progress (spinner instead of an icon).
        case progress
        case success
        case info
        case warning
        case error

        var defaultIcon: String {
            switch self {
            case .progress: return "hourglass"
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .progress: return AppTheme.accent
            case .success: return AppTheme.success
            case .info: return AppTheme.accent
            case .warning: return AppTheme.warning
            case .error: return AppTheme.review
            }
        }
    }

    enum Style {
        case card
        case inline
    }

    let kind: Kind
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    var style: Style = .card
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.pareDisplayScale) private var scale

    init(
        kind: Kind,
        title: String,
        detail: String? = nil,
        icon: String? = nil,
        style: Style = .card,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.icon = icon
        self.style = style
        self.onDismiss = onDismiss
        self.accessory = accessory
    }

    var body: some View {
        switch style {
        case .card:
            GlassCard {
                row
            }
        case .inline:
            row
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    AppTheme.Fill.control,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                )
        }
    }

    private var row: some View {
        HStack(spacing: 14) {
            leadingIndicator

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(scale.font(14, weight: .semibold))
                    .foregroundStyle(style == .inline ? kind.tint : AppTheme.textPrimary)
                    .lineLimit(3)
                if let detail {
                    Text(detail)
                        .font(scale.font(12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            accessory()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(scale.font(12, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if kind == .progress {
            ProgressView()
                .scaleEffect(0.85)
        } else {
            Image(systemName: icon ?? kind.defaultIcon)
                .foregroundStyle(kind.tint)
                .font(scale.font(style == .inline ? 14 : 22))
        }
    }
}

extension StatusBanner where Accessory == EmptyView {
    init(
        kind: Kind,
        title: String,
        detail: String? = nil,
        icon: String? = nil,
        style: Style = .card,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            kind: kind,
            title: title,
            detail: detail,
            icon: icon,
            style: style,
            onDismiss: onDismiss,
            accessory: { EmptyView() }
        )
    }
}

struct StatusBanner_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack(spacing: 12) {
                StatusBanner(kind: .progress, title: "Moving files to Trash…")
                StatusBanner(
                    kind: .success,
                    title: "Cleaned 1.2 GB",
                    detail: "3 items skipped (policy check).",
                    onDismiss: {}
                ) {
                    Button("Undo") {}
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppTheme.accent)
                }
                StatusBanner(
                    kind: .warning,
                    title: "2 files restored.",
                    icon: "arrow.uturn.backward.circle.fill",
                    onDismiss: {}
                )
                StatusBanner(kind: .error, title: "Cleanup failed: permission denied.", onDismiss: {})
            }
            .padding(24)
            .background(AppTheme.base)
            .frame(width: 560)
            .previewDisplayName("Card states")

            StatusBanner(
                kind: .warning,
                title: "Finder could not reveal that path.",
                style: .inline
            )
            .padding(24)
            .background(AppTheme.base)
            .frame(width: 480)
            .previewDisplayName("Inline warning")
        }
    }
}

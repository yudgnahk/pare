import SwiftUI
import PareCore

/// Unified row for selectable scan candidates: checkbox, risk, path, size, reveal, exclude.
struct SelectableCandidateRow: View {
    let path: String
    let displayName: String
    let subtitle: String?
    let sizeText: String
    let riskLevel: RiskLevel
    let isSelected: Bool
    let isSelectable: Bool
    let canReveal: Bool
    let indent: CGFloat
    let onToggle: () -> Void
    let onReveal: () -> Void
    var onExclude: (() -> Void)? = nil
    /// Folder-style leading icon when this row is a bulk folder group.
    var isFolder: Bool = false
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Color.clear.frame(width: indent)

            Button(action: onToggle) {
                Image(systemName: checkboxIcon)
                    .font(scale.font(16, weight: .semibold))
                    .foregroundStyle(checkboxColor)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            .help(isSelectable
                  ? (isFolder ? "Select all safe items in this folder" : "Include in Clean selected")
                  : "Advanced items cannot be cleaned here")

            Image(systemName: isFolder ? "folder.fill" : riskIcon)
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(isFolder ? AppTheme.accent : riskColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(scale.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Text(riskBadgeLabel)
                .font(scale.badge)
                .tracking(0.3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(riskColor.opacity(0.2), in: Capsule(style: .continuous))
                .foregroundStyle(riskColor)

            Text(sizeText)
                .font(scale.font(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            Button(action: onReveal) {
                Image(systemName: "folder")
                    .font(scale.font(12, weight: .semibold))
                    .foregroundStyle(canReveal ? AppTheme.accent : AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canReveal)
            .help("Show in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.55))
        )
        .contextMenu {
            if isSelectable {
                Button(action: onToggle) {
                    Label(isSelected ? "Deselect" : "Select for clean", systemImage: "checkmark.circle")
                }
            }
            Button(action: onReveal) {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(!canReveal)
            if let onExclude {
                Button(action: onExclude) {
                    Label("Exclude from Scans", systemImage: "eye.slash")
                }
            }
        }
    }

    private var checkboxIcon: String {
        if !isSelectable { return "circle.slash" }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var checkboxColor: Color {
        if !isSelectable { return AppTheme.textTertiary }
        return isSelected ? AppTheme.accent : AppTheme.textSecondary
    }

    private var riskBadgeLabel: String {
        switch riskLevel {
        case .safe: return "SAFE"
        case .review: return "REVIEW"
        case .advanced: return "ADV"
        }
    }

    private var riskColor: Color {
        switch riskLevel {
        case .safe: return AppTheme.success
        case .review: return AppTheme.warning
        case .advanced: return AppTheme.review
        }
    }

    private var riskIcon: String {
        switch riskLevel {
        case .safe: return "doc.fill"
        case .review: return "doc.badge.ellipsis"
        case .advanced: return "exclamationmark.triangle.fill"
        }
    }
}

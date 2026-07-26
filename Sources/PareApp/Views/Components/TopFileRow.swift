import SwiftUI
import PareCore

struct TopFileRow: View {
    let path: String
    let category: String
    let reason: String
    let riskLevel: RiskLevel
    let sizeText: String
    let lastUsedText: String
    var onExclude: (() -> Void)? = nil
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.panelSecondary)
                    .frame(width: scale.scaled(34), height: scale.scaled(34))

                Image(systemName: riskIcon)
                    .foregroundStyle(riskColor)
                    .font(scale.font(14, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(scale.rowMono)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(reason)
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 8) {
                    Text(category)
                    Text("•")
                    Text(lastUsedText)
                }
                .font(scale.rowMeta)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.85))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(sizeText)
                    .font(scale.font(14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(riskLabel)
                    .font(scale.badge)
                    .tracking(0.4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(riskColor.opacity(0.22), in: Capsule(style: .continuous))
                    .foregroundStyle(riskColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(riskBorderColor, lineWidth: 1)
                )
        )
        .contextMenu {
            if let onExclude {
                Button(action: onExclude) {
                    Label("Exclude from Scans", systemImage: "eye.slash")
                }
            }
        }
    }

    private var riskLabel: String {
        switch riskLevel {
        case .safe:     return "SAFE"
        case .review:   return "REVIEW"
        case .advanced: return "ADVANCED"
        }
    }

    private var riskColor: Color {
        switch riskLevel {
        case .safe:     return AppTheme.success
        case .review:   return AppTheme.warning
        case .advanced: return AppTheme.review
        }
    }

    private var riskIcon: String {
        switch riskLevel {
        case .safe:     return "doc.fill"
        case .review:   return "doc.badge.ellipsis"
        case .advanced: return "exclamationmark.triangle.fill"
        }
    }

    private var riskBorderColor: Color {
        switch riskLevel {
        case .safe:     return Color.white.opacity(0.08)
        case .review:   return AppTheme.warning.opacity(0.18)
        case .advanced: return AppTheme.review.opacity(0.22)
        }
    }
}

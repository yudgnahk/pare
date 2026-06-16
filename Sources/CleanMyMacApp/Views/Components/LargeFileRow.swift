import SwiftUI
import CleanMyMacCore

struct LargeFileRow: View {
    let path: String
    let sizeText: String
    let lastUsedText: String
    let riskLevel: RiskLevel
    let reason: String
    let canReveal: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(riskBadgeLabel)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(riskColor.opacity(0.2), in: Capsule(style: .continuous))
                        .foregroundStyle(riskColor)

                    Text(reason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Text(path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(sizeText)
                    Text("•")
                    Text(lastUsedText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 10)

            Button("Show in Finder", action: onReveal)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(!canReveal)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(riskBorderColor, lineWidth: 1)
                )
        )
    }

    private var riskBadgeLabel: String {
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

    private var riskBorderColor: Color {
        switch riskLevel {
        case .safe:     return Color.white.opacity(0.08)
        case .review:   return AppTheme.warning.opacity(0.15)
        case .advanced: return AppTheme.review.opacity(0.22)
        }
    }
}

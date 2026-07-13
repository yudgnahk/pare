import SwiftUI
import PareCore

struct LargeFileRow: View {
    let path: String
    let sizeText: String
    let lastUsedText: String
    let riskLevel: RiskLevel
    let reason: String
    let canReveal: Bool
    let onReveal: () -> Void
    var onExclude: (() -> Void)? = nil

    var body: some View {
        // Stack path + action on narrow widths so the Finder button never clips.
        ViewThatFits(in: .horizontal) {
            wideLayout
            compactLayout
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.7))
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
            Button(action: onReveal) {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(!canReveal)
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            fileMeta
            Spacer(minLength: 10)
            revealButton
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            fileMeta
            revealButton
        }
    }

    private var fileMeta: some View {
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
    }

    private var revealButton: some View {
        SecondaryActionButton(
            title: "Show in Finder",
            systemImage: "folder",
            role: .accent,
            isEnabled: canReveal,
            action: onReveal
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

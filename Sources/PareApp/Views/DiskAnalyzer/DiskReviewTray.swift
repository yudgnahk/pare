import SwiftUI
import PareCore

/// Bottom bar showing the Disk Analyzer's review tray totals, plus Clear and
/// Review & Clean actions. Builds the `CleanConfirmationSheet.Config` for the confirm step.
struct DiskReviewTray: View {
    let count: Int
    let totalBytes: Int64
    let reviewRiskCount: Int
    let findings: [ScanFinding]
    let formatBytes: (Int64) -> String
    let onClear: () -> Void
    let onReviewAndClean: () -> Void
    var onRemove: (ScanFinding) -> Void = { _ in }
    var isCleaning = false

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        VStack(spacing: 6) {
            if !findings.isEmpty {
                findingChips
            }
            actionBar
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.panelSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.Hairline.standard).frame(height: 1)
        }
    }

    private var findingChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(findings, id: \.path) { finding in
                    findingChip(finding)
                }
            }
        }
    }

    private func findingChip(_ finding: ScanFinding) -> some View {
        HStack(spacing: 6) {
            Text(URL(fileURLWithPath: finding.path).lastPathComponent)
                .font(scale.font(11, weight: .medium))
                .lineLimit(1)
                .help(finding.path)
            Button { onRemove(finding) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(scale.font(11))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(isCleaning)
            .help("Remove from Review")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.Fill.subtle, in: Capsule())
    }

    private var actionBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "tray.full.fill")
                .font(scale.font(14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(summary)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: AppTheme.Spacing.sm)

            SecondaryActionButton(title: "Clear", systemImage: "xmark", isEnabled: !isCleaning, action: onClear)
            SecondaryActionButton(
                title: "Review & Clean",
                systemImage: "checkmark.circle.fill",
                role: reviewRiskCount > 0 ? .destructive : .accent,
                isEnabled: !isCleaning,
                action: onReviewAndClean
            )
        }
    }

    private var summary: String {
        let itemWord = count == 1 ? "item" : "items"
        var text = "Review: \(count) \(itemWord) · \(formatBytes(totalBytes))"
        if reviewRiskCount > 0 {
            text += " · \(reviewRiskCount) review-risk"
        }
        return text
    }
}

/// Builds the confirmation sheet config for the review tray's contents.
enum DiskReviewTrayConfirmation {
    static func config(
        count: Int,
        totalBytes: Int64,
        reviewRiskCount: Int,
        paths: [String],
        formatBytes: (Int64) -> String
    ) -> CleanConfirmationSheet.Config {
        let itemWord = count == 1 ? "Smart Scan finding" : "Smart Scan findings"
        var infoLines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "tray.and.arrow.down.fill",
                color: AppTheme.accent,
                text: "\(count) \(itemWord) (\(formatBytes(totalBytes))) will be moved to the Trash."
            ),
            .init(
                icon: "folder",
                color: AppTheme.accent,
                text: "Each finding is cleaned whole, including anything inside it you did not select."
            ),
            .init(
                icon: "arrow.uturn.backward",
                color: AppTheme.accent,
                text: "You can restore everything from the Trash afterward."
            )
        ]
        let hasReviewRisk = reviewRiskCount > 0
        if hasReviewRisk {
            infoLines.append(
                .init(
                    icon: "exclamationmark.triangle",
                    color: AppTheme.review,
                    text: "\(reviewRiskCount) review-risk \(reviewRiskCount == 1 ? "item" : "items") included."
                )
            )
        }
        if paths.isEmpty {
            infoLines.append(.init(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "The selected findings are no longer in the latest Smart Scan and will not be cleaned."))
        }
        infoLines.append(contentsOf: paths.sorted().map { path in
            .init(
                icon: "doc.text",
                color: AppTheme.textSecondary,
                text: path
            )
        })

        return CleanConfirmationSheet.Config(
            title: "Review & Clean",
            subtitle: "\(count) \(itemWord) selected",
            headerIcon: "tray.and.arrow.down.fill",
            headerTint: hasReviewRisk ? AppTheme.review : AppTheme.accent,
            warningText: hasReviewRisk
                ? "This includes REVIEW-risk items. Proceed only if you have reviewed them."
                : nil,
            infoLines: infoLines,
            confirmTint: hasReviewRisk ? AppTheme.review : AppTheme.success
        )
    }
}

#if DEBUG
struct DiskReviewTray_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DiskReviewTray(
                count: 3,
                totalBytes: 1_200_000_000,
                reviewRiskCount: 0,
                findings: [],
                formatBytes: { "\($0 / 1_000_000) MB" },
                onClear: {},
                onReviewAndClean: {}
            )
            .environment(\.colorScheme, .light)
            .previewDisplayName("Light")

            DiskReviewTray(
                count: 5,
                totalBytes: 2_400_000_000,
                reviewRiskCount: 2,
                findings: [],
                formatBytes: { "\($0 / 1_000_000) MB" },
                onClear: {},
                onReviewAndClean: {}
            )
            .environment(\.colorScheme, .dark)
            .previewDisplayName("Dark — review risk")
        }
        .frame(width: 640)
    }
}
#endif

import SwiftUI

/// Parameterized dark-themed clean confirmation sheet.
///
/// One component replaces the three ~85%-identical sheets (Quick Clean,
/// Deep Clean, Clean Selected): icon header, optional warning banner,
/// info-line list, and Cancel / confirm footer.
struct CleanConfirmationSheet: View {
    struct InfoLine: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let text: String
    }

    struct Size {
        var minWidth: CGFloat = 400
        var idealWidth: CGFloat = 440
        var maxWidth: CGFloat = AppTheme.Sheet.standardWidth
        var minHeight: CGFloat = 300
        var idealHeight: CGFloat = 340
        var maxHeight: CGFloat = AppTheme.Sheet.operationHeight
    }

    struct Config {
        var title: String
        var subtitle: String
        var subtitleColor: Color = AppTheme.textSecondary
        var headerIcon: String
        var headerTint: Color
        /// Prominent tinted warning banner above the info lines (Deep Clean).
        var warningText: String? = nil
        var infoLines: [InfoLine]
        var confirmTitle: String = "Move to Trash"
        var confirmTint: Color = AppTheme.success
        var confirmForeground: Color = .black
        var size = Size()
    }

    let config: Config
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 18) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let warningText = config.warningText {
                            warningBanner(warningText)
                        }

                        infoList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)

                footer
            }
            .padding(28)
        }
        .frame(
            minWidth: config.size.minWidth,
            idealWidth: config.size.idealWidth,
            maxWidth: config.size.maxWidth,
            minHeight: config.size.minHeight,
            idealHeight: config.size.idealHeight,
            maxHeight: config.size.maxHeight
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(config.headerTint.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: config.headerIcon)
                    .foregroundStyle(config.headerTint)
                    .font(scale.font(20, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(config.title)
                    .font(scale.sheetTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(config.subtitle)
                    .font(scale.caption)
                    .foregroundStyle(config.subtitleColor)
            }
        }
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.review)
                .font(scale.font(16, weight: .bold))
            Text(text)
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.cardCompact)
        .background(
            AppTheme.review.opacity(0.12),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }

    private var infoList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(config.infoLines) { line in
                infoRow(line)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            AppTheme.Fill.subtle,
            in: RoundedRectangle(cornerRadius: AppTheme.Spacing.cardCompact, style: .continuous)
        )
    }

    private func infoRow(_ line: InfoLine) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: line.icon)
                .foregroundStyle(line.color)
                .font(scale.font(14, weight: .semibold))
                .frame(width: 20)
            Text(line.text)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.borderless)
                .font(scale.font(14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    AppTheme.Fill.control,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                )
                .keyboardShortcut(.cancelAction)

            Button(config.confirmTitle, action: onConfirm)
                .font(scale.font(14, weight: .bold))
                .foregroundStyle(config.confirmForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    config.confirmTint,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                )
                .buttonStyle(.borderless)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
struct CleanConfirmationSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CleanConfirmationSheet(
                config: .init(
                    title: "Quick Clean",
                    subtitle: "Safe-risk findings only",
                    headerIcon: "trash.fill",
                    headerTint: AppTheme.success,
                    infoLines: [
                        .init(
                            icon: "checkmark.shield.fill",
                            color: AppTheme.success,
                            text: "128 safe-risk files will be moved to Trash."
                        ),
                        .init(
                            icon: "exclamationmark.triangle",
                            color: AppTheme.warning,
                            text: "Review and Advanced findings are never touched."
                        ),
                        .init(
                            icon: "arrow.uturn.backward",
                            color: AppTheme.accent,
                            text: "You can undo immediately after cleanup via the Undo button."
                        )
                    ]
                ),
                onCancel: {},
                onConfirm: {}
            )
            .previewDisplayName("Quick Clean")

            CleanConfirmationSheet(
                config: .init(
                    title: "Deep Clean",
                    subtitle: "Safe + Review-risk findings",
                    subtitleColor: AppTheme.review,
                    headerIcon: "bolt.fill",
                    headerTint: AppTheme.review,
                    warningText: "Deep Clean includes REVIEW-risk items. Proceed only if you have reviewed them.",
                    infoLines: [
                        .init(
                            icon: "bolt.fill",
                            color: AppTheme.review,
                            text: "212 files will be moved to Trash (34 review-risk)."
                        )
                    ],
                    confirmTint: AppTheme.review,
                    confirmForeground: .white,
                    size: .init(
                        minWidth: 420,
                        idealWidth: 480,
                        maxWidth: AppTheme.Sheet.wideWidth,
                        minHeight: 380,
                        idealHeight: 420,
                        maxHeight: 560
                    )
                ),
                onCancel: {},
                onConfirm: {}
            )
            .previewDisplayName("Deep Clean")
        }
    }
}
#endif

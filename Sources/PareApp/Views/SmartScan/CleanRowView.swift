import SwiftUI
import PareCore

/// One folder in a clean category: checkbox, owner icon, `Owner · kind`, Review tag, path line, size, reveal.
struct CleanRowView: View, Equatable {
    let row: CategoryFolderRow
    let owner: FolderOwner
    let appPath: String?
    let title: String
    let subtitle: String
    let sizeText: String
    let selectionState: CategorySelectState
    let canReveal: Bool
    let isReview: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void
    @Environment(\.pareDisplayScale) private var scale

    nonisolated static func == (lhs: CleanRowView, rhs: CleanRowView) -> Bool {
        lhs.row == rhs.row && lhs.owner == rhs.owner && lhs.appPath == rhs.appPath
            && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.sizeText == rhs.sizeText
            && lhs.selectionState == rhs.selectionState && lhs.canReveal == rhs.canReveal && lhs.isReview == rhs.isReview
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if row.isSelectable {
                Button(action: onToggle) {
                    Image(systemName: TriSelectionState(selectionState).systemImage)
                        .font(scale.font(16, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
                .help("Select this folder for Clean selected")
                .accessibilityLabel(SelectAccessibility.folderLabel(path: title))
                .accessibilityValue(SelectAccessibility.stateText(TriSelectionState(selectionState)))
            } else {
                Color.clear.frame(width: 20, height: 1)
            }

            OwnerIconView(owner: owner, appPath: appPath, size: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(scale.rowTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isReview {
                        Text("Review")
                            .font(scale.badge)
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.warning.opacity(0.16), in: Capsule())
                            .fixedSize()
                            .help("Starts unticked. May sign you out or remove data.")
                    }
                }
                Text(subtitle)
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.displayPath)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .help("Show folder in Finder")
            .accessibilityLabel("Show \(title) in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.55))
        )
    }
}

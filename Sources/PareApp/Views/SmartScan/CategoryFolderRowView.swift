import SwiftUI
import PareCore

// MARK: - CategoryFolderRowView (lightweight, equatable inputs)

struct CategoryFolderRowView: View, Equatable {
    let row: CategoryFolderRow
    let category: ScanCategory
    let sizeText: String
    let selectionState: CategorySelectState
    let canReveal: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void
    @Environment(\.pareDisplayScale) private var scale

    nonisolated static func == (lhs: CategoryFolderRowView, rhs: CategoryFolderRowView) -> Bool {
        lhs.row == rhs.row
            && lhs.category == rhs.category
            && lhs.sizeText == rhs.sizeText
            && lhs.selectionState == rhs.selectionState
            && lhs.canReveal == rhs.canReveal
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: checkboxIcon)
                    .font(scale.font(16, weight: .semibold))
                    .foregroundStyle(row.isSelectable ? AppTheme.accent : AppTheme.textTertiary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .disabled(!row.isSelectable)
            .help(row.isSafeFolder
                  ? "Select this entire folder for Clean selected"
                  : "Select cleanable items in this folder")

            IconTile(category: category, size: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayPath)
                    .font(scale.rowMono)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(row.itemCount == 1
                     ? "1 item · \(riskLabel)"
                     : "\(row.itemCount) items rolled up · \(riskLabel)")
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
            }

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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.55))
        )
        .contextMenu {
            if row.isSelectable {
                Button(action: onToggle) {
                    Label(
                        selectionState == .all ? "Deselect folder" : "Select folder",
                        systemImage: "checkmark.circle"
                    )
                }
            }
            Button(action: onReveal) {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private var checkboxIcon: String {
        switch selectionState {
        case .all: return "checkmark.circle.fill"
        case .partial: return "minus.circle.fill"
        case .none: return "circle"
        }
    }

    private var riskLabel: String {
        switch row.riskLevel {
        case .safe: return "SAFE"
        case .review: return "REVIEW"
        case .advanced: return "ADVANCED"
        }
    }
}

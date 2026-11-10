import SwiftUI
import PareCore

/// One owner (app, project, tool, macOS or Other): header checkbox for its safe folders, then its folder rows.
struct OwnerGroupSection: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    let group: OwnerGroup
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        let isExpanded = viewModel.isOwnerGroupExpanded(group)
        VStack(alignment: .leading, spacing: 6) {
            header(isExpanded: isExpanded)
            if isExpanded {
                rows
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(isExpanded ? AppTheme.Hairline.faint : AppTheme.Hairline.faint.opacity(0.5))
        )
    }

    @ViewBuilder
    private func header(isExpanded: Bool) -> some View {
        let size = viewModel.formattedOwnerSize(bytes: group.totalBytes, isPartial: group.hasPartialSize)
        let state = TriSelectionState(viewModel.ownerGroupSelectionState(group))
        if group.owner.kind == .project {
            ProjectGroupHeader(
                group: group,
                sizeText: size,
                isExpanded: isExpanded,
                selection: state,
                activityText: viewModel.projectActivityText(for: group),
                selectHelp: viewModel.groupHoldReason(safeFolderIds: group.safeFolderIds) ?? Self.selectHelp(group),
                onToggleSelect: { viewModel.toggleOwnerGroup(group) },
                onToggleExpand: { viewModel.toggleOwnerGroupExpanded(group) }
            )
        } else {
            DisclosureSelectRow(
                style: .category,
                title: group.owner.displayName,
                badgeText: ScanDashboardViewModel.folderBadge(group.folderIds.count),
                sizeText: size,
                isExpanded: isExpanded,
                selection: state,
                isSelectable: group.isSelectable,
                selectHelp: viewModel.groupHoldReason(safeFolderIds: group.safeFolderIds) ?? Self.selectHelp(group),
                onToggleSelect: { viewModel.toggleOwnerGroup(group) },
                onToggleExpand: { viewModel.toggleOwnerGroupExpanded(group) }
            ) {
                Self.icon(for: group.owner, scale: scale)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 5) {
            ForEach(group.rows) { ownerRow in
                CategoryFolderRowView(
                    row: ownerRow.row,
                    category: ownerRow.category,
                    sizeText: viewModel.formattedFolderSize(ownerRow.row),
                    selectionState: viewModel.folderSelectionState(ownerRow.row),
                    canReveal: viewModel.canReveal(path: ownerRow.row.folderPath),
                    onToggle: { viewModel.toggleFolder(ownerRow.row) },
                    onReveal: { viewModel.revealInFinder(path: ownerRow.row.folderPath) },
                    chip: CategoryStyle.chipLabel(for: ownerRow.category),
                    label: ownerRow.label,
                    holdReason: viewModel.holdReason(forFolderId: ownerRow.id)
                )
            }
            if group.hiddenRowCount > 0 {
                Text("+\(group.hiddenRowCount) more")
                    .font(scale.micro)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 30)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 8)
        .padding(.bottom, 4)
    }

    static func selectHelp(_ group: OwnerGroup) -> String {
        group.isSelectable ? "Select safe folders" : "Review items: tick one by one"
    }

    static func ownerHelp(_ owner: FolderOwner) -> String {
        switch owner.kind {
        case .macOS: return "Owned by macOS"
        case .other: return "Owner unknown"
        case .app, .project, .tool: return ""
        }
    }

    static func icon(for owner: FolderOwner, scale: DisplayScale) -> some View {
        Image(systemName: OwnerIcon.symbol(for: owner))
            .font(scale.font(14, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 22)
            .help(ownerHelp(owner))
    }
}

extension TriSelectionState {
    init(_ state: CategorySelectState) {
        switch state {
        case .all: self = .all
        case .partial: self = .partial
        case .none: self = .none
        }
    }
}

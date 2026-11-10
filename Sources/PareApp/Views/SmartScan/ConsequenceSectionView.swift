import SwiftUI
import PareCore

/// One consequence group: header with a safe-only checkbox and `selected / total`, its rows, then the fold row.
struct ConsequenceSectionView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    let section: ConsequenceSection
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        let group = section.group
        let isExpanded = viewModel.isConsequenceExpanded(group)
        VStack(alignment: .leading, spacing: 6) {
            DisclosureSelectRow(
                style: .category,
                title: ScanDashboardViewModel.consequenceTitle(group),
                subtitle: ScanDashboardViewModel.consequenceSubtitle(group),
                sizeText: viewModel.consequenceSizeText(section),
                isExpanded: isExpanded,
                selection: TriSelectionState(viewModel.consequenceSelectionState(section)),
                isSelectable: section.isSelectable,
                selectHelp: viewModel.consequenceSelectHelp(section),
                onToggleSelect: { viewModel.toggleConsequenceSection(section) },
                onToggleExpand: { viewModel.toggleConsequenceExpanded(group) }
            ) {
                Self.groupIcon(group, scale: scale)
            }
            if isExpanded {
                rows
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Hairline.faint.opacity(isExpanded ? 1 : 0.5))
        )
    }

    private var rows: some View {
        VStack(spacing: 5) {
            ForEach(section.rows) { rowView($0) }
            if section.hiddenRowCount > 0 { moreText(section.hiddenRowCount) }
            if section.smallRowCount > 0 { smallRows }
        }
        .padding(.leading, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var smallRows: some View {
        let group = section.group
        let isExpanded = viewModel.isSmallRowsExpanded(group)
        DisclosureSelectRow(
            style: .tool,
            title: ScanDashboardViewModel.smallRowsTitle(section.smallRowCount),
            sizeText: ScanReportPresenter.formatFindingSize(
                bytes: section.smallBytes, isComplete: !section.smallHasPartialSize
            ),
            isExpanded: isExpanded,
            selection: TriSelectionState(viewModel.smallRowsSelectionState(section)),
            isSelectable: !section.smallSafeFolderIds.isEmpty,
            selectHelp: viewModel.consequenceSelectHelp(section),
            onToggleSelect: { viewModel.toggleSmallRows(section) },
            onToggleExpand: { viewModel.toggleSmallRowsExpanded(group) }
        ) {
            Image(systemName: "square.stack.3d.down.right")
                .font(scale.font(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20)
        }
        if isExpanded {
            VStack(spacing: 5) {
                ForEach(section.smallRows) { rowView($0) }
                if section.hiddenSmallRowCount > 0 { moreText(section.hiddenSmallRowCount) }
            }
            .padding(.leading, 12)
        }
    }

    private func rowView(_ row: ConsequenceRow) -> some View {
        let folder = ScanDashboardViewModel.folderRow(row)
        return ConsequenceRowView(
            row: folder,
            owner: row.owner,
            appPath: viewModel.appIconPath(for: row.owner),
            title: ScanDashboardViewModel.rowTitle(row),
            subtitle: viewModel.rowSubtitle(row),
            sizeText: viewModel.formattedFolderSize(folder),
            selectionState: viewModel.folderSelectionState(folder),
            canReveal: viewModel.canReveal(path: row.record.folderPath),
            onToggle: { viewModel.toggleFolder(folder) },
            onReveal: { viewModel.revealInFinder(path: row.record.folderPath) }
        )
    }

    private func moreText(_ count: Int) -> some View {
        Text("+\(count) more")
            .font(scale.micro)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 30)
            .padding(.top, 2)
    }

    static func groupIcon(_ group: ConsequenceGroup, scale: DisplayScale) -> some View {
        let (symbol, tint): (String, Color) = {
            switch group {
            case .rebuildsItself: return ("arrow.triangle.2.circlepath", AppTheme.success)
            case .slowerNextBuild: return ("hammer.fill", AppTheme.accent)
            case .needsALook: return ("eye.fill", AppTheme.warning)
            case .sizeOnly: return ("ruler", AppTheme.textTertiary)
            }
        }()
        return Image(systemName: symbol)
            .font(scale.font(14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22)
    }
}

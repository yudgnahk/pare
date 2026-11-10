import SwiftUI
import PareCore

/// One clean category: header with a safe-only checkbox and `selected / total`, its rows, then the fold row.
struct CleanSectionView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    let section: CleanSection
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        let group = section.group
        let isExpanded = viewModel.isCleanExpanded(group)
        VStack(alignment: .leading, spacing: 6) {
            DisclosureSelectRow(
                style: .category,
                title: ScanDashboardViewModel.cleanTitle(group),
                subtitle: ScanDashboardViewModel.cleanSubtitle(group),
                sizeText: viewModel.cleanSizeText(section),
                isExpanded: isExpanded,
                selection: TriSelectionState(viewModel.cleanSelectionState(section)),
                isSelectable: section.isSelectable,
                selectHelp: viewModel.cleanSelectHelp(section),
                onToggleSelect: { viewModel.toggleCleanSection(section) },
                onToggleExpand: { viewModel.toggleCleanExpanded(group) }
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
            selectHelp: viewModel.cleanSelectHelp(section),
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

    private func rowView(_ row: CleanRow) -> some View {
        let folder = ScanDashboardViewModel.folderRow(row)
        return CleanRowView(
            row: folder,
            owner: row.owner,
            appPath: viewModel.appIconPath(for: row.owner),
            title: ScanDashboardViewModel.rowTitle(row),
            subtitle: viewModel.rowSubtitle(row),
            sizeText: viewModel.formattedFolderSize(folder),
            selectionState: viewModel.folderSelectionState(folder),
            canReveal: viewModel.canReveal(path: row.record.folderPath),
            isReview: row.record.riskLevel == .review,
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

    static func groupIcon(_ group: CleanCategory, scale: DisplayScale) -> some View {
        let (symbol, tint): (String, Color) = {
            switch group {
            case .appCaches: return ("tray.full.fill", AppTheme.accent)
            case .communication: return ("message.fill", AppTheme.accent)
            case .developerTools: return ("hammer.fill", AppTheme.accent)
            case .projects: return ("folder.fill", AppTheme.accent)
            case .aiTools: return ("brain.head.profile", AppTheme.accent)
            case .siteData: return ("globe", AppTheme.warning)
            case .oldVersions: return ("archivebox.fill", AppTheme.warning)
            case .system: return ("applelogo", AppTheme.textSecondary)
            case .sizeOnly: return ("ruler", AppTheme.textTertiary)
            }
        }()
        return Image(systemName: symbol)
            .font(scale.font(14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22)
    }
}

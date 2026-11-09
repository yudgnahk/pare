import SwiftUI
import PareCore

/// Results grouped by scan category, then tool, then folder.
struct CategoryBrowserList: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        // Keep collapsed by default — only expanded categories show folder rows.
        VStack(spacing: 8) {
            ForEach(viewModel.summaries) { summary in
                categoryFolderSection(summary)
            }
        }
    }

    private func categoryFolderSection(_ summary: SummaryItem) -> some View {
        let isExpanded = viewModel.isCategoryExpanded(summary.category)
        let selectionState = viewModel.categorySelectionState(summary.category)

        return VStack(alignment: .leading, spacing: 6) {
            DisclosureSelectRow(
                style: .category,
                title: summary.category.rawValue,
                badgeText: categoryBadge(summary),
                sizeText: viewModel.formattedBytes(summary.reclaimableBytes),
                isExpanded: isExpanded,
                selection: TriSelectionState(selectionState),
                selectHelp: "Toggle all SAFE folders in this category",
                onToggleSelect: { viewModel.toggleCategory(summary.category) },
                onToggleExpand: { viewModel.toggleCategoryExpanded(summary.category) }
            ) {
                IconTile(category: summary.category, size: 28)
            }

            if isExpanded {
                if viewModel.usesToolGrouping(for: summary.category) {
                    let groups = viewModel.toolGroups(for: summary.category)
                    if groups.isEmpty {
                        Text("No reclaimable folders in this category")
                            .font(scale.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.leading, 30)
                            .padding(.bottom, 4)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(groups) { group in
                                toolGroupSection(group)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.bottom, 4)
                    }
                } else {
                    flatFolderList(for: summary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(isExpanded ? AppTheme.Hairline.faint : AppTheme.Hairline.faint.opacity(0.5))
        )
    }

    private func flatFolderList(for summary: SummaryItem) -> some View {
        let rows = viewModel.folderRows(for: summary.category)
        return Group {
            if rows.isEmpty {
                Text("No reclaimable folders in this category")
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 30)
                    .padding(.bottom, 4)
            } else {
                VStack(spacing: 5) {
                    ForEach(rows) { row in
                        CategoryFolderRowView(
                            row: row,
                            category: summary.category,
                            sizeText: viewModel.formattedFolderSize(row),
                            selectionState: viewModel.folderSelectionState(row),
                            canReveal: viewModel.canReveal(path: row.folderPath),
                            onToggle: { viewModel.toggleFolder(row) },
                            onReveal: { viewModel.revealInFinder(path: row.folderPath) }
                        )
                    }
                    let rolled = rows.reduce(0) { $0 + $1.itemCount }
                    if summary.fileCount > rolled {
                        Text("Showing largest \(rows.count) folders · \(summary.fileCount) files rolled up")
                            .font(scale.micro)
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.leading, 30)
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, 8)
                .padding(.bottom, 4)
            }
        }
    }

    private func toolGroupSection(_ group: CategoryToolGroup) -> some View {
        let isExpanded = viewModel.isToolGroupExpanded(group)
        let selectionState = viewModel.toolGroupSelectionState(group)

        return VStack(alignment: .leading, spacing: 4) {
            DisclosureSelectRow(
                style: .tool,
                title: group.toolName,
                badgeText: "\(group.folderCount) folder\(group.folderCount == 1 ? "" : "s")",
                sizeText: viewModel.formattedBytes(group.totalBytes),
                isExpanded: isExpanded,
                selection: TriSelectionState(selectionState),
                isSelectable: group.isSelectable,
                selectHelp: "Select safe folders under \(group.toolName)",
                onToggleSelect: { viewModel.toggleToolGroup(group) },
                onToggleExpand: { viewModel.toggleToolGroupExpanded(group) }
            ) {
                Image(systemName: OwnerIcon.symbol(forName: group.toolName))
                    .font(scale.font(12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 18)
            }

            if isExpanded {
                let rows = viewModel.folderRows(for: group)
                VStack(spacing: 4) {
                    ForEach(rows) { row in
                        CategoryFolderRowView(
                            row: row,
                            category: group.category,
                            sizeText: viewModel.formattedFolderSize(row),
                            selectionState: viewModel.folderSelectionState(row),
                            canReveal: viewModel.canReveal(path: row.folderPath),
                            onToggle: { viewModel.toggleFolder(row) },
                            onReveal: { viewModel.revealInFinder(path: row.folderPath) }
                        )
                    }
                    if rows.isEmpty {
                        Text("No folder rows for this tool")
                            .font(scale.micro)
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.leading, 28)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private func categoryBadge(_ summary: SummaryItem) -> String {
        if viewModel.usesToolGrouping(for: summary.category) {
            let tools = viewModel.toolGroups(for: summary.category).count
            if tools > 0 {
                return "\(tools) tool\(tools == 1 ? "" : "s")"
            }
        }
        if summary.folderCount > 0 {
            return "\(summary.folderCount) folder\(summary.folderCount == 1 ? "" : "s")"
        }
        return "\(summary.fileCount) item\(summary.fileCount == 1 ? "" : "s")"
    }
}

import AppKit
import Foundation
import SwiftUI
import PareCore

struct ScanDashboardView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @StateObject private var exclusionListViewModel = ExclusionListViewModel()
    @Environment(\.pareDisplayScale) private var scale
    @State private var showSettings = false
    @State private var showProjectPaths = false

    /// Calm hero when idle or first-time scan; rich results after success.
    private var showsHero: Bool {
        switch viewModel.state {
        case .idle:
            return true
        case .scanning:
            return viewModel.summaries.isEmpty
        case .success:
            return false
        }
    }

    var body: some View {
        ZStack {
            // Background comes from the shell; keep transparent fill for transitions.
            Color.clear

            if showsHero {
                HeroScanView(viewModel: viewModel) {
                    exclusionListViewModel.load()
                    showSettings = true
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                resultsScroll
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No global animations on the results tree — they re-run during scroll and lag hard.
        .sheet(item: $viewModel.pendingCleanup) { pending in
            let config: CleanConfirmationSheet.Config = {
                switch pending {
                case .quick: return quickCleanConfig
                case .deep: return deepCleanConfig
                case .selected: return selectedCleanConfig
                }
            }()
            CleanConfirmationSheet(
                config: config,
                onCancel: { viewModel.cancelPendingCleanup() },
                onConfirm: { viewModel.confirmPendingCleanup() }
            )
        }
        .sheet(isPresented: $showSettings) {
            ExclusionListView(viewModel: exclusionListViewModel)
        }
        .sheet(isPresented: $showProjectPaths) {
            ProjectScanPathsView()
        }
        // Stay mounted for both hero and results so FDA re-probes after System Settings.
        .onAppear {
            viewModel.refreshPermissionCoaching()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissionCoaching()
        }
    }

    private var resultsScroll: some View {
        ScrollView {
            // Single lazy stack — nested LazyVStacks inside a VStack defeat laziness
            // and measure every expanded folder row up front (main-thread scroll lag).
            LazyVStack(spacing: AppTheme.Spacing.xl, pinnedViews: []) {
                resultsHeader
                permissionCoachingSection
                scanWarningsSection
                selectionBar
                cleanupStatusBanner
                metrics
                deviceBackupsSection
                categoryBrowser
                toolShareSection
                largestItemsSection
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.vertical, AppTheme.Spacing.pageVertical)
            .frame(maxWidth: .infinity)
        }
    }

    /// Scan warnings — rule failures and unreadable locations (R1.2/R1.3).
    @ViewBuilder
    private var scanWarningsSection: some View {
        if !viewModel.scanWarnings.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.scanWarnings, id: \.self) { warning in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.warning)
                            Text(warning)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permissionCoachingSection: some View {
        if viewModel.showFullDiskAccessBanner {
            FullDiskAccessCard(
                style: .fullDiskAccess,
                onOpenSettings: { viewModel.openFullDiskAccessSettings() },
                onDismiss: { viewModel.dismissFullDiskAccessBanner() },
                onRescan: { viewModel.runScan(forceRescan: true) }
            )
        } else if viewModel.showEmptyScanCoaching {
            FullDiskAccessCard(
                style: emptyScanCardStyle,
                onOpenSettings: { viewModel.openFullDiskAccessSettings() },
                onRescan: { viewModel.runScan(forceRescan: true) }
            )
        }
    }

    private var emptyScanCardStyle: FullDiskAccessCard.Style {
        switch viewModel.emptyScanCoachingStyle {
        case .likelyMissingFDA:
            return .emptyScan(fullDiskAccessLikelyMissing: true)
        case .permissionsUpdatedNeedsRescan:
            return .permissionsUpdatedNeedsRescan
        case .genuinelyEmpty:
            return .emptyScan(fullDiskAccessLikelyMissing: false)
        }
    }

    private var selectionBar: some View {
        GlassCard(padding: AppTheme.Spacing.cardCompact) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Review & Clean")
                        .font(scale.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("\(viewModel.selectedCandidatesCount) selected · \(viewModel.formattedBytes(viewModel.selectedCandidatesBytes))")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text("SAFE items start selected. REVIEW (e.g. Local Storage) starts off — may sign you out of websites.")
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 8, lineSpacing: 8, alignment: .leading) {
                    PrimaryActionButton(
                        title: "Clean selected",
                        systemImage: "checkmark.circle.fill",
                        isLoading: viewModel.isCleaning,
                        style: .compact,
                        tint: .success,
                        isEnabled: viewModel.selectedCandidatesCount > 0
                    ) {
                        viewModel.requestCleanSelected()
                    }

                    SecondaryActionButton(title: "All Safe", systemImage: "checkmark.shield") {
                        viewModel.collapseBrowserSections()
                        viewModel.selectAllSafe()
                    }

                    SecondaryActionButton(title: "Clear", systemImage: "xmark") {
                        // Collapse expanded trees first so Clear doesn't re-diff huge views.
                        viewModel.collapseBrowserSections()
                        viewModel.clearSelection()
                    }

                    if viewModel.quickCleanCandidatesCount > 0 {
                        SecondaryActionButton(title: "Quick Clean (all safe)", role: .accent) {
                            viewModel.requestQuickClean()
                        }
                    }
                }
            }
        }
    }

    /// Compact post-scan header with reclaimable hero metric + clean actions.
    private var resultsHeader: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Smart Scan")
                            .font(scale.caption)
                            .foregroundStyle(AppTheme.accent)

                        Text(viewModel.formattedBytes(viewModel.totalReclaimableBytes))
                            .font(scale.font(28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Reclaimable across \(viewModel.summaries.count) categories")
                            .font(scale.body)
                            .foregroundStyle(AppTheme.textSecondary)

                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                            Text(lastScanText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.Fill.control, in: Capsule(style: .continuous))
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        IconActionButton(
                            systemImage: "folder.badge.plus",
                            help: "Manage project scan paths"
                        ) {
                            showProjectPaths = true
                        }

                        IconActionButton(
                            systemImage: "gearshape",
                            help: "Manage excluded paths"
                        ) {
                            exclusionListViewModel.load()
                            showSettings = true
                        }
                    }
                }

                FlowLayout(spacing: 8, lineSpacing: 8, alignment: .leading) {
                    if viewModel.isScanning {
                        ScanPulseView()
                            .frame(width: 18, height: 18)

                        SecondaryActionButton(title: "Cancel") {
                            viewModel.cancelScan()
                        }
                    }

                    PrimaryActionButton(
                        title: viewModel.isScanning ? "Scanning…" : "Rescan",
                        systemImage: "sparkles",
                        isLoading: viewModel.isScanning,
                        style: .compact
                    ) {
                        viewModel.runScan()
                    }

                    if viewModel.state == .success {
                        SecondaryActionButton(
                            title: "Force Rescan",
                            systemImage: "arrow.clockwise"
                        ) {
                            viewModel.runScan(forceRescan: true)
                        }
                        .help("Clear the scan cache and do a full traversal")
                    }

                    if viewModel.state == .success && viewModel.selectedCandidatesCount > 0 {
                        PrimaryActionButton(
                            title: "Clean selected",
                            systemImage: "checkmark.circle.fill",
                            isLoading: viewModel.isCleaning,
                            style: .compact,
                            tint: .success
                        ) {
                            viewModel.requestCleanSelected()
                        }
                    }

                    if viewModel.state == .success && viewModel.reviewRiskCandidatesCount > 0 {
                        SecondaryActionButton(
                            title: "Deep Clean all…",
                            systemImage: "bolt.fill",
                            role: .destructive
                        ) {
                            viewModel.requestDeepClean()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var deviceBackupsSection: some View {
        if !viewModel.deviceBackupFindings.isEmpty {
            DeviceBackupsCard(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var cleanupStatusBanner: some View {
        switch viewModel.cleanupState {
        case .idle, .confirming:
            EmptyView()

        case .cleaning:
            StatusBanner(kind: .progress, title: "Moving files to Trash…")

        case .done(let bytesFreed, let skippedCount):
            StatusBanner(
                kind: .success,
                title: "Cleaned \(viewModel.formattedBytes(bytesFreed))",
                detail: skippedCount > 0 ? "\(skippedCount) items skipped (policy check)." : nil,
                onDismiss: { viewModel.dismissCleanupResult() }
            ) {
                if viewModel.canUndo {
                    Button("Undo") { viewModel.undoLastCleanup() }
                        .buttonStyle(.borderless)
                        .font(scale.font(13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }

        case .undoing:
            StatusBanner(kind: .progress, title: "Restoring files from Trash…")

        case .undone(let restoredCount, let failedCount):
            StatusBanner(
                kind: failedCount > 0 ? .error : .warning,
                title: failedCount > 0
                    ? "Restored \(restoredCount) of \(restoredCount + failedCount) files — \(failedCount) could not be restored (check the Trash)."
                    : "\(restoredCount) file\(restoredCount == 1 ? "" : "s") restored.",
                icon: "arrow.uturn.backward.circle.fill",
                onDismiss: { viewModel.dismissCleanupResult() }
            )

        case .error(let message):
            StatusBanner(
                kind: .error,
                title: message,
                onDismiss: { viewModel.dismissCleanupResult() }
            )
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: AppTheme.Breakpoint.metricMin), spacing: AppTheme.Spacing.md)
            ],
            spacing: AppTheme.Spacing.md
        ) {
            MetricTile(
                label: "Reclaimable",
                value: viewModel.formattedBytes(viewModel.totalReclaimableBytes),
                detail: viewModel.summaries.isEmpty
                    ? "Run a scan to estimate reclaimable storage"
                    : "Across \(viewModel.summaries.count) categories",
                tint: AppTheme.success
            )

            MetricTile(
                label: "Top Candidates",
                value: "\(viewModel.topFindings.count)",
                detail: "Largest files and caches from latest scan",
                tint: AppTheme.accent
            )

            MetricTile(
                label: "Status",
                value: statusLabel,
                detail: statusDetail,
                tint: statusColor
            )
        }
    }

    // MARK: - Browse by category (folder-only, no per-file children)

    private var categoryBrowser: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Browse by category")
                        .font(scale.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Expand a category → tool (same names as the chart) → folders with full paths. Developer Package Caches groups by JetBrains, Package Managers, VS Code, etc.")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.summaries.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "No scan results yet",
                        message: "Start a scan to browse reclaimable storage by category.",
                        layout: .inline
                    )
                } else {
                    // Keep collapsed by default — only expanded categories show folder rows.
                    VStack(spacing: 8) {
                        ForEach(viewModel.summaries) { summary in
                            categoryFolderSection(summary)
                        }
                    }
                }
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
                selection: triState(selectionState),
                selectHelp: "Toggle all SAFE folders in this category",
                onToggleSelect: { viewModel.toggleCategory(summary.category) },
                onToggleExpand: { viewModel.toggleCategoryExpanded(summary.category) }
            ) {
                Circle()
                    .fill(CategoryStyle.tint(for: summary.category))
                    .frame(width: 8, height: 8)
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
                            sizeText: viewModel.formattedBytes(row.totalBytes),
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
                badgeText: "\(group.folderCount) folders",
                sizeText: viewModel.formattedBytes(group.totalBytes),
                isExpanded: isExpanded,
                selection: triState(selectionState),
                isSelectable: group.isSelectable,
                selectHelp: "Select all folders under \(group.toolName)",
                onToggleSelect: { viewModel.toggleToolGroup(group) },
                onToggleExpand: { viewModel.toggleToolGroupExpanded(group) }
            ) {
                Image(systemName: toolIcon(for: group.toolName))
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
                            sizeText: viewModel.formattedBytes(row.totalBytes),
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

    private func toolIcon(for name: String) -> String {
        switch name {
        case "Xcode": return "hammer.fill"
        case "VS Code", "Cursor": return "chevron.left.forwardslash.chevron.right"
        case "JetBrains": return "j.circle.fill"
        case "Docker": return "shippingbox.fill"
        case "Safari": return "safari.fill"
        case "Chrome", "Brave", "Edge", "Opera", "Arc": return "globe"
        case "Firefox": return "flame.fill"
        case "Package Managers": return "shippingbox"
        case "System Logs": return "doc.text.fill"
        case "Temp Files": return "clock.arrow.circlepath"
        case "Slack": return "message.fill"
        case "Zoom": return "video.fill"
        case "Spotify": return "music.note"
        case "OpenCode": return "terminal"
        default: return "app.fill"
        }
    }

    private func categoryBadge(_ summary: SummaryItem) -> String {
        if viewModel.usesToolGrouping(for: summary.category) {
            let tools = viewModel.toolGroups(for: summary.category).count
            if tools > 0 {
                return "\(tools) tools"
            }
        }
        if summary.folderCount > 0 {
            return "\(summary.folderCount) folders"
        }
        return "\(summary.fileCount) items"
    }


    // MARK: - Tool share (donut)

    @ViewBuilder
    private var toolShareSection: some View {
        if !viewModel.perToolRollups.isEmpty {
            ToolShareChart(
                rollups: viewModel.perToolRollups,
                formatBytes: viewModel.formattedBytes
            )
        }
    }

    // MARK: - Largest items (merged Top Files + Large Files)

    private var largestItemsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Largest items")
                        .font(scale.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Biggest reclaimable paths across all categories. Select items to clean, or open in Finder.")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let feedback = viewModel.revealFeedback {
                    StatusBanner(kind: .warning, title: feedback, style: .inline)
                }

                let safeItems = viewModel.largestSafeItems
                let reviewItems = viewModel.largestReviewItems
                if safeItems.isEmpty && reviewItems.isEmpty {
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: "Nothing to review yet",
                        message: "Largest candidates appear after a completed scan.",
                        layout: .inline
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !safeItems.isEmpty {
                            largestRiskGroupHeader(
                                title: "SAFE",
                                detail: "\(safeItems.count) items · \(viewModel.formattedBytes(safeItems.reduce(0) { $0 + $1.sizeBytes }))",
                                color: AppTheme.success
                            )
                            ForEach(safeItems) { finding in
                                largestItemRow(finding)
                            }
                        }
                        if !reviewItems.isEmpty {
                            largestRiskGroupHeader(
                                title: "REVIEW",
                                detail: "\(reviewItems.count) items · \(viewModel.formattedBytes(reviewItems.reduce(0) { $0 + $1.sizeBytes }))",
                                color: AppTheme.warning
                            )
                            ForEach(reviewItems) { finding in
                                largestItemRow(finding)
                            }
                        }
                    }
                }
            }
        }
    }

    private func largestRiskGroupHeader(title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(scale.badge)
                .tracking(0.4)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.2), in: Capsule(style: .continuous))
                .foregroundStyle(color)
            Text(detail)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func largestItemRow(_ finding: FindingItem) -> some View {
        SelectableCandidateRow(
            path: finding.path,
            displayName: largestItemDisplayName(finding),
            subtitle: largestItemSubtitle(finding),
            sizeText: viewModel.formattedBytes(finding.sizeBytes),
            riskLevel: finding.riskLevel,
            isSelected: viewModel.isSelected(path: finding.path),
            isSelectable: finding.riskLevel != .advanced,
            canReveal: viewModel.canReveal(path: finding.path),
            indent: 0,
            onToggle: { viewModel.toggleSelection(path: finding.path) },
            onReveal: { viewModel.revealInFinder(path: finding.path) },
            onExclude: { viewModel.exclude(path: finding.path) },
            isFolder: isLikelyFolderFinding(finding)
        )
    }

    private func largestItemDisplayName(_ finding: FindingItem) -> String {
        let name = URL(fileURLWithPath: finding.path).lastPathComponent
        if finding.category == .userCaches {
            return "\(name) · app cache"
        }
        return name
    }

    private func largestItemSubtitle(_ finding: FindingItem) -> String {
        "\(finding.category.rawValue) · \(viewModel.abbreviatedPath(finding.path))"
    }

    private func isLikelyFolderFinding(_ finding: FindingItem) -> Bool {
        // Precomputed at scan finish — no FileManager calls during body evaluation.
        viewModel.isFolderFinding(path: finding.path)
    }

    private func triState(_ state: CategorySelectState) -> TriSelectionState {
        switch state {
        case .all: return .all
        case .partial: return .partial
        case .none: return .none
        }
    }

    private var lastScanText: String {
        guard let date = viewModel.lastScanDate else {
            return "Last scan: Not run"
        }

        if let duration = viewModel.lastScanDuration {
            return "Last scan: \(viewModel.formattedDate(date)) • \(String(format: "%.1fs", duration))"
        }

        return "Last scan: \(viewModel.formattedDate(date))"
    }

    private var statusLabel: String {
        switch viewModel.state {
        case .idle:
            return "Ready"
        case .scanning:
            return "Scanning"
        case .success:
            return "Complete"
        }
    }

    private var statusDetail: String {
        switch viewModel.state {
        case .idle:
            return "Select profile and start scan"
        case .scanning:
            return "Analyzing files and cache footprints"
        case .success:
            return "Results updated from latest run"
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .idle:
            return AppTheme.warning
        case .scanning:
            return AppTheme.accent
        case .success:
            return AppTheme.success
        }
    }

}

// MARK: - CategoryFolderRowView (lightweight, equatable inputs)

private struct CategoryFolderRowView: View, Equatable {
    let row: CategoryFolderRow
    let sizeText: String
    let selectionState: CategorySelectState
    let canReveal: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void
    @Environment(\.pareDisplayScale) private var scale

    static func == (lhs: CategoryFolderRowView, rhs: CategoryFolderRowView) -> Bool {
        lhs.row == rhs.row
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

            Image(systemName: "folder.fill")
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 16)

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

// MARK: - Clean confirmation copy

/// Shared heads-up when a clean is large enough that Spotlight may busy-update
/// (incremental FSEvents work — not a full index wipe).
private enum CleanConfirmationSpotlightWarning {
    static let message =
        "Large clean: macOS Spotlight may be busy updating search indexes for a while. " +
        "This is normal incremental work, not a full reindex. Pare never deletes Spotlight’s own store."
}

// MARK: - Clean confirmation configs

extension ScanDashboardView {
    private var quickCleanConfig: CleanConfirmationSheet.Config {
        var lines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "checkmark.shield.fill",
                color: AppTheme.success,
                text: "\(viewModel.quickCleanCandidatesCount) safe-risk file\(viewModel.quickCleanCandidatesCount == 1 ? "" : "s") will be moved to Trash."
            ),
            .init(
                icon: "exclamationmark.triangle",
                color: AppTheme.warning,
                text: "Review and Advanced findings are never touched."
            )
        ]
        if viewModel.quickCleanMayTriggerSpotlightWork {
            lines.append(.init(
                icon: "magnifyingglass",
                color: AppTheme.warning,
                text: CleanConfirmationSpotlightWarning.message
            ))
        }
        lines.append(.init(
            icon: "arrow.uturn.backward",
            color: AppTheme.accent,
            text: "You can undo immediately after cleanup via the Undo button."
        ))
        lines.append(.init(
            icon: "externaldrive",
            color: AppTheme.textSecondary,
            text: "Estimated space: \(viewModel.formattedBytes(viewModel.quickCleanCandidatesBytes))"
        ))

        return .init(
            title: "Quick Clean",
            subtitle: "Safe-risk findings only",
            headerIcon: "trash.fill",
            headerTint: AppTheme.success,
            infoLines: lines,
            size: .init(minHeight: 320, idealHeight: 360)
        )
    }

    private var deepCleanConfig: CleanConfirmationSheet.Config {
        var lines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "bolt.fill",
                color: AppTheme.review,
                text: "\(viewModel.deepCleanCandidatesCount) file\(viewModel.deepCleanCandidatesCount == 1 ? "" : "s") will be moved to Trash (\(viewModel.reviewRiskCandidatesCount) review-risk)."
            ),
            .init(
                icon: "exclamationmark.shield",
                color: AppTheme.warning,
                text: "ADVANCED findings (e.g. Docker VM data) are never touched."
            )
        ]
        if viewModel.deepCleanMayTriggerSpotlightWork {
            lines.append(.init(
                icon: "magnifyingglass",
                color: AppTheme.warning,
                text: CleanConfirmationSpotlightWarning.message
            ))
        }
        lines.append(.init(
            icon: "arrow.uturn.backward",
            color: AppTheme.accent,
            text: "You can undo immediately after cleanup via the Undo button."
        ))
        lines.append(.init(
            icon: "externaldrive",
            color: AppTheme.textSecondary,
            text: "Estimated space: \(viewModel.formattedBytes(viewModel.deepCleanCandidatesBytes))"
        ))

        return .init(
            title: "Deep Clean",
            subtitle: "Safe + Review-risk findings",
            subtitleColor: AppTheme.review,
            headerIcon: "bolt.fill",
            headerTint: AppTheme.review,
            warningText: "Deep Clean includes REVIEW-risk items — files that may be regenerated by your apps but could require re-configuration. Proceed only if you have reviewed them.",
            infoLines: lines,
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
        )
    }

    private var selectedCleanConfig: CleanConfirmationSheet.Config {
        var lines: [CleanConfirmationSheet.InfoLine] = [
            .init(
                icon: "checkmark.circle",
                color: AppTheme.success,
                text: "\(viewModel.selectedCandidatesCount) item(s) · \(viewModel.formattedBytes(viewModel.selectedCandidatesBytes))"
            )
        ]
        if viewModel.selectedReviewCount > 0 {
            lines.append(.init(
                icon: "exclamationmark.triangle",
                color: AppTheme.warning,
                text: "\(viewModel.selectedReviewCount) REVIEW item(s) — may include browser Local Storage or similar site data."
            ))
        }
        if viewModel.selectedCleanMayTriggerSpotlightWork {
            lines.append(.init(
                icon: "magnifyingglass",
                color: AppTheme.warning,
                text: CleanConfirmationSpotlightWarning.message
            ))
        }
        lines.append(.init(
            icon: "arrow.uturn.backward",
            color: AppTheme.accent,
            text: "Moved to Trash; Undo available after cleanup."
        ))

        return .init(
            title: "Clean selected",
            subtitle: "Only items you checked",
            headerIcon: "checkmark.circle.fill",
            headerTint: AppTheme.accent,
            infoLines: lines
        )
    }
}

// MARK: - ScanPulseView

private struct ScanPulseView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.22))
                .scaleEffect(pulse ? 1.4 : 0.8)
                .opacity(pulse ? 0.08 : 0.32)

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

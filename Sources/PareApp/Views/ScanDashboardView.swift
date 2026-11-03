import AppKit
import Foundation
import SwiftUI
import PareCore

struct ScanDashboardView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @ObservedObject var volume: VolumeUsageModel
    @StateObject private var exclusionListViewModel = ExclusionListViewModel()
    @Environment(\.pareDisplayScale) private var scale
    @State private var showSettings = false
    @State private var showProjectPaths = false
    @State private var resultsAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                HeroScanView(viewModel: viewModel, volume: volume, onOpenSettings: openExclusions)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                resultsScroll
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No global animations on the results tree — they re-run during scroll and lag hard.
        .sheet(item: $viewModel.pendingCleanup, onDismiss: {
            viewModel.cancelPendingCleanup()
        }) { pending in
            let config: CleanConfirmationSheet.Config = {
                switch pending {
                case .quick: return quickCleanConfig
                case .deep: return deepCleanConfig
                case .selected, .diskReview: return selectedCleanConfig
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
                cleanupStatusBanner
                ScanSummaryHero(
                    viewModel: viewModel,
                    volume: volume,
                    onManageExclusions: openExclusions,
                    onManageProjectPaths: { showProjectPaths = true }
                )
                .modifier(RevealOnAppear(appeared: resultsAppeared, index: 0))
                permissionCoachingSection
                scanWarningsSection
                decisionTiles
                    .modifier(RevealOnAppear(appeared: resultsAppeared, index: 1))
                deviceBackupsSection
                categoryBrowser
                    .modifier(RevealOnAppear(appeared: resultsAppeared, index: 2))
                toolShareSection
                largestItemsSection
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, AppTheme.Spacing.pageVertical)
            // Room for the floating action bar so the last card never hides under it.
            .padding(.bottom, scale.space(112))
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if viewModel.state == .success || !viewModel.summaries.isEmpty {
                CleanActionBar(viewModel: viewModel)
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.bottom, AppTheme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            volume.refresh()
            MotionPolicy.perform(AppTheme.Motion.reveal, reduceMotion: reduceMotion) { resultsAppeared = true }
        }
        .onChange(of: viewModel.state) { _ in volume.refresh() }
    }

    private func openExclusions() {
        exclusionListViewModel.load()
        showSettings = true
    }

    private var decisionTiles: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.md), count: 3),
            spacing: AppTheme.Spacing.md
        ) {
            MetricTile(
                label: "Safe to clean",
                icon: "checkmark.shield.fill",
                bytes: viewModel.quickCleanCandidatesBytes,
                detail: "\(viewModel.quickCleanCandidatesCount) items marked Safe",
                tint: AppTheme.success
            )
            MetricTile(
                label: "Needs review",
                icon: "eye.fill",
                bytes: viewModel.candidateStats.reviewBytes,
                detail: viewModel.reviewRiskCandidatesCount == 0
                    ? "Nothing needs a second opinion"
                    : "\(viewModel.reviewRiskCandidatesCount) Review items — may sign you out of sites or apps",
                tint: AppTheme.warning
            )
            MetricTile(
                label: "Selected",
                icon: "checkmark.circle.fill",
                bytes: viewModel.selectedCandidatesBytes,
                detail: "\(viewModel.selectedCandidatesCount) items will go to the Trash when you clean",
                tint: AppTheme.accentText
            )
        }
    }

    /// Scan warnings — rule failures and unreadable locations (R1.2/R1.3).
    @ViewBuilder
    private var scanWarningsSection: some View {
        if !viewModel.scanWarnings.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.scanWarnings.enumerated()), id: \.offset) { _, warning in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(scale.font(12, weight: .semibold))
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
            CleanResultCard(
                bytesFreed: bytesFreed,
                skippedCount: skippedCount,
                canUndo: viewModel.canUndo,
                onUndo: { viewModel.undoLastCleanup() },
                skipExplanation: viewModel.cleanup.resultExplanation,
                reclaim: viewModel.cleanup.lastReclaim,
                onDismiss: { viewModel.dismissCleanupResult() }
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))

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

    // MARK: - Browse by category (folder-only, no per-file children)

    private var categoryBrowser: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Browse by category")
                        .font(scale.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Open a category to see each tool and folder. Tick what you want gone.")
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
                return "\(tools) tool\(tools == 1 ? "" : "s")"
            }
        }
        if summary.folderCount > 0 {
            return "\(summary.folderCount) folder\(summary.folderCount == 1 ? "" : "s")"
        }
        return "\(summary.fileCount) item\(summary.fileCount == 1 ? "" : "s")"
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
                    Text("The biggest reclaimable paths across every category.")
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
            sizeText: viewModel.formattedFindingSize(finding),
            riskLevel: finding.riskLevel,
            isSelected: viewModel.isSelected(path: finding.path),
            isSelectable: finding.riskLevel != .advanced,
            canReveal: viewModel.canReveal(path: finding.path),
            indent: 0,
            onToggle: { viewModel.toggleSelection(path: finding.path) },
            onReveal: { viewModel.revealInFinder(path: finding.path) },
            onExclude: { viewModel.exclude(path: finding.path) },
            isFolder: isLikelyFolderFinding(finding),
            activityText: viewModel.cacheActivityText(path: finding.path)
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
}

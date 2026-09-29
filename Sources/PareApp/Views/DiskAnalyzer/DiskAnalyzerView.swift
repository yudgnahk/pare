import SwiftUI
import AppKit
import PareCore

/// Composes the Disk Analyzer screen: header summary, filter bar, breadcrumb, the
/// table/inspector split (inspector collapses below `inspectorCollapseWidth`), the
/// review tray, the cleanup confirmation sheet and the result banner.
struct DiskAnalyzerView: View {
    @ObservedObject var viewModel: DiskAnalyzerViewModel
    /// Lets the inspector's "Run Smart Scan" action reach `ScanDashboardViewModel` without this
    /// view owning a reference to it; `PareApp.swift` wires the real closure.
    var onRunSmartScan: () -> Void = {}

    @Environment(\.pareDisplayScale) private var scale
    @State private var windowWidth: CGFloat = AppTheme.Window.defaultWidth

    private static let inspectorWidth: CGFloat = 280
    private static let inspectorCollapseWidth: CGFloat = 1100

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            if showsCleanupBanner {
                cleanupStatusBanner
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.bottom, AppTheme.Spacing.sm)
            }

            if viewModel.isLoading {
                loadingBody
            } else if viewModel.currentURL != nil {
                analyzerBody
            } else {
                emptyBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { windowWidth = currentWindowWidth() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            windowWidth = (note.object as? NSWindow)?.frame.width ?? windowWidth
        }
        .sheet(item: $viewModel.pendingCleanup, onDismiss: {
            viewModel.cancelPendingCleanup()
        }) { _ in
            CleanConfirmationSheet(
                config: reviewCleanupConfig,
                onCancel: { viewModel.cancelPendingCleanup() },
                onConfirm: { viewModel.confirmReviewCleanup() }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Analyzer")
                    .font(scale.pageTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                if let url = viewModel.currentURL {
                    Text(url.path)
                        .font(scale.rowMono)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let level = viewModel.level {
                        Text(levelSummary(level))
                            .font(scale.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                } else {
                    Text("Choose a directory to analyze disk usage.")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 8, lineSpacing: 8, alignment: .leading) {
                if viewModel.currentURL != nil {
                    IconActionButton(
                        systemImage: "arrow.clockwise",
                        help: "Refresh",
                        isEnabled: !viewModel.isLoading
                    ) {
                        viewModel.refresh()
                    }
                }

                SecondaryActionButton(
                    title: "Choose Directory",
                    systemImage: "folder",
                    role: .accent
                ) {
                    viewModel.chooseDirectory()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, AppTheme.Spacing.pageVertical)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private func levelSummary(_ level: DiskLevelLoader.Level) -> String {
        let itemWord = level.totalItemCount == 1 ? "item" : "items"
        return "\(level.hasPartialSize ? "At least " : "")\(viewModel.formattedBytes(level.totalBytes)) \u{00B7} \(level.totalItemCount) \(itemWord)"
    }

    // MARK: Error

    private func errorBanner(_ message: String) -> some View {
        ErrorBanner(message: message) {
            viewModel.errorMessage = nil
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.bottom, 10)
    }

    // MARK: Cleanup result banner

    private var showsCleanupBanner: Bool {
        switch viewModel.cleanupState {
        case .idle, .confirming: return false
        default: return true
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
            doneBanner(bytesFreed: bytesFreed, skippedCount: skippedCount)

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
            StatusBanner(kind: .error, title: message, onDismiss: { viewModel.dismissCleanupResult() })
        }
    }

    private func doneBanner(bytesFreed: Int64, skippedCount: Int) -> some View {
        let saveWarning = viewModel.transactionSaveError.map { "Undo record warning: \($0)" }
        let skipDetails = skipDetailsText(skippedCount: skippedCount)
        let details = [skipDetails, saveWarning].compactMap { $0 }.joined(separator: "\n")
        let isError = saveWarning != nil || (bytesFreed == 0 && skippedCount > 0)
        return StatusBanner(
            kind: isError ? .error : (skippedCount > 0 ? .warning : .success),
            title: doneTitle(bytesFreed: bytesFreed, skippedCount: skippedCount, undoRecordFailed: saveWarning != nil),
            detail: details.isEmpty ? nil : details,
            onDismiss: { viewModel.dismissCleanupResult() }
        ) {
            if viewModel.canUndo {
                Button("Undo") { viewModel.undoLastCleanup() }
                    .buttonStyle(.borderless)
                    .font(scale.font(13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private func skipDetailsText(skippedCount: Int) -> String? {
        let reasons = viewModel.cleanupSkippedReasons.prefix(3)
        let omitted = max(0, skippedCount - reasons.count)
        let lines = [
            reasons.isEmpty ? nil : reasons.joined(separator: "\n"),
            omitted > 0 ? "and \(omitted) more skipped item\(omitted == 1 ? "" : "s")" : nil
        ].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func doneTitle(bytesFreed: Int64, skippedCount: Int, undoRecordFailed: Bool) -> String {
        let freed = viewModel.formattedBytes(bytesFreed)
        if undoRecordFailed {
            return bytesFreed > 0 ? "Cleaned \(freed); undo record failed" : "Cleanup finished, but its undo record failed"
        }
        if bytesFreed == 0 && skippedCount > 0 { return "No items cleaned · \(skippedCount) skipped" }
        if skippedCount > 0 { return "Cleaned \(freed) · \(skippedCount) skipped" }
        return "Cleaned \(freed)"
    }

    // MARK: Loading

    private var loadingBody: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(viewModel.loadingProgress.map { "Analyzing disk usage… \($0.scanned) of \($0.total)" } ?? "Analyzing disk usage…")
                .font(scale.font(14, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
    }

    // MARK: Empty (no directory chosen)

    private var emptyBody: some View {
        EmptyStateView(
            icon: "externaldrive.badge.questionmark",
            title: "No directory selected",
            message: "Click \u{201C}Choose Directory\u{201D} to explore disk usage with a sortable, size-aware tree.",
            maxTextWidth: 380
        )
    }

    // MARK: Analyzer body

    private var analyzerBody: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            DiskFilterBar(search: $viewModel.search, kindFilter: $viewModel.kindFilter, sizeFloor: $viewModel.sizeFloor)

            DiskBreadcrumbBar(
                crumbs: viewModel.crumbs,
                canGoUp: viewModel.crumbs.count > 1,
                totalLabel: viewModel.formattedBytes(viewModel.level?.totalBytes ?? 0),
                onSelect: { viewModel.select(crumb: $0) },
                onGoUp: { viewModel.goUp() }
            )

            HStack(spacing: 0) {
                tableOrEmptyState

                if showsInspector {
                    Divider().overlay(AppTheme.Hairline.standard)
                    DiskInspectorPane(
                        entry: selectedEntry,
                        resolution: selectedEntryResolution,
                        formatBytes: viewModel.formattedBytes,
                        onReveal: { viewModel.revealInFinder($0.url) },
                        onCopyPath: copyPath,
                        onAddToReview: { viewModel.addToReview($0) },
                        onRunSmartScan: onRunSmartScan
                    )
                    .frame(width: Self.inspectorWidth)
                }
            }

            if viewModel.reviewTrayCount > 0 {
                DiskReviewTray(
                    count: viewModel.reviewTrayCount,
                    totalBytes: viewModel.reviewTrayTotalBytes,
                    reviewRiskCount: viewModel.reviewTrayReviewRiskCount,
                    findings: viewModel.reviewTrayFindings,
                    formatBytes: viewModel.formattedBytes,
                    onClear: { viewModel.clearReview() },
                    onReviewAndClean: { viewModel.requestReviewCleanup() },
                    onRemove: { viewModel.removeFromReview(path: $0.path) },
                    isCleaning: viewModel.cleanupIsBusy
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.bottom, AppTheme.Spacing.pageVertical)
    }

    @ViewBuilder
    private var tableOrEmptyState: some View {
        if viewModel.visibleEntries.isEmpty {
            EmptyStateView(
                icon: "line.3.horizontal.decrease.circle",
                title: hasActiveFilter ? "No matches" : "Empty folder",
                message: hasActiveFilter
                    ? "No items match the current search and filters."
                    : "This folder has no items to show."
            )
        } else {
            DiskAnalyzerTable(
                entries: viewModel.visibleEntries,
                levelTotalBytes: viewModel.level?.totalBytes ?? 0,
                selection: $viewModel.selection,
                sortOrder: $viewModel.sortOrder,
                kindStyle: DiskKindStyle.style(for:),
                onOpen: { viewModel.open($0) },
                onReveal: { viewModel.revealInFinder($0.url) },
                onCopyPath: copyPath,
                onAddToReview: { viewModel.addToReview($0) },
                reviewResolution: { viewModel.reviewResolution(for: $0) }
            )
        }
    }

    private var hasActiveFilter: Bool {
        !viewModel.search.isEmpty || viewModel.kindFilter != nil || viewModel.sizeFloor != .any
    }

    private var selectedEntry: DiskEntry? {
        guard viewModel.selection.count == 1, let id = viewModel.selection.first else { return nil }
        return viewModel.visibleEntries.first { $0.id == id }
    }

    private var selectedEntryResolution: DiskReviewResolution {
        guard let entry = selectedEntry else { return .notCandidate }
        return viewModel.reviewResolution(for: entry)
    }

    private var showsInspector: Bool {
        windowWidth >= Self.inspectorCollapseWidth
    }

    private func copyPath(_ entry: DiskEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.path, forType: .string)
    }

    private func currentWindowWidth() -> CGFloat {
        NSApplication.shared.windows.first(where: \.isVisible)?.frame.width ?? AppTheme.Window.defaultWidth
    }

    private var reviewCleanupConfig: CleanConfirmationSheet.Config {
        DiskReviewTrayConfirmation.config(
            count: viewModel.reviewTrayCount,
            totalBytes: viewModel.reviewTrayTotalBytes,
            reviewRiskCount: viewModel.reviewTrayReviewRiskCount,
            paths: viewModel.reviewTrayFindings.map(\.path),
            formatBytes: viewModel.formattedBytes
        )
    }
}

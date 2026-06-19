import Foundation
import SwiftUI
import PareCore

struct ScanDashboardView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @StateObject private var exclusionListViewModel = ExclusionListViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    cleanupStatusBanner
                    metrics
                    summaries
                    byToolBreakdown
                    largeFilesByCategory
                    topFiles
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
        .sheet(isPresented: $viewModel.showCleanConfirmation) {
            QuickCleanConfirmationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDeepCleanConfirmation) {
            DeepCleanConfirmationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            ExclusionListView(viewModel: exclusionListViewModel)
        }
    }

    private var header: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clean My Mac")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Smart cleanup insights for your system and dev workloads")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 10) {
                        Image(systemName: "clock")
                        Text(lastScanText)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                        if viewModel.isScanning {
                            ScanPulseView()
                                .frame(width: 20, height: 20)

                            Button("Cancel") { viewModel.cancelScan() }
                                .buttonStyle(.borderless)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        PrimaryActionButton(
                            title: "Scan Now",
                            systemImage: "sparkles",
                            isLoading: viewModel.isScanning
                        ) {
                            viewModel.runScan()
                        }

                        if viewModel.state == .success {
                            Button {
                                viewModel.runScan(forceRescan: true)
                            } label: {
                                Label("Force Rescan", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Clear the scan cache and do a full traversal")
                        }

                        Button {
                            exclusionListViewModel.load()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Manage excluded paths")

                        if viewModel.state == .success && viewModel.quickCleanCandidatesCount > 0 {
                            PrimaryActionButton(
                                title: "Quick Clean",
                                systemImage: "trash.fill",
                                isLoading: viewModel.isCleaning
                            ) {
                                viewModel.requestQuickClean()
                            }
                        }

                        if viewModel.state == .success && viewModel.reviewRiskCandidatesCount > 0 {
                            PrimaryActionButton(
                                title: "Deep Clean",
                                systemImage: "bolt.fill",
                                isLoading: viewModel.isCleaning
                            ) {
                                viewModel.requestDeepClean()
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var cleanupStatusBanner: some View {
        switch viewModel.cleanupState {
        case .idle, .confirming:
            EmptyView()

        case .cleaning:
            GlassCard {
                HStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Moving files to Trash…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                }
            }

        case .done(let bytesFreed, let skippedCount):
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                        .font(.system(size: 22))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cleaned \(viewModel.formattedBytes(bytesFreed))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        if skippedCount > 0 {
                            Text("\(skippedCount) items skipped (policy check).")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    Spacer()

                    if viewModel.canUndo {
                        Button("Undo") { viewModel.undoLastCleanup() }
                            .buttonStyle(.borderless)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    Button {
                        viewModel.dismissCleanupResult()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

        case .undoing:
            GlassCard {
                HStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Restoring files from Trash…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                }
            }

        case .undone(let restoredCount):
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(AppTheme.warning)
                        .font(.system(size: 22))

                    Text("\(restoredCount) file\(restoredCount == 1 ? "" : "s") restored.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Button {
                        viewModel.dismissCleanupResult()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

        case .error(let message):
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.review)
                        .font(.system(size: 22))

                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(3)

                    Spacer()

                    Button {
                        viewModel.dismissCleanupResult()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 16) {
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

    private var summaries: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Category Overview")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                if viewModel.summaries.isEmpty {
                    placeholder(
                        icon: "tray",
                        title: "No scan results yet",
                        message: "Start a scan to see category-level reclaimable storage."
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(viewModel.summaries.enumerated()), id: \.element.id) { index, summary in
                            CategorySummaryRow(
                                title: summary.category.rawValue,
                                bytesText: viewModel.formattedBytes(summary.reclaimableBytes),
                                fileCount: summary.fileCount,
                                share: viewModel.summaryShare(for: summary.reclaimableBytes),
                                color: color(for: summary.category)
                            )
                            .opacity(viewModel.resultsVisible ? 1 : 0)
                            .offset(y: viewModel.resultsVisible ? 0 : 6)
                            .animation(
                                .spring(response: 0.36, dampingFraction: 0.85)
                                .delay(Double(index) * 0.05),
                                value: viewModel.resultsVisible
                            )
                        }
                    }
                }
            }
        }
    }

    private var topFiles: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Files and Caches")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                if viewModel.topFindings.isEmpty {
                    placeholder(
                        icon: "doc.text.magnifyingglass",
                        title: "Nothing to review yet",
                        message: "Top candidates will appear after a completed scan."
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.topFindings.prefix(12).enumerated()), id: \.element.id) { index, finding in
                            TopFileRow(
                                path: finding.path,
                                category: finding.category.rawValue,
                                reason: finding.reason,
                                riskLevel: finding.riskLevel,
                                sizeText: viewModel.formattedBytes(finding.sizeBytes),
                                lastUsedText: viewModel.formattedDate(finding.lastUsed),
                                onExclude: { viewModel.exclude(path: finding.path) }
                            )
                            .opacity(viewModel.resultsVisible ? 1 : 0)
                            .scaleEffect(viewModel.resultsVisible ? 1 : 0.98)
                            .animation(
                                .spring(response: 0.38, dampingFraction: 0.86)
                                .delay(Double(index) * 0.04),
                                value: viewModel.resultsVisible
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var byToolBreakdown: some View {
        if !viewModel.perToolRollups.isEmpty {
            ByToolBreakdownCard(
                rollups: viewModel.perToolRollups,
                resultsVisible: viewModel.resultsVisible,
                formatBytes: viewModel.formattedBytes
            )
        }
    }

    private var largeFilesByCategory: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Large Files by Category")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Only files larger than \(viewModel.formattedBytes(ScanPolicy.largeFileThresholdBytes)) are shown.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                if let feedback = viewModel.revealFeedback {
                    Label(feedback, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if viewModel.largeFilesByCategory.isEmpty {
                    placeholder(
                        icon: "externaldrive.badge.exclamationmark",
                        title: "No large files in current policy",
                        message: "Run a scan or switch profile to review files above the threshold."
                    )
                } else {
                    VStack(spacing: 14) {
                        ForEach(Array(viewModel.largeFilesByCategory.enumerated()), id: \.element.id) { index, group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(group.category.rawValue)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Spacer()
                                    Text(viewModel.formattedBytes(group.totalBytes))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }

                                ForEach(group.files.prefix(5)) { file in
                                    LargeFileRow(
                                        path: file.path,
                                        sizeText: viewModel.formattedBytes(file.sizeBytes),
                                        lastUsedText: viewModel.formattedDate(file.lastUsed),
                                        riskLevel: file.riskLevel,
                                        reason: file.reason,
                                        canReveal: viewModel.canReveal(path: file.path),
                                        onReveal: { viewModel.revealInFinder(path: file.path) },
                                        onExclude: { viewModel.exclude(path: file.path) }
                                    )
                                }
                            }
                            .opacity(viewModel.resultsVisible ? 1 : 0)
                            .offset(y: viewModel.resultsVisible ? 0 : 8)
                            .animation(
                                .spring(response: 0.37, dampingFraction: 0.86)
                                .delay(Double(index) * 0.06),
                                value: viewModel.resultsVisible
                            )
                        }
                    }
                }
            }
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

    private func color(for category: ScanCategory) -> Color {
        switch category {
        case .userCaches:
            return AppTheme.accent
        case .temporaryFiles:
            return AppTheme.warning
        case .logsAndCrashReports:
            return AppTheme.review
        case .browserCaches:
            return AppTheme.success
        case .developerBuildArtifacts:
            return Color(red: 0.68, green: 0.57, blue: 0.96)
        case .developerPackageCaches:
            return Color(red: 0.50, green: 0.85, blue: 0.94)
        case .developerSimulatorCaches:
            return Color(red: 0.86, green: 0.66, blue: 0.44)
        case .designerCaches:
            return Color(red: 0.92, green: 0.62, blue: 0.41)
        case .videoBuilderCaches:
            return Color(red: 0.48, green: 0.77, blue: 0.61)
        }
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - QuickCleanConfirmationSheet

private struct QuickCleanConfirmationSheet: View {
    @ObservedObject var viewModel: ScanDashboardViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.success.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: "trash.fill")
                            .foregroundStyle(AppTheme.success)
                            .font(.system(size: 20, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Clean")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Safe-risk findings only")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(icon: "checkmark.shield.fill", color: AppTheme.success,
                            text: "\(viewModel.quickCleanCandidatesCount) safe-risk file\(viewModel.quickCleanCandidatesCount == 1 ? "" : "s") will be moved to Trash.")
                    infoRow(icon: "exclamationmark.triangle", color: AppTheme.warning,
                            text: "Review and Advanced findings are never touched.")
                    infoRow(icon: "arrow.uturn.backward", color: AppTheme.accent,
                            text: "You can undo immediately after cleanup via the Undo button.")
                    infoRow(icon: "externaldrive", color: AppTheme.textSecondary,
                            text: "Estimated space: \(viewModel.formattedBytes(viewModel.quickCleanCandidatesBytes))")
                }
                .padding(16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 12) {
                    Button("Cancel") { viewModel.cancelCleanup() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Move to Trash") { viewModel.confirmQuickClean() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.success, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .buttonStyle(.borderless)
                }
            }
            .padding(28)
        }
        .frame(width: 440, height: 340)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - DeepCleanConfirmationSheet

private struct DeepCleanConfirmationSheet: View {
    @ObservedObject var viewModel: ScanDashboardViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.review.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(AppTheme.review)
                            .font(.system(size: 20, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deep Clean")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Safe + Review-risk findings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.review)
                    }
                }

                // Warning banner
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.review)
                        .font(.system(size: 16, weight: .bold))
                    Text("Deep Clean includes REVIEW-risk items — files that may be regenerated by your apps but could require re-configuration. Proceed only if you have reviewed them.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(AppTheme.review.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(icon: "bolt.fill", color: AppTheme.review,
                            text: "\(viewModel.deepCleanCandidatesCount) file\(viewModel.deepCleanCandidatesCount == 1 ? "" : "s") will be moved to Trash (\(viewModel.reviewRiskCandidatesCount) review-risk).")
                    infoRow(icon: "exclamationmark.shield", color: AppTheme.warning,
                            text: "ADVANCED findings (e.g. Docker VM data) are never touched.")
                    infoRow(icon: "arrow.uturn.backward", color: AppTheme.accent,
                            text: "You can undo immediately after cleanup via the Undo button.")
                    infoRow(icon: "externaldrive", color: AppTheme.textSecondary,
                            text: "Estimated space: \(viewModel.formattedBytes(viewModel.deepCleanCandidatesBytes))")
                }
                .padding(16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 12) {
                    Button("Cancel") { viewModel.cancelDeepClean() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Move to Trash") { viewModel.confirmDeepClean() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.review, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .buttonStyle(.borderless)
                }
            }
            .padding(28)
        }
        .frame(width: 480, height: 400)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - ByToolBreakdownCard

private struct ByToolBreakdownCard: View {
    let rollups: [ScanDashboardViewModel.ToolRollupItem]
    let resultsVisible: Bool
    let formatBytes: (Int64) -> String

    @State private var expandedApps: Set<String> = []

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("By Tool")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                VStack(spacing: 8) {
                    ForEach(Array(rollups.enumerated()), id: \.element.id) { index, rollup in
                        ToolRollupRow(
                            rollup: rollup,
                            isExpanded: expandedApps.contains(rollup.app),
                            formatBytes: formatBytes
                        ) {
                            if expandedApps.contains(rollup.app) {
                                expandedApps.remove(rollup.app)
                            } else {
                                expandedApps.insert(rollup.app)
                            }
                        }
                        .opacity(resultsVisible ? 1 : 0)
                        .offset(y: resultsVisible ? 0 : 6)
                        .animation(
                            .spring(response: 0.36, dampingFraction: 0.85)
                            .delay(Double(index) * 0.05),
                            value: resultsVisible
                        )
                    }
                }
            }
        }
    }
}

private struct ToolRollupRow: View {
    let rollup: ScanDashboardViewModel.ToolRollupItem
    let isExpanded: Bool
    let formatBytes: (Int64) -> String
    let onTap: () -> Void

    private var toolIcon: String {
        switch rollup.app {
        case "Xcode": return "hammer.fill"
        case "VS Code": return "chevron.left.forwardslash.chevron.right"
        case "JetBrains": return "j.circle.fill"
        case "Docker": return "shippingbox.fill"
        case "Safari": return "safari.fill"
        case "Chrome": return "globe"
        case "Firefox": return "flame.fill"
        case "Adobe": return "a.circle.fill"
        case "Figma": return "pencil.and.outline"
        case "DaVinci Resolve": return "film.fill"
        case "Final Cut Pro": return "scissors"
        case "Package Managers": return "shippingbox"
        case "System Logs": return "doc.text.fill"
        case "Temp Files": return "clock.arrow.circlepath"
        case "Slack": return "message.fill"
        case "Zoom": return "video.fill"
        case "Spotify": return "music.note"
        default: return "puzzlepiece.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: toolIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)

                    Text(rollup.app)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Text("\(Int(rollup.share * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 34, alignment: .trailing)

                    Text(formatBytes(rollup.totalBytes))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 72, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Share bar + file count header
                    HStack(spacing: 10) {
                        Spacer().frame(width: 32)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(AppTheme.accent)
                                    .frame(width: geo.size.width * rollup.share, height: 4)
                            }
                        }
                        .frame(height: 4)
                        Text("\(rollup.fileCount) file\(rollup.fileCount == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 68, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    if rollup.topFiles.isEmpty {
                        Text("No files above 1 MB")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.leading, 44)
                            .padding(.bottom, 8)
                    } else {
                        ForEach(rollup.topFiles) { file in
                            HStack(spacing: 10) {
                                Spacer().frame(width: 32)
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                                    .frame(width: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.fileName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(file.abbreviatedParent)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(formatBytes(file.sizeBytes))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(width: 68, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                        }

                        let remaining = rollup.fileCount - rollup.topFiles.count
                        if remaining > 0 {
                            Text("and \(remaining) more file\(remaining == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.leading, 56)
                                .padding(.top, 2)
                                .padding(.bottom, 6)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isExpanded)
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

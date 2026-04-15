import Foundation
import SwiftUI
import App BCore

struct ScanDashboardView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    metrics
                    summaries
                    largeFilesByCategory
                    topFiles
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
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

                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Profile", selection: $viewModel.selectedProfile) {
                        ForEach(ScanDashboardViewModel.DashboardProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    HStack(spacing: 10) {
                        if viewModel.isScanning {
                            ScanPulseView()
                                .frame(width: 20, height: 20)
                        }

                        PrimaryActionButton(
                            title: "Scan Now",
                            systemImage: "sparkles",
                            isLoading: viewModel.isScanning
                        ) {
                            viewModel.runScan()
                        }
                    }
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
                                sizeText: viewModel.formattedBytes(finding.sizeBytes),
                                confidenceText: viewModel.confidenceLabel(for: finding.confidence),
                                lastUsedText: viewModel.formattedDate(finding.lastUsed),
                                confidenceColor: confidenceColor(for: finding.confidence)
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
                                        canReveal: viewModel.canReveal(path: file.path)
                                    ) {
                                        viewModel.revealInFinder(path: file.path)
                                    }
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
        }
    }

    private func confidenceColor(for confidence: Double) -> Color {
        if confidence >= 0.9 {
            return AppTheme.success
        }
        if confidence >= 0.7 {
            return AppTheme.warning
        }
        return AppTheme.review
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

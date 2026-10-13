import SwiftUI
import PareCore

/// View-only process tree: which branch of processes holds memory and CPU.
struct ProcessesView: View {
    @ObservedObject var viewModel: ProcessMonitorViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        ModuleChrome(
            destination: .processes,
            subtitle: "Memory and CPU of your own processes, grouped under the process that started them."
        ) {
            content
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.bottom, AppTheme.Spacing.pageVertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch (viewModel.state, viewModel.tree.roots.isEmpty) {
        case (.error(let message), true):
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Processes unavailable",
                message: message,
                tint: AppTheme.warning
            )
        case (.loaded, true):
            EmptyStateView(
                icon: "cpu",
                title: "No processes found",
                message: "Pare found no running processes owned by you.",
                tint: DestinationStyle.tint(for: .processes)
            )
        case (_, true):
            LoadingStateView(message: "Reading processes…")
        case (_, false):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if case .error(let message) = viewModel.state {
                    ErrorBanner(message: message + " Showing the last reading.")
                }
                summary
                table
            }
        }
    }

    private var summary: some View {
        let tree = viewModel.tree
        return HStack(spacing: AppTheme.Spacing.lg) {
            summaryItem("Processes", value: "\(tree.processCount)")
            summaryItem("Memory", value: ProcessFormat.memory(tree.totalFootprintBytes))
            summaryItem("CPU", value: ProcessFormat.cpu(tree.totalCPUPercent))
            Spacer(minLength: 0)
            Label("View only · refreshes every few seconds", systemImage: "eye")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func summaryItem(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(scale.font(14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var table: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                TableHeaderRow(spacing: AppTheme.Spacing.md) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Memory").frame(width: ProcessColumns.memory(scale), alignment: .trailing)
                    Text("CPU").frame(width: ProcessColumns.cpu(scale), alignment: .trailing)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            ProcessTreeRowView(row: row) { viewModel.toggle(row.id) }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Column widths shared by the header and every row.
enum ProcessColumns {
    static func memory(_ scale: DisplayScale) -> CGFloat { scale.scaled(96) }
    static func cpu(_ scale: DisplayScale) -> CGFloat { scale.scaled(64) }
}

enum ProcessFormat {
    static func memory(_ bytes: UInt64) -> String {
        ScanReportPresenter.formatBytes(Int64(clamping: bytes))
    }

    /// "—" until a second sample makes CPU measurable.
    static func cpu(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        return percent < 0.1 ? "0%" : String(format: percent < 10 ? "%.1f%%" : "%.0f%%", percent)
    }
}

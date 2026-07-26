import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PareCore

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.pareDisplayScale) private var scale
    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        ModuleChrome(
            title: "Cleanup History",
            subtitle: "Review and restore previously cleaned items.",
            systemImage: "clock.arrow.circlepath"
        ) {
            VStack(spacing: 0) {
                // Header actions
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

                    if !viewModel.transactions.isEmpty {
                        FlowLayout(spacing: 8, lineSpacing: 8, alignment: .leading) {
                            Menu {
                                Button("Export as JSON…") { exportJSON() }
                                Button("Export as CSV…") { exportCSV() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export")
                                }
                                .font(scale.font(12, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: AppTheme.Control.secondaryHeight)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppTheme.Fill.hover)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(AppTheme.Hairline.strong, lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .help("Export cleanup history")

                            SecondaryActionButton(
                                title: "Clear History",
                                systemImage: "trash",
                                role: .destructive
                            ) {
                                viewModel.clearAll()
                            }
                            .help("Delete all cleanup history records")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.bottom, AppTheme.Spacing.md)

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) {
                        viewModel.errorMessage = nil
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.bottom, 12)
                }

                if viewModel.transactions.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No cleanup history",
                        message: "Run a Quick Clean or Deep Clean to create a history record."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.transactions) { transaction in
                                TransactionCard(
                                    transaction: transaction,
                                    isExpanded: expandedIDs.contains(transaction.id),
                                    restoringItemID: viewModel.restoringItemID,
                                    formatBytes: viewModel.formattedBytes,
                                    formatDate: viewModel.formattedDate,
                                    onToggle: {
                                        if expandedIDs.contains(transaction.id) {
                                            expandedIDs.remove(transaction.id)
                                        } else {
                                            expandedIDs.insert(transaction.id)
                                        }
                                    },
                                    onRestoreItem: { item in
                                        Task { await viewModel.restoreItem(item) }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                        .padding(.bottom, AppTheme.Spacing.pageVertical)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.load() }
    }

    // MARK: Export

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "pare-history.json"
        panel.message = "Choose where to save the cleanup history"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(viewModel.transactions) else { return }
        try? data.write(to: url, options: .atomicWrite)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pare-history.csv"
        panel.message = "Choose where to save the cleanup history as CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var rows = ["date,profile,file_path,size_bytes,risk_level,is_dry_run"]
        for tx in viewModel.transactions {
            let date = tx.timestamp.ISO8601Format()
            for item in tx.items {
                let escapedPath = item.originalPath.replacingOccurrences(of: "\"", with: "\"\"")
                rows.append("\(date),\(tx.profileName),\"\(escapedPath)\",\(item.sizeBytes),\(item.riskLevelRaw),\(tx.isDryRun)")
            }
        }
        let csv = rows.joined(separator: "\n")
        try? csv.data(using: .utf8)?.write(to: url, options: .atomicWrite)
    }
}

// MARK: - TransactionCard

private struct TransactionCard: View {
    @Environment(\.pareDisplayScale) private var scale
    let transaction: CleanupTransaction
    let isExpanded: Bool
    let restoringItemID: String?
    let formatBytes: (Int64) -> String
    let formatDate: (Date) -> String
    let onToggle: () -> Void
    let onRestoreItem: (CleanupItem) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                // Session header row
                Button(action: onToggle) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                    .font(scale.font(13, weight: .semibold))
                                    .foregroundStyle(AppTheme.success)
                                Text(formatDate(transaction.timestamp))
                                    .font(scale.font(14, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                if transaction.isDryRun {
                                    Text("DRY RUN")
                                        .font(scale.font(10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.warning.opacity(0.2), in: Capsule())
                                        .foregroundStyle(AppTheme.warning)
                                }
                            }
                            Text("\(transaction.items.count) item\(transaction.items.count == 1 ? "" : "s") · \(transaction.profileName) profile")
                                .font(scale.font(12, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Text(formatBytes(transaction.totalBytesCandidates))
                            .font(scale.font(15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(scale.font(12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.borderless)

                if isExpanded {
                    Divider()
                        .opacity(0.15)
                        .padding(.vertical, 10)

                    VStack(spacing: 8) {
                        ForEach(transaction.items, id: \.originalPath) { item in
                            CleanupItemRow(
                                item: item,
                                isRestoring: restoringItemID == item.originalPath,
                                formatBytes: formatBytes,
                                onRestore: { onRestoreItem(item) }
                            )
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isExpanded)
    }
}

// MARK: - CleanupItemRow

private struct CleanupItemRow: View {
    @Environment(\.pareDisplayScale) private var scale
    let item: CleanupItem
    let isRestoring: Bool
    let formatBytes: (Int64) -> String
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(scale.font(11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text((item.originalPath as NSString).lastPathComponent)
                    .font(scale.font(12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(item.originalPath)
                    .font(scale.font(10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(item.sizeBytes))
                .font(scale.font(11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

            if item.trashedPath != nil {
                Button(action: onRestore) {
                    if isRestoring {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Restore")
                            .font(scale.font(12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRestoring)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.Hairline.faint, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
    }
}

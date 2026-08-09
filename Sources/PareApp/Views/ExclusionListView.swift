import SwiftUI
import PareCore

struct ExclusionListView: View {
    @Environment(\.pareDisplayScale) private var scale
    @ObservedObject var viewModel: ExclusionListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Excluded Paths")
                            .font(scale.font(20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Paths listed here are never flagged in scan results.")
                            .font(scale.font(12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderless)
                        .font(scale.font(14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider().opacity(0.15)

                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(scale.font(12, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                        Text(errorMessage)
                            .font(scale.font(12, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(AppTheme.warning.opacity(0.12))
                }

                if viewModel.entries.isEmpty {
                    EmptyStateView(
                        icon: "eye.slash",
                        title: "No exclusions yet",
                        message: "Right-click any finding and choose\n\"Exclude from Scans\" to add it here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.entries) { entry in
                                ExclusionEntryRow(entry: entry) {
                                    viewModel.remove(id: entry.id)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .frame(width: AppTheme.Sheet.standardWidth, height: AppTheme.Sheet.standardHeight)
    }
}

private struct ExclusionEntryRow: View {
    @Environment(\.pareDisplayScale) private var scale
    let entry: ExclusionEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.matchType == .prefix ? "folder.fill" : "doc.fill")
                .font(scale.font(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path)
                    .font(scale.font(12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(entry.matchType == .prefix ? "prefix match" : "exact match")
                    .font(scale.font(10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(scale.font(13, weight: .semibold))
                    .foregroundStyle(AppTheme.review)
            }
            .buttonStyle(.borderless)
            .help("Remove exclusion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
    }
}

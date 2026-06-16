import SwiftUI
import CleanMyMacCore

struct ExclusionListView: View {
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
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Paths listed here are never flagged in scan results.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider().opacity(0.15)

                if viewModel.entries.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                        Text("No exclusions yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Right-click any finding and choose\n\"Exclude from Scans\" to add it here.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
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
        .frame(width: 540, height: 420)
    }
}

private struct ExclusionEntryRow: View {
    let entry: ExclusionEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.matchType == .prefix ? "folder.fill" : "doc.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(entry.matchType == .prefix ? "prefix match" : "exact match")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.review)
            }
            .buttonStyle(.borderless)
            .help("Remove exclusion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

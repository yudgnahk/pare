import SwiftUI
import PareCore

struct DiskAnalyzerView: View {
    @ObservedObject var viewModel: DiskAnalyzerViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        ZStack {
            // Shell provides AppBackgroundView.

            VStack(spacing: 0) {
                header

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                if viewModel.isLoading {
                    loadingBody
                } else if let root = viewModel.rootNode {
                    treeBody(root: root)
                } else {
                    emptyBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Analyzer")
                    .font(scale.pageTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                if let url = viewModel.rootURL {
                    Text(url.path)
                        .font(scale.rowMono)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Choose a directory to analyze disk usage.")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 8, lineSpacing: 8, alignment: .leading) {
                if viewModel.rootURL != nil {
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

    // MARK: Error

    private func errorBanner(_ message: String) -> some View {
        ErrorBanner(message: message) {
            viewModel.errorMessage = nil
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.bottom, 10)
    }

    // MARK: Loading

    private var loadingBody: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyzing disk usage…")
                .font(scale.font(14, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
    }

    // MARK: Empty

    private var emptyBody: some View {
        EmptyStateView(
            icon: "externaldrive.badge.questionmark",
            title: "No directory selected",
            message: "Click \u{201C}Choose Directory\u{201D} to explore disk usage with a sortable, size-aware tree.",
            maxTextWidth: 380
        )
    }

    // MARK: Tree

    private func treeBody(root: DiskAnalyzerViewModel.DiskNode) -> some View {
        List(root.children, id: \.id, children: \.expandableChildren) { node in
            DiskNodeRow(
                node: node,
                formatBytes: viewModel.formattedBytes
            ) {
                viewModel.revealInFinder(node.url)
            } onTrash: {
                viewModel.moveToTrash(node.url)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - DiskNodeRow

private struct DiskNodeRow: View {
    let node: DiskAnalyzerViewModel.DiskNode
    let formatBytes: (Int64) -> String
    let onReveal: () -> Void
    let onTrash: () -> Void
    @Environment(\.pareDisplayScale) private var scale

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(scale.font(14, weight: .medium))
                .foregroundStyle(node.isDirectory ? AppTheme.accent : AppTheme.textSecondary.opacity(0.7))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(node.name)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(AppTheme.Fill.subtle)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barColor)
                            .frame(width: max(3, geo.size.width * node.shareOfParent), height: 3)
                    }
                }
                .frame(height: 3)
            }

            Spacer(minLength: 8)

            Text(formatBytes(node.sizeBytes))
                .font(scale.font(14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: scale.scaled(84), alignment: .trailing)

            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onReveal) {
                        Image(systemName: "arrow.right.circle")
                            .font(scale.font(13))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")

                    Button(action: onTrash) {
                        Image(systemName: "trash")
                            .font(scale.font(13))
                            .foregroundStyle(AppTheme.review)
                    }
                    .buttonStyle(.borderless)
                    .help("Move to Trash")
                }
            } else {
                // Reserve space so the row width doesn't shift on hover.
                Color.clear.frame(width: 46, height: 16)
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
    }

    private var barColor: Color {
        let share = node.shareOfParent
        if share > 0.5 { return AppTheme.review }
        if share > 0.25 { return AppTheme.warning }
        return AppTheme.accent
    }
}

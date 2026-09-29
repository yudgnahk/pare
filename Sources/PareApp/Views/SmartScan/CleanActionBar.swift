import SwiftUI

/// Floating bottom bar that owns every clean action; each one still opens its confirmation sheet.
struct CleanActionBar: View {
    @ObservedObject var viewModel: ScanDashboardViewModel

    @Environment(\.pareDisplayScale) private var scale
    @Environment(\.isSnapshotRendering) private var isSnapshotRendering

    private var hasSelection: Bool { viewModel.selectedCandidatesCount > 0 }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            selectionSummary
            Spacer(minLength: AppTheme.Spacing.sm)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    selectionMenu
                    deepCleanButton
                    quickCleanButton
                    cleanSelectedButton
                }
                HStack(spacing: 8) {
                    compactMenu
                    cleanSelectedButton
                }
            }
        }
        .padding(.horizontal, scale.space(AppTheme.Spacing.lg))
        .padding(.vertical, scale.space(AppTheme.Spacing.md))
        .background(barBackground)
        .shadow(color: AppTheme.Shadow.card.opacity(AppTheme.Elevation.floating.opacity), radius: AppTheme.Elevation.floating.radius, y: AppTheme.Elevation.floating.y)
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: hasSelection ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(hasSelection ? AppTheme.success : AppTheme.textTertiary)
                Text(hasSelection ? "\(viewModel.selectedCandidatesCount) selected" : "Nothing selected")
                    .foregroundStyle(AppTheme.textPrimary)
                if hasSelection {
                    CountingBytesText(bytes: viewModel.selectedCandidatesBytes, font: scale.font(14, weight: .bold, design: .rounded), color: AppTheme.textPrimary)
                }
            }
            .font(scale.font(14, weight: .semibold))
            .lineLimit(1)

            Text("Everything goes to the Trash first")
                .font(scale.font(11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var selectionMenu: some View {
        Menu {
            selectionItems
        } label: {
            Label("Select", systemImage: "checklist")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(AppTheme.textPrimary)
        .help("Change which items are selected")
    }

    @ViewBuilder
    private var selectionItems: some View {
        Button("Select All Safe Items") {
            viewModel.collapseBrowserSections()
            viewModel.selectAllSafe()
        }
        Button("Clear Selection") {
            // Collapse expanded trees first so Clear doesn't re-diff huge views.
            viewModel.collapseBrowserSections()
            viewModel.clearSelection()
        }
    }

    private var compactMenu: some View {
        Menu {
            selectionItems
            Divider()
            if viewModel.quickCleanCandidatesCount > 0 {
                Button("Quick Clean All Safe Items…") { viewModel.requestQuickClean() }
            }
            if viewModel.reviewRiskCandidatesCount > 0 {
                Button("Deep Clean Safe + Review…", role: .destructive) { viewModel.requestDeepClean() }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var deepCleanButton: some View {
        if viewModel.reviewRiskCandidatesCount > 0 {
            SecondaryActionButton(title: "Deep Clean…", systemImage: "bolt", role: .destructive, isEnabled: !viewModel.isCleaning) {
                viewModel.requestDeepClean()
            }
            .help("Safe + Review items. Opens a confirmation first.")
        }
    }

    @ViewBuilder
    private var quickCleanButton: some View {
        if viewModel.quickCleanCandidatesCount > 0 {
            SecondaryActionButton(title: "Quick Clean", systemImage: "checkmark.shield", role: .accent, isEnabled: !viewModel.isCleaning) {
                viewModel.requestQuickClean()
            }
            .help("All Safe items, regardless of selection. Opens a confirmation first.")
        }
    }

    private var cleanSelectedButton: some View {
        PrimaryActionButton(
            title: "Clean Selected",
            systemImage: "trash",
            isLoading: viewModel.isCleaning,
            style: .compact,
            tint: .success,
            isEnabled: hasSelection
        ) {
            viewModel.requestCleanSelected()
        }
    }

    @ViewBuilder
    private var barBackground: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
        ZStack {
            if isSnapshotRendering {
                shape.fill(AppTheme.panel)
            } else {
                shape.fill(.regularMaterial)
                shape.fill(AppTheme.cardFill.opacity(0.55))
            }
            shape.strokeBorder(AppTheme.Hairline.strong, lineWidth: 1)
        }
    }
}

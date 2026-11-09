import SwiftUI
import PareCore

/// Results grouped by owner: Apps, Projects, Developer tools, macOS, Other. No animation on this tree.
struct OwnerBrowserView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        if viewModel.ownerSections.isEmpty {
            Text("Nothing to clean.")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.ownerSections) { section in
                    sectionView(section)
                }
            }
        }
    }

    private func sectionView(_ section: OwnerSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ScanDashboardViewModel.sectionTitle(section.kind))
                    .font(scale.badge)
                    .tracking(0.4)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 8)
                Text(viewModel.formattedOwnerSize(bytes: section.totalBytes, isPartial: section.hasPartialSize))
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            VStack(spacing: 8) {
                ForEach(section.groups) { group in
                    OwnerGroupSection(viewModel: viewModel, group: group)
                }
            }
        }
    }
}

#if DEBUG
struct OwnerBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        OwnerBrowserView(viewModel: makeModel())
            .padding(24)
            .frame(width: 720)
            .background(AppTheme.base)
    }

    @MainActor
    private static func makeModel() -> ScanDashboardViewModel {
        let model = ScanDashboardViewModel(browseModes: .inMemory())
        model.applySnapshotResults(SnapshotFixtures.scanReport, owners: SnapshotFixtures.ownerInputs)
        return model
    }
}
#endif

import SwiftUI
import PareCore

/// Smart Scan results by clean category, narrowed by owner chips. No animation on this tree.
struct CleanListView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        if viewModel.cleanRows.isEmpty {
            Text("Nothing to clean.")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                OwnerChipsBar(viewModel: viewModel)
                ForEach(viewModel.cleanSections) { section in
                    CleanSectionView(viewModel: viewModel, section: section)
                }
            }
        }
    }

    static func emptyMessage(grouped: Bool) -> String {
        grouped
            ? "Start a scan to see what you can clean."
            : "Start a scan to browse reclaimable storage by category."
    }
}

#if DEBUG
struct CleanListView_Previews: PreviewProvider {
    static var previews: some View {
        CleanListView(viewModel: makeModel())
            .padding(24)
            .frame(width: 760)
            .background(AppTheme.base)
    }

    @MainActor
    private static func makeModel() -> ScanDashboardViewModel {
        let model = ScanDashboardViewModel()
        model.applySnapshotResults(SnapshotFixtures.scanReport, owners: SnapshotFixtures.ownerInputs)
        return model
    }
}
#endif

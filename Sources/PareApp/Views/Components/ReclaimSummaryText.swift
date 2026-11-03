import PareCore
import SwiftUI

/// "Estimated X · Disk actually gained Y", plus the empty-the-Trash hint when the disk gained far less.
struct ReclaimSummaryText: View {
    let summary: ReclaimSummary

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.text)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
            if let hint = summary.trashHint {
                Label(hint, systemImage: "trash")
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
struct ReclaimSummaryText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReclaimSummaryText(summary: ReclaimSummary(estimatedBytes: 4_200_000_000, measuredBytes: 4_100_000_000))
            ReclaimSummaryText(summary: ReclaimSummary(estimatedBytes: 4_200_000_000, measuredBytes: 12_000_000))
        }
        .padding()
    }
}
#endif

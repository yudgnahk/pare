import PareCore
import SwiftUI

/// Compact startup-disk meter for the sidebar footer.
struct StorageMeter: View {
    let usage: VolumeUsage

    @Environment(\.pareDisplayScale) private var scale

    /// Below this share of free space the meter turns apricot.
    static let lowSpaceThreshold = 0.10

    private var isLow: Bool {
        usage.totalBytes > 0 && Double(usage.availableBytes) / Double(usage.totalBytes) < Self.lowSpaceThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(scale.font(11, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                Text(usage.name)
                    .font(scale.font(12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Fill.control)
                    Capsule()
                        .fill(isLow ? AnyShapeStyle(AppTheme.warm) : AnyShapeStyle(AppTheme.barGradient))
                        .frame(width: max(6, geo.size.width * usage.usedFraction))
                }
            }
            .frame(height: 6)

            Text("\(ScanReportPresenter.formatBytes(usage.availableBytes)) available of \(ScanReportPresenter.formatBytes(usage.totalBytes))")
                .font(scale.font(11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isLow ? AppTheme.warmText : AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }
}

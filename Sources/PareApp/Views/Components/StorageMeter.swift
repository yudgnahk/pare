import PareCore
import SwiftUI

/// Compact startup-disk meter for the sidebar footer.
struct StorageMeter: View {
    let usage: VolumeUsage
    /// Optional breakdown line under the free-space text; hidden when it has nothing to say.
    var header: DiskHeaderSnapshot?

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

            if let detail = header?.detailLine {
                Text(detail)
                    .font(scale.font(10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(warnsOfSwapPressure ? AppTheme.warning : AppTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(warnsOfSwapPressure
                        ? "\(detail). Heavy swap on a nearly full disk slows the Mac — free space or quit memory-heavy apps."
                        : detail)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var warnsOfSwapPressure: Bool {
        header?.warnsOfSwapPressure(freeBytes: usage.availableBytes) ?? false
    }
}

#if DEBUG
struct StorageMeter_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            StorageMeter(
                usage: VolumeUsage(name: "Macintosh HD", totalBytes: 494_000_000_000, availableBytes: 82_000_000_000),
                header: DiskHeaderSnapshot(purgeableBytes: 3_200_000_000, swapUsedBytes: 1_100_000_000, localSnapshotCount: 4)
            )
            StorageMeter(
                usage: VolumeUsage(name: "Macintosh HD", totalBytes: 494_000_000_000, availableBytes: 7_000_000_000),
                header: DiskHeaderSnapshot(purgeableBytes: nil, swapUsedBytes: 6_500_000_000, localSnapshotCount: 0)
            )
        }
        .padding()
        .frame(width: 240)
    }
}
#endif

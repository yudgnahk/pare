import SwiftUI
import PareCore

/// Donut chart of reclaimable space by attributed tool/app (visual only — selection lives elsewhere).
/// Pure SwiftUI/Canvas so it works on macOS 13 (Charts `SectorMark` needs 14+).
struct ToolShareChart: View {
    let rollups: [ToolRollup]
    let formatBytes: (Int64) -> String
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where space goes")
                        .font(scale.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Share of reclaimable storage by app or tool. Use Browse by category or Largest items to select what to clean.")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if rollups.isEmpty {
                    Text("No tool breakdown for this scan.")
                        .font(scale.body)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ViewThatFits(in: .horizontal) {
                        wideLayout
                        compactLayout
                    }
                }
            }
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 20) {
            donut
                .frame(width: 168, height: 168)
            legend
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            donut
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity)
            legend
        }
    }

    private var donut: some View {
        let slices = sliceData
        return ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let rect = CGRect(
                    x: (size.width - side) / 2,
                    y: (size.height - side) / 2,
                    width: side,
                    height: side
                )
                let lineWidth = side * 0.18
                let inset = lineWidth / 2 + 1
                let drawRect = rect.insetBy(dx: inset, dy: inset)

                var start = Angle.degrees(-90)
                for slice in slices {
                    let end = start + slice.angle
                    var path = Path()
                    path.addArc(
                        center: CGPoint(x: drawRect.midX, y: drawRect.midY),
                        radius: drawRect.width / 2,
                        startAngle: start,
                        endAngle: end,
                        clockwise: false
                    )
                    context.stroke(
                        path,
                        with: .color(slice.color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    // Small gap between slices
                    start = end + .degrees(slices.count > 1 ? 1.2 : 0)
                }
            }

            VStack(spacing: 2) {
                Text("\(rollups.count)")
                    .font(scale.font(18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("tools")
                    .font(scale.micro)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage share by tool")
        .accessibilityValue(accessibilitySummary)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rollups.prefix(10).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(CategoryStyle.chartColor(at: index))
                        .frame(width: 8, height: 8)

                    Text(item.app)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(Int((item.share * 100).rounded()))%")
                        .font(scale.font(11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()

                    Text(formatBytes(item.totalBytes))
                        .font(scale.font(12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            if rollups.count > 10 {
                Text("+\(rollups.count - 10) more")
                    .font(scale.micro)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private struct Slice {
        let angle: Angle
        let color: Color
    }

    private var sliceData: [Slice] {
        let total = rollups.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard total > 0 else { return [] }
        let gapCount = max(rollups.count, 1)
        let gapDegrees = rollups.count > 1 ? 1.2 * Double(gapCount) : 0
        let usable = 360.0 - gapDegrees
        return rollups.enumerated().map { index, item in
            let fraction = Double(item.totalBytes) / Double(total)
            return Slice(
                angle: .degrees(usable * fraction),
                color: CategoryStyle.chartColor(at: index)
            )
        }
    }

    private var accessibilitySummary: String {
        rollups.prefix(5).map {
            "\($0.app) \(Int(($0.share * 100).rounded())) percent"
        }.joined(separator: ", ")
    }
}

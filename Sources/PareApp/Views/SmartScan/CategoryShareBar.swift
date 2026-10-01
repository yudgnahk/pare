import SwiftUI
import PareCore

/// Stacked bar of reclaimable bytes by category, with a legend for the largest few.
struct CategoryShareBar: View {
    let summaries: [SummaryItem]
    let formatBytes: (Int64) -> String
    var legendCount = 4

    @Environment(\.pareDisplayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var total: Int64 { max(summaries.reduce(0) { $0 + $1.reclaimableBytes }, 1) }
    private var visible: [SummaryItem] { summaries.filter { $0.reclaimableBytes > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar
            FlowLayout(spacing: 14, lineSpacing: 6, alignment: .leading) {
                ForEach(visible.prefix(legendCount)) { summary in
                    LegendDot(
                        color: CategoryStyle.tint(for: summary.category),
                        label: summary.category.rawValue,
                        value: formatBytes(summary.reclaimableBytes)
                    )
                }
                if visible.count > legendCount {
                    Text("+\(visible.count - legendCount) more")
                        .font(scale.font(12, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .onAppear {
            MotionPolicy.perform(AppTheme.Motion.reveal.delay(0.2), reduceMotion: reduceMotion) { grown = true }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(visible.count - 1, 0)) * 2
            let usable = max(geo.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(visible) { summary in
                    let share = CGFloat(summary.reclaimableBytes) / CGFloat(total)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CategoryStyle.tint(for: summary.category))
                        .frame(width: max(3, usable * share))
                        .help("\(summary.category.rawValue) · \(formatBytes(summary.reclaimableBytes))")
                }
            }
            .frame(width: grown ? geo.size.width : 0, alignment: .leading)
            .clipShape(Capsule(style: .continuous))
        }
        .frame(height: scale.space(10))
        .background(AppTheme.Fill.control, in: Capsule(style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Reclaimable space by category")
    }
}

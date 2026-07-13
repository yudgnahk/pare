import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String
    let tint: Color
    @Environment(\.displayScale) private var scale

    var body: some View {
        GlassCard(padding: scale.space(16)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(label.uppercased())
                        .font(scale.font(11, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(scale.font(30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail)
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

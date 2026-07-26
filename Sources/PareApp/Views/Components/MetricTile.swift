import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String
    let tint: Color
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        GlassCard(padding: scale.space(AppTheme.Spacing.lg)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(label.uppercased())
                        .font(scale.micro)
                        .tracking(1.0)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(scale.font(24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail)
                    .font(scale.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

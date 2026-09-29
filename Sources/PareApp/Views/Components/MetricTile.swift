import SwiftUI

/// Decision tile: icon, uppercase label, a counting byte total (or plain value), and a detail line.
struct MetricTile: View {
    let label: String
    var icon: String = "circle.fill"
    var bytes: Int64? = nil
    var value: String = ""
    let detail: String
    let tint: Color

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        GlassCard(padding: scale.space(AppTheme.Spacing.lg), cornerRadius: AppTheme.Radius.lg, elevation: .subtle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(scale.font(12, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    Text(label.uppercased())
                        .font(scale.eyebrow)
                        .tracking(1.1)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Group {
                    if let bytes {
                        CountingBytesText(bytes: bytes, font: scale.font(26, weight: .bold, design: .rounded))
                    } else {
                        Text(value)
                            .font(scale.font(26, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(detail)
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
        }
    }
}

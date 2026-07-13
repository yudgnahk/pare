import SwiftUI
import PareCore

struct CategorySummaryRow: View {
    let title: String
    let bytesText: String
    let fileCount: Int
    let share: Double
    let color: Color
    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(title)
                        .font(scale.rowTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                Text(bytesText)
                    .font(scale.font(14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.75), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geometry.size.width * share))
                }
            }
            .frame(height: 8)

            Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

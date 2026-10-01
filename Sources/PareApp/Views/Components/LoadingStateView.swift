import SwiftUI

/// Centered loading placeholder: slow-spinning seafoam arc plus a status line.
struct LoadingStateView: View {
    let message: String
    var detail: String? = nil

    @Environment(\.pareDisplayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Fill.control, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: reduceMotion ? 1 : 0.28)
                    .stroke(AppTheme.ringGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(MotionPolicy.animation(.linear(duration: 1.1).repeatForever(autoreverses: false), reduceMotion: reduceMotion), value: spinning)
            }
            .frame(width: scale.space(40), height: scale.space(40))
            .accessibilityHidden(true)

            Text(message)
                .font(scale.font(14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            if let detail {
                Text(detail)
                    .font(scale.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { spinning = true }
        .accessibilityElement(children: .combine)
    }
}

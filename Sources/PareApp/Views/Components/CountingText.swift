import SwiftUI
import PareCore

/// Byte total that counts up from zero on appear and eases between later values.
struct CountingBytesText: View {
    let bytes: Int64
    var font: Font
    var color: Color = AppTheme.textPrimary

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatableNumberText(value: shown, format: { ScanReportPresenter.formatBytes(Int64($0)) })
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityLabel(ScanReportPresenter.formatBytes(bytes))
            .onAppear { animate(to: bytes) }
            .onChange(of: bytes) { animate(to: $0) }
    }

    private func animate(to target: Int64) {
        MotionPolicy.perform(AppTheme.Motion.countUp, reduceMotion: reduceMotion) {
            shown = Double(target)
        }
    }
}

/// Whole-number percentage that eases between values (scan progress).
struct CountingPercentText: View {
    let fraction: Double
    var font: Font
    var color: Color = AppTheme.textPrimary

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatableNumberText(value: shown, format: { "\(Int(($0 * 100).rounded()))%" })
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .onAppear { animate(to: fraction) }
            .onChange(of: fraction) { animate(to: $0) }
    }

    private func animate(to target: Double) {
        MotionPolicy.perform(AppTheme.Motion.standard, reduceMotion: reduceMotion) {
            shown = min(max(target, 0), 1)
        }
    }
}

/// Re-formats its text every animation frame so numbers roll rather than cross-fade.
private struct AnimatableNumberText: View, Animatable {
    var value: Double
    let format: @Sendable (Double) -> String

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

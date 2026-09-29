import SwiftUI

/// Disk ring: seafoam arc for used space with the reclaimable share in apricot at its tip.
struct DiskUsageRing<Center: View>: View {
    var usedFraction: Double
    var reclaimableFraction: Double = 0
    var diameter: CGFloat
    var lineWidth: CGFloat
    @ViewBuilder var center: () -> Center

    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var used: Double { drawn ? clamp(usedFraction) : 0 }
    private var reclaimStart: Double { drawn ? clamp(usedFraction - reclaimableFraction) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Fill.control, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: used)
                .stroke(AppTheme.ringGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if reclaimableFraction > 0 {
                Circle()
                    .trim(from: reclaimStart, to: used)
                    .stroke(AppTheme.warm, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: AppTheme.warm.opacity(0.45), radius: lineWidth * 0.6)
            }

            center()
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            MotionPolicy.perform(AppTheme.Motion.ringFill.delay(0.15), reduceMotion: reduceMotion) {
                drawn = true
            }
        }
        .motionAwareAnimation(AppTheme.Motion.ringFill, value: usedFraction)
        .motionAwareAnimation(AppTheme.Motion.ringFill, value: reclaimableFraction)
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// Honest scan progress: rule-count arc plus a soft travelling highlight on the track.
struct ScanProgressRing: View {
    var fraction: Double
    var diameter: CGFloat
    var lineWidth: CGFloat

    @State private var orbiting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Fill.control, lineWidth: lineWidth)

            if !reduceMotion {
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.accentBright.opacity(0), AppTheme.accentBright.opacity(0.35)],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(65)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(orbiting ? 270 : -90))
                    .animation(AppTheme.Motion.orbit, value: orbiting)
            }

            Circle()
                .trim(from: 0, to: min(max(fraction, 0.015), 1))
                .stroke(AppTheme.ringGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: AppTheme.accentBright.opacity(0.4), radius: lineWidth * 0.5)
                .motionAwareAnimation(AppTheme.Motion.standard, value: fraction)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { orbiting = true }
        .accessibilityElement()
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

#if DEBUG
struct DiskUsageRing_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 32) {
            DiskUsageRing(usedFraction: 0.68, reclaimableFraction: 0.08, diameter: 200, lineWidth: 14) {
                Text("68%").font(.title.bold())
            }
            ScanProgressRing(fraction: 0.42, diameter: 200, lineWidth: 14)
        }
        .padding(32)
        .background(AppTheme.base)
    }
}
#endif

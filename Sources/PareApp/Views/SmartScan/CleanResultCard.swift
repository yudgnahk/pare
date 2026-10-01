import SwiftUI

/// The "you just freed X" moment: drawn check ring, counting total, one-shot sparkle burst, Undo.
struct CleanResultCard: View {
    let bytesFreed: Int64
    let skippedCount: Int
    let canUndo: Bool
    let onUndo: () -> Void
    /// Replaces the generic skip count when one symlinked ancestor blocked every item.
    var skipExplanation: String?
    let onDismiss: () -> Void

    @Environment(\.pareDisplayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrated = false

    var body: some View {
        GlassCard(padding: scale.space(AppTheme.Spacing.xl), cornerRadius: AppTheme.Radius.hero) {
            HStack(alignment: .center, spacing: scale.space(AppTheme.Spacing.xl)) {
                badge
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLEANUP COMPLETE")
                        .font(scale.eyebrow)
                        .tracking(1.1)
                        .foregroundStyle(AppTheme.success)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        CountingBytesText(bytes: bytesFreed, font: scale.display)
                        Text("freed")
                            .font(scale.font(20, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Text(detail)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                actions
            }
        }
        .background(successGlow)
        .onAppear {
            MotionPolicy.perform(AppTheme.Motion.gentle, reduceMotion: reduceMotion) { celebrated = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        let base = "Moved to the Trash. Nothing is erased until you empty it."
        guard skippedCount > 0 else { return base }
        if let skipExplanation { return base + " " + skipExplanation }
        return base + " \(skippedCount) item\(skippedCount == 1 ? " was" : "s were") skipped by the safety check."
    }

    private var badge: some View {
        let size = scale.space(84)
        return ZStack {
            if !reduceMotion {
                SparkleBurst(active: celebrated, radius: size * 0.78)
            }
            Circle()
                .fill(AppTheme.success.opacity(0.14))
            Circle()
                .trim(from: 0, to: celebrated ? 1 : 0)
                .stroke(AppTheme.success, style: StrokeStyle(lineWidth: scale.space(5), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(scale.space(5))
            Image(systemName: "checkmark")
                .font(scale.font(30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.success)
                .scaleEffect(celebrated ? 1 : 0.4)
                .opacity(celebrated ? 1 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if canUndo {
                SecondaryActionButton(title: "Undo", systemImage: "arrow.uturn.backward", role: .accent, action: onUndo)
                    .help("Put everything back from the Trash")
            }
            IconActionButton(systemImage: "xmark", help: "Dismiss", action: onDismiss)
        }
        .fixedSize()
    }

    private var successGlow: some View {
        RadialGradient(
            colors: [AppTheme.success.opacity(0.16), .clear],
            center: .leading,
            startRadius: 10,
            endRadius: 380
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Eight sparkles that fly outward once and fade; decorative only.
private struct SparkleBurst: View {
    let active: Bool
    let radius: CGFloat

    private static let count = 8

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { index in
                let angle = Double(index) / Double(Self.count) * 2 * .pi
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 11 : 5, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 3) ? AppTheme.warm : AppTheme.accentBright)
                    .offset(
                        x: active ? cos(angle) * radius : 0,
                        y: active ? sin(angle) * radius : 0
                    )
                    .opacity(active ? 0 : 1)
                    .animation(.easeOut(duration: 1.1).delay(0.25), value: active)
            }
        }
    }
}

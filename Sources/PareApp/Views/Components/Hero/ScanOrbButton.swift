import SwiftUI

/// The Smart Scan call to action: a luminous seafoam orb with a slow breathing halo.
struct ScanOrbButton: View {
    let title: String
    var subtitle: String? = nil
    var diameter: CGFloat
    let action: () -> Void

    @State private var hovering = false
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentBright.opacity(hovering ? 0.30 : 0.20))
                    .frame(width: diameter * 1.12, height: diameter * 1.12)
                    .scaleEffect(breathing ? 1.04 : 0.97)
                    .blur(radius: diameter * 0.08)

                Circle()
                    .fill(AppTheme.ctaGradient)
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [AppTheme.sheen.opacity(0.28), .clear],
                                    center: UnitPoint(x: 0.35, y: 0.2),
                                    startRadius: 0,
                                    endRadius: diameter * 0.6
                                )
                            )
                    )
                    .overlay(Circle().strokeBorder(AppTheme.sheen.opacity(0.22), lineWidth: 1))
                    .shadow(color: AppTheme.accentDeep.opacity(0.45), radius: 22, y: 12)

                label
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(AppTheme.Motion.standard, value: hovering)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
        .onHover { hovering = $0 }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AppTheme.Motion.breathe) { breathing = true }
        }
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(title)
        .help("Scan this Mac for reclaimable space")
    }

    private var label: some View {
        VStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(scale.font(22, weight: .semibold))
            Text(title)
                .font(scale.font(24, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(scale.font(11, weight: .semibold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(AppTheme.onAccent)
    }
}

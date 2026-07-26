import SwiftUI

/// Large circular primary CTA inspired by App B's Scan control.
struct PrimaryRingButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.pareDisplayScale) private var scale
    @State private var hovering = false
    @State private var pulsing = false

    private var size: CGFloat { scale.scaled(AppTheme.Control.ringButtonSize) }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Soft outer glow
                Circle()
                    .fill(AppTheme.accent.opacity(hovering || isLoading ? 0.22 : 0.12))
                    .frame(width: size + 28, height: size + 28)
                    .scaleEffect(pulsing && isLoading ? 1.08 : 1)
                    .blur(radius: 2)

                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                AppTheme.accent,
                                AppTheme.accentDeep,
                                AppTheme.success.opacity(0.8),
                                AppTheme.accent
                            ],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(
                        isLoading
                            ? .linear(duration: 1.6).repeatForever(autoreverses: false)
                            : .default,
                        value: isLoading
                    )

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.panel.opacity(0.95),
                                AppTheme.panelSecondary.opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size - 10, height: size - 10)
                    .overlay(
                        Circle()
                            .strokeBorder(AppTheme.Hairline.strong, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.25), radius: hovering ? 18 : 10, y: 6)

                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(AppTheme.accent)
                } else {
                    Text(title)
                        .font(scale.font(15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .scaleEffect(hovering && isEnabled && !isLoading ? 1.04 : 1)
            .animation(AppTheme.Motion.standard, value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .onHover { hovering = $0 }
        .onAppear {
            if isLoading { pulsing = true }
        }
        .onChange(of: isLoading) { loading in
            pulsing = loading
        }
        .accessibilityLabel(title)
    }
}

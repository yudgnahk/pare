import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.textPrimary)
                } else {
                    Image(systemName: systemImage)
                }

                Text(isLoading ? "Scanning..." : title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent,
                                AppTheme.success
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.5 : 0.26), lineWidth: 1)
            )
            .scaleEffect(hovering ? 1.02 : 1)
            .shadow(color: AppTheme.accent.opacity(0.3), radius: hovering ? 14 : 8, x: 0, y: 6)
            .animation(.easeOut(duration: 0.18), value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { inside in
            hovering = inside
        }
    }
}

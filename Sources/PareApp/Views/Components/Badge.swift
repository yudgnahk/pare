import SwiftUI

/// Tiny status chip used inside rows ("pinned", "auto", "MAS", "brew", "SIP").
struct Badge: View {
    let text: String
    let color: Color
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        Text(text)
            .font(scale.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                color.opacity(0.18),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.badge, style: .continuous)
            )
    }
}

#Preview("Badges") {
    HStack(spacing: 8) {
        Badge(text: "pinned", color: AppTheme.accent)
        Badge(text: "auto", color: AppTheme.accent)
        Badge(text: "orphaned", color: AppTheme.warning)
        Badge(text: "brew", color: AppTheme.success)
        Badge(text: "SIP", color: AppTheme.textSecondary)
    }
    .padding(24)
    .background(AppTheme.base)
}

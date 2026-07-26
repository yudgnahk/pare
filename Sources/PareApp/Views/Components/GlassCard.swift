import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = AppTheme.Spacing.card
    var cornerRadius: CGFloat = AppTheme.Radius.xl
    let content: Content

    init(
        padding: CGFloat = AppTheme.Spacing.card,
        cornerRadius: CGFloat = AppTheme.Radius.xl,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.panel.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        AppTheme.Hairline.strong,
                                        AppTheme.accent.opacity(0.08),
                                        AppTheme.Hairline.faint
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
    }
}

import SwiftUI

/// Raised card surface: translucent panel fill, top-edge sheen, soft two-layer shadow.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = AppTheme.Spacing.card
    var cornerRadius: CGFloat = AppTheme.Radius.xl
    var elevation: AppTheme.Elevation = .raised
    let content: Content

    init(
        padding: CGFloat = AppTheme.Spacing.card,
        cornerRadius: CGFloat = AppTheme.Radius.xl,
        elevation: AppTheme.Elevation = .raised,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevation = elevation
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(AppTheme.cardFill)
                    .overlay(
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [AppTheme.Shadow.highlight, AppTheme.Hairline.standard, AppTheme.Hairline.faint],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: AppTheme.Shadow.card.opacity(0.5 * elevation.opacity), radius: 1, x: 0, y: 1)
                    .shadow(color: AppTheme.Shadow.card.opacity(elevation.opacity), radius: elevation.radius, x: 0, y: elevation.y)
            )
    }
}

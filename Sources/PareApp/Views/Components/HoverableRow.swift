import SwiftUI

/// Shared hover chrome for list rows: horizontal/vertical padding, rounded
/// hover highlight, and `onHover` tracking that writes into the row's own
/// `@State` binding so the row can also fade action buttons in/out.
struct HoverableRowModifier: ViewModifier {
    @Binding var isHovered: Bool
    var verticalPadding: CGFloat
    var horizontalPadding: CGFloat = AppTheme.Spacing.lg
    var hoverFill: Color = AppTheme.Fill.subtle
    var restFill: Color = .clear

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .fill(isHovered ? hoverFill : restFill)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Applies the standard hoverable-row chrome (padding + rounded highlight).
    func hoverableRow(
        isHovered: Binding<Bool>,
        verticalPadding: CGFloat,
        horizontalPadding: CGFloat = AppTheme.Spacing.lg,
        hoverFill: Color = AppTheme.Fill.subtle,
        restFill: Color = .clear
    ) -> some View {
        modifier(
            HoverableRowModifier(
                isHovered: isHovered,
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                hoverFill: hoverFill,
                restFill: restFill
            )
        )
    }
}

private struct HoverableRowPreviewHost: View {
    @State private var isHovered = false

    var body: some View {
        HStack {
            Text("Hover me")
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text(isHovered ? "hovered" : "resting")
                .foregroundStyle(AppTheme.textSecondary)
        }
        .hoverableRow(isHovered: $isHovered, verticalPadding: 10)
    }
}

#Preview("HoverableRow") {
    VStack(spacing: 4) {
        HoverableRowPreviewHost()
        HoverableRowPreviewHost()
    }
    .padding(24)
    .background(AppTheme.base)
}

import SwiftUI

/// Shared chrome for sortable-table column headers (Apps, Homebrew tabs):
/// header typography, secondary tint, padding, and the dark header strip.
/// Call sites provide the column labels; widths stay at the call site because
/// they must match the row layout beneath.
struct TableHeaderRow<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
        .font(scale.tableHeader)
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.tableHeaderBackground)
    }
}

#if DEBUG
struct TableHeaderRow_Previews: PreviewProvider {
    static var previews: some View {
        TableHeaderRow {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Version").frame(width: 100, alignment: .leading)
            Text("Size").frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 50)
        }
        .frame(width: 520)
        .background(AppTheme.base)
        .previewDisplayName("TableHeaderRow")
    }
}
#endif

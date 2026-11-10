import SwiftUI

/// `Apps · Categories` switch. Plain buttons, not `Picker(.segmented)`, which grabs key focus.
struct BrowseModeSwitch: View {
    let mode: BrowseMode
    let onSelect: (BrowseMode) -> Void
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BrowseMode.allCases, id: \.self) { option in
                Button { onSelect(option) } label: {
                    Text(Self.title(option))
                        .font(scale.caption)
                        .lineLimit(1)
                        .foregroundStyle(mode == option ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            mode == option ? AppTheme.Fill.selected : Color.clear,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.chipCompact, style: .continuous)
                        )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Self.accessibilityLabel(option))
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .help("Group results")
    }

    static func emptyMessage(byApp: Bool) -> String {
        "Start a scan to browse reclaimable storage by \(byApp ? "app" : "category")."
    }

    static func accessibilityLabel(_ mode: BrowseMode) -> String {
        "Browse by \(mode == .apps ? "app" : "category")"
    }

    static func title(_ mode: BrowseMode) -> String {
        switch mode {
        case .apps: return "Apps"
        case .categories: return "Categories"
        }
    }
}

#if DEBUG
struct BrowseModeSwitch_Previews: PreviewProvider {
    static var previews: some View {
        BrowseModeSwitch(mode: .apps, onSelect: { _ in })
            .padding(24)
            .background(AppTheme.base)
    }
}
#endif

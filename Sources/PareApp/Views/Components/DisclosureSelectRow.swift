import SwiftUI

/// Tri-state selection for a group of findings (all / some / none selected).
enum TriSelectionState {
    case all
    case partial
    case none

    var systemImage: String {
        switch self {
        case .all: return "checkmark.circle.fill"
        case .partial: return "minus.circle.fill"
        case .none: return "circle"
        }
    }
}

/// Shared anatomy of the expandable "Browse by category" section headers:
/// [tri-state select] [leading visual · title · count chip … size · chevron].
///
/// `.category` style renders the top-level category row; `.tool` style renders
/// the nested tool-group row (denser, on a recessed background).
struct DisclosureSelectRow<Leading: View>: View {
    enum Style {
        case category
        case tool
    }

    let style: Style
    let title: String
    var badgeText: String? = nil
    let sizeText: String
    let isExpanded: Bool
    let selection: TriSelectionState
    var isSelectable: Bool = true
    var selectHelp: String = ""
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void
    @ViewBuilder let leading: () -> Leading

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: style == .category ? 10 : 8) {
            selectButton
            disclosureButton
        }
        .padding(.horizontal, style == .category ? 4 : 8)
        .padding(.vertical, style == .category ? 6 : 7)
        .background(rowBackground)
    }

    private var selectButton: some View {
        Button(action: onToggleSelect) {
            Image(systemName: selection.systemImage)
                .font(scale.font(style == .category ? 16 : 15, weight: .semibold))
                .foregroundStyle(isSelectable ? AppTheme.accent : AppTheme.textTertiary)
                .frame(width: 20)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .help(selectHelp)
    }

    private var disclosureButton: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: style == .category ? 10 : 8) {
                leading()

                Text(title)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if let badgeText {
                    Text(badgeText)
                        .font(scale.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.Fill.control, in: Capsule())
                }

                Spacer(minLength: style == .category ? 8 : 6)

                Text(sizeText)
                    .font(scale.font(style == .category ? 14 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(scale.micro)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: style == .category ? 12 : nil)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if style == .tool {
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.65))
        }
    }
}

#if DEBUG
struct DisclosureSelectRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            DisclosureSelectRow(
                style: .category,
                title: "Developer Package Caches",
                badgeText: "6 tools",
                sizeText: "12.4 GB",
                isExpanded: false,
                selection: .partial,
                selectHelp: "Toggle all SAFE folders in this category",
                onToggleSelect: {},
                onToggleExpand: {}
            ) {
                Circle()
                    .fill(CategoryStyle.sky)
                    .frame(width: 8, height: 8)
            }

            DisclosureSelectRow(
                style: .tool,
                title: "JetBrains",
                badgeText: "4 folders",
                sizeText: "3.1 GB",
                isExpanded: true,
                selection: .all,
                selectHelp: "Select all folders under JetBrains",
                onToggleSelect: {},
                onToggleExpand: {}
            ) {
                Image(systemName: "j.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 18)
            }
        }
        .padding(24)
        .background(AppTheme.base)
        .frame(width: 560)
        .previewDisplayName("Category + tool rows")
    }
}
#endif

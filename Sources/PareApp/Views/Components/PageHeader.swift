import SwiftUI

/// Module title bar: destination-colored tile, title, subtitle, trailing actions (wrap below when narrow).
struct PageHeader<Actions: View>: View {
    let destination: AppDestination
    var title: String? = nil
    let subtitle: String?
    @ViewBuilder var actions: () -> Actions

    @Environment(\.pareDisplayScale) private var scale

    init(
        destination: AppDestination,
        title: String? = nil,
        subtitle: String?,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.destination = destination
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
                titleBlock
                Spacer(minLength: AppTheme.Spacing.md)
                actionRow
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                titleBlock
                actionRow
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, AppTheme.Spacing.pageVertical)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: destination.systemImage, swatch: DestinationStyle.swatch(for: destination), size: scale.space(40))
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? destination.title)
                    .font(scale.pageTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            actions()
        }
        .fixedSize()
    }
}

extension PageHeader where Actions == EmptyView {
    init(destination: AppDestination, title: String? = nil, subtitle: String?) {
        self.init(destination: destination, title: title, subtitle: subtitle) { EmptyView() }
    }
}

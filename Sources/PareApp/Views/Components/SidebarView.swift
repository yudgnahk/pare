import SwiftUI

/// Always-visible left navigation — fixed column, not collapsible SplitView.
struct SidebarView: View {
    @Binding var selection: AppDestination
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Leave room for window traffic lights over the sidebar (hidden title bar).
            Color.clear
                .frame(height: 12)

            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(SidebarSection.allCases) { section in
                        sectionBlock(section)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .background(AppTheme.Fill.control)
                .padding(.horizontal, 12)

            footerHint
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            PareBrandLogo(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pare")
                    .font(scale.font(16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Surgical cleanup")
                    .font(scale.font(11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pare")
    }

    private func sectionBlock(_ section: SidebarSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.rawValue.uppercased())
                .font(scale.font(11, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(section.destinations) { destination in
                sidebarRow(destination)
            }
        }
    }

    private func sidebarRow(_ destination: AppDestination) -> some View {
        let selected = selection == destination
        return Button {
            withAnimation(AppTheme.Motion.standard) {
                selection = destination
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.systemImage)
                    .font(scale.font(14, weight: .semibold))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)

                Text(destination.title)
                    .font(scale.font(14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if selected {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .fill(selected ? AppTheme.sidebarSelected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .strokeBorder(
                        selected ? AppTheme.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Motion.quick, value: selected)
        .help(destination.title)
    }

    private var footerHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Text size")
                .font(scale.font(10, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
            Text("⌘+  ·  ⌘−  ·  ⌘0")
                .font(scale.font(11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebarBackground: some View {
        ZStack(alignment: .top) {
            // Solid base so the menu is never transparent/invisible
            AppTheme.sidebar

            LinearGradient(
                colors: [
                    AppTheme.accent.opacity(0.10),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )

            // Right edge depth
            HStack {
                Spacer()
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 8)
            }
        }
        .ignoresSafeArea()
    }
}

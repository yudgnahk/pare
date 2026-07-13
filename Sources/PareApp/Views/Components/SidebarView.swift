import SwiftUI

/// Always-visible left navigation — fixed column, not collapsible SplitView.
struct SidebarView: View {
    @Binding var selection: AppDestination
    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 18)

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
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 12)

            footerHint
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, y: 2)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pare")
                    .font(scale.font(17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Surgical cleanup")
                    .font(scale.font(10, weight: .medium))
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
                .font(scale.font(10, weight: .bold, design: .rounded))
                .tracking(1.0)
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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)

                Text(destination.title)
                    .font(scale.font(13, weight: selected ? .semibold : .medium))
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AppTheme.sidebarSelected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? AppTheme.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppDestination
    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(SidebarSection.allCases) { section in
                        sectionBlock(section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
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
                    .frame(width: 32, height: 32)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Pare")
                    .font(scale.font(16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Surgical cleanup")
                    .font(scale.font(10, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionBlock(_ section: SidebarSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.rawValue.uppercased())
                .font(scale.font(10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)

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
                    .frame(width: 18)
                Text(destination.title)
                    .font(scale.font(13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AppTheme.textPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AppTheme.sidebarSelected.opacity(0.95) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? AppTheme.accent.opacity(0.35) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Motion.quick, value: selected)
    }

    private var sidebarBackground: some View {
        ZStack {
            AppTheme.sidebar.opacity(0.92)
            LinearGradient(
                colors: [
                    AppTheme.accent.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

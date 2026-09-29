import SwiftUI

/// Always-visible left navigation — fixed column, not collapsible SplitView.
struct SidebarView: View {
    @Binding var selection: AppDestination
    @Environment(\.pareDisplayScale) private var scale
    @Environment(\.isSnapshotRendering) private var isSnapshotRendering
    @StateObject private var volume = VolumeUsageModel()
    @State private var hovered: AppDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Leave room for window traffic lights over the sidebar (hidden title bar).
            Color.clear
                .frame(height: 12)

            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 30)
                .padding(.bottom, 20)

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

            footer
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
        .onAppear { volume.refresh() }
        .onChange(of: selection) { _ in volume.refresh() }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            PareBrandLogo(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pare")
                    .font(scale.font(16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Calm, careful cleanup")
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
                .font(scale.eyebrow)
                .tracking(1.1)
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
        let isHovered = hovered == destination && !selected
        return Button {
            withAnimation(AppTheme.Motion.standard) {
                selection = destination
            }
        } label: {
            HStack(spacing: 10) {
                IconTile(symbol: destination.systemImage, swatch: DestinationStyle.swatch(for: destination), size: 24)

                Text(destination.title)
                    .font(scale.font(14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(rowBackground(selected: selected, hovered: isHovered))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? destination : (hovered == destination ? nil : hovered) }
        .animation(AppTheme.Motion.quick, value: selected)
        .animation(AppTheme.Motion.quick, value: isHovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(destination.title)
    }

    private func rowBackground(selected: Bool, hovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
        return shape
            .fill(selected ? AppTheme.accent.opacity(0.14) : (hovered ? AppTheme.Fill.subtle : Color.clear))
            .overlay(shape.strokeBorder(selected ? AppTheme.accent.opacity(0.22) : Color.clear, lineWidth: 1))
    }

    @ViewBuilder
    private var footer: some View {
        if let usage = volume.usage {
            StorageMeter(usage: usage)
                .padding(12)
                .background(
                    AppTheme.Fill.subtle,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                )
                .help("Startup disk usage")
        }
    }

    private var sidebarBackground: some View {
        ZStack(alignment: .top) {
            if isSnapshotRendering {
                AppTheme.sidebar
            } else {
                SidebarMaterial()
            }

            // Brand gradient over vibrancy: seafoam at the top, deepening toward accentDeep
            // near the bottom. Stronger than a flat wash so vibrancy still reads as Pare.
            // textSecondary stays >= 4.5:1 against the opaque sidebar-material approximation
            // at every stop (checked at the 0.18 top stop, the highest-risk case).
            LinearGradient(
                stops: [
                    .init(color: AppTheme.accent.opacity(0.18), location: 0.0),
                    .init(color: AppTheme.accent.opacity(0.08), location: 0.45),
                    .init(color: AppTheme.accentDeep.opacity(0.05), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                Spacer()
                Rectangle()
                    .fill(AppTheme.Hairline.standard)
                    .frame(width: 1)
            }
        }
        .ignoresSafeArea()
    }
}

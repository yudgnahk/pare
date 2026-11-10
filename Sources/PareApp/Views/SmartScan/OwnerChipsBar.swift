import SwiftUI
import PareCore

/// `All`, the largest owners, then `More…` for the rest. Plain buttons, not a segmented picker, which grabs key focus.
struct OwnerChipsBar: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        let active = viewModel.ownerFilter
        let more = viewModel.moreChips
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chipButton(id: nil, title: "All", bytes: viewModel.allChipBytes, icon: nil, isOn: active == nil)
                ForEach(viewModel.primaryChips) { chip in
                    chipButton(id: chip.id, title: chip.title, bytes: chip.bytes, icon: chip, isOn: active == chip.id)
                }
                if !more.isEmpty {
                    moreMenu(more, active: more.first { $0.id == active })
                }
            }
        }
    }

    private func chipButton(id: String?, title: String, bytes: Int64, icon: OwnerChip?, isOn: Bool) -> some View {
        Button { viewModel.setOwnerFilter(id) } label: {
            chipLabel(title: title, bytes: bytes, icon: icon, isOn: isOn)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Show \(title)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func moreMenu(_ chips: [OwnerChip], active: OwnerChip?) -> some View {
        Menu {
            ForEach(chips) { chip in
                Button("\(chip.title)  \(viewModel.formattedBytes(chip.bytes))") { viewModel.setOwnerFilter(chip.id) }
            }
        } label: {
            if let active {
                chipLabel(title: active.title, bytes: active.bytes, icon: active, isOn: true)
            } else {
                chipLabel(title: "More…", bytes: nil, icon: nil, isOn: false)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More owners")
    }

    private func chipLabel(title: String, bytes: Int64?, icon: OwnerChip?, isOn: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon {
                OwnerIconView(owner: icon.owner, appPath: viewModel.appIconPath(for: icon.owner), size: 14)
            }
            Text(title)
                .font(scale.caption)
                .foregroundStyle(isOn ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(1)
            if let bytes {
                Text(viewModel.formattedBytes(bytes))
                    .font(scale.micro)
                    .foregroundStyle(AppTheme.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isOn ? AppTheme.Fill.selected : AppTheme.Fill.subtle,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.chipCompact, style: .continuous)
        )
        .fixedSize()
    }
}

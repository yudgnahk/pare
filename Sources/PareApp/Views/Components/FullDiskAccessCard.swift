import SwiftUI

/// Coaching card when Full Disk Access looks missing or a scan returned ~0 reclaimable.
struct FullDiskAccessCard: View {
    enum Style {
        /// Missing FDA — primary coaching.
        case fullDiskAccess
        /// Scan finished with nothing reclaimable (may still mention FDA).
        case emptyScan(fullDiskAccessLikelyMissing: Bool)
        /// User granted FDA after a scan that ran without it — need a fresh scan.
        case permissionsUpdatedNeedsRescan
    }

    let style: Style
    var onOpenSettings: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onRescan: (() -> Void)?

    @Environment(\.displayScale) private var scale

    var body: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 40, height: 40)
                    Image(systemName: iconName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(scale.font(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(detail)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    FlowLayout(spacing: 8, lineSpacing: 8, alignment: .leading) {
                        if showsOpenSettings, let onOpenSettings {
                            SecondaryActionButton(
                                title: "Open Full Disk Access",
                                systemImage: "lock.shield",
                                role: .accent,
                                action: onOpenSettings
                            )
                        }
                        if let onRescan, showsRescan {
                            SecondaryActionButton(title: "Rescan", systemImage: "arrow.clockwise") {
                                onRescan()
                            }
                        }
                        if let onDismiss {
                            SecondaryActionButton(title: "Dismiss", action: onDismiss)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch style {
        case .fullDiskAccess:
            return "Full Disk Access recommended"
        case .emptyScan(let missing):
            return missing ? "Scan looks empty — check permissions" : "Nothing reclaimable right now"
        case .permissionsUpdatedNeedsRescan:
            return "Permissions updated — rescan"
        }
    }

    private var detail: String {
        switch style {
        case .fullDiskAccess:
            return "Without Full Disk Access, Pare cannot see many caches and developer folders. Grant access in System Settings, then rescan."
        case .emptyScan(let missing):
            if missing {
                return "Reclaimable space is ~0. That often means Full Disk Access is missing, not that your disk is already clean. Open Privacy settings, enable Pare, then rescan."
            }
            return "No safe reclaimable items matched this scan. Try adding project paths in Settings, or Force Rescan after large installs finish."
        case .permissionsUpdatedNeedsRescan:
            return "Full Disk Access looks granted, but this scan finished without it. Rescan to measure reclaimable space with full library access."
        }
    }

    private var showsOpenSettings: Bool {
        switch style {
        case .fullDiskAccess:
            return true
        case .emptyScan(let missing):
            return missing
        case .permissionsUpdatedNeedsRescan:
            return false
        }
    }

    private var showsRescan: Bool {
        switch style {
        case .fullDiskAccess, .emptyScan, .permissionsUpdatedNeedsRescan:
            return true
        }
    }

    private var iconName: String {
        switch style {
        case .fullDiskAccess:
            return "lock.shield"
        case .emptyScan(let missing):
            return missing ? "exclamationmark.shield" : "checkmark.circle"
        case .permissionsUpdatedNeedsRescan:
            return "arrow.clockwise.circle"
        }
    }

    private var iconColor: Color {
        switch style {
        case .fullDiskAccess, .emptyScan(true), .permissionsUpdatedNeedsRescan:
            return AppTheme.warning
        case .emptyScan(false):
            return AppTheme.success
        }
    }

    private var iconBackground: Color {
        iconColor.opacity(0.16)
    }
}

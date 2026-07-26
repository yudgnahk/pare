import AppKit
import PareCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var textZoom: TextZoomController
    @Environment(\.pareDisplayScale) private var scale
    @StateObject private var exclusionVM = ExclusionListViewModel()
    @State private var showExclusions = false
    @State private var showProjectPaths = false
    @State private var fullDiskAccessStatus: FullDiskAccessStatus = .unknown

    var body: some View {
        ModuleChrome(
            title: "Settings",
            subtitle: "Exclusions, project paths, and display preferences",
            systemImage: "gearshape"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fullDiskAccessCard

                    settingsCard(
                        title: "Scan exclusions",
                        detail: "Paths Pare should never flag or clean.",
                        icon: "eye.slash",
                        actionTitle: "Manage…",
                        action: {
                            exclusionVM.load()
                            showExclusions = true
                        }
                    )

                    settingsCard(
                        title: "Project scan paths",
                        detail: "Extra folders to include when scanning developer projects.",
                        icon: "folder.badge.plus",
                        actionTitle: "Manage…",
                        action: { showProjectPaths = true }
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Text size", systemImage: "textformat.size")
                                .font(scale.font(14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("Adjust readability for large displays. Shortcuts: ⌘+ / ⌘− / ⌘0.")
                                .font(scale.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                SecondaryActionButton(
                                    title: "Smaller",
                                    systemImage: "minus",
                                    isEnabled: textZoom.canZoomOut
                                ) {
                                    textZoom.zoomOut()
                                }

                                Text(textZoom.percentLabel)
                                    .font(scale.font(15, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(minWidth: 56)

                                SecondaryActionButton(
                                    title: "Larger",
                                    systemImage: "plus",
                                    isEnabled: textZoom.canZoomIn
                                ) {
                                    textZoom.zoomIn()
                                }

                                SecondaryActionButton(title: "Reset") {
                                    textZoom.reset()
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About Pare")
                                .font(scale.font(14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Surgical, deliberate reduction — reclaim space without guessing.")
                                .font(scale.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.bottom, AppTheme.Spacing.pageVertical)
            }
        }
        .sheet(isPresented: $showExclusions) {
            ExclusionListView(viewModel: exclusionVM)
        }
        .sheet(isPresented: $showProjectPaths) {
            ProjectScanPathsView()
        }
        .onAppear { refreshFullDiskAccessStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshFullDiskAccessStatus()
        }
    }

    private var fullDiskAccessCard: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .fill(fdaAccent.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "lock.shield")
                        .foregroundStyle(fdaAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Full Disk Access")
                        .font(scale.font(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(fdaDetail)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                SecondaryActionButton(
                    title: "Open Settings",
                    role: .accent
                ) {
                    for url in FullDiskAccessChecker.systemSettingsURLs {
                        if NSWorkspace.shared.open(url) { return }
                    }
                }
            }
        }
    }

    private var fdaAccent: Color {
        switch fullDiskAccessStatus {
        case .granted: return AppTheme.success
        case .denied: return AppTheme.warning
        case .unknown: return AppTheme.accent
        }
    }

    private var fdaDetail: String {
        switch fullDiskAccessStatus {
        case .granted:
            return "Granted — Pare can read protected caches and developer folders."
        case .denied:
            return "Not detected. Grant Full Disk Access, then return here and rescan."
        case .unknown:
            return "Status unclear on this Mac. If scans look empty, grant Full Disk Access."
        }
    }

    private func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = FullDiskAccessChecker.status()
    }

    private func settingsCard(
        title: String,
        detail: String,
        icon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        GlassCard {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(scale.font(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(detail)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                SecondaryActionButton(title: actionTitle, role: .accent, action: action)
            }
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var textZoom: TextZoomController
    @Environment(\.displayScale) private var scale
    @StateObject private var exclusionVM = ExclusionListViewModel()
    @State private var showExclusions = false
    @State private var showProjectPaths = false

    var body: some View {
        ModuleChrome(
            title: "Settings",
            subtitle: "Exclusions, project paths, and display preferences",
            systemImage: "gearshape"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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

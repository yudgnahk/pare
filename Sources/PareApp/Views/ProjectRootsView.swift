import SwiftUI
import PareCore

/// Card shown in the Scan tab for managing auto-discovered project roots.
/// Visible only when any roots have been discovered or the user has added one manually.
struct ProjectRootsCard: View {
    @Environment(\.pareDisplayScale) private var scale
    @ObservedObject var viewModel: ProjectRootsViewModel
    @State private var isExpanded = true

    var body: some View {
        GlassCard {
            VStack(spacing: 0) {
                // Header
                Button(action: { withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(scale.font(15, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Project Roots")
                                .font(scale.font(14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(subtitle)
                                .font(scale.font(11, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            if viewModel.isDiscovering {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Button(action: viewModel.runDiscovery) {
                                    Label("Rescan", systemImage: "arrow.clockwise")
                                        .font(scale.font(11, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            Button(action: viewModel.addManualPath) {
                                Image(systemName: "folder.badge.plus")
                                    .font(scale.font(13, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(AppTheme.accent)
                            .help("Add folder manually")
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(scale.font(10, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().opacity(0.12).padding(.top, 12)

                    if viewModel.discoveredRoots.isEmpty && viewModel.manualAdditions.isEmpty {
                        emptyState
                    } else {
                        rootsList
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: Private

    private var subtitle: String {
        guard viewModel.hasRunDiscovery else { return "Tap Rescan to find project roots automatically" }
        let count = viewModel.discoveredRoots.filter(\.confirmed).count + viewModel.manualAdditions.count
        return "\(count) root\(count == 1 ? "" : "s") included in artifact scan"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No project roots found")
                .font(scale.font(13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Run Rescan to discover project roots automatically via Spotlight,\nor add a folder manually.")
                .font(scale.font(11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var rootsList: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.discoveredRoots, id: \.url) { item in
                rootRow(
                    url: item.url,
                    confirmed: item.confirmed,
                    isManual: false
                )
            }
            ForEach(viewModel.manualAdditions, id: \.self) { url in
                rootRow(url: url, confirmed: true, isManual: true)
            }
        }
        .padding(.top, 10)
    }

    private func rootRow(url: URL, confirmed: Bool, isManual: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { confirmed },
                set: { newValue in viewModel.toggleRoot(url, confirmed: newValue) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(isManual)

            Image(systemName: isManual ? "folder.badge.person.crop" : "folder.fill")
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(confirmed ? AppTheme.accent : AppTheme.textSecondary.opacity(0.5))
                .frame(width: 16)

            Text(url.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            ))
            .font(scale.font(11, weight: .medium, design: .monospaced))
            .foregroundStyle(confirmed ? AppTheme.textPrimary : AppTheme.textSecondary.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer()

            if isManual {
                Button(role: .destructive) { viewModel.removeManual(url) } label: {
                    Image(systemName: "xmark")
                        .font(scale.font(10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Remove manual entry")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.Hairline.faint, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
    }
}

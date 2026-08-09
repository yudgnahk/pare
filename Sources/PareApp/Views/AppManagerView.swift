import SwiftUI
import AppKit
import PareCore

struct AppManagerView: View {
    @ObservedObject var viewModel: AppManagerViewModel
    @Environment(\.pareDisplayScale) private var scale

    /// Token that changes when list membership / order inputs change so the
    /// scroll view can reset to a stable top origin instead of mid-list jumps.
    private var listResetToken: String {
        [
            viewModel.searchText,
            viewModel.hideSystemApps ? "1" : "0",
            viewModel.showOnlyOutdated ? "1" : "0",
            viewModel.sortField.rawValue,
            viewModel.sortAscending ? "asc" : "desc",
            "\(viewModel.filteredApps.count)"
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            // Shell provides AppBackgroundView.

            // Fixed chrome (header / filters / metrics) + list region below.
            // Only the list scrolls — chrome never rides the scroll view.
            VStack(spacing: 0) {
                headerBar
                filterBar
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.top, scale.space(AppTheme.Spacing.md))
                    .padding(.bottom, scale.space(AppTheme.Spacing.sm))
                metricsRow
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.bottom, scale.space(AppTheme.Spacing.md))
                    // Reserve a constant strip so chips appearing/disappearing
                    // don't shove the list origin up/down.
                    .frame(minHeight: scale.space(34), alignment: .leading)

                appTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.showUninstallSheet) {
            if let app = viewModel.selectedApp {
                AppUninstallConfirmSheet(viewModel: viewModel, app: app)
            }
        }
        .onAppear {
            if viewModel.loadState == .idle { viewModel.loadApps() }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "square.grid.2x2")
                        .font(scale.font(17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("App Manager")
                        .font(scale.pageTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Browse, update, and cleanly uninstall installed applications")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if viewModel.loadState == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(AppTheme.accent)
                        .frame(height: AppTheme.Control.secondaryHeight)

                    SecondaryActionButton(title: "Cancel") {
                        viewModel.cancelLoad()
                    }
                } else {
                    PrimaryActionButton(
                        title: "Refresh",
                        systemImage: "arrow.clockwise",
                        isLoading: viewModel.loadState == .loading,
                        style: .compact
                    ) { viewModel.loadApps() }

                    if viewModel.loadState == .loaded {
                        SecondaryActionButton(
                            title: viewModel.checkingUpdates ? "Checking…" : "Check Updates",
                            systemImage: "arrow.down.circle",
                            isLoading: viewModel.checkingUpdates,
                            role: .accent,
                            isEnabled: !viewModel.checkingUpdates
                        ) { viewModel.checkForUpdates() }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, AppTheme.Spacing.pageVertical)
        .padding(.bottom, 4)
    }

    // MARK: - Filter Bar
    // Single-row HStack (not FlowLayout) so toggles never reflow chrome height
    // and shift where the list starts.

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .font(scale.caption)
                TextField("Search apps…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(scale.body)
                    .foregroundStyle(AppTheme.textPrimary)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .frame(maxWidth: 280)

            Toggle("Hide system apps", isOn: $viewModel.hideSystemApps)
                .toggleStyle(.checkbox)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize()

            // Always reserve space so the filter row height/width stays stable
            // when updates become available after "Check Updates".
            Toggle(
                "Updates only\(viewModel.outdatedCount > 0 ? " (\(viewModel.outdatedCount))" : "")",
                isOn: $viewModel.showOnlyOutdated
            )
            .toggleStyle(.checkbox)
            .font(scale.caption)
            .foregroundStyle(viewModel.outdatedCount > 0 ? AppTheme.warning : AppTheme.textSecondary)
            .disabled(viewModel.outdatedCount == 0)
            .opacity(viewModel.outdatedCount > 0 ? 1 : 0.45)
            .fixedSize()

            Spacer(minLength: 8)

            sortMenu
        }
        .frame(maxWidth: .infinity, minHeight: scale.space(36), alignment: .leading)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AppManagerViewModel.SortField.allCases, id: \.self) { field in
                Button {
                    viewModel.toggleSort(field)
                } label: {
                    if viewModel.sortField == field {
                        Label(
                            "\(field.rawValue) \(viewModel.sortAscending ? "↑" : "↓")",
                            systemImage: viewModel.sortAscending ? "arrow.up" : "arrow.down"
                        )
                    } else {
                        Text(field.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort: \(viewModel.sortField.rawValue)")
            }
            .font(scale.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricChip(
                label: "\(viewModel.apps.count)",
                sub: "apps installed",
                color: AppTheme.accent
            )
            metricChip(
                label: ByteCountFormatter.string(fromByteCount: viewModel.totalSizeBytes, countStyle: .file),
                sub: "total size",
                color: AppTheme.textSecondary
            )
            if viewModel.checkingUpdates {
                metricChip(label: "Checking…", sub: "for updates", color: AppTheme.warning)
            } else if viewModel.outdatedCount > 0 {
                metricChip(
                    label: "\(viewModel.outdatedCount)",
                    sub: "updates available",
                    color: AppTheme.warning
                )
            }
            if case .done(let trashed, let failed) = viewModel.uninstallState {
                metricChip(
                    label: "\(trashed) trashed\(failed > 0 ? ", \(failed) failed" : "")",
                    sub: "last uninstall",
                    color: failed > 0 ? AppTheme.review : AppTheme.success
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func metricChip(label: String, sub: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(scale.chip)
                .foregroundStyle(color)
            Text(sub)
                .font(scale.chipSub)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
    }

    // MARK: - App Table

    private var appTable: some View {
        VStack(spacing: 0) {
            if let feedback = viewModel.updateFeedback {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text(feedback)
                        .font(scale.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button {
                        viewModel.dismissUpdateFeedback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(scale.font(11, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.vertical, 8)
            }

            Group {
                switch viewModel.loadState {
                case .idle:
                    emptyPrompt(icon: "apps.iphone", text: "Click Refresh to load installed apps")
                case .loading:
                    loadingPlaceholder
                case .error(let msg):
                    emptyPrompt(icon: "exclamationmark.triangle", text: msg)
                case .loaded:
                    if viewModel.filteredApps.isEmpty {
                        emptyPrompt(icon: emptyIcon, text: emptyMessage)
                    } else {
                        appList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var emptyIcon: String {
        viewModel.showOnlyOutdated ? "checkmark.seal" : "magnifyingglass"
    }

    private var emptyMessage: String {
        if viewModel.showOnlyOutdated {
            if viewModel.checkingUpdates {
                return "Checking for updates…"
            }
            if !viewModel.hasCheckedUpdates {
                return "Click “Check Updates” to find outdated apps"
            }
            return "All apps are up to date"
        }
        if !viewModel.searchText.isEmpty {
            return "No apps match the current search"
        }
        return "No apps match the current filters"
    }

    private var appList: some View {
        StableListContainer(resetToken: listResetToken) {
            tableHeader
        } content: {
            ForEach(viewModel.filteredApps) { app in
                AppRow(
                    app: app,
                    isUpdating: viewModel.updatingAppIDs.contains(app.id),
                    onUpdate: { viewModel.updateApp(app) },
                    onUninstall: { viewModel.requestUninstall(for: app) }
                )
            }
        }
    }

    private var tableHeader: some View {
        TableHeaderRow(spacing: 0) {
            Text("Application")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Version")
                .frame(width: scale.colVersion, alignment: .leading)
            Text("Size")
                .frame(width: scale.colSize, alignment: .trailing)
            if scale.sizeClass != .compact {
                Text("Installed")
                    .frame(width: scale.colDate, alignment: .trailing)
            }
            Text("Last Used")
                .frame(width: scale.colDate, alignment: .trailing)
            Spacer().frame(width: scale.scaled(120))
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(AppTheme.accent)
            Text("Scanning installed applications…")
                .font(scale.body)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyPrompt(icon: String, text: String) -> some View {
        EmptyStateView(icon: icon, message: text)
    }
}

// MARK: - AppRow

private struct AppRow: View {
    let app: InstalledApp
    var isUpdating: Bool = false
    var onUpdate: (() -> Void)? = nil
    let onUninstall: () -> Void
    @Environment(\.pareDisplayScale) private var scale
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private var hasUpdate: Bool { app.updateInfo?.hasUpdate == true }

    var body: some View {
        HStack(spacing: 0) {
            // Icon + name
            HStack(spacing: 10) {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(scale.rowTitle)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        if app.isSystemApp {
                            Badge(text: "SIP", color: AppTheme.textSecondary)
                        }
                        if app.isMAS {
                            Badge(text: "MAS", color: AppTheme.accent)
                        }
                        if app.isHomebrewManaged {
                            Badge(text: "brew", color: AppTheme.success)
                        }
                        if hasUpdate, let available = app.updateInfo?.availableVersion {
                            Badge(text: "→ \(available)", color: AppTheme.warning)
                        }
                    }
                    if let bundleID = app.bundleID {
                        Text(bundleID)
                            .font(scale.font(10, weight: .regular, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Version
            Text(app.version.isEmpty ? "—" : app.version)
                .font(scale.rowMono)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: scale.colVersion, alignment: .leading)
                .lineLimit(1)

            // Size
            Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                .font(scale.font(12, weight: .semibold, design: .rounded))
                .foregroundStyle(app.sizeBytes > 500_000_000 ? AppTheme.review : AppTheme.textPrimary)
                .frame(width: scale.colSize, alignment: .trailing)

            if scale.sizeClass != .compact {
                // Install date
                Text(app.installDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: scale.colDate, alignment: .trailing)
            }

            // Always retain Last Used as a table column, even in compact windows.
            Text(app.lastUsed.map { Self.dateFormatter.string(from: $0) } ?? "Never")
                .font(scale.rowMeta)
                .foregroundStyle(app.lastUsed == nil ? AppTheme.textSecondary.opacity(0.5) : AppTheme.textSecondary)
                .frame(width: scale.colDate, alignment: .trailing)

            // Actions
            HStack(spacing: 8) {
                if hasUpdate {
                    updateButton
                }

                Button {
                    NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")

                Button(action: onUninstall) {
                    Image(systemName: "trash")
                        .foregroundStyle(app.isSystemApp ? AppTheme.textSecondary.opacity(0.3) : AppTheme.review)
                }
                .buttonStyle(.borderless)
                .disabled(app.isSystemApp)
                .help(app.isSystemApp ? "System apps cannot be removed (SIP-protected)" : "Uninstall \(app.name)")
            }
            .frame(width: scale.scaled(120), alignment: .trailing)
            .opacity(isHovered || hasUpdate ? 1 : 0.6)
        }
        .hoverableRow(isHovered: $isHovered, verticalPadding: scale.space(10))
        .contextMenu {
            if hasUpdate {
                Button("Update…") { onUpdate?() }
            }
            Button("Open") {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: app.path),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("Uninstall…", role: .destructive) { onUninstall() }
                .disabled(app.isSystemApp)
        }
    }

    @ViewBuilder
    private var updateButton: some View {
        Button {
            onUpdate?()
        } label: {
            HStack(spacing: 4) {
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: app.isHomebrewManaged ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                }
                Text(isUpdating ? "Updating" : "Update")
                    .font(scale.micro)
            }
            .foregroundStyle(AppTheme.warning)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.warning.opacity(0.16))
            )
        }
        .buttonStyle(.borderless)
        .disabled(isUpdating || onUpdate == nil)
        .help(updateHelpText)
    }

    private var updateHelpText: String {
        guard let info = app.updateInfo else { return "Update" }
        if app.isHomebrewManaged {
            return "Upgrade \(app.name) to \(info.availableVersion) via Homebrew"
        }
        switch info.channel {
        case .mas:
            return "Open Mac App Store to update \(app.name) (\(info.availableVersion))"
        case .sparkle:
            return "Download update for \(app.name) (\(info.availableVersion))"
        }
    }

    private var appIcon: some View {
        Group {
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            let side = scale.scaled(32)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.chipCompact, style: .continuous))
        }
    }

}

// MARK: - Uninstall Confirm Sheet

struct AppUninstallConfirmSheet: View {
    @Environment(\.pareDisplayScale) private var scale
    @ObservedObject var viewModel: AppManagerViewModel
    let app: InstalledApp

    private var leftovers: [AppLeftover] { viewModel.pendingLeftovers }
    private var normalLeftovers: [AppLeftover] { leftovers.filter { !$0.isGroupContainer } }
    private var groupContainers: [AppLeftover] { leftovers.filter { $0.isGroupContainer } }

    private var totalBytes: Int64 {
        let base = app.sizeBytes
        let leftoverBytes = normalLeftovers.reduce(0) { $0 + $1.sizeBytes }
        let groupBytes = viewModel.includeGroupContainers
            ? groupContainers.reduce(0) { $0 + $1.sizeBytes } : 0
        return base + leftoverBytes + groupBytes
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Uninstall \(app.name)?")
                        .font(scale.font(18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) + " will be freed")
                        .font(scale.font(13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // App bundle
                    leftoverSection(title: "Application Bundle", items: [
                        LeftoverRow(
                            path: app.path,
                            size: app.sizeBytes,
                            isGroup: false,
                            isSelected: .constant(true)
                        )
                    ])

                    // Per-category leftovers
                    let grouped = Dictionary(grouping: normalLeftovers, by: { $0.category })
                    ForEach(AppLeftoverCategory.allCases, id: \.self) { cat in
                        if let items = grouped[cat], !items.isEmpty {
                            leftoverSection(
                                title: cat.rawValue,
                                items: items.map { leftover in
                                    LeftoverRow(
                                        path: leftover.path,
                                        size: leftover.sizeBytes,
                                        isGroup: false,
                                        isSelected: .constant(true)
                                    )
                                }
                            )
                        }
                    }

                    // Group containers — warning
                    if !groupContainers.isEmpty {
                        groupContainerSection
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 380)

            Divider()

            // Footer actions
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { viewModel.cancelUninstall() }
                    .keyboardShortcut(.escape)
                Button(role: .destructive) {
                    viewModel.confirmUninstall()
                } label: {
                    if viewModel.uninstallState == .uninstalling {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 80)
                    } else {
                        Text("Move to Trash")
                    }
                }
                .keyboardShortcut(.return)
                .disabled(viewModel.uninstallState == .uninstalling)
            }
            .padding(20)
        }
        .frame(minWidth: AppTheme.Sheet.standardWidth, idealWidth: AppTheme.Sheet.wideWidth, maxWidth: AppTheme.Sheet.wideWidth)
        .frame(minHeight: 340, idealHeight: AppTheme.Sheet.standardHeight, maxHeight: 620)
        .background(.regularMaterial)
    }

    private func leftoverSection(title: String, items: [LeftoverRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(scale.font(11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 2) {
                ForEach(items.indices, id: \.self) { i in
                    items[i]
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        }
    }

    private var groupContainerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                Text("Shared Data")
                    .font(scale.font(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text("This data may be shared with other apps in the same suite. Remove only if you are uninstalling all related apps.")
                .font(scale.font(12))
                .foregroundStyle(.secondary)

            Toggle("Also remove shared group containers", isOn: $viewModel.includeGroupContainers)
                .font(scale.font(12, weight: .medium))
                .toggleStyle(.checkbox)

            if viewModel.includeGroupContainers {
                VStack(spacing: 2) {
                    ForEach(groupContainers) { leftover in
                        LeftoverRow(
                            path: leftover.path,
                            size: leftover.sizeBytes,
                            isGroup: true,
                            isSelected: .constant(true)
                        )
                    }
                }
                .padding(10)
                .background(AppTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            }
        }
        .padding(AppTheme.Spacing.cardCompact)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
}

private struct LeftoverRow: View {
    @Environment(\.pareDisplayScale) private var scale
    let path: String
    let size: Int64
    let isGroup: Bool
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGroup ? "folder.badge.questionmark" : "doc")
                .font(scale.font(11))
                .foregroundStyle(isGroup ? AppTheme.warning : AppTheme.textSecondary)
                .frame(width: 16)

            Text(path)
                .font(scale.font(11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if size > 0 {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(scale.font(11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

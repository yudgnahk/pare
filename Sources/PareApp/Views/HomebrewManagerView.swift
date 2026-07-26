import SwiftUI
import PareCore

struct HomebrewManagerView: View {
    @StateObject private var viewModel = HomebrewManagerViewModel()
    @Environment(\.pareDisplayScale) private var scale

    /// Resets list scroll when search, tab, or dependency toggle changes.
    private var listResetToken: String {
        [
            viewModel.selectedTab.rawValue,
            viewModel.searchText,
            viewModel.showAllFormulae ? "1" : "0",
            "\(viewModel.filteredFormulae.count)",
            "\(viewModel.filteredCasks.count)",
            "\(viewModel.filteredOutdated.count)",
            "\(viewModel.filteredMigrationCandidates.count)"
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            // Shell provides AppBackgroundView.

            if !viewModel.isInstalled {
                notInstalledPlaceholder
            } else {
                // Fixed chrome + scrollable list region only.
                VStack(spacing: 0) {
                    headerBar
                    tabPickerRow
                        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                        .padding(.top, scale.space(AppTheme.Spacing.md))
                        .padding(.bottom, 6)
                    filterBar
                        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                        .padding(.bottom, scale.space(AppTheme.Spacing.sm))
                        .frame(minHeight: scale.space(36), alignment: .leading)
                    tabContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.showOperationSheet) {
            BrewOperationSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.leaveConfirmCask) { cask in
            LeaveHomebrewConfirmSheet(
                cask: cask,
                forceQuit: $viewModel.leaveForceQuit,
                onCancel: { viewModel.cancelLeaveHomebrew() },
                onConfirm: { viewModel.confirmLeaveHomebrew() }
            )
        }
        .sheet(item: $viewModel.pendingConfirmation) { pending in
            HomebrewConfirmationSheet(
                pending: pending,
                onCancel: { viewModel.cancelConfirmation() },
                onConfirm: { viewModel.confirmPendingOperation() }
            )
        }
        .onAppear {
            if viewModel.loadState == .idle { viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Homebrew Manager")
                        .font(scale.pageTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Manage formulae, casks, updates, and migrate apps to Homebrew")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            headerActions
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, AppTheme.Spacing.pageVertical)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var headerActions: some View {
        if viewModel.loadState == .loading {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .tint(AppTheme.accent)
                .frame(height: AppTheme.Control.secondaryHeight)
        } else {
            HStack(spacing: 8) {
                PrimaryActionButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    isLoading: viewModel.loadState == .loading,
                    style: .compact
                ) { viewModel.load() }

                if viewModel.loadState == .loaded && !viewModel.brewManagedOutdated.isEmpty {
                    PrimaryActionButton(
                        title: "Upgrade All (\(viewModel.brewManagedOutdated.count))",
                        systemImage: "arrow.up.circle",
                        isLoading: false,
                        style: .compact,
                        tint: .warning
                    ) { viewModel.requestUpgradeAll() }
                }
                if viewModel.loadState == .loaded && !viewModel.autoUpdateOutdated.isEmpty {
                    PrimaryActionButton(
                        title: "Self-updating (\(viewModel.autoUpdateOutdated.count))",
                        systemImage: "exclamationmark.arrow.circlepath",
                        isLoading: false,
                        style: .compact,
                        tint: .review
                    ) { viewModel.requestGreedyUpgradeAll() }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Tab picker
    // Uses plain Buttons instead of Picker(.segmented) — NSSegmentedControl
    // auto-grabs key focus and swallows keystrokes before the TextField sees them.

    private var tabPickerRow: some View {
        // Single-row scroll keeps chrome height fixed on narrow windows.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(HomebrewManagerViewModel.Tab.allCases, id: \.self) { tab in
                    Button { viewModel.selectedTab = tab } label: {
                        Text(tabLabel(tab))
                            .font(scale.caption)
                            .lineLimit(1)
                            .foregroundStyle(
                                viewModel.selectedTab == tab
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                viewModel.selectedTab == tab
                                    ? Color.white.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(3)
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Filter bar (search + contextual toggle only)

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .font(scale.caption)
                TextField("Search…", text: $viewModel.searchText)
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
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 280)

            Spacer(minLength: 8)

            // Always present so chrome height doesn't jump when leaving Formulae.
            Toggle("Show dependencies", isOn: $viewModel.showAllFormulae)
                .toggleStyle(.checkbox)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .opacity(viewModel.selectedTab == .formulae ? 1 : 0)
                .disabled(viewModel.selectedTab != .formulae)
                .fixedSize()
                .onChange(of: viewModel.showAllFormulae) { _ in
                    if viewModel.selectedTab == .formulae {
                        viewModel.reloadFormulae()
                    }
                }

            if viewModel.selectedTab == .formulae {
                formulaSortMenu
            }
        }
    }

    private var formulaSortMenu: some View {
        Menu {
            ForEach(HomebrewManagerViewModel.FormulaSortField.allCases, id: \.self) { field in
                Button {
                    viewModel.toggleFormulaSort(field)
                } label: {
                    if viewModel.formulaSortField == field {
                        Label(
                            "\(field.rawValue) \(viewModel.formulaSortAscending ? "↑" : "↓")",
                            systemImage: viewModel.formulaSortAscending ? "arrow.up" : "arrow.down"
                        )
                    } else {
                        Text(field.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort: \(viewModel.formulaSortField.rawValue)")
            }
            .font(scale.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort formulae by name, size, or install date")
    }

    private func tabLabel(_ tab: HomebrewManagerViewModel.Tab) -> String {
        switch tab {
        case .formulae: return "Formulae (\(viewModel.formulae.count))"
        case .casks:
            let orphaned = viewModel.casks.filter(\.isOrphaned).count
            return orphaned > 0
                ? "Casks (\(viewModel.casks.count), \(orphaned) orphaned)"
                : "Casks (\(viewModel.casks.count))"
        case .outdated:
            let n = viewModel.outdated.count
            return n > 0 ? "Outdated (\(n))" : "Outdated"
        case .migrate:
            let n = viewModel.migrationCandidates.count
            return n > 0 ? "Migrate (\(n))" : "Migrate"
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.loadState {
        case .idle:
            emptyPrompt(icon: "shippingbox", text: "Click Refresh to load Homebrew packages")
        case .loading:
            loadingView
        case .error(let msg):
            emptyPrompt(icon: "exclamationmark.triangle", text: msg)
        case .loaded:
            VStack(spacing: 0) {
                switch viewModel.selectedTab {
                case .formulae: formulaeList
                case .casks: casksList
                case .outdated: outdatedList
                case .migrate: migrateList
                }
                if hasActiveTabItems {
                    bulkActionBar
                }
            }
        }
    }

    private var hasActiveTabItems: Bool {
        switch viewModel.selectedTab {
        case .formulae: !viewModel.filteredFormulae.isEmpty
        case .casks: !viewModel.filteredCasks.isEmpty
        case .outdated: !viewModel.filteredOutdated.isEmpty
        case .migrate: !viewModel.filteredMigrationCandidates.isEmpty
        }
    }

    // MARK: - Formulae

    private var formulaeList: some View {
        Group {
            if viewModel.filteredFormulae.isEmpty {
                emptyPrompt(icon: "shippingbox", text: "No formulae match the current filters")
            } else {
                StableListContainer(resetToken: listResetToken) {
                    formulaeHeader
                } content: {
                    ForEach(viewModel.filteredFormulae) { formula in
                        FormulaRow(
                            formula: formula,
                            isSelected: viewModel.isSelected(formula.id),
                            onToggleSelection: { viewModel.toggleSelection(id: formula.id) }
                        ) {
                            viewModel.uninstall(formula: formula)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var formulaeHeader: some View {
        TableHeaderRow {
            selectionColumnSpacer
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Version").frame(width: scale.scaled(100), alignment: .leading)
            Text("Size").frame(width: scale.colSize, alignment: .trailing)
            if scale.sizeClass != .compact {
                Text("Installed").frame(width: scale.colDate, alignment: .trailing)
                Text("Requested").frame(width: scale.scaled(90), alignment: .center)
            }
            Spacer().frame(width: scale.scaled(50))
        }
    }

    // MARK: - Casks

    private var casksList: some View {
        Group {
            if viewModel.filteredCasks.isEmpty {
                emptyPrompt(icon: "app.badge", text: "No casks match the current filters")
            } else {
                StableListContainer(resetToken: listResetToken) {
                    casksHeader
                } content: {
                    ForEach(viewModel.filteredCasks) { cask in
                        CaskRow(
                            cask: cask,
                            isSelected: viewModel.isSelected(cask.id),
                            onToggleSelection: { viewModel.toggleSelection(id: cask.id) },
                            onLeaveHomebrew: {
                                viewModel.requestLeaveHomebrew(cask: cask)
                            },
                            onUninstall: {
                                viewModel.uninstall(cask: cask)
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var casksHeader: some View {
        TableHeaderRow {
            selectionColumnSpacer
            Text("Token").frame(maxWidth: .infinity, alignment: .leading)
            Text("Version").frame(width: scale.scaled(120), alignment: .leading)
            if scale.sizeClass != .compact {
                Text("App").frame(width: scale.scaled(160), alignment: .leading)
                Text("Installed").frame(width: scale.colDate, alignment: .trailing)
                Text("Last Used").frame(width: scale.colDate, alignment: .trailing)
            }
            Spacer().frame(width: scale.scaled(100))
        }
    }

    // MARK: - Outdated

    private var outdatedList: some View {
        Group {
            if viewModel.filteredOutdated.isEmpty {
                emptyPrompt(icon: "checkmark.seal", text: "All packages are up to date")
            } else {
                VStack(spacing: 0) {
                    if !viewModel.autoUpdateOutdated.isEmpty {
                        outdatedAutoUpdateExplainer
                    }
                    StableListContainer(resetToken: listResetToken) {
                        outdatedHeader
                    } content: {
                        ForEach(viewModel.filteredOutdated) { pkg in
                            OutdatedRow(
                                package: pkg,
                                isSelected: viewModel.isSelected(pkg.id),
                                selectionEnabled: !pkg.pinned,
                                onToggleSelection: { viewModel.toggleSelection(id: pkg.id) }
                            ) {
                                viewModel.upgrade(package: pkg)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var outdatedAutoUpdateExplainer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.accent)
            Text("Self-updating casks (auto badge) update themselves. Upgrade All skips them. Prefer Leave Homebrew for browsers/IDEs if you run brew upgrade --greedy in Terminal.")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
    }

    private var outdatedHeader: some View {
        TableHeaderRow {
            selectionColumnSpacer
            Text("Package").frame(maxWidth: .infinity, alignment: .leading)
            Text("Installed").frame(width: scale.scaled(120), alignment: .leading)
            Text("Available").frame(width: scale.scaled(120), alignment: .leading)
            if scale.sizeClass != .compact {
                Text("Type").frame(width: scale.scaled(80), alignment: .center)
            }
            Spacer().frame(width: scale.colActions)
        }
    }

    // MARK: - Migrate

    private var migrateList: some View {
        Group {
            if viewModel.migrationCandidates.isEmpty && viewModel.loadState == .loaded {
                emptyPrompt(
                    icon: "checkmark.circle",
                    text: "No migration candidates found — all detectable apps are already managed by Homebrew"
                )
            } else if viewModel.filteredMigrationCandidates.isEmpty {
                emptyPrompt(icon: "magnifyingglass", text: "No candidates match the current search")
            } else {
                VStack(spacing: 0) {
                    migrateExplainer
                    StableListContainer(resetToken: listResetToken) {
                        EmptyView()
                    } content: {
                        ForEach(viewModel.filteredMigrationCandidates) { candidate in
                            MigrateCandidateRow(
                                candidate: candidate,
                                isSelected: viewModel.isSelected(candidate.id),
                                onToggleSelection: { viewModel.toggleSelection(id: candidate.id) }
                            ) {
                                viewModel.migrate(candidate: candidate)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var bulkActionBar: some View {
        HStack(spacing: 10) {
            Text(selectionSummaryLabel)
                .font(scale.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Button("Select All Visible") { viewModel.selectAllVisible() }
                .buttonStyle(.borderless)
                .font(scale.caption)
            Button("Clear Selection") { viewModel.clearSelection() }
                .buttonStyle(.borderless)
                .font(scale.caption)
                .disabled(viewModel.selectedCount == 0)
            Spacer()
            Button(bulkActionTitle) { viewModel.requestBulkAction() }
                .buttonStyle(.borderedProminent)
                .tint(bulkActionTint)
                .disabled(viewModel.actionableSelectedCount == 0 || viewModel.isOperationRunning)
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
    }

    private var selectionSummaryLabel: String {
        let selected = viewModel.selectedCount
        let actionable = viewModel.actionableSelectedCount
        if viewModel.selectedTab == .outdated, selected > actionable {
            return "\(selected) selected (\(actionable) upgradeable)"
        }
        return "\(selected) selected"
    }

    /// Matches `SelectionControl` width so header titles align with row content.
    private var selectionColumnSpacer: some View {
        Spacer().frame(width: 28)
    }

    private var bulkActionTitle: String {
        switch viewModel.selectedTab {
        case .formulae, .casks: return "Uninstall Selected"
        case .outdated: return "Upgrade Selected"
        case .migrate: return "Adopt Selected"
        }
    }

    private var bulkActionTint: Color {
        switch viewModel.selectedTab {
        case .formulae, .casks: return AppTheme.warning
        case .outdated: return AppTheme.success
        case .migrate: return AppTheme.success
        }
    }

    private var migrateExplainer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.accent)
            Text("These apps are installed outside Homebrew but have matching casks. Adopting them lets Homebrew manage their updates.")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Shared helpers

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(AppTheme.accent)
            Text("Loading Homebrew packages…")
                .font(scale.body)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyPrompt(icon: String, text: String) -> some View {
        EmptyStateView(icon: icon, message: text)
    }

    private var notInstalledPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: scale.scaled(64)))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.4))
            Text("Homebrew Not Installed")
                .font(scale.font(22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Homebrew is a popular package manager for macOS.\nInstall it to manage formulae, casks, and more.")
                .font(scale.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Visit brew.sh") {
                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SelectionControl: View {
    let isSelected: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(
                    !isEnabled
                        ? AppTheme.textSecondary.opacity(0.3)
                        : (isSelected ? AppTheme.accent : AppTheme.textSecondary.opacity(0.65))
                )
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel("Select row")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(
            !isEnabled
                ? "Pinned packages cannot be selected for upgrade"
                : (isSelected ? "Deselect" : "Select")
        )
    }
}

private struct HomebrewConfirmationSheet: View {
    let pending: HomebrewManagerViewModel.PendingConfirmation
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var isDestructive: Bool {
        pending.action == .uninstallFormulae || pending.action == .uninstallCasks
    }

    private var namesPreview: String {
        let preview = pending.names.prefix(5).joined(separator: ", ")
        let remainder = pending.names.count - min(pending.names.count, 5)
        return remainder > 0 ? "\(preview), and \(remainder) more" : preview
    }

    private var commandLines: [String] {
        BrewBulkPlanning.commandPreviewLines(commands: pending.commands, maxVisible: 5)
    }

    private var patternSummary: String? {
        BrewBulkPlanning.commandPatternSummary(commands: pending.commands)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: isDestructive ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isDestructive ? AppTheme.warning : AppTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pending.action.title)
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(pending.names.count) selected")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Text(pending.action.operationDescription)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 6) {
                Text("Affected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(namesPreview)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(pending.commands.count > 1 ? "Homebrew commands" : "Homebrew command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let patternSummary {
                    Text(patternSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(commandLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if pending.commands.count > 1 {
                    Text("Runs once per item, in the order shown.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if pending.warnsAboutAutoUpdates {
                Label("One or more selected casks update themselves. Homebrew may replace an open app; save work and expect to relaunch it.", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if isDestructive {
                    Button(pending.action.title, role: .destructive, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.warning)
                } else {
                    Button(pending.action.title, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(.regularMaterial)
    }
}

// MARK: - FormulaRow

private struct FormulaRow: View {
    let formula: BrewFormula
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onUninstall: () -> Void
    @Environment(\.pareDisplayScale) private var scale
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            SelectionControl(isSelected: isSelected, action: onToggleSelection)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formula.name)
                        .font(scale.rowTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if formula.pinned { Badge(text: "pinned", color: AppTheme.accent) }
                }
                if !formula.desc.isEmpty {
                    Text(formula.desc)
                        .font(scale.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formula.version)
                .font(scale.rowMono)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: scale.scaled(100), alignment: .leading)
                .lineLimit(1)

            Text(formula.sizeBytes > 0
                ? ByteCountFormatter.string(fromByteCount: formula.sizeBytes, countStyle: .file)
                : "—")
                .font(scale.font(12, weight: .semibold, design: .rounded))
                .foregroundStyle(formula.sizeBytes > 100_000_000 ? AppTheme.review : AppTheme.textPrimary)
                .frame(width: scale.colSize, alignment: .trailing)

            if scale.sizeClass != .compact {
                Text(formula.installDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: scale.colDate, alignment: .trailing)

                Image(systemName: formula.installedOnRequest ? "checkmark" : "minus")
                    .font(scale.rowMeta)
                    .foregroundStyle(formula.installedOnRequest ? AppTheme.success : AppTheme.textSecondary.opacity(0.4))
                    .frame(width: scale.scaled(90), alignment: .center)
            }

            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .foregroundStyle(AppTheme.review)
            }
            .buttonStyle(.borderless)
            .help("Uninstall \(formula.name)")
            .frame(width: scale.scaled(50), alignment: .trailing)
            .opacity(isHovered ? 1 : 0.5)
        }
        .hoverableRow(isHovered: $isHovered, verticalPadding: scale.space(10))
    }

}

// MARK: - CaskRow

private struct CaskRow: View {
    let cask: BrewCask
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onLeaveHomebrew: () -> Void
    let onUninstall: () -> Void
    @Environment(\.pareDisplayScale) private var scale
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            SelectionControl(isSelected: isSelected, action: onToggleSelection)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cask.token)
                        .font(scale.rowTitle)
                        .foregroundStyle(cask.isOrphaned ? AppTheme.warning : AppTheme.textPrimary)
                        .lineLimit(1)
                    if cask.isOrphaned {
                        Badge(text: "orphaned", color: AppTheme.warning)
                    }
                    if cask.autoUpdates {
                        Badge(text: "auto", color: AppTheme.accent)
                    }
                }
                if cask.isOrphaned {
                    Text("App not found — removed without brew uninstall")
                        .font(scale.font(10, weight: .regular))
                        .foregroundStyle(AppTheme.warning.opacity(0.8))
                } else if cask.autoUpdates {
                    Text("Updates itself — Leave Homebrew if brew upgrade breaks sessions")
                        .font(scale.font(10, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(cask.version)
                .font(scale.rowMono)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: scale.scaled(120), alignment: .leading)
                .lineLimit(1)

            if scale.sizeClass != .compact {
                Text(cask.isOrphaned ? "—" : (cask.installedAppNames.first ?? "—"))
                    .font(scale.caption)
                    .foregroundStyle(cask.isOrphaned ? AppTheme.textSecondary.opacity(0.4) : AppTheme.textSecondary)
                    .frame(width: scale.scaled(160), alignment: .leading)
                    .lineLimit(1)

                Text(cask.installDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: scale.colDate, alignment: .trailing)

                Text(cask.isOrphaned ? "Orphaned" : (cask.lastUsed.map { Self.dateFormatter.string(from: $0) } ?? "Never"))
                    .font(scale.rowMeta)
                    .foregroundStyle(cask.isOrphaned ? AppTheme.warning : (cask.lastUsed == nil ? AppTheme.textSecondary.opacity(0.5) : AppTheme.textSecondary))
                    .frame(width: scale.colDate, alignment: .trailing)
            }

            HStack(spacing: 10) {
                if !cask.isOrphaned {
                    Button(action: onLeaveHomebrew) {
                        Image(systemName: "link.badge.minus")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.borderless)
                    .help("Leave Homebrew — keep \(cask.token) app, stop Brew upgrades")
                }

                Button(action: onUninstall) {
                    HStack(spacing: 4) {
                        Image(systemName: cask.isOrphaned ? "trash.fill" : "trash")
                        if cask.isOrphaned {
                            Text("Clean up")
                                .font(scale.micro)
                        }
                    }
                    .foregroundStyle(AppTheme.warning)
                }
                .buttonStyle(.borderless)
                .help(cask.isOrphaned
                      ? "Remove \(cask.token) from Homebrew records (app already deleted)"
                      : "Uninstall \(cask.token) (removes the app)")
            }
            .frame(width: cask.isOrphaned ? scale.scaled(90) : scale.scaled(100), alignment: .trailing)
            .opacity(isHovered ? 1 : (cask.isOrphaned ? 0.8 : 0.5))
        }
        .hoverableRow(
            isHovered: $isHovered,
            verticalPadding: scale.space(cask.isOrphaned ? 12 : 10),
            hoverFill: cask.isOrphaned ? AppTheme.warning.opacity(0.12) : AppTheme.Fill.subtle,
            restFill: cask.isOrphaned ? AppTheme.warning.opacity(0.07) : .clear
        )
    }

}

// MARK: - Leave Homebrew confirmation

private struct LeaveHomebrewConfirmSheet: View {
    let cask: BrewCask
    @Binding var forceQuit: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "link.badge.minus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave Homebrew")
                        .font(.system(size: 18, weight: .semibold))
                    Text(cask.token)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                bullet("Keeps the app in Applications — does not delete it")
                bullet("Removes Homebrew ownership so brew upgrade will not replace it")
                bullet("Does not wipe preferences or caches (no --zap)")
                if cask.autoUpdates {
                    bullet("This app updates itself — recommended if brew upgrade breaks open sessions")
                }
                bullet("You can re-adopt later from the Migrate tab")
            }

            Toggle("Force quit the app if it is running", isOn: $forceQuit)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Leave Homebrew", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(.regularMaterial)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - OutdatedRow

private struct OutdatedRow: View {
    let package: BrewOutdatedPackage
    let isSelected: Bool
    var selectionEnabled: Bool = true
    let onToggleSelection: () -> Void
    let onUpgrade: () -> Void
    @Environment(\.pareDisplayScale) private var scale
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            SelectionControl(
                isSelected: isSelected,
                isEnabled: selectionEnabled,
                action: onToggleSelection
            )
                .frame(width: 28, alignment: .leading)
            HStack(spacing: 6) {
                Text(package.name)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if package.pinned { Badge(text: "pinned", color: AppTheme.accent) }
                if package.isAutoUpdate { Badge(text: "auto", color: AppTheme.accent) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(package.installedVersions.joined(separator: ", "))
                .font(scale.rowMono)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: scale.scaled(120), alignment: .leading)
                .lineLimit(1)

            Text(package.currentVersion)
                .font(scale.font(12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.warning)
                .frame(width: scale.scaled(120), alignment: .leading)
                .lineLimit(1)

            if scale.sizeClass != .compact {
                Text(package.isFormula ? "formula" : "cask")
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: scale.scaled(80), alignment: .center)
            }

            HStack(spacing: 8) {
                if !package.pinned {
                    Button(action: onUpgrade) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text(package.isAutoUpdate ? "Force" : "Upgrade")
                        }
                        .font(scale.micro)
                        .foregroundStyle(package.isAutoUpdate ? AppTheme.warning : AppTheme.success)
                    }
                    .buttonStyle(.borderless)
                    .help(
                        package.isAutoUpdate
                            ? "Force Brew upgrade of self-updating \(package.name) — quit the app first; may break a running session"
                            : "Upgrade \(package.name) to \(package.currentVersion)"
                    )
                } else {
                    Text("Pinned")
                        .font(scale.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                }
            }
            .frame(width: scale.colActions, alignment: .trailing)
            .opacity(isHovered ? 1 : 0.7)
        }
        .hoverableRow(isHovered: $isHovered, verticalPadding: scale.space(10))
    }

}

// MARK: - MigrateCandidateRow

private struct MigrateCandidateRow: View {
    let candidate: MigrationCandidate
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onMigrate: () -> Void
    @Environment(\.pareDisplayScale) private var scale
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            SelectionControl(isSelected: isSelected, action: onToggleSelection)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.appName)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if let bid = candidate.bundleID {
                    Text(bid)
                        .font(scale.font(10, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(candidate.caskToken)
                .font(scale.rowMono)
                .foregroundStyle(AppTheme.accent)
                .frame(width: scale.scaled(160), alignment: .leading)
                .lineLimit(1)

            if scale.sizeClass != .compact {
                Text(candidate.currentPath)
                    .font(scale.font(10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: scale.scaled(260), alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button(action: onMigrate) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Adopt")
                }
                .font(scale.micro)
                .foregroundStyle(AppTheme.success)
            }
            .buttonStyle(.borderless)
            .help(candidate.adoptCommand)
            .frame(width: scale.colActions, alignment: .trailing)
            .opacity(isHovered ? 1 : 0.7)
        }
        .hoverableRow(isHovered: $isHovered, verticalPadding: scale.space(10))
    }
}

// MARK: - BrewOperationSheet

struct BrewOperationSheet: View {
    @ObservedObject var viewModel: HomebrewManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logView
            Divider()
            footer
        }
        .frame(width: 620, height: 480)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 14) {
            operationIcon
            VStack(alignment: .leading, spacing: 4) {
                switch viewModel.operationState {
                case .running(let label):
                    Text(label)
                        .font(.system(size: 17, weight: .semibold))
                case .succeeded:
                    Text("Operation Completed")
                        .font(.system(size: 17, weight: .semibold))
                case .partiallySucceeded:
                    Text("Completed with Errors")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                case .failed:
                    Text("Operation Failed")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.red)
                case .idle:
                    Text("Ready")
                        .font(.system(size: 17, weight: .semibold))
                }
                if case .running = viewModel.operationState {
                    Text("\(viewModel.operationLog.count) lines")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var operationIcon: some View {
        switch viewModel.operationState {
        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .frame(width: 32, height: 32)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
        case .partiallySucceeded:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.warning)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)
        case .idle:
            Image(systemName: "shippingbox")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(viewModel.operationLog.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lineColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 1)
                            .id(index)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.3))
            .onChange(of: viewModel.operationLog.count) { _ in
                if let last = viewModel.operationLog.indices.last {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fail") { return .red.opacity(0.9) }
        if lower.contains("warning") || lower.contains("warn") { return .yellow.opacity(0.9) }
        if lower.contains("==>") { return .cyan.opacity(0.9) }
        return .white.opacity(0.75)
    }

    private var footer: some View {
        HStack {
            if case .failed(let msg) = viewModel.operationState {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case .partiallySucceeded = viewModel.operationState,
                      let summary = viewModel.operationSummary {
                Text(summary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let summary = viewModel.operationSummary {
                Text(summary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(summary.contains("failed") ? AppTheme.warning : AppTheme.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
            Button(isRunning ? "Running…" : "Done") {
                viewModel.dismissOperation()
            }
            .disabled(isRunning)
            .keyboardShortcut(.return)
        }
        .padding(20)
    }

    private var isRunning: Bool {
        if case .running = viewModel.operationState { return true }
        return false
    }
}

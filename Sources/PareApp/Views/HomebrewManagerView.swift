import SwiftUI
import PareCore

struct HomebrewManagerView: View {
    @StateObject private var viewModel = HomebrewManagerViewModel()
    @Environment(\.displayScale) private var scale

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
            AppBackgroundView()

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
        .onAppear {
            if viewModel.loadState == .idle { viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Homebrew Manager")
                        .font(scale.heroTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Manage formulae, casks, updates, and migrate apps to Homebrew")
                        .font(scale.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                headerActions
            }
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

                if viewModel.loadState == .loaded && !viewModel.outdated.isEmpty {
                    PrimaryActionButton(
                        title: "Upgrade All (\(viewModel.outdated.count))",
                        systemImage: "arrow.up.circle",
                        isLoading: false,
                        style: .compact,
                        tint: .warning
                    ) { viewModel.upgradeAll() }
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
        }
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
            switch viewModel.selectedTab {
            case .formulae: formulaeList
            case .casks: casksList
            case .outdated: outdatedList
            case .migrate: migrateList
            }
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
                        FormulaRow(formula: formula) {
                            viewModel.uninstall(formula: formula)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var formulaeHeader: some View {
        HStack {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Version").frame(width: scale.scaled(120), alignment: .leading)
            if scale.sizeClass != .compact {
                Text("Installed").frame(width: scale.colDate, alignment: .trailing)
                Text("Requested").frame(width: scale.scaled(90), alignment: .center)
            }
            Spacer().frame(width: scale.scaled(50))
        }
        .font(scale.tableHeader)
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12))
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
                        CaskRow(cask: cask) {
                            viewModel.uninstall(cask: cask)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var casksHeader: some View {
        HStack {
            Text("Token").frame(maxWidth: .infinity, alignment: .leading)
            Text("Version").frame(width: scale.scaled(120), alignment: .leading)
            if scale.sizeClass != .compact {
                Text("App").frame(width: scale.scaled(160), alignment: .leading)
                Text("Installed").frame(width: scale.colDate, alignment: .trailing)
            }
            Spacer().frame(width: scale.scaled(50))
        }
        .font(scale.tableHeader)
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12))
    }

    // MARK: - Outdated

    private var outdatedList: some View {
        Group {
            if viewModel.filteredOutdated.isEmpty {
                emptyPrompt(icon: "checkmark.seal", text: "All packages are up to date")
            } else {
                StableListContainer(resetToken: listResetToken) {
                    outdatedHeader
                } content: {
                    ForEach(viewModel.filteredOutdated) { pkg in
                        OutdatedRow(package: pkg) {
                            viewModel.upgrade(package: pkg)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var outdatedHeader: some View {
        HStack {
            Text("Package").frame(maxWidth: .infinity, alignment: .leading)
            Text("Installed").frame(width: scale.scaled(120), alignment: .leading)
            Text("Available").frame(width: scale.scaled(120), alignment: .leading)
            if scale.sizeClass != .compact {
                Text("Type").frame(width: scale.scaled(80), alignment: .center)
            }
            Spacer().frame(width: scale.colActions)
        }
        .font(scale.tableHeader)
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12))
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
                            MigrateCandidateRow(candidate: candidate) {
                                viewModel.migrate(candidate: candidate)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: scale.scaled(40)))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
            Text(text)
                .font(scale.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - FormulaRow

private struct FormulaRow: View {
    let formula: BrewFormula
    let onUninstall: () -> Void
    @Environment(\.displayScale) private var scale
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formula.name)
                        .font(scale.rowTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if formula.pinned { badge("pinned", color: AppTheme.accent) }
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
                .frame(width: scale.scaled(120), alignment: .leading)
                .lineLimit(1)

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
        .padding(.horizontal, 16)
        .padding(.vertical, scale.space(10))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(scale.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - CaskRow

private struct CaskRow: View {
    let cask: BrewCask
    let onUninstall: () -> Void
    @Environment(\.displayScale) private var scale
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cask.token)
                        .font(scale.rowTitle)
                        .foregroundStyle(cask.isOrphaned ? AppTheme.warning : AppTheme.textPrimary)
                        .lineLimit(1)
                    if cask.isOrphaned {
                        badge("orphaned", color: AppTheme.warning)
                    }
                    if cask.autoUpdates {
                        badge("auto", color: AppTheme.accent)
                    }
                }
                if cask.isOrphaned {
                    Text("App not found — removed without brew uninstall")
                        .font(scale.font(10, weight: .regular))
                        .foregroundStyle(AppTheme.warning.opacity(0.8))
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
                  : "Uninstall \(cask.token)")
            .frame(width: cask.isOrphaned ? scale.scaled(90) : scale.scaled(50), alignment: .trailing)
            .opacity(isHovered ? 1 : (cask.isOrphaned ? 0.8 : 0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, scale.space(cask.isOrphaned ? 12 : 10))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    cask.isOrphaned
                        ? AppTheme.warning.opacity(isHovered ? 0.12 : 0.07)
                        : Color.white.opacity(isHovered ? 0.06 : 0)
                )
        )
        .onHover { isHovered = $0 }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(scale.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - OutdatedRow

private struct OutdatedRow: View {
    let package: BrewOutdatedPackage
    let onUpgrade: () -> Void
    @Environment(\.displayScale) private var scale
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(package.name)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if package.pinned { badge("pinned", color: AppTheme.accent) }
                if package.isAutoUpdate { badge("auto", color: AppTheme.textSecondary) }
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
                            Text("Upgrade")
                        }
                        .font(scale.micro)
                        .foregroundStyle(AppTheme.success)
                    }
                    .buttonStyle(.borderless)
                    .help("Upgrade \(package.name) to \(package.currentVersion)")
                } else {
                    Text("Pinned")
                        .font(scale.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                }
            }
            .frame(width: scale.colActions, alignment: .trailing)
            .opacity(isHovered ? 1 : 0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, scale.space(10))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(scale.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - MigrateCandidateRow

private struct MigrateCandidateRow: View {
    let candidate: MigrationCandidate
    let onMigrate: () -> Void
    @Environment(\.displayScale) private var scale
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, scale.space(10))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
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

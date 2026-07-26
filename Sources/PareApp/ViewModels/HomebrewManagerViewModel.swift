import Foundation
import SwiftUI
import PareCore

@MainActor
final class HomebrewManagerViewModel: ObservableObject {

    enum Tab: String, CaseIterable {
        case formulae = "Formulae"
        case casks = "Casks"
        case outdated = "Outdated"
        case migrate = "Migrate"
    }

    typealias FormulaSortField = BrewListFiltering.FormulaSortField

    enum OperationState {
        case idle
        case running(label: String)
        case succeeded
        /// Some items succeeded and some failed in a multi-item batch.
        case partiallySucceeded
        case failed(String)
    }

    enum ConfirmationAction: String, Identifiable {
        case uninstallFormulae, uninstallCasks, upgradePackages, adoptApps

        var id: String { rawValue }
        var title: String {
            switch self {
            case .uninstallFormulae: return "Uninstall Formulae"
            case .uninstallCasks: return "Uninstall Casks"
            case .upgradePackages: return "Upgrade Packages"
            case .adoptApps: return "Adopt Apps"
            }
        }
        var operationDescription: String {
            switch self {
            case .uninstallFormulae: return "Remove the selected formulae from Homebrew."
            case .uninstallCasks: return "Uninstall the selected casks and remove their apps."
            case .upgradePackages: return "Upgrade the selected Homebrew packages."
            case .adoptApps: return "Adopt the selected apps into Homebrew casks."
            }
        }

        /// The tab whose selection this action consumes.
        var tab: Tab {
            switch self {
            case .uninstallFormulae: return .formulae
            case .uninstallCasks: return .casks
            case .upgradePackages: return .outdated
            case .adoptApps: return .migrate
            }
        }
    }

    struct PendingConfirmation: Identifiable {
        enum Mode {
            case aggregate(names: [String], command: [String])
            case perItem([(name: String, command: [String])])
        }

        let id = UUID()
        let action: ConfirmationAction
        let mode: Mode
        let warnsAboutAutoUpdates: Bool

        var names: [String] {
            switch mode {
            case .aggregate(let names, _): return names
            case .perItem(let items): return items.map(\.name)
            }
        }

        var commands: [[String]] {
            switch mode {
            case .aggregate(_, let command): return [command]
            case .perItem(let items): return items.map(\.command)
            }
        }
    }

    /// One selection container for all four tabs — replaces the previous four
    /// parallel `Set<String>` properties and their per-method `switch` dispatchers.
    struct TabState {
        private var selections: [Tab: Set<String>] = [:]

        subscript(tab: Tab) -> Set<String> {
            get { selections[tab] ?? [] }
            set { selections[tab] = newValue }
        }

        func isSelected(_ id: String, in tab: Tab) -> Bool {
            self[tab].contains(id)
        }

        func count(in tab: Tab) -> Int {
            self[tab].count
        }

        mutating func toggle(_ id: String, in tab: Tab) {
            if self[tab].contains(id) {
                self[tab].remove(id)
            } else {
                self[tab].insert(id)
            }
        }

        mutating func union<S: Sequence>(_ ids: S, in tab: Tab) where S.Element == String {
            self[tab].formUnion(ids)
        }

        mutating func clear(_ tab: Tab) {
            selections[tab] = []
        }

        mutating func clearAll() {
            selections = [:]
        }
    }

    // MARK: - Published

    @Published var selectedTab: Tab = .formulae
    @Published var loadState: LoadState = .idle
    @Published var formulae: [BrewFormula] = []
    @Published var casks: [BrewCask] = []
    @Published var outdated: [BrewOutdatedPackage] = []
    @Published var migrationCandidates: [MigrationCandidate] = []
    /// Migration candidates load after the main inventory (needs the app scan);
    /// tracked separately so Migrate shows a real loading state, not a false empty.
    @Published private(set) var isLoadingMigrationCandidates = false
    @Published var searchText = ""
    @Published var showAllFormulae = false
    @Published var formulaSortField: FormulaSortField = .size
    @Published var formulaSortAscending = false

    @Published var operationState: OperationState = .idle
    @Published var operationLog: [String] = []
    @Published var showOperationSheet = false

    /// Cask pending confirmation for Leave Homebrew.
    @Published var leaveConfirmCask: BrewCask?
    @Published var leaveForceQuit = false
    @Published var pendingConfirmation: PendingConfirmation?
    @Published private(set) var tabSelections = TabState()
    @Published var operationSummary: String?
    /// Non-nil when a background formulae refresh failed (R0.9 — no silent failures).
    @Published var reloadError: String?

    // MARK: - Computed

    var isInstalled: Bool { BrewRunner.shared.isInstalled }

    /// Outdated packages that `brew upgrade` (non-greedy) will touch.
    var brewManagedOutdated: [BrewOutdatedPackage] {
        BrewListFiltering.brewManagedOutdated(outdated)
    }

    /// Self-updating casks visible via greedy outdated discovery.
    var autoUpdateOutdated: [BrewOutdatedPackage] {
        BrewListFiltering.autoUpdateOutdated(outdated)
    }

    var filteredFormulae: [BrewFormula] {
        BrewListFiltering.filterFormulae(
            formulae,
            search: searchText,
            sortField: formulaSortField,
            ascending: formulaSortAscending
        )
    }

    func toggleFormulaSort(_ field: FormulaSortField) {
        if formulaSortField == field {
            formulaSortAscending.toggle()
        } else {
            formulaSortField = field
            formulaSortAscending = field == .name
        }
    }

    var filteredCasks: [BrewCask] {
        BrewListFiltering.filterCasks(casks, search: searchText)
    }

    var orphanedCasksCount: Int { casks.filter(\.isOrphaned).count }

    var filteredOutdated: [BrewOutdatedPackage] {
        BrewListFiltering.filterOutdated(outdated, search: searchText)
    }

    var filteredMigrationCandidates: [MigrationCandidate] {
        BrewListFiltering.filterMigrationCandidates(migrationCandidates, search: searchText)
    }

    var selectedCount: Int {
        tabSelections.count(in: selectedTab)
    }

    /// Count of selected items that can actually run the current tab's bulk action.
    /// On Outdated, pinned packages are excluded (they cannot be upgraded).
    var actionableSelectedCount: Int {
        guard selectedTab == .outdated else { return selectedCount }
        let selected = tabSelections[.outdated]
        return outdated.filter { selected.contains($0.id) && !$0.pinned }.count
    }

    var isOperationRunning: Bool {
        if case .running = operationState { return true }
        return false
    }

    // MARK: - Private

    private let inventory = BrewInventory()
    private let outdatedChecker = BrewOutdatedChecker()
    private let migrationAdvisor = MigrationAdvisor()
    private let appInventory = AppInventory()
    /// Streamed brew output pending publication (batched to avoid one
    /// `@Published` array mutation — and view diff — per output line).
    private var pendingLogLines: [String] = []
    private var logFlushScheduled = false

    // MARK: - Actions

    func load() {
        guard loadState != .loading else { return }
        loadState = .loading
        Task {
            do {
                async let brewData = inventory.scan(showAll: showAllFormulae)
                async let outdatedData = outdatedChecker.check()

                let (f, c) = try await brewData
                let o = try await outdatedData

                self.formulae = f
                self.casks = c
                self.outdated = o
                self.tabSelections.clearAll()
                self.loadState = .loaded

                // Fetch migration candidates in the background (needs app inventory)
                self.isLoadingMigrationCandidates = true
                Task {
                    defer { self.isLoadingMigrationCandidates = false }
                    let apps = await appInventory.scan()
                    self.migrationCandidates = await migrationAdvisor.candidates(for: apps)
                    self.tabSelections.clear(.migrate)
                }
            } catch let error as BrewError {
                self.loadState = .error(error.localizedDescription)
            } catch {
                self.loadState = .error(error.localizedDescription)
            }
        }
    }

    func reloadFormulae() {
        guard loadState == .loaded else { return }
        Task {
            do {
                let (f, c) = try await inventory.scan(showAll: showAllFormulae)
                self.formulae = f
                self.casks = c
                self.tabSelections.clear(.formulae)
                self.tabSelections.clear(.casks)
                self.reloadError = nil
            } catch {
                // R0.9: never fail silently — keep the existing list but say why
                // the refresh didn't happen.
                self.reloadError = "Could not refresh packages: \(error.localizedDescription)"
            }
        }
    }

    func requestUpgradeAll() {
        guard !brewManagedOutdated.isEmpty else { return }
        requestConfirmation(
            action: .upgradePackages,
            mode: .aggregate(names: brewManagedOutdated.map(\.name), command: ["upgrade"]),
            warnsAboutAutoUpdates: false
        )
    }

    func requestGreedyUpgradeAll() {
        guard !outdated.isEmpty else { return }
        requestConfirmation(
            action: .upgradePackages,
            mode: .aggregate(names: outdated.map(\.name), command: ["upgrade", "--greedy"]),
            warnsAboutAutoUpdates: !autoUpdateOutdated.isEmpty
        )
    }

    func upgrade(package: BrewOutdatedPackage) {
        guard !package.pinned else { return }
        requestConfirmation(
            action: .upgradePackages,
            mode: .perItem([(name: package.name, command: BrewBulkPlanning.upgradeArgs(for: package))]),
            warnsAboutAutoUpdates: package.isAutoUpdate
        )
    }

    func uninstall(formula: BrewFormula) {
        requestConfirmation(
            action: .uninstallFormulae,
            mode: .perItem([(name: formula.name, command: BrewBulkPlanning.uninstallFormulaArgs(name: formula.name))]),
            warnsAboutAutoUpdates: false
        )
    }

    func uninstall(cask: BrewCask) {
        requestConfirmation(
            action: .uninstallCasks,
            mode: .perItem([(name: cask.token, command: BrewBulkPlanning.uninstallCaskArgs(token: cask.token))]),
            warnsAboutAutoUpdates: false
        )
    }

    /// Begin Leave Homebrew flow — shows confirmation sheet.
    func requestLeaveHomebrew(cask: BrewCask) {
        leaveForceQuit = false
        leaveConfirmCask = cask
    }

    func cancelLeaveHomebrew() {
        leaveConfirmCask = nil
        leaveForceQuit = false
    }

    /// Detach cask from Homebrew while keeping the app on disk (no zap).
    func confirmLeaveHomebrew() {
        guard let cask = leaveConfirmCask else { return }
        let forceQuit = leaveForceQuit
        leaveConfirmCask = nil
        leaveForceQuit = false

        beginOperation(label: "Leaving Homebrew: \(cask.token)…")

        Task {
            let leaver = CaskLeaveHomebrew()
            do {
                let result = try await leaver.leave(
                    cask: cask,
                    forceQuitRunning: forceQuit
                ) { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                    }
                }
                self.casks.removeAll { $0.token == result.token }
                self.flushLogNow()
                self.operationState = .succeeded
            } catch {
                self.appendLog(error.localizedDescription)
                self.flushLogNow()
                self.operationState = .failed(error.localizedDescription)
            }
        }
    }

    func migrate(candidate: MigrationCandidate) {
        requestConfirmation(
            action: .adoptApps,
            mode: .perItem([(name: candidate.appName, command: BrewBulkPlanning.adoptArgs(caskToken: candidate.caskToken))]),
            warnsAboutAutoUpdates: false
        )
    }

    // MARK: - Selection

    func toggleSelection(id: String) {
        // Pinned outdated packages cannot be upgraded — keep selection aligned
        // with the action.
        if selectedTab == .outdated,
           let pkg = outdated.first(where: { $0.id == id }), pkg.pinned {
            return
        }
        tabSelections.toggle(id, in: selectedTab)
    }

    func isSelected(_ id: String) -> Bool {
        tabSelections.isSelected(id, in: selectedTab)
    }

    func selectAllVisible() {
        tabSelections.union(visibleSelectableIDs(in: selectedTab), in: selectedTab)
    }

    func clearSelection() {
        tabSelections.clear(selectedTab)
    }

    /// IDs eligible for multi-select in a tab's currently filtered list.
    private func visibleSelectableIDs(in tab: Tab) -> [String] {
        switch tab {
        case .formulae: return filteredFormulae.map(\.id)
        case .casks: return filteredCasks.map(\.id)
        case .outdated: return BrewBulkPlanning.selectableOutdatedIDs(from: filteredOutdated)
        case .migrate: return filteredMigrationCandidates.map(\.id)
        }
    }

    func requestBulkAction() {
        switch selectedTab {
        case .formulae:
            let selected = tabSelections[.formulae]
            let values = formulae.filter { selected.contains($0.id) }
            let items = values.map { (name: $0.name, command: BrewBulkPlanning.uninstallFormulaArgs(name: $0.name)) }
            requestConfirmation(
                action: .uninstallFormulae,
                mode: .perItem(items),
                warnsAboutAutoUpdates: false
            )
        case .casks:
            let selected = tabSelections[.casks]
            let values = casks.filter { selected.contains($0.id) }
            let items = values.map { (name: $0.token, command: BrewBulkPlanning.uninstallCaskArgs(token: $0.token)) }
            requestConfirmation(
                action: .uninstallCasks,
                mode: .perItem(items),
                warnsAboutAutoUpdates: false
            )
        case .outdated:
            let selectedIDs = tabSelections[.outdated]
            let selected = outdated.filter { selectedIDs.contains($0.id) }
            let values = BrewBulkPlanning.upgradeablePackages(from: selected)
            guard !values.isEmpty else { return }
            let items = values.map { (name: $0.name, command: BrewBulkPlanning.upgradeArgs(for: $0)) }
            requestConfirmation(
                action: .upgradePackages,
                mode: .perItem(items),
                warnsAboutAutoUpdates: values.contains(where: \.isAutoUpdate)
            )
        case .migrate:
            let selected = tabSelections[.migrate]
            let values = migrationCandidates.filter { selected.contains($0.id) }
            let items = values.map { (name: $0.appName, command: BrewBulkPlanning.adoptArgs(caskToken: $0.caskToken)) }
            requestConfirmation(
                action: .adoptApps,
                mode: .perItem(items),
                warnsAboutAutoUpdates: false
            )
        }
    }

    func cancelConfirmation() { pendingConfirmation = nil }

    func confirmPendingOperation() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        Task { @MainActor in
            self.runBatch(pending)
        }
    }

    func dismissOperation() {
        let shouldReload: Bool
        switch operationState {
        case .succeeded, .partiallySucceeded, .failed:
            shouldReload = true
        case .idle, .running:
            shouldReload = false
        }

        operationState = .idle
        operationLog = []
        operationSummary = nil
        pendingLogLines = []
        showOperationSheet = false

        // Reload inventory + migrate list so adopted casks stay gone after Done.
        if shouldReload, loadState == .loaded || loadState == .idle {
            load()
        }
    }

    // MARK: - Private

    private func requestConfirmation(
        action: ConfirmationAction,
        mode: PendingConfirmation.Mode,
        warnsAboutAutoUpdates: Bool
    ) {
        guard !isOperationRunning else { return }
        switch mode {
        case .aggregate(let names, let command):
            guard !names.isEmpty, !command.isEmpty else { return }
        case .perItem(let items):
            guard !items.isEmpty else { return }
        }
        pendingConfirmation = PendingConfirmation(
            action: action,
            mode: mode,
            warnsAboutAutoUpdates: warnsAboutAutoUpdates
        )
    }

    private func runBatch(_ pending: PendingConfirmation) {
        beginOperation(label: "\(pending.action.title) \(pending.names.count) item(s)…")

        Task {
            var successes = 0
            var failures = 0
            let operations: [(name: String, command: [String])]
            switch pending.mode {
            case .aggregate(let names, let command):
                operations = [(name: names.joined(separator: ", "), command: command)]
            case .perItem(let items):
                operations = items
            }
            for (name, args) in operations {
                appendLog("==> brew \(args.joined(separator: " "))")
                do {
                    for try await line in BrewRunner.shared.stream(args) { appendLog(line) }
                    successes += 1
                } catch {
                    failures += 1
                    appendLog("Failed \(name): \(error.localizedDescription)")
                }
            }
            flushLogNow()
            let result = BrewBulkPlanning.batchResult(successes: successes, failures: failures)
            operationSummary = result.summary
            switch result.outcome {
            case .succeeded:
                operationState = .succeeded
            case .partiallySucceeded:
                operationState = .partiallySucceeded
            case .failed:
                operationState = .failed(result.summary)
            }
            tabSelections.clear(pending.action.tab)
        }
    }

    private func beginOperation(label: String) {
        operationLog = []
        operationSummary = nil
        pendingLogLines = []
        operationState = .running(label: label)
        showOperationSheet = true
    }

    // MARK: - Batched operation log

    /// Buffer a streamed output line; the published log is updated at most
    /// ~12×/second instead of once per line.
    private func appendLog(_ line: String) {
        pendingLogLines.append(line)
        scheduleLogFlush()
    }

    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            self?.logFlushScheduled = false
            self?.flushLogNow()
        }
    }

    private func flushLogNow() {
        guard !pendingLogLines.isEmpty else { return }
        operationLog.append(contentsOf: pendingLogLines)
        pendingLogLines.removeAll()
    }
}

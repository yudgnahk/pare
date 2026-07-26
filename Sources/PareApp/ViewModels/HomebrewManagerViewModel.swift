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

    enum FormulaSortField: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case installed = "Installed"
    }

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

    // MARK: - Published

    @Published var selectedTab: Tab = .formulae
    @Published var loadState: LoadState = .idle
    @Published var formulae: [BrewFormula] = []
    @Published var casks: [BrewCask] = []
    @Published var outdated: [BrewOutdatedPackage] = []
    @Published var migrationCandidates: [MigrationCandidate] = []
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
    @Published private(set) var selectedFormulaIDs: Set<String> = []
    @Published private(set) var selectedCaskIDs: Set<String> = []
    @Published private(set) var selectedOutdatedIDs: Set<String> = []
    @Published private(set) var selectedMigrationIDs: Set<String> = []
    @Published var operationSummary: String?
    /// Non-nil when a background formulae refresh failed (R0.9 — no silent failures).
    @Published var reloadError: String?

    // MARK: - Computed

    var isInstalled: Bool { BrewRunner.shared.isInstalled }

    /// Outdated packages that `brew upgrade` (non-greedy) will touch.
    /// Self-updating casks are excluded — they update themselves.
    var brewManagedOutdated: [BrewOutdatedPackage] {
        outdated.filter { $0.isFormula || !$0.isAutoUpdate }
    }

    /// Self-updating casks visible via greedy outdated discovery.
    var autoUpdateOutdated: [BrewOutdatedPackage] {
        outdated.filter { !$0.isFormula && $0.isAutoUpdate }
    }

    var filteredFormulae: [BrewFormula] {
        var result = formulae
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.desc.localizedCaseInsensitiveContains(searchText)
            }
        }
        result.sort { a, b in
            let ascending: Bool
            switch formulaSortField {
            case .name:
                ascending = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                ascending = a.sizeBytes < b.sizeBytes
            case .installed:
                ascending = (a.installDate ?? .distantPast) < (b.installDate ?? .distantPast)
            }
            return formulaSortAscending ? ascending : !ascending
        }
        return result
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
        let base: [BrewCask]
        if searchText.isEmpty {
            base = casks
        } else {
            base = casks.filter {
                $0.token.localizedCaseInsensitiveContains(searchText)
                    || $0.installedAppNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        // Orphaned casks float to the top so they are immediately visible.
        return base.sorted { a, b in
            if a.isOrphaned != b.isOrphaned { return a.isOrphaned }
            return a.token.localizedCaseInsensitiveCompare(b.token) == .orderedAscending
        }
    }

    var orphanedCasksCount: Int { casks.filter(\.isOrphaned).count }

    var filteredOutdated: [BrewOutdatedPackage] {
        guard !searchText.isEmpty else { return outdated }
        return outdated.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredMigrationCandidates: [MigrationCandidate] {
        guard !searchText.isEmpty else { return migrationCandidates }
        return migrationCandidates.filter {
            $0.appName.localizedCaseInsensitiveContains(searchText)
                || $0.caskToken.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedCount: Int {
        switch selectedTab {
        case .formulae: return selectedFormulaIDs.count
        case .casks: return selectedCaskIDs.count
        case .outdated: return selectedOutdatedIDs.count
        case .migrate: return selectedMigrationIDs.count
        }
    }

    /// Count of selected items that can actually run the current tab's bulk action.
    /// On Outdated, pinned packages are excluded (they cannot be upgraded).
    var actionableSelectedCount: Int {
        switch selectedTab {
        case .formulae: return selectedFormulaIDs.count
        case .casks: return selectedCaskIDs.count
        case .outdated:
            return outdated.filter { selectedOutdatedIDs.contains($0.id) && !$0.pinned }.count
        case .migrate: return selectedMigrationIDs.count
        }
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
                self.clearAllSelections()
                self.loadState = .loaded

                // Fetch migration candidates in the background (needs app inventory)
                Task {
                    let apps = await appInventory.scan()
                    self.migrationCandidates = await migrationAdvisor.candidates(for: apps)
                    self.selectedMigrationIDs.removeAll()
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
                self.selectedFormulaIDs.removeAll()
                self.selectedCaskIDs.removeAll()
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

        operationLog = []
        operationSummary = nil
        operationState = .running(label: "Leaving Homebrew: \(cask.token)…")
        showOperationSheet = true

        Task {
            let leaver = CaskLeaveHomebrew()
            do {
                let result = try await leaver.leave(
                    cask: cask,
                    forceQuitRunning: forceQuit
                ) { [weak self] line in
                    Task { @MainActor in
                        self?.operationLog.append(line)
                    }
                }
                self.casks.removeAll { $0.token == result.token }
                self.operationState = .succeeded
            } catch let error as CaskLeaveError {
                self.operationLog.append(error.localizedDescription)
                self.operationState = .failed(error.localizedDescription)
            } catch {
                self.operationLog.append(error.localizedDescription)
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

    func toggleSelection(id: String) {
        switch selectedTab {
        case .formulae: toggle(id, in: &selectedFormulaIDs)
        case .casks: toggle(id, in: &selectedCaskIDs)
        case .outdated:
            // Pinned packages cannot be upgraded — keep selection aligned with action.
            if let pkg = outdated.first(where: { $0.id == id }), pkg.pinned {
                return
            }
            toggle(id, in: &selectedOutdatedIDs)
        case .migrate: toggle(id, in: &selectedMigrationIDs)
        }
    }

    func isSelected(_ id: String) -> Bool {
        switch selectedTab {
        case .formulae: return selectedFormulaIDs.contains(id)
        case .casks: return selectedCaskIDs.contains(id)
        case .outdated: return selectedOutdatedIDs.contains(id)
        case .migrate: return selectedMigrationIDs.contains(id)
        }
    }

    func selectAllVisible() {
        switch selectedTab {
        case .formulae: selectedFormulaIDs.formUnion(filteredFormulae.map(\.id))
        case .casks: selectedCaskIDs.formUnion(filteredCasks.map(\.id))
        case .outdated:
            selectedOutdatedIDs.formUnion(
                BrewBulkPlanning.selectableOutdatedIDs(from: filteredOutdated)
            )
        case .migrate: selectedMigrationIDs.formUnion(filteredMigrationCandidates.map(\.id))
        }
    }

    func clearSelection() {
        switch selectedTab {
        case .formulae: selectedFormulaIDs.removeAll()
        case .casks: selectedCaskIDs.removeAll()
        case .outdated: selectedOutdatedIDs.removeAll()
        case .migrate: selectedMigrationIDs.removeAll()
        }
    }

    func requestBulkAction() {
        switch selectedTab {
        case .formulae:
            let values = formulae.filter { selectedFormulaIDs.contains($0.id) }
            let items = values.map { (name: $0.name, command: BrewBulkPlanning.uninstallFormulaArgs(name: $0.name)) }
            requestConfirmation(
                action: .uninstallFormulae,
                mode: .perItem(items),
                warnsAboutAutoUpdates: false
            )
        case .casks:
            let values = casks.filter { selectedCaskIDs.contains($0.id) }
            let items = values.map { (name: $0.token, command: BrewBulkPlanning.uninstallCaskArgs(token: $0.token)) }
            requestConfirmation(
                action: .uninstallCasks,
                mode: .perItem(items),
                warnsAboutAutoUpdates: false
            )
        case .outdated:
            let selected = outdated.filter { selectedOutdatedIDs.contains($0.id) }
            let values = BrewBulkPlanning.upgradeablePackages(from: selected)
            guard !values.isEmpty else { return }
            let items = values.map { (name: $0.name, command: BrewBulkPlanning.upgradeArgs(for: $0)) }
            requestConfirmation(
                action: .upgradePackages,
                mode: .perItem(items),
                warnsAboutAutoUpdates: values.contains(where: \.isAutoUpdate)
            )
        case .migrate:
            let values = migrationCandidates.filter { selectedMigrationIDs.contains($0.id) }
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
        operationLog = []
        operationSummary = nil
        operationState = .running(label: "\(pending.action.title) \(pending.names.count) item(s)…")
        showOperationSheet = true

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
                operationLog.append("==> brew \(args.joined(separator: " "))")
                do {
                    for try await line in BrewRunner.shared.stream(args) { operationLog.append(line) }
                    successes += 1
                } catch {
                    failures += 1
                    operationLog.append("Failed \(name): \(error.localizedDescription)")
                }
            }
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
            clearSelection(for: pending.action)
        }
    }

    private func clearAllSelections() {
        selectedFormulaIDs.removeAll()
        selectedCaskIDs.removeAll()
        selectedOutdatedIDs.removeAll()
        selectedMigrationIDs.removeAll()
    }

    private func clearSelection(for action: ConfirmationAction) {
        switch action {
        case .uninstallFormulae: selectedFormulaIDs.removeAll()
        case .uninstallCasks: selectedCaskIDs.removeAll()
        case .upgradePackages: selectedOutdatedIDs.removeAll()
        case .adoptApps: selectedMigrationIDs.removeAll()
        }
    }

    private func toggle(_ id: String, in selection: inout Set<String>) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

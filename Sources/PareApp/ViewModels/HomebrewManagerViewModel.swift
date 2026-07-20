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

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)

        static func == (lhs: LoadState, rhs: LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.loaded, .loaded): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    enum OperationState {
        case idle
        case running(label: String)
        case succeeded
        case failed(String)
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
    @Published var showGreedyUpgradeConfirm = false

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
                self.loadState = .loaded

                // Fetch migration candidates in the background (needs app inventory)
                Task {
                    let apps = await appInventory.scan()
                    self.migrationCandidates = await migrationAdvisor.candidates(for: apps)
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
            } catch {}
        }
    }

    /// Upgrade formulae + non-auto casks only (`brew upgrade`, no `--greedy`).
    func upgradeAll() {
        let count = brewManagedOutdated.count
        let label = count == 0
            ? "Upgrading packages…"
            : "Upgrading \(count) package(s)…"
        runOperation(label: label, args: ["upgrade"])
    }

    /// Explicit greedy upgrade — includes self-updating casks (Chrome, VS Code, …).
    /// Prefer confirming via `showGreedyUpgradeConfirm` before calling.
    func upgradeAllIncludingAutoUpdates() {
        runOperation(
            label: "Upgrading all packages (including self-updating casks)…",
            args: ["upgrade", "--greedy"]
        )
    }

    func upgrade(package: BrewOutdatedPackage) {
        let args: [String] = package.isFormula
            ? ["upgrade", package.name]
            : ["upgrade", "--cask", package.name]
        let label: String
        if package.isAutoUpdate {
            label = "Upgrading \(package.name) (self-updating — may require restart)…"
        } else {
            label = "Upgrading \(package.name)…"
        }
        runOperation(label: label, args: args)
    }

    func uninstall(formula: BrewFormula) {
        runOperation(label: "Uninstalling \(formula.name)…", args: ["uninstall", formula.name])
    }

    func uninstall(cask: BrewCask) {
        runOperation(label: "Uninstalling \(cask.token)…", args: ["uninstall", "--cask", cask.token])
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
        runOperation(
            label: "Adopting \(candidate.appName)…",
            args: ["install", "--cask", "--adopt", candidate.caskToken],
            onSuccess: { [weak self] in
                // Drop immediately so the row disappears without waiting for Done.
                self?.migrationCandidates.removeAll { $0.caskToken == candidate.caskToken }
            }
        )
    }

    func dismissOperation() {
        let shouldReload: Bool
        if case .succeeded = operationState {
            shouldReload = true
        } else if case .failed = operationState {
            shouldReload = true
        } else {
            shouldReload = false
        }

        operationState = .idle
        operationLog = []
        showOperationSheet = false

        // Reload inventory + migrate list so adopted casks stay gone after Done.
        if shouldReload, loadState == .loaded || loadState == .idle {
            load()
        }
    }

    // MARK: - Private

    private func runOperation(
        label: String,
        args: [String],
        onSuccess: (() -> Void)? = nil
    ) {
        operationLog = []
        operationState = .running(label: label)
        showOperationSheet = true

        Task {
            do {
                for try await line in BrewRunner.shared.stream(args) {
                    self.operationLog.append(line)
                }
                self.operationState = .succeeded
                onSuccess?()
            } catch let error as BrewError {
                self.operationState = .failed(error.localizedDescription)
            } catch {
                self.operationState = .failed(error.localizedDescription)
            }
        }
    }
}

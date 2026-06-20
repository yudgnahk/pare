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
    @Published var showOnlyOrphaned = false
    @Published var selectedCaskTokens: Set<String> = []

    @Published var operationState: OperationState = .idle
    @Published var operationLog: [String] = []
    @Published var showOperationSheet = false

    // MARK: - Computed

    var isInstalled: Bool { BrewRunner.shared.isInstalled }

    var filteredFormulae: [BrewFormula] {
        guard !searchText.isEmpty else { return formulae }
        return formulae.filter { $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.desc.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredCasks: [BrewCask] {
        var base: [BrewCask] = searchText.isEmpty ? casks : casks.filter {
            $0.token.localizedCaseInsensitiveContains(searchText)
                || $0.installedAppNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
        if showOnlyOrphaned {
            base = base.filter(\.isOrphaned)
        }
        // Orphaned casks float to the top so they are immediately visible.
        return base.sorted { a, b in
            if a.isOrphaned != b.isOrphaned { return a.isOrphaned }
            return a.token.localizedCaseInsensitiveCompare(b.token) == .orderedAscending
        }
    }

    var orphanedCasksCount: Int { casks.filter(\.isOrphaned).count }

    var allFilteredCasksSelected: Bool {
        !filteredCasks.isEmpty && filteredCasks.allSatisfy { selectedCaskTokens.contains($0.token) }
    }

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

    func upgradeAll() {
        runOperation(label: "Upgrading all packages…", args: ["upgrade", "--greedy"])
    }

    func upgrade(package: BrewOutdatedPackage) {
        let args: [String] = package.isFormula
            ? ["upgrade", package.name]
            : ["upgrade", "--cask", package.name]
        runOperation(label: "Upgrading \(package.name)…", args: args)
    }

    func uninstall(formula: BrewFormula) {
        runOperation(label: "Uninstalling \(formula.name)…", args: ["uninstall", formula.name])
    }

    func uninstall(cask: BrewCask) {
        let args = ["uninstall", "--cask", cask.token]
        if cask.requiresSudo {
            showPasswordPrompt(label: "Uninstalling \(cask.token)…", args: args)
        } else {
            runOperation(label: "Uninstalling \(cask.token)…", args: args)
        }
    }

    func toggleCaskSelection(_ token: String) {
        if selectedCaskTokens.contains(token) {
            selectedCaskTokens.remove(token)
        } else {
            selectedCaskTokens.insert(token)
        }
    }

    func toggleSelectAllCasks() {
        if allFilteredCasksSelected {
            selectedCaskTokens = []
        } else {
            filteredCasks.forEach { selectedCaskTokens.insert($0.token) }
        }
    }

    func clearCaskSelection() {
        selectedCaskTokens = []
    }

    func uninstallSelectedCasks() {
        let selected = casks.filter { selectedCaskTokens.contains($0.token) }
        guard !selected.isEmpty else { return }
        let tokens = selected.map(\.token).sorted()
        let label = tokens.count == 1
            ? "Uninstalling \(tokens[0])…"
            : "Uninstalling \(tokens.count) casks…"
        let args = ["uninstall", "--cask"] + tokens
        if selected.contains(where: \.requiresSudo) {
            showPasswordPrompt(label: label, args: args)
        } else {
            runOperation(label: label, args: args)
        }
        selectedCaskTokens = []
    }

    func migrate(candidate: MigrationCandidate) {
        // Optimistic removal — count drops instantly without waiting for the background reload.
        // If the operation fails, dismissOperation() → load() restores the real list.
        migrationCandidates.removeAll { $0.caskToken == candidate.caskToken }
        runOperation(
            label: "Adopting \(candidate.appName)…",
            args: ["install", "--cask", "--adopt", candidate.caskToken]
        )
    }

    func dismissOperation() {
        operationState = .idle
        operationLog = []
        showOperationSheet = false
        selectedCaskTokens = []
        if loadState == .loaded { load() }
    }

    // MARK: - Private

    // MARK: - Privileged (sudo-required) casks

    @Published var showingPasswordPromptSheet = false
    private(set) var pendingPrivilegedLabel = ""
    private var pendingPrivilegedArgs: [String] = []

    private func showPasswordPrompt(label: String, args: [String]) {
        pendingPrivilegedLabel = label
        pendingPrivilegedArgs = args
        showingPasswordPromptSheet = true
    }

    func executePrivileged(password: String) {
        showingPasswordPromptSheet = false
        runPrivilegedOperation(label: pendingPrivilegedLabel, args: pendingPrivilegedArgs, password: password)
    }

    func cancelPasswordPrompt() {
        showingPasswordPromptSheet = false
    }

    private func runPrivilegedOperation(label: String, args: [String], password: String) {
        operationLog = []
        operationState = .running(label: label)
        showOperationSheet = true

        Task {
            do {
                for try await line in BrewRunner.shared.streamPrivileged(args, password: password) {
                    self.operationLog.append(line)
                }
                self.operationState = .succeeded
            } catch let error as BrewError {
                self.operationState = .failed(error.localizedDescription)
            } catch {
                self.operationState = .failed(error.localizedDescription)
            }
        }
    }

    private func runOperation(label: String, args: [String]) {
        operationLog = []
        operationState = .running(label: label)
        showOperationSheet = true

        Task {
            do {
                for try await line in BrewRunner.shared.stream(args) {
                    self.operationLog.append(line)
                }
                self.operationState = .succeeded
            } catch let error as BrewError {
                self.operationState = .failed(error.localizedDescription)
            } catch {
                self.operationState = .failed(error.localizedDescription)
            }
        }
    }
}

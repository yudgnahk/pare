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
        guard !searchText.isEmpty else { return casks }
        return casks.filter {
            $0.token.localizedCaseInsensitiveContains(searchText)
                || $0.installedAppNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
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
        runOperation(label: "Uninstalling \(cask.token)…", args: ["uninstall", "--cask", cask.token])
    }

    func migrate(candidate: MigrationCandidate) {
        runOperation(
            label: "Adopting \(candidate.appName)…",
            args: ["install", "--cask", "--adopt", candidate.caskToken]
        )
    }

    func dismissOperation() {
        operationState = .idle
        operationLog = []
        showOperationSheet = false

        // Reload after any operation completes
        if loadState == .loaded { load() }
    }

    // MARK: - Private

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

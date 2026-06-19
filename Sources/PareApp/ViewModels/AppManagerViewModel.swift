import Foundation
import SwiftUI
import PareCore

@MainActor
final class AppManagerViewModel: ObservableObject {

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

    enum SortField: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case installDate = "Installed"
        case lastUsed = "Last Used"
    }

    enum UninstallState: Equatable {
        case idle
        case confirming
        case uninstalling
        case done(trashed: Int, failed: Int)
        case error(String)

        static func == (lhs: UninstallState, rhs: UninstallState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.confirming, .confirming), (.uninstalling, .uninstalling): return true
            case (.done(let t1, let f1), .done(let t2, let f2)): return t1 == t2 && f1 == f2
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Published state

    @Published var loadState: LoadState = .idle
    @Published var apps: [InstalledApp] = []
    @Published var searchText: String = ""
    @Published var hideSystemApps = false
    @Published var showOnlyOutdated = false
    @Published var sortField: SortField = .size
    @Published var sortAscending = false
    @Published var checkingUpdates = false
    @Published var uninstallState: UninstallState = .idle

    // Uninstall flow
    @Published var selectedApp: InstalledApp?
    @Published var pendingLeftovers: [AppLeftover] = []
    @Published var includeGroupContainers = false
    @Published var showUninstallSheet = false

    // MARK: - Private

    private let inventory = AppInventory()
    private let checker = OutdatedChecker()
    private let uninstaller = AppUninstaller()
    private var scanTask: Task<Void, Never>?

    // MARK: - Computed

    var filteredApps: [InstalledApp] {
        var result = apps

        if hideSystemApps { result = result.filter { !$0.isSystemApp } }
        if showOnlyOutdated { result = result.filter { $0.updateInfo?.hasUpdate == true } }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || ($0.bundleID?.localizedCaseInsensitiveContains(searchText) == true)
            }
        }

        result.sort { a, b in
            let ascending: Bool
            switch sortField {
            case .name:
                ascending = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                ascending = a.sizeBytes < b.sizeBytes
            case .installDate:
                ascending = (a.installDate ?? .distantPast) < (b.installDate ?? .distantPast)
            case .lastUsed:
                ascending = (a.lastUsed ?? .distantPast) < (b.lastUsed ?? .distantPast)
            }
            return sortAscending ? ascending : !ascending
        }

        return result
    }

    var totalSizeBytes: Int64 { apps.reduce(0) { $0 + $1.sizeBytes } }
    var outdatedCount: Int { apps.filter { $0.updateInfo?.hasUpdate == true }.count }
    var updateCheckCount: Int { apps.filter { !$0.isSystemApp && $0.bundleID != nil }.count }

    // MARK: - Actions

    func loadApps() {
        guard loadState != .loading else { return }
        loadState = .loading
        scanTask = Task {
            let found = await inventory.scan()
            guard !Task.isCancelled else { return }
            self.apps = found
            self.loadState = .loaded
        }
    }

    func checkForUpdates() {
        guard !checkingUpdates, !apps.isEmpty else { return }
        checkingUpdates = true
        Task {
            let updates = await checker.checkAll(apps)
            guard !Task.isCancelled else {
                self.checkingUpdates = false
                return
            }
            self.apps = self.apps.map { app in
                guard let id = app.bundleID, let info = updates[id] else { return app }
                var updated = app
                updated.updateInfo = info
                return updated
            }
            self.checkingUpdates = false
        }
    }

    func cancelLoad() {
        scanTask?.cancel()
        loadState = .idle
    }

    func toggleSort(_ field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = field == .name
        }
    }

    // MARK: - Uninstall flow

    func requestUninstall(for app: InstalledApp) {
        selectedApp = app
        pendingLeftovers = uninstaller.findLeftovers(for: app)
        includeGroupContainers = false
        uninstallState = .confirming
        showUninstallSheet = true
    }

    func confirmUninstall() {
        guard let app = selectedApp else { return }
        uninstallState = .uninstalling
        Task {
            let (trashed, failed) = await uninstaller.uninstall(
                app: app,
                leftovers: pendingLeftovers,
                includeGroupContainers: includeGroupContainers
            )
            self.apps.removeAll { $0.path == app.path }
            self.uninstallState = .done(trashed: trashed.count, failed: failed.count)
            self.showUninstallSheet = false
            self.selectedApp = nil
            self.pendingLeftovers = []
        }
    }

    func cancelUninstall() {
        uninstallState = .idle
        showUninstallSheet = false
        selectedApp = nil
        pendingLeftovers = []
    }
}

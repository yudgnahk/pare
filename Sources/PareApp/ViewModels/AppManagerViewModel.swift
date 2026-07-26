import Foundation
import AppKit
import SwiftUI
import PareCore

@MainActor
final class AppManagerViewModel: ObservableObject {

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
    /// True after the user has run at least one successful update check this session.
    @Published var hasCheckedUpdates = false
    @Published var uninstallState: UninstallState = .idle
    /// App IDs currently running an in-app update (Homebrew cask upgrade).
    @Published var updatingAppIDs: Set<String> = []
    @Published var updateFeedback: String?

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
    private var updateCheckTask: Task<Void, Never>?

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

        // Snapshot update results so a Refresh does not wipe the "Updates only" list.
        let previousByBundleID: [String: UpdateInfo] = Dictionary(
            uniqueKeysWithValues: apps.compactMap { app -> (String, UpdateInfo)? in
                guard let id = app.bundleID, let info = app.updateInfo else { return nil }
                return (id, info)
            }
        )
        let previousByPath: [String: UpdateInfo] = Dictionary(
            uniqueKeysWithValues: apps.compactMap { app -> (String, UpdateInfo)? in
                guard let info = app.updateInfo else { return nil }
                return (app.path, info)
            }
        )
        let shouldRecheckUpdates = hasCheckedUpdates || showOnlyOutdated || !previousByBundleID.isEmpty

        scanTask = Task {
            let found = await inventory.scan()
            guard !Task.isCancelled else { return }

            self.apps = found.map { app in
                var merged = app
                if let id = app.bundleID, let info = previousByBundleID[id] {
                    merged.updateInfo = info
                } else if let info = previousByPath[app.path] {
                    merged.updateInfo = info
                }
                return merged
            }
            self.loadState = .loaded

            // Re-verify after inventory refresh so the filter stays accurate.
            if shouldRecheckUpdates {
                await self.performUpdateCheck()
            }
        }
    }

    func checkForUpdates() {
        guard !checkingUpdates, !apps.isEmpty else { return }
        updateCheckTask?.cancel()
        updateCheckTask = Task {
            await performUpdateCheck()
        }
    }

    /// Opens the update channel for the app (MAS / Sparkle URL), or runs
    /// `brew upgrade --cask` when the app is Homebrew-managed.
    func updateApp(_ app: InstalledApp) {
        updateFeedback = nil

        // Homebrew casks can be upgraded in-place without leaving Pare.
        if app.isHomebrewManaged,
           let token = uninstaller.homebrewCaskToken(for: app) {
            guard !updatingAppIDs.contains(app.id) else { return }
            updatingAppIDs.insert(app.id)
            Task {
                defer { self.updatingAppIDs.remove(app.id) }
                do {
                    _ = try await BrewRunner.shared.run(["upgrade", "--cask", token, "--greedy"])
                    // Mark as up-to-date locally, then refresh inventory.
                    if let idx = self.apps.firstIndex(where: { $0.id == app.id }) {
                        self.apps[idx].updateInfo = nil
                    }
                    self.updateFeedback = "Updated \(app.name) via Homebrew"
                    // Soft refresh so size/version update without clearing the list filter.
                    let found = await inventory.scan()
                    let previous = Dictionary(
                        uniqueKeysWithValues: self.apps.compactMap { a -> (String, UpdateInfo)? in
                            guard let id = a.bundleID, let info = a.updateInfo else { return nil }
                            return (id, info)
                        }
                    )
                    self.apps = found.map { scanned in
                        var a = scanned
                        if let id = scanned.bundleID, let info = previous[id] {
                            a.updateInfo = info
                        }
                        // Clear update for the app we just upgraded.
                        if a.id == app.id || a.path == app.path {
                            a.updateInfo = nil
                        }
                        return a
                    }
                } catch {
                    self.updateFeedback = error.localizedDescription
                }
            }
            return
        }

        // MAS / Sparkle: open the store page or download URL.
        if let url = app.updateInfo?.updateURL {
            NSWorkspace.shared.open(url)
            updateFeedback = app.updateInfo?.channel == .mas
                ? "Opened Mac App Store for \(app.name)"
                : "Opened download page for \(app.name)"
            return
        }

        // Last resort: reveal the app so the user can open it (many Sparkle apps
        // check for updates on launch).
        NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
        updateFeedback = "No direct update link — revealed \(app.name) in Finder"
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

    func dismissUpdateFeedback() {
        updateFeedback = nil
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

    // MARK: - Private

    private func performUpdateCheck() async {
        guard !apps.isEmpty else { return }
        checkingUpdates = true
        let snapshot = apps
        let updates = await checker.checkAll(snapshot)
        guard !Task.isCancelled else {
            checkingUpdates = false
            return
        }
        apps = apps.map { app in
            guard let id = app.bundleID, let info = updates[id] else { return app }
            var updated = app
            updated.updateInfo = info
            return updated
        }
        hasCheckedUpdates = true
        checkingUpdates = false
    }
}

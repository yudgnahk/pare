import Foundation
import os

/// A leftover the uninstaller declined to trash, and why.
public struct AppUninstallSkip: Sendable, Equatable {
    public let path: String
    public let reason: String
}

public struct AppUninstallResult: Sendable {
    public let trashed: [String]
    public let skipped: [AppUninstallSkip]
    public let failed: [AppUninstallSkip]
    /// History record for undo; nil when nothing was trashed or it could not be saved.
    public let transactionID: UUID?
}

public enum AppUninstallError: Error, LocalizedError, Equatable {
    case appRunning(String)
    case appExcluded(String)
    case exclusionsUnreadable
    case openFileCheckUnavailable

    public var errorDescription: String? {
        switch self {
        case .appRunning(let name):
            return "Quit \(name) before uninstalling it."
        case .appExcluded(let name):
            return "\(name) is in your exclusion list, so Pare won't remove it."
        case .exclusionsUnreadable:
            return "Pare couldn't read your exclusion list, so nothing was removed."
        case .openFileCheckUnavailable:
            return "Pare couldn't check which files are in use, so nothing was removed."
        }
    }
}

/// Scans for per-app leftover files and moves the app + leftovers to Trash.
/// Never permanently deletes — always moves to Trash and records an undoable transaction.
public struct AppUninstaller: Sendable {
    static let logger = Logger(subsystem: "Pare", category: "uninstall")
    static let systemLaunchItemReason = "System launch item — remove it with the app's own uninstaller"
    static let excludedReason = "In your exclusion list"

    private let home: URL
    private let systemLibrary: URL
    private let launchAgents: any LaunchAgentUnloading
    private let runningApps: any RunningAppsProviding
    private let openFiles: any OpenFileSnapshotProviding
    private let exclusions: @Sendable () -> ExclusionList?
    private let trashItem: @Sendable (URL) throws -> URL?
    private let transactionStore: CleanupTransactionStore

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library"),
        launchAgents: any LaunchAgentUnloading = LaunchctlAgentUnloader(),
        runningApps: any RunningAppsProviding = WorkspaceRunningAppsProvider(),
        openFiles: any OpenFileSnapshotProviding = LsofOpenFileSnapshotProvider(),
        exclusions: (@Sendable () -> ExclusionList?)? = nil,
        trashItem: (@Sendable (URL) throws -> URL?)? = nil,
        transactionStore: CleanupTransactionStore = .shared
    ) {
        self.home = home
        self.systemLibrary = systemLibrary
        self.launchAgents = launchAgents
        self.runningApps = runningApps
        self.openFiles = openFiles
        self.exclusions = exclusions ?? { try? ExclusionStore.shared.load() }
        self.trashItem = trashItem ?? Self.moveToSystemTrash
        self.transactionStore = transactionStore
    }

    private static let moveToSystemTrash: @Sendable (URL) throws -> URL? = { url in
        var resultURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
        return resultURL as URL?
    }

    private var library: URL { home.appendingPathComponent("Library") }

    // MARK: - Discovery

    /// Leftovers for `app`, matched on bundle-ID dot boundaries. Files a more specific bundle ID in
    /// `otherBundleIDs` also claims are dropped; symlinks are never offered.
    public func findLeftovers(for app: InstalledApp, otherBundleIDs: Set<String> = []) -> [AppLeftover] {
        guard let bundleID = app.bundleID, ScanPolicy.isUsableLeftoverBundleID(bundleID) else { return [] }
        let excluded = exclusions() ?? .empty
        var leftovers: [AppLeftover] = []

        let exactNames: [(folder: String, name: String, category: AppLeftoverCategory)] = [
            ("Application Support", bundleID, .support),
            ("Caches", bundleID, .caches),
            ("Containers", bundleID, .containers),
            ("WebKit", bundleID, .webkit),
            ("HTTPStorages", bundleID, .httpStorage),
            ("Saved Application State", "\(bundleID).savedState", .savedState),
            ("Application Scripts", bundleID, .applicationScripts),
            ("Logs", bundleID, .logs),
            ("Cookies", "\(bundleID).binarycookies", .cookies),
        ]
        for entry in exactNames {
            let url = library.appendingPathComponent(entry.folder).appendingPathComponent(entry.name)
            if let leftover = makeLeftover(at: url, category: entry.category, excluded: excluded) {
                leftovers.append(leftover)
            }
        }

        leftovers += namedItems(in: library.appendingPathComponent("Preferences"), app: bundleID, others: otherBundleIDs) { url, match in
            makeLeftover(at: url, category: .preferences, selected: match == .exact, excluded: excluded)
        }
        // A user agent is booted out before trashing, but it can still belong to a helper the user keeps.
        leftovers += namedItems(in: library.appendingPathComponent("LaunchAgents"), app: bundleID, others: otherBundleIDs) { url, _ in
            makeLeftover(at: url, category: .launchAgents, selected: false, excluded: excluded)
        }
        let systemFolders: [(String, AppLeftoverCategory)] = [("LaunchAgents", .launchAgents), ("LaunchDaemons", .launchDaemons)]
        for (folder, category) in systemFolders {
            leftovers += namedItems(in: systemLibrary.appendingPathComponent(folder), app: bundleID, others: otherBundleIDs) { url, _ in
                makeLeftover(at: url, category: category, excluded: excluded, reportOnly: Self.systemLaunchItemReason)
            }
        }
        leftovers += groupContainers(bundleID: bundleID, others: otherBundleIDs, excluded: excluded)

        return leftovers.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    private func namedItems(
        in directory: URL,
        app bundleID: String,
        others: Set<String>,
        make: (URL, BundleIDNameMatch) -> AppLeftover?
    ) -> [AppLeftover] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted().compactMap { name in
            let match = ScanPolicy.bundleIDNameMatch(name, bundleID: bundleID)
            guard match != .none, name.lowercased().hasSuffix(".plist"),
                  !ScanPolicy.isLeftoverClaimedByOtherApp(name, bundleID: bundleID, otherBundleIDs: others, isGroupContainer: false)
            else { return nil }
            return make(directory.appendingPathComponent(name), match)
        }
    }

    private func groupContainers(bundleID: String, others: Set<String>, excluded: ExclusionList) -> [AppLeftover] {
        let directory = library.appendingPathComponent("Group Containers")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted().compactMap { name in
            guard ScanPolicy.groupContainerNameMatches(name, bundleID: bundleID),
                  !ScanPolicy.isLeftoverClaimedByOtherApp(name, bundleID: bundleID, otherBundleIDs: others, isGroupContainer: true)
            else { return nil }
            return makeLeftover(
                at: directory.appendingPathComponent(name),
                category: .groupContainers,
                isGroupContainer: true,
                excluded: excluded
            )
        }
    }

    private func makeLeftover(
        at url: URL,
        category: AppLeftoverCategory,
        isGroupContainer: Bool = false,
        selected: Bool? = nil,
        excluded: ExclusionList,
        reportOnly: String? = nil
    ) -> AppLeftover? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return nil }
        let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
        let size = isDirectory ? FileSystemUtils.directorySize(url: url) : ((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        let reason = reportOnly ?? (excluded.blocksRemoval(of: url.path) ? Self.excludedReason : nil)
        return AppLeftover(
            path: url.path,
            sizeBytes: size,
            category: category,
            isGroupContainer: isGroupContainer,
            isSelectedByDefault: selected,
            reportOnlyReason: reason
        )
    }

    /// Checks if the app is managed by Homebrew by inspecting the caskroom receipt.
    public func homebrewCaskToken(for app: InstalledApp) -> String? {
        HomebrewCaskroom.token(forAppName: app.name, path: app.path)
    }

    // MARK: - Uninstall

    /// Moves the app bundle, then each of `leftovers` the user kept ticked, to Trash.
    /// Every leftover is re-checked here; a running app, unreadable exclusion list or missing open-file
    /// listing refuses the whole uninstall, and a leftover with anything open at or under it is skipped.
    public func uninstall(app: InstalledApp, leftovers: [AppLeftover]) async throws -> AppUninstallResult {
        if let bundleID = app.bundleID?.lowercased(),
           runningApps.runningApps().contains(where: { $0.bundleIdentifier.lowercased() == bundleID }) {
            throw AppUninstallError.appRunning(app.name)
        }
        guard let excluded = exclusions() else { throw AppUninstallError.exclusionsUnreadable }
        guard !excluded.blocksRemoval(of: app.path) else { throw AppUninstallError.appExcluded(app.name) }
        // Taken before anything moves: without it an open database would be trashed under its writer.
        guard let firstSnapshot = await openFiles.snapshot() else { throw AppUninstallError.openFileCheckUnavailable }

        var items: [CleanupItem] = []
        do {
            items.append(try trash(path: app.path, size: app.sizeBytes, reason: "Uninstalled \(app.name)"))
        } catch {
            // Leftovers stay while the app is still installed.
            let rest = leftovers.map { AppUninstallSkip(path: $0.path, reason: "The app itself could not be moved to Trash") }
            return AppUninstallResult(
                trashed: [],
                skipped: rest,
                failed: [AppUninstallSkip(path: app.path, reason: error.localizedDescription)],
                transactionID: nil
            )
        }

        let screened = await screen(leftovers, excluded: excluded)
        var skipped = screened.skipped
        var failed: [AppUninstallSkip] = []
        // A stopped agent no longer holds its own files; the older listing is the safe fallback.
        let snapshot = screened.stoppedAgent ? (await openFiles.snapshot() ?? firstSnapshot) : firstSnapshot
        for leftover in screened.pending {
            if let holder = snapshot.holder(atOrUnder: leftover.path) {
                skipped.append(AppUninstallSkip(path: leftover.path, reason: "In use by \(holder)"))
                continue
            }
            do {
                items.append(try trash(path: leftover.path, size: leftover.sizeBytes, reason: "\(app.name) leftover: \(leftover.category.rawValue)"))
            } catch {
                failed.append(AppUninstallSkip(path: leftover.path, reason: error.localizedDescription))
            }
        }

        return AppUninstallResult(
            trashed: items.map(\.originalPath),
            skipped: skipped,
            failed: failed,
            transactionID: record(items, appName: app.name)
        )
    }

    /// Splits `leftovers` into those still eligible and those refused, booting out user launch agents on the way.
    private func screen(
        _ leftovers: [AppLeftover],
        excluded: ExclusionList
    ) async -> (pending: [AppLeftover], skipped: [AppUninstallSkip], stoppedAgent: Bool) {
        var pending: [AppLeftover] = []
        var skipped: [AppUninstallSkip] = []
        var stoppedAgent = false
        for leftover in leftovers {
            if let reason = refusal(for: leftover, excluded: excluded) {
                skipped.append(AppUninstallSkip(path: leftover.path, reason: reason))
                continue
            }
            if leftover.category == .launchAgents {
                switch await launchAgents.unload(plistAt: URL(fileURLWithPath: leftover.path)) {
                case .unloaded:
                    stoppedAgent = true
                case .notLoaded:
                    break
                case .failed(let reason):
                    skipped.append(AppUninstallSkip(path: leftover.path, reason: "Launch agent still loaded (\(reason))"))
                    continue
                }
            }
            pending.append(leftover)
        }
        return (pending, skipped, stoppedAgent)
    }

    /// Why `leftover` must not be trashed now, or nil.
    private func refusal(for leftover: AppLeftover, excluded: ExclusionList) -> String? {
        if let reason = leftover.reportOnlyReason { return reason }
        guard ScanPolicy.isAppLeftoverLocation(leftover.path, home: home) else {
            return "Outside the folders Pare uninstalls from"
        }
        guard !ScanPolicy.isSymbolicLink(atPath: leftover.path) else { return "Symbolic link" }
        guard FileManager.default.fileExists(atPath: leftover.path) else { return "Already gone" }
        guard !excluded.blocksRemoval(of: leftover.path) else { return Self.excludedReason }
        return nil
    }

    private func trash(path: String, size: Int64, reason: String) throws -> CleanupItem {
        let trashedURL = try trashItem(URL(fileURLWithPath: path))
        return CleanupItem(
            originalPath: path,
            trashedPath: trashedURL?.path,
            sizeBytes: size,
            reason: reason,
            riskLevel: .review
        )
    }

    private func record(_ items: [CleanupItem], appName: String) -> UUID? {
        guard !items.isEmpty else { return nil }
        let transaction = CleanupTransaction(profileName: "Uninstall \(appName)", isDryRun: false, items: items)
        do {
            try transactionStore.save(transaction)
            return transaction.id
        } catch {
            Self.logger.error("Saving uninstall history failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

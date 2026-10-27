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
    /// History record for undo; nil when nothing was trashed.
    public let transactionID: UUID?
    /// Set when the last History save failed, so Undo may miss some trashed items.
    public let undoSaveError: String?
}

public enum AppUninstallError: Error, LocalizedError, Equatable {
    case appRunning(String)
    case appInUse(app: String, holder: String)
    case appExcluded(String)
    case exclusionsUnreadable
    case openFileCheckUnavailable
    case undoRecordUnavailable

    public var errorDescription: String? {
        switch self {
        case .appRunning(let name):
            return "Quit \(name) before uninstalling it."
        case .appInUse(let name, let holder):
            return "\(holder) is using \(name). Quit it before uninstalling."
        case .undoRecordUnavailable:
            return "Pare couldn't save an Undo record, so nothing was removed."
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
    private let appCopies: any AppCopyLocating
    private let exclusions: @Sendable () -> ExclusionList?
    private let trashItem: @Sendable (URL) throws -> URL?
    private let transactionStore: CleanupTransactionStore

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library"),
        launchAgents: any LaunchAgentUnloading = LaunchctlAgentUnloader(),
        runningApps: any RunningAppsProviding = WorkspaceRunningAppsProvider(),
        openFiles: any OpenFileSnapshotProviding = LsofOpenFileSnapshotProvider(),
        appCopies: any AppCopyLocating = LaunchServicesAppCopyLocator(),
        exclusions: (@Sendable () -> ExclusionList?)? = nil,
        trashItem: (@Sendable (URL) throws -> URL?)? = nil,
        transactionStore: CleanupTransactionStore = .shared
    ) {
        self.home = home
        self.systemLibrary = systemLibrary
        self.launchAgents = launchAgents
        self.runningApps = runningApps
        self.openFiles = openFiles
        self.appCopies = appCopies
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

    /// Paths of other installed apps sharing `app`'s bundle ID; their data is the same files.
    public static func otherCopies(of app: InstalledApp, in apps: [InstalledApp]) -> [String] {
        guard let id = app.bundleID?.lowercased() else { return [] }
        return apps.filter { $0.path != app.path && $0.bundleID?.lowercased() == id }.map(\.path)
    }

    /// `inventoryCopies` plus copies LaunchServices knows of, minus `app` itself, missing paths and Trash.
    func mergedOtherCopies(of app: InstalledApp, inventoryCopies: [String]) -> [String] {
        guard let bundleID = app.bundleID else { return inventoryCopies }
        // Case-sensitive on purpose: a mismatch only over-blocks, a false match would trash shared data.
        var seen: Set<String> = [Self.copyKey(app.path)]
        var merged: [String] = []
        for path in inventoryCopies where seen.insert(Self.copyKey(path)).inserted {
            merged.append(path)
        }
        for url in appCopies.appURLs(forBundleID: bundleID) {
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), !Self.isInTrash(path),
                  seen.insert(Self.copyKey(path)).inserted else { continue }
            merged.append(path)
        }
        return merged
    }

    private static func copyKey(_ path: String) -> String {
        ScanPolicy.canonicalPathURL(URL(fileURLWithPath: path).resolvingSymlinksInPath()).path
    }

    private static func isInTrash(_ path: String) -> Bool {
        URL(fileURLWithPath: path).pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    static func sharedCopyReason(appName: String, otherCopyPaths: [String]) -> String? {
        otherCopyPaths.first.map { "Another copy of \(appName) at \($0) still uses this" }
    }

    /// Leftovers for `app`, matched on bundle-ID dot boundaries. Files a more specific bundle ID in
    /// `otherBundleIDs` also claims are dropped, everything is report-only while another copy
    /// (from `otherCopyPaths` or LaunchServices) exists, and symlinks are never offered.
    public func findLeftovers(
        for app: InstalledApp,
        otherBundleIDs: Set<String> = [],
        otherCopyPaths: [String] = []
    ) -> [AppLeftover] {
        guard let bundleID = app.bundleID, ScanPolicy.isUsableLeftoverBundleID(bundleID) else { return [] }
        let excluded = exclusions() ?? .empty
        let copies = mergedOtherCopies(of: app, inventoryCopies: otherCopyPaths)
        let shared = Self.sharedCopyReason(appName: app.name, otherCopyPaths: copies)
        let allowDerived = ScanPolicy.allowsDerivedLeftovers(bundleID: bundleID, appPath: app.path)
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
            if let leftover = makeLeftover(at: url, category: entry.category, excluded: excluded, reportOnly: shared) {
                leftovers.append(leftover)
            }
        }

        let prefs = library.appendingPathComponent("Preferences")
        leftovers += namedItems(in: prefs, app: bundleID, others: otherBundleIDs, allowDerived: allowDerived) { url, match in
            makeLeftover(at: url, category: .preferences, selected: match == .exact, excluded: excluded, reportOnly: shared)
        }
        // A user agent is booted out before trashing, but it can still belong to a helper the user keeps.
        let agents = library.appendingPathComponent("LaunchAgents")
        leftovers += namedItems(in: agents, app: bundleID, others: otherBundleIDs, allowDerived: allowDerived) { url, _ in
            makeLeftover(at: url, category: .launchAgents, selected: false, excluded: excluded, reportOnly: shared)
        }
        let systemFolders: [(String, AppLeftoverCategory)] = [("LaunchAgents", .launchAgents), ("LaunchDaemons", .launchDaemons)]
        for (folder, category) in systemFolders {
            let directory = systemLibrary.appendingPathComponent(folder)
            leftovers += namedItems(in: directory, app: bundleID, others: otherBundleIDs, allowDerived: allowDerived) { url, _ in
                makeLeftover(at: url, category: category, excluded: excluded, reportOnly: Self.systemLaunchItemReason)
            }
        }
        // Group containers match ID components anywhere in the name, so a generic ID would match too much.
        if allowDerived {
            leftovers += groupContainers(bundleID: bundleID, others: otherBundleIDs, excluded: excluded, shared: shared)
        }

        return leftovers.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    private func namedItems(
        in directory: URL,
        app bundleID: String,
        others: Set<String>,
        allowDerived: Bool,
        make: (URL, BundleIDNameMatch) -> AppLeftover?
    ) -> [AppLeftover] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted().compactMap { name in
            let match = ScanPolicy.bundleIDNameMatch(name, bundleID: bundleID)
            guard match == .exact || (allowDerived && match == .derived), name.lowercased().hasSuffix(".plist"),
                  !ScanPolicy.isLeftoverClaimedByOtherApp(name, bundleID: bundleID, otherBundleIDs: others, isGroupContainer: false)
            else { return nil }
            return make(directory.appendingPathComponent(name), match)
        }
    }

    private func groupContainers(bundleID: String, others: Set<String>, excluded: ExclusionList, shared: String?) -> [AppLeftover] {
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
                excluded: excluded,
                reportOnly: shared
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
    /// Every leftover is re-checked here and refused while another copy exists; a running or
    /// in-use app, unreadable exclusion list, missing open-file listing or unsaved undo record refuses
    /// the whole uninstall, and a leftover with anything open at or under it is skipped.
    public func uninstall(
        app: InstalledApp,
        leftovers: [AppLeftover],
        otherCopyPaths: [String] = []
    ) async throws -> AppUninstallResult {
        let (excluded, firstSnapshot) = try await preflight(app)
        // Looked up before the bundle moves, while LaunchServices still lists it as itself.
        let shared = Self.sharedCopyReason(
            appName: app.name,
            otherCopyPaths: mergedOtherCopies(of: app, inventoryCopies: otherCopyPaths)
        )
        var history = UninstallHistory(appName: app.name, store: transactionStore)
        do { try history.begin() } catch { throw AppUninstallError.undoRecordUnavailable }

        var items: [CleanupItem] = []
        do {
            items.append(try trash(path: app.path, size: app.sizeBytes, reason: "Uninstalled \(app.name)"))
        } catch {
            history.discard()
            // Leftovers stay while the app is still installed.
            let rest = leftovers.map { AppUninstallSkip(path: $0.path, reason: "The app itself could not be moved to Trash") }
            return AppUninstallResult(
                trashed: [],
                skipped: rest,
                failed: [AppUninstallSkip(path: app.path, reason: error.localizedDescription)],
                transactionID: nil,
                undoSaveError: nil
            )
        }
        history.record(items)

        let screened = await screen(leftovers, excluded: excluded, shared: shared)
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
                history.record(items)
            } catch {
                failed.append(AppUninstallSkip(path: leftover.path, reason: error.localizedDescription))
            }
        }

        return AppUninstallResult(
            trashed: items.map(\.originalPath),
            skipped: skipped,
            failed: failed,
            transactionID: history.id,
            undoSaveError: history.saveError
        )
    }

    /// Checks that refuse the whole uninstall before anything moves.
    private func preflight(_ app: InstalledApp) async throws -> (ExclusionList, OpenFileSnapshot) {
        if let bundleID = app.bundleID?.lowercased(),
           runningApps.runningApps().contains(where: { $0.bundleIdentifier.lowercased() == bundleID }) {
            throw AppUninstallError.appRunning(app.name)
        }
        guard let excluded = exclusions() else { throw AppUninstallError.exclusionsUnreadable }
        guard !excluded.blocksRemoval(of: app.path) else { throw AppUninstallError.appExcluded(app.name) }
        // Taken before anything moves: without it an open database would be trashed under its writer.
        guard let snapshot = await openFiles.snapshot() else { throw AppUninstallError.openFileCheckUnavailable }
        // Helpers and CLI tools inside the bundle run under other bundle IDs, or none.
        if let holder = snapshot.holder(atOrUnder: app.path) {
            throw AppUninstallError.appInUse(app: app.name, holder: holder)
        }
        return (excluded, snapshot)
    }

    /// Splits `leftovers` into those still eligible and those refused, booting out user launch agents on the way.
    private func screen(
        _ leftovers: [AppLeftover],
        excluded: ExclusionList,
        shared: String?
    ) async -> (pending: [AppLeftover], skipped: [AppUninstallSkip], stoppedAgent: Bool) {
        var pending: [AppLeftover] = []
        var skipped: [AppUninstallSkip] = []
        var stoppedAgent = false
        for leftover in leftovers {
            if let reason = leftover.reportOnlyReason ?? shared ?? refusal(for: leftover, excluded: excluded) {
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
}

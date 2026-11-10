import Foundation
import PareCore

/// What owner resolution needs beyond the findings.
struct OwnerInputs: Sendable {
    let homeDirectory: URL
    let installedApps: InstalledAppIndex
    let registeredRoots: [URL]
    let probe: any ProjectMarkerProbing

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedApps: InstalledAppIndex = .empty,
        registeredRoots: [URL] = [],
        probe: any ProjectMarkerProbing = FileSystemMarkerProbe()
    ) {
        self.homeDirectory = homeDirectory
        self.installedApps = installedApps
        self.registeredRoots = registeredRoots
        self.probe = probe
    }
}

/// Owner-derived scan output: the relabeled aggregate, sections, clean-list rows, donut feed and owner cache.
struct OwnerResults: Sendable {
    let aggregate: FolderAggregate
    let sections: [OwnerSection]
    /// Empty when owners are off; the legacy category list is shown instead.
    let cleanRows: [CleanRow]
    let ownerByFolderPath: [String: FolderOwner]
    let toolRollups: [ToolRollup]
}

/// Replays owners resolved at scan finish, so an exclusion never resolves again.
struct CachedOwnerResolver: OwnerResolving {
    let owners: [String: FolderOwner]

    func owner(forFolderPath path: String) -> FolderOwner { owners[path] ?? .other }
}

extension ScanDashboardViewModel {
    /// Finalize waits this long for the installed-app index, then resolves without it.
    nonisolated static let installedAppsWaitSeconds = 2.0
    nonisolated static let installedAppsLoadBudget: TimeInterval = 20

    // MARK: - Pipeline (off the main actor)

    /// Starts reading installed apps; call alongside the rules so finalize rarely waits.
    nonisolated static func startInstalledAppsLoad() -> TimeBoxedValue<InstalledAppIndex> {
        let box = TimeBoxedValue<InstalledAppIndex>()
        let budget = installedAppsLoadBudget
        Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let roots = ["/Applications", "/System/Applications", home + "/Applications"].map(URL.init(fileURLWithPath:))
            let index = InstalledAppIndex.load(
                roots: roots, locator: LaunchServicesAppCopyLocator(), deadline: Date().addingTimeInterval(budget),
                isCancelled: { box.isCancelled }
            )
            box.fulfill(index)
        }
        return box
    }

    /// Nil when the owner view is off; installed apps fall back to `.empty` after the wait.
    nonisolated static func gatherOwnerInputs(_ installedApps: TimeBoxedValue<InstalledAppIndex>?) async -> OwnerInputs? {
        guard let installedApps else { return nil }
        let roots = await ProjectRootGathering.registeredRoots()
        let index = await installedApps.value(waitingAtMost: installedAppsWaitSeconds) ?? .empty
        return OwnerInputs(installedApps: index, registeredRoots: roots)
    }

    nonisolated static func ownerResolver(for aggregate: FolderAggregate, inputs: OwnerInputs) -> OwnerResolver {
        let projects = ProjectIndex.build(
            folderPaths: aggregate.recordsByFolderId.values.map(\.folderPath),
            registeredRoots: inputs.registeredRoots,
            homeDirectory: inputs.homeDirectory,
            probe: inputs.probe
        )
        return OwnerResolver(homeDirectory: inputs.homeDirectory, installedApps: inputs.installedApps, projects: projects)
    }

    /// A nil resolver keeps legacy labels and the per-finding donut.
    nonisolated static func ownerResults(
        aggregate: FolderAggregate,
        findings: [ScanFinding],
        resolver: (any OwnerResolving)?
    ) -> OwnerResults {
        guard let resolver else {
            return OwnerResults(
                aggregate: aggregate, sections: [], cleanRows: [], ownerByFolderPath: [:],
                toolRollups: FolderRollup.makeToolRollups(from: findings)
            )
        }
        let (sections, byId) = OwnerGrouping.build(aggregate: aggregate, resolver: resolver)
        var byPath: [String: FolderOwner] = [:]
        for (id, owner) in byId {
            if let record = aggregate.recordsByFolderId[id] { byPath[record.folderPath] = owner }
        }
        let sizeOnly = CleanListing.sizeOnlyRecords(from: findings)
        var rowOwners = byId
        for record in sizeOnly {
            let owner = byPath[record.folderPath] ?? resolver.owner(forFolderPath: record.folderPath)
            byPath[record.folderPath] = owner
            rowOwners[record.id] = owner
        }
        let records = aggregate.recordsByFolderId.values.filter { byId[$0.id] != nil } + sizeOnly
        return OwnerResults(
            aggregate: FolderRollup.relabelingTools(aggregate, ownerByFolderId: byId),
            sections: sections,
            cleanRows: CleanListing.rows(records: records, owners: rowOwners),
            ownerByFolderPath: byPath,
            toolRollups: FolderRollup.makeToolRollups(owners: byId, records: aggregate.recordsByFolderId)
        )
    }

    /// App bundle paths for the app owners among `rows`; lookups go through the index's bounded fallback.
    nonisolated static func appIconPaths(for rows: [CleanRow], index: InstalledAppIndex) -> [String: String] {
        var paths: [String: String] = [:]
        var seen: Set<String> = []
        for row in rows where row.owner.kind == .app && seen.insert(row.owner.key).inserted {
            if let url = index.appURL(for: row.owner) { paths[row.owner.key] = url.path }
        }
        return paths
    }

    // MARK: - Browser state

    var isOwnerViewEnabled: Bool { SmartScanFeatures.ownerView }

    /// Reads the safe rows only, so a hand-ticked review row never flips the group checkbox.
    func ownerGroupSelectionState(_ group: OwnerGroup) -> CategorySelectState {
        selection.selectionState(of: group.safeFolderIds)
    }

    /// Activity line for a project owner; nil until project activity is known.
    func projectActivityText(for owner: FolderOwner) -> String? {
        owner.projectRoot.flatMap { projectActivity[$0] }?.text(now: Date())
    }
}

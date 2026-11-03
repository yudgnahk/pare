import Foundation

/// Old app versions kept side by side (e.g. `releases/0.9.0-…`, `0.10.0-…`, `0.10.1-…`): offered for review,
/// keeping the newest two and any version a running process executes from. No process snapshot, no findings.
public struct VersionSiblingsRule: ScanRule {
    public let id = "version-siblings"
    public let title = "Old App Versions"
    public let reason = "Older version kept beside newer ones"
    public let category: ScanCategory = .applications
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.8

    /// Levels below each root whose children are inspected.
    static let maxDepth = 5
    /// Shared cap on listed directory entries so large dot-directories cannot slow the scan.
    static let entryBudget = 50_000
    /// Wider directories (session stores, message logs) only have their versioned names checked, never descended into.
    static let fanOutLimit = 256
    /// Parent names too generic to identify the app; the grandparent names it instead.
    static let genericParentNames: Set<String> = ["releases", "versions", "version", "builds", "bin", "app", "packages"]

    private let runningExecutables: any RunningExecutablesProviding

    public init(runningExecutables: any RunningExecutablesProviding = PsRunningExecutablesProvider()) {
        self.runningExecutables = runningExecutables
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        var budget = Self.entryBudget
        var groups: [[(url: URL, name: VersionedName)]] = []
        for root in Self.roots(home: environment.homeDirectory) where budget > 0 && !Task.isCancelled {
            collectGroups(in: root, depth: 0, budget: &budget, groups: &groups)
        }
        guard !groups.isEmpty else { return [] }
        // Fail closed: without knowing what runs, no version is offered.
        guard let executables = await runningExecutables.runningExecutablePaths() else { return [] }
        return groups.flatMap { findings(for: $0, executables: executables, sizeIndex: environment.sizeIndex) }
    }

    // MARK: - Private

    /// Each `~/.<dir>` and each `~/Library/Application Support/<app>`, minus excluded trees.
    static func roots(home: URL) -> [URL] {
        let appSupport = home.appending(path: "Library/Application Support")
        let dotDirectories = directories(in: home).filter { $0.lastPathComponent.hasPrefix(".") }
        return (dotDirectories + directories(in: appSupport))
            .filter { !ScanPolicy.isUnderVersionSiblingExcludedTree($0) }
    }

    private static func directories(in parent: URL) -> [URL] {
        DirectoryListing.contents(of: parent).map { realDirectories($0.entries, of: $0) } ?? []
    }

    /// Real directories only: `d_type` rules out files and symlinks, so only directories pay the package lookup.
    private static func realDirectories(_ entries: [DirectoryListing.Entry], of listing: DirectoryListing.Listing) -> [URL] {
        // Drains the bridged URL objects per listing instead of holding them for the whole walk.
        autoreleasepool {
            entries.filter { $0.kind == .directory }
                .map(listing.url(of:))
                .filter { entry in
                    guard let values = try? entry.resourceValues(forKeys: [.isPackageKey]) else { return false }
                    return values.isPackage != true
                }
                .sorted { $0.path < $1.path }
        }
    }

    private func collectGroups(
        in directory: URL,
        depth: Int,
        budget: inout Int,
        groups: inout [[(url: URL, name: VersionedName)]]
    ) {
        guard depth <= Self.maxDepth, budget > 0, !Task.isCancelled else { return }
        guard let listing = DirectoryListing.contents(of: directory) else { return }
        let isWide = listing.entries.count > Self.fanOutLimit
        // A wide directory only has its versioned names checked, so it costs one `readdir` and no per-entry lookup.
        let listed = Self.realDirectories(
            isWide ? listing.entries.filter { VersionedName($0.name) != nil } : listing.entries, of: listing
        )
        let children = listed.filter { !ScanPolicy.isUnderVersionSiblingExcludedTree($0) }
        budget -= children.count
        var versioned: [String: [(url: URL, name: VersionedName)]] = [:]
        for child in children {
            if let name = VersionedName(child.lastPathComponent) {
                versioned[name.groupKey, default: []].append((child, name))
            }
        }
        let found = versioned.values.filter { $0.count >= ScanPolicy.versionSiblingMinimumGroupSize }
        groups += found
        guard !isWide else { return }
        let members = Set(found.flatMap { $0.map(\.url.path) })
        for child in children where !members.contains(child.path) {
            collectGroups(in: child, depth: depth + 1, budget: &budget, groups: &groups)
        }
    }

    private func findings(
        for group: [(url: URL, name: VersionedName)],
        executables: [String],
        sizeIndex: DirectorySizeIndex
    ) -> [ScanFinding] {
        let newestFirst = group.sorted { $1.name.version < $0.name.version }
        let kept = Array(newestFirst.prefix(ScanPolicy.versionSiblingKeepCount))
        guard kept.count == ScanPolicy.versionSiblingKeepCount,
              !ScanPolicy.isPinnedVersionSiblingGroup(group.map(\.url)) else { return [] }
        let label = Self.displayVersion(for: group)
        let appName = Self.appName(for: group[0].url)
        return newestFirst.dropFirst(kept.count).compactMap { (candidate: (url: URL, name: VersionedName)) -> ScanFinding? in
            guard !ScanPolicy.isExecutedFrom(candidate.url, runningExecutables: executables),
                  !ScanPolicy.containsSensitiveDataMarker(candidate.url) else { return nil }
            let size = sizeIndex.directorySize(url: candidate.url)
            guard size > 0 else { return nil }
            return ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: "Older \(appName) version \(label(candidate.name)); newest \(label(kept[0].name)) "
                    + "and \(label(kept[1].name)) are kept",
                path: candidate.url.path,
                sizeBytes: size,
                lastUsed: try? candidate.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                confidence: confidence
            )
        }
    }

    /// Drops a prerelease every member shares (e.g. a platform tag like `aarch64`), so `0.9.0-aarch64` reads `0.9.0`.
    private static func displayVersion(for group: [(url: URL, name: VersionedName)]) -> (VersionedName) -> String {
        let shared = Set(group.map(\.name.version.prerelease)).count == 1 && !group[0].name.version.prerelease.isEmpty
        return { name in
            shared ? "\(name.version.major).\(name.version.minor).\(name.version.patch)" : name.token
        }
    }

    private static func appName(for member: URL) -> String {
        let parent = member.deletingLastPathComponent()
        let name = parent.lastPathComponent
        return genericParentNames.contains(name.lowercased()) ? parent.deletingLastPathComponent().lastPathComponent : name
    }
}

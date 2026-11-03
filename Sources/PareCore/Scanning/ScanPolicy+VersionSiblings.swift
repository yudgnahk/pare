import Foundation

// MARK: - Version siblings (old app versions kept side by side)

/// Why a version sibling stays at cleanup time.
public enum VersionSiblingRefusal: Sendable, Equatable {
    /// Not a version sibling Pare offers at all; reported as a plain policy refusal.
    case outsidePolicy
    case processListUnavailable
    case fewerNewerVersions
    case pinnedByAlias
    case runningFrom

    public var reason: String {
        switch self {
        case .outsidePolicy: return "not an old version Pare offers"
        case .processListUnavailable: return "running programs could not be listed"
        case .fewerNewerVersions: return "fewer than \(ScanPolicy.versionSiblingKeepCount) newer versions"
        case .pinnedByAlias: return "an alias pins this version group"
        case .runningFrom: return "a running program uses this version"
        }
    }
}

extension ScanPolicy {

    /// Fewer side-by-side versions than this is normal (current + one rollback).
    public static let versionSiblingMinimumGroupSize = 3
    /// Newest versions always kept: the live one and one previous for rollback.
    public static let versionSiblingKeepCount = 2

    public static func isUnderVersionSiblingExcludedTree(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { versionSiblingExcludedDirectoryNames.contains($0.lowercased()) }
    }

    /// Sibling directories (including `url`) whose names differ from `url`'s only in the semver token.
    static func versionSiblings(of url: URL) -> [(url: URL, name: VersionedName)] {
        guard let own = VersionedName(url.lastPathComponent) else { return [] }
        let parent = url.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        return entries.compactMap { (entry: URL) -> (url: URL, name: VersionedName)? in
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let name = VersionedName(entry.lastPathComponent), name.groupKey == own.groupKey else { return nil }
            return (entry, name)
        }
    }

    /// True when `url` is one of at least `versionSiblingMinimumGroupSize` version siblings outside excluded trees.
    public static func isVersionSiblingMember(_ url: URL) -> Bool {
        guard VersionedName(url.lastPathComponent) != nil, !isUnderVersionSiblingExcludedTree(url) else { return false }
        return versionSiblings(of: url).count >= versionSiblingMinimumGroupSize
    }

    /// A versioned folder in a version-sibling location whose group fell below the minimum (e.g. an older
    /// sibling went earlier in the same batch), so it can no longer have two newer versions.
    public static func isShrunkVersionSiblingGroup(_ url: URL) -> Bool {
        guard VersionedName(url.lastPathComponent) != nil, !isUnderVersionSiblingExcludedTree(url),
              isVersionSiblingLocation(url) else { return false }
        let siblings = versionSiblings(of: url)
        // The listing names the parent's other folders too; a folder that is gone must stay "not found".
        guard siblings.contains(where: { $0.url.lastPathComponent == url.lastPathComponent }) else { return false }
        return siblings.count < versionSiblingMinimumGroupSize
    }

    /// Cleanup-time gate: still at least two newer siblings, no alias pins the group, and no running process
    /// executes from it. Fail-closed: no process snapshot means not reclaimable.
    public static func isReclaimableVersionSibling(
        _ url: URL,
        runningExecutables: [String]?,
        customRoots: [URL] = GoCacheLocations.shared.resolvedRoots
    ) -> Bool {
        versionSiblingRefusal(url, runningExecutables: runningExecutables, customRoots: customRoots) == nil
    }

    /// Why `url` must stay at cleanup time, or nil when `isReclaimableVersionSibling` would pass it.
    public static func versionSiblingRefusal(
        _ url: URL,
        runningExecutables: [String]?,
        customRoots: [URL] = GoCacheLocations.shared.resolvedRoots
    ) -> VersionSiblingRefusal? {
        guard isVersionSiblingLocation(url), isVersionSiblingMember(url),
              !isNeverCleanPath(url, customRoots: customRoots),
              !containsSensitiveDataMarker(url), !isSearchIndexSensitivePath(url),
              let own = VersionedName(url.lastPathComponent) else { return .outsidePolicy }
        guard let runningExecutables else { return .processListUnavailable }
        let siblings = versionSiblings(of: url)
        guard siblings.filter({ own.version < $0.name.version }).count >= versionSiblingKeepCount else {
            return .fewerNewerVersions
        }
        guard !isPinnedVersionSiblingGroup(siblings.map(\.url)) else { return .pinnedByAlias }
        guard !isExecutedFrom(url, runningExecutables: runningExecutables) else { return .runningFrom }
        return nil
    }

    /// Inside the rule's own roots and nowhere protected: a dot directory directly in a home folder (one
    /// holding `Library`) or `Library/Application Support/<app>/`. Never Documents, Desktop, Downloads,
    /// containers or iCloud Drive, whatever the finding's category.
    public static func isVersionSiblingLocation(_ url: URL) -> Bool {
        let lower = url.path.lowercased()
        if protectedPathMarkers.contains(where: { $0 != "/library/application support/" && lower.contains($0) }) {
            return false
        }
        let parents = Array(url.standardizedFileURL.pathComponents.dropLast())
        if parents.contains("Mobile Documents") { return false }
        if let index = parents.indices.dropFirst().first(where: { parents[$0] == "Application Support" && parents[$0 - 1] == "Library" }) {
            return index + 1 < parents.count
        }
        return parents.indices.contains { index in
            let name = parents[index]
            guard index > 0, name.hasPrefix("."), name != ".", name != ".." else { return false }
            return FileManager.default.fileExists(atPath: NSString.path(withComponents: Array(parents[..<index])) + "/Library")
        }
    }

    /// True when a running executable lives at or under `directory`, compared in canonical, case-folded spelling
    /// with symlinks resolved on both sides (fnm runs node through a `fnm_multishells/…` link).
    public static func isExecutedFrom(_ directory: URL, runningExecutables: [String]) -> Bool {
        let bases = Set([directory, directory.resolvingSymlinksInPath()].map { canonicalPathURL($0).path.lowercased() })
        return runningExecutables.contains { path in
            let url = URL(fileURLWithPath: path)
            return [url, url.resolvingSymlinksInPath()].contains { candidate in
                let executable = canonicalPathURL(candidate).path.lowercased()
                return bases.contains { executable == $0 || executable.hasPrefix($0 + "/") }
            }
        }
    }
}

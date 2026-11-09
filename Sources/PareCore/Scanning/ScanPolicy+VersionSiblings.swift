import Foundation

// MARK: - Version siblings (old app versions kept side by side)

/// Why a version sibling stays at cleanup time.
public enum VersionSiblingRefusal: Sendable, Equatable {
    /// Not a version sibling Pare offers at all; reported as a plain policy refusal.
    case outsidePolicy
    /// No program inside, or it holds user data (saves, profiles, databases).
    case notAnAppInstall
    case processListUnavailable
    case fewerNewerVersions
    case pinnedByAlias
    case runningFrom

    public var reason: String {
        switch self {
        case .outsidePolicy: return "not an old version Pare offers"
        case .notAnAppInstall: return "not an app install"
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

    /// Cleanup-time gate: an app install, still at least two newer siblings, no alias pins the group, and no running process
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
        guard isVersionInstall(url) else { return .notAnAppInstall }
        guard let runningExecutables else { return .processListUnavailable }
        let siblings = versionSiblings(of: url)
        // Only real installs count as newer: an empty newer folder must not leave the sole working version offered.
        let newerInstalls = siblings.filter { own.version < $0.name.version && isVersionInstall($0.url) }
        guard newerInstalls.count >= versionSiblingKeepCount else {
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

// MARK: - Install evidence

extension ScanPolicy {

    /// Folder names that mark user data (game worlds, launcher instances, profiles), never an install.
    public static let versionSiblingUserDataNames: Set<String> = [
        "saves", "worlds", "world", "instances", "profiles", "documents", "userdata", "savegames", "backups", "projects",
    ]
    public static let versionSiblingUserDataExtensions: Set<String> = ["db", "sqlite", "sqlite3"]
    /// Levels below a version folder inspected for programs and user data.
    static let versionInstallEvidenceDepth = 2
    /// Entries inspected per version folder; a larger tree is not judged and stays.
    static let versionInstallEvidenceEntryBudget = 5_000
    /// Executable files whose header is read per version folder.
    static let versionInstallExecutableProbeLimit = 64
    private static let machOExecuteFileType: UInt32 = 2 // MH_EXECUTE

    /// True when `url` holds an app's own program (a Mach-O executable or `.app` within two levels) and no sign of user
    /// data in or above it. Only contents count: `docs/releases/<version>` has the same parent name as a real install.
    public static func isVersionInstall(_ url: URL) -> Bool {
        let parents = url.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard !parents.contains(where: { versionSiblingUserDataNames.contains($0.lowercased()) }),
              !isInsideProject(url), let contents = versionInstallContents(url), !contents.holdsUserData else { return false }
        return contents.hasProgram
    }

    private struct VersionInstallContents {
        var hasProgram = false
        var holdsUserData = false
        var probesLeft = ScanPolicy.versionInstallExecutableProbeLimit
    }

    /// Breadth-first, symlinks never followed; nil when the entry budget runs out before the walk ends.
    private static func versionInstallContents(_ root: URL) -> VersionInstallContents? {
        var contents = VersionInstallContents()
        var budget = versionInstallEvidenceEntryBudget
        var level = [root]
        for _ in 0..<versionInstallEvidenceDepth where !level.isEmpty {
            var next: [URL] = []
            for directory in level {
                // An unreadable folder may hold user data, so it fails closed.
                guard let listing = DirectoryListing.contents(of: directory) else {
                    contents.holdsUserData = true
                    continue
                }
                budget -= listing.entries.count
                guard budget >= 0 else { return nil }
                next += listing.entries.compactMap { inspect($0, in: listing, contents: &contents) }
            }
            level = next
        }
        return contents
    }

    /// Records what `entry` shows about its version folder; returns it when it is a directory to descend into.
    private static func inspect(
        _ entry: DirectoryListing.Entry,
        in listing: DirectoryListing.Listing,
        contents: inout VersionInstallContents
    ) -> URL? {
        let lower = entry.name.lowercased()
        let ext = (lower as NSString).pathExtension
        switch entry.kind {
        case .directory:
            if versionSiblingUserDataNames.contains(lower) { contents.holdsUserData = true }
            guard ext != "app" else {
                if isRealAppBundle(listing.url(of: entry)) { contents.hasProgram = true }
                return nil
            }
            return listing.url(of: entry)
        case .regularFile:
            if versionSiblingUserDataExtensions.contains(ext) { contents.holdsUserData = true }
            let path = listing.url(of: entry).path
            guard !contents.hasProgram, contents.probesLeft > 0, access(path, X_OK) == 0 else { return nil }
            contents.probesLeft -= 1
            contents.hasProgram = isMachOExecutable(atPath: path)
            return nil
        case .symbolicLink, .other:
            return nil
        }
    }

    /// A bundle counts only with a regular executable file in `Contents/MacOS`; a bare `*.app` folder proves nothing.
    static func isRealAppBundle(_ url: URL) -> Bool {
        guard let listing = DirectoryListing.contents(of: url.appending(path: "Contents/MacOS")) else { return false }
        return listing.entries.contains { $0.kind == .regularFile && access(listing.url(of: $0).path, X_OK) == 0 }
    }

    /// True when `url` or an ancestor below its home folder (the one holding `Library`) has `.git` (file or
    /// directory) or another project marker, so a repo's built output is never taken for an install.
    static func isInsideProject(_ url: URL) -> Bool {
        var directory = url.standardizedFileURL
        while directory.path != "/" {
            let path = directory.path
            if directory != url.standardizedFileURL, FileManager.default.fileExists(atPath: path + "/Library") { return false }
            if projectRootMarkerFileNames.contains(where: { FileManager.default.fileExists(atPath: path + "/" + $0) }) {
                return true
            }
            directory = directory.deletingLastPathComponent()
        }
        return false
    }

    /// Reads the Mach-O header (the first slice of a universal binary) and checks for `MH_EXECUTE`.
    static func isMachOExecutable(atPath path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        func bytes(_ count: Int, at offset: UInt64) -> [UInt8]? {
            var buffer = [UInt8](repeating: 0, count: count)
            return pread(descriptor, &buffer, count, off_t(offset)) == count ? buffer : nil
        }
        guard let header = bytes(32, at: 0) ?? bytes(16, at: 0) else { return false }
        if let fileType = thinMachOFileType(header) { return fileType == machOExecuteFileType }
        let magic = bigEndianWord(header, 0)
        // Java class files share the fat magic; their "slice count" is a class-file version far above 20.
        guard magic == 0xCAFE_BABE || magic == 0xCAFE_BABF, header.count == 32,
              (1...20).contains(bigEndianWord(header, 4)) else { return false }
        let offset = magic == 0xCAFE_BABF
            ? UInt64(bigEndianWord(header, 16)) << 32 | UInt64(bigEndianWord(header, 20))
            : UInt64(bigEndianWord(header, 16))
        guard offset > 0, offset < UInt64(Int32.max), let slice = bytes(16, at: offset) else { return false }
        return thinMachOFileType(slice) == machOExecuteFileType
    }

    /// The `filetype` of a single-architecture Mach-O header, or nil for anything else.
    private static func thinMachOFileType(_ header: [UInt8]) -> UInt32? {
        switch bigEndianWord(header, 0) {
        case 0xCFFA_EDFE, 0xCEFA_EDFE: return bigEndianWord(header, 12).byteSwapped
        case 0xFEED_FACF, 0xFEED_FACE: return bigEndianWord(header, 12)
        default: return nil
        }
    }

    private static func bigEndianWord(_ data: [UInt8], _ offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }
}

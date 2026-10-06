import Foundation

// MARK: - Never-clean working sets

extension ScanPolicy {

    /// Lowercased path-component runs of tool-managed caches that must never reach the Trash,
    /// matched anywhere in a path so the check does not depend on the home directory.
    public static let neverCleanComponentSequences: [[String]] = [
        ["library", "caches", "go-build"],
        ["go", "pkg", "mod"],
    ]

    /// `Library/Caches` folders holding Google identity state; deleting them makes Google apps rewrite it at ~50 MB/s.
    public static let neverCleanUserCacheFolderNames: Set<String> = ["gippseudonymousid", "cctclearcutlogger"]

    /// Lowercased component runs of app user data (sessions, credentials, identity) next to reclaimable caches.
    public static let neverCleanUserDataComponentSequences: [[String]] = [
        [".local", "share", "opencode", "storage"],
        [".local", "share", "opencode", "auth.json"],
    ] + neverCleanUserCacheFolderNames.sorted().map { ["library", "caches", $0] }

    /// File-name prefixes protected directly inside a parent run, so SQLite `-wal`/`-shm` side files match too.
    public static let neverCleanUserDataFilePrefixes: [(parent: [String], prefix: String)] = [
        (parent: [".local", "share", "opencode"], prefix: "opencode.db"),
    ]

    /// True for Go's build and module caches (default spelling or a `go env` location) and for protected user data.
    public static func isNeverCleanPath(
        _ url: URL,
        customRoots: [URL] = GoCacheLocations.shared.resolvedRoots
    ) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let matchesDefault = neverCleanComponentSequences.contains { containsRun($0, in: components) }
        return matchesDefault
            || isProtectedUserDataPath(components: components)
            || customRoots.contains { isCanonicallyEqualToOrDescendant(candidate: url, root: $0) }
    }

    /// The non-Go subset of `isNeverCleanPath`: app user data or identity state, never a cache.
    public static func isProtectedUserDataPath(_ url: URL) -> Bool {
        isProtectedUserDataPath(components: url.standardizedFileURL.pathComponents.map { $0.lowercased() })
    }

    private static func isProtectedUserDataPath(components: [String]) -> Bool {
        neverCleanUserDataComponentSequences.contains { containsRun($0, in: components) }
            || neverCleanUserDataFilePrefixes.contains { entry in
                components.indices.contains { index in
                    index >= entry.parent.count
                        && components[index].hasPrefix(entry.prefix)
                        && components[(index - entry.parent.count)..<index].elementsEqual(entry.parent)
                }
            }
    }

    private static func containsRun(_ run: [String], in components: [String]) -> Bool {
        guard !run.isEmpty, components.count >= run.count else { return false }
        return (0...(components.count - run.count)).contains { start in
            components[start..<(start + run.count)].elementsEqual(run)
        }
    }
}

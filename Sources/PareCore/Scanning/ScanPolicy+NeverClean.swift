import Foundation

// MARK: - Never-clean working sets

extension ScanPolicy {

    /// Lowercased path-component runs of tool-managed caches that must never reach the Trash,
    /// matched anywhere in a path so the check does not depend on the home directory.
    public static let neverCleanComponentSequences: [[String]] = [
        ["library", "caches", "go-build"],
        ["go", "pkg", "mod"],
    ]

    /// True for Go's build and module caches at their default spelling or at a `go env` location.
    public static func isNeverCleanPath(
        _ url: URL,
        customRoots: [URL] = GoCacheLocations.shared.resolvedRoots
    ) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let matchesDefault = neverCleanComponentSequences.contains { containsRun($0, in: components) }
        return matchesDefault || customRoots.contains { isCanonicallyEqualToOrDescendant(candidate: url, root: $0) }
    }

    private static func containsRun(_ run: [String], in components: [String]) -> Bool {
        guard !run.isEmpty, components.count >= run.count else { return false }
        return (0...(components.count - run.count)).contains { start in
            components[start..<(start + run.count)].elementsEqual(run)
        }
    }
}

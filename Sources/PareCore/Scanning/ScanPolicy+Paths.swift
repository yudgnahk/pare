import Foundation
import Darwin

extension ScanPolicy {

    /// macOS roots that are symlinks into `/private`; Foundation reports both spellings.
    private static let privateAliasRoots = ["/tmp", "/var", "/etc"]

    /// Standardized path with `/tmp`, `/var` and `/etc` spelled under `/private`, purely lexically.
    public static func canonicalPathURL(_ url: URL) -> URL {
        let path = url.standardizedFileURL.path
        for alias in privateAliasRoots where path == alias || path.hasPrefix(alias + "/") {
            return URL(fileURLWithPath: "/private" + path)
        }
        return URL(fileURLWithPath: path)
    }

    /// `isEqualToOrDescendant` after `canonicalPathURL` on both sides, so `/var/…` matches `/private/var/…`.
    public static func isCanonicallyEqualToOrDescendant(
        candidate: URL,
        root: URL,
        caseSensitive: Bool = false
    ) -> Bool {
        isEqualToOrDescendant(
            candidate: canonicalPathURL(candidate),
            root: canonicalPathURL(root),
            caseSensitive: caseSensitive
        )
    }

    /// Whether the volume holding `path` (or its nearest existing ancestor) distinguishes name case.
    /// Unknown answers count as case-sensitive: stricter matching can only drop matches, never add them.
    public static func volumeSupportsCaseSensitiveNames(atPath path: String) -> Bool {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while true {
            if let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
               let caseSensitive = values.volumeSupportsCaseSensitiveNames {
                return caseSensitive
            }
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { return true }
            url = parent
        }
    }

    /// macOS-owned `/private` alias roots — exempt so every temp or `/var/folders` path is not blocked.
    private static let symlinkExemptSystemPaths: Set<String> = Set(["/private", "/private/tmp"] + privateAliasRoots)

    /// True when any component of `path` (after standardizing) is a symbolic link, ignoring the system aliases.
    public static func hasSymbolicLinkComponent(atPath path: String) -> Bool {
        var current = ""
        for component in URL(fileURLWithPath: path).standardizedFileURL.pathComponents {
            current = current.isEmpty
                ? component
                : URL(fileURLWithPath: current).appendingPathComponent(component).path
            if symlinkExemptSystemPaths.contains(current) { continue }
            if isSymbolicLink(atPath: current) { return true }
        }
        return false
    }

    private static func isSymbolicLink(atPath path: String) -> Bool {
        var metadata = stat()
        return lstat(path, &metadata) == 0 && (metadata.st_mode & S_IFMT) == S_IFLNK
    }
}

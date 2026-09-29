import Foundation

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
    public static func isCanonicallyEqualToOrDescendant(candidate: URL, root: URL) -> Bool {
        isEqualToOrDescendant(candidate: canonicalPathURL(candidate), root: canonicalPathURL(root))
    }
}

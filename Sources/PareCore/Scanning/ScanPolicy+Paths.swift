import Foundation
import Darwin

extension ScanPolicy {

    /// macOS roots that are symlinks into `/private`; Foundation reports both spellings.
    private static let privateAliasRoots = ["/tmp", "/var", "/etc"]

    /// Standardized path with `/tmp`, `/var` and `/etc` spelled under `/private`, purely lexically.
    /// Firmlinked `/System/Volumes/Data/<root>` spellings become `/<root>` unless `normalizingFirmlinks` is false
    /// (Disk Analyzer navigation keeps the physical spelling so breadcrumbs stay inside the browsed tree).
    public static func canonicalPathURL(_ url: URL, normalizingFirmlinks: Bool = true) -> URL {
        var path = url.standardizedFileURL.path
        if normalizingFirmlinks {
            path = firmlinkNormalizedPath(path)
        }
        for alias in privateAliasRoots where path == alias || path.hasPrefix(alias + "/") {
            return URL(fileURLWithPath: "/private" + path)
        }
        return URL(fileURLWithPath: path)
    }

    /// One lookup key for every spelling of a path: canonical (`/var` → `/private/var`) and lowercased.
    public static func canonicalPathKey(_ path: String) -> String {
        canonicalPathURL(URL(fileURLWithPath: path)).path.lowercased()
    }

    /// Mount point of the writable Data volume that firmlinks point into.
    public static let dataVolumeRoot = "/System/Volumes/Data"

    /// Used when `/usr/share/firmlinks` is unreadable; each maps `/System/Volumes/Data/<name>` to `/<name>`.
    static let fallbackFirmlinkRoots = [
        "Users", "Applications", "Library", "private", "usr/local", "opt", "cores", "Volumes",
        "AppleInternal", "pkg", "System/Library/Caches",
    ]

    /// (data-volume spelling, root spelling) pairs, longest first so nested firmlinks win.
    static let firmlinkPairs: [(data: String, root: String)] = firmlinkPairs(
        fromFile: (try? String(contentsOfFile: "/usr/share/firmlinks", encoding: .utf8)) ?? ""
    )

    /// Parses `/usr/share/firmlinks` lines (`/<root>\t<data-relative>`), falling back to the static list.
    static func firmlinkPairs(fromFile contents: String) -> [(data: String, root: String)] {
        let parsed: [(data: String, root: String)] = contents.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: true).map(String.init)
            guard fields.count == 2, fields[0].hasPrefix("/"), !fields[1].isEmpty, !fields[1].hasPrefix("/") else {
                return nil
            }
            return (data: dataVolumeRoot + "/" + fields[1], root: fields[0])
        }
        let pairs = parsed.isEmpty
            ? fallbackFirmlinkRoots.map { (data: dataVolumeRoot + "/" + $0, root: "/" + $0) }
            : parsed
        return pairs.sorted { $0.data.count > $1.data.count }
    }

    /// Rewrites a `/System/Volumes/Data/<firmlink>` prefix to `/<firmlink>` on whole components only.
    static func firmlinkNormalizedPath(_ path: String, pairs: [(data: String, root: String)] = firmlinkPairs) -> String {
        guard path.hasPrefix(dataVolumeRoot + "/") else { return path }
        for pair in pairs {
            if path == pair.data { return pair.root }
            if path.hasPrefix(pair.data + "/") { return pair.root + path.dropFirst(pair.data.count) }
        }
        return path
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

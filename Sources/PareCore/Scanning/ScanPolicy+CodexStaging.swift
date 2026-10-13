import Foundation

// MARK: - Codex marketplace staging leftovers

extension ScanPolicy {

    /// The only two folders whose direct children may be reclaimed, as path components below `~`.
    public static let codexStagingRootComponents: [[String]] = [
        [".codex", ".tmp", "bundled-marketplaces"],
        [".codex", ".tmp", "marketplaces", ".staging"],
    ]

    /// Staging entries Codex creates while installing or upgrading a marketplace.
    public static let codexStagingEntryPrefixes = ["openai-bundled.staging-", "marketplace-upgrade-", "marketplace-add-"]

    /// Codex's own rollback copies, never reclaimable even if one appears inside a staging root.
    static let codexStagingNeverPrefixes = ["marketplace-backup-"]

    /// A staging folder untouched this long was abandoned by an interrupted install or upgrade.
    public static let codexStagingMinAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    public static func isCodexStagingEntryName(_ name: String) -> Bool {
        !codexStagingNeverPrefixes.contains { name.hasPrefix($0) }
            && codexStagingEntryPrefixes.contains { name.hasPrefix($0) && name.count > $0.count }
    }

    /// A direct child of one of the two staging roots, matched by whole path components.
    public static func isCodexStagingEntryLocation(_ url: URL) -> Bool {
        codexStagingRoot(containing: url.standardizedFileURL.path).map {
            $0 == url.deletingLastPathComponent().standardizedFileURL.path
        } ?? false
    }

    /// The staging root path that `path` lies strictly inside, if any.
    public static func codexStagingRoot(containing path: String) -> String? {
        // Cheap pre-check: this runs for every finding during folder rollup.
        guard path.contains("/.codex/.tmp/") else { return nil }
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        for root in codexStagingRootComponents {
            guard components.count > root.count else { continue }
            for start in 0...(components.count - root.count - 1)
            where Array(components[start..<(start + root.count)]) == root {
                return NSString.path(withComponents: Array(components[...(start + root.count - 1)]))
            }
        }
        return nil
    }

    /// Scan- and cleanup-time gate (the caller also checks that Codex and ChatGPT are not running):
    /// a direct child of a staging root, a staging prefix and not a backup, a physical path, and
    /// last written more than `codexStagingMinAgeSeconds` ago.
    public static func isReclaimableCodexStagingEntry(_ url: URL, now: Date = Date()) -> Bool {
        guard isCodexStagingEntryName(url.lastPathComponent), isCodexStagingEntryLocation(url),
              !hasSymbolicLinkComponent(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey]),
              values.isSymbolicLink != true,
              let lastWrite = [values.contentModificationDate, values.creationDate].compactMap({ $0 }).max() else {
            return false
        }
        return now.timeIntervalSince(lastWrite) > codexStagingMinAgeSeconds
    }
}

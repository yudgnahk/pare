import Foundation

// MARK: - Path safety predicates (R1.7 split — data lives in +Markers)

extension ScanPolicy {

    public static func isSearchIndexSensitivePath(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return searchIndexSensitivePathMarkers.contains { path.contains($0) }
    }

    /// Large cleans cause heavy incremental Spotlight work (FSEvents), even without
    /// touching search-index caches. Thresholds for a user-facing heads-up.
    public static let largeCleanSpotlightWarningItemThreshold = 100
    public static let largeCleanSpotlightWarningBytesThreshold: Int64 = 1 * 1024 * 1024 * 1024 // 1 GB

    public static func shouldWarnAboutSpotlightIndexing(itemCount: Int, totalBytes: Int64) -> Bool {
        itemCount >= largeCleanSpotlightWarningItemThreshold
            || totalBytes >= largeCleanSpotlightWarningBytesThreshold
    }

    public static func isReconstructibleCachePath(_ url: URL) -> Bool {
        if isSearchIndexSensitivePath(url) { return false }
        let path = url.path.lowercased()
        return reconstructibleCachePathMarkers.contains { path.contains($0) }
    }

    /// True when the path contains a credential/user-data marker (bookmarks, history,
    /// login, session, cookies, keychain). Rules must use this — never a private,
    /// divergent copy of the marker list (R1.4).
    public static func containsSensitiveDataMarker(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return sensitiveDataMarkers.contains { path.contains($0) }
    }

    /// True when the path is JetBrains plugin/driver data requiring review.
    public static func isJetBrainsReviewRequiredPath(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return jetBrainsReviewRequiredMarkerPairs.contains {
            path.contains($0.ide) && path.contains($0.subtree)
        }
    }

    /// Returns `true` for installer files sitting inside `~/Downloads`, `~/Desktop`, or
    /// iCloud Drive (`~/Library/Mobile Documents/`). ZIP files are included so that
    /// installer ZIPs found by `InstallerFileRule` (which performs binary verification
    /// at scan time) can be cleaned by `CleanupEngine` after user confirmation.
    public static func isInstallerFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard installerExtensions.contains(ext) || ext == "zip" else { return false }
        let path = url.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
        return path.hasPrefix(home + "/downloads/")
            || path.hasPrefix(home + "/desktop/")
            || path.hasPrefix(home + "/library/mobile documents/")
    }

    /// `true` when the directory name is a dependency tree that must never be reclaimable.
    public static func isProjectDependencyDirectory(_ name: String) -> Bool {
        projectDependencyDirectoryNames.contains(name.lowercased())
    }

    /// Returns `true` when the URL's last path component is a known build-artifact directory name.
    /// NOTE: name-only match — for cleanup decisions use `isReclaimableProjectArtifact`,
    /// which additionally requires project-root evidence (fail-closed).
    public static func isProjectArtifact(_ url: URL) -> Bool {
        projectArtifactDirectoryNames.contains(url.lastPathComponent.lowercased())
    }

    /// Cleanup-time gate for project build artifacts. Fail-closed: a bare directory
    /// named `build`/`dist`/`target` anywhere on disk is NOT enough — the path must be
    /// under a registered project scan root, or an ancestor directory must contain a
    /// project marker (`.git`, `package.json`, `Cargo.toml`, …).
    /// The user's home directory itself is never accepted as project-root evidence
    /// (dotfile repos must not turn all of `~` into a cleanable project).
    public static func isReclaimableProjectArtifact(
        _ url: URL,
        registeredRootPaths: [String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        guard isProjectArtifact(url) else { return false }

        let path = url.path
        let underRegisteredRoot = registeredRootPaths.contains { root in
            guard !root.isEmpty else { return false }
            let normalized = root.hasSuffix("/") ? String(root.dropLast()) : root
            return path == normalized || path.hasPrefix(normalized + "/")
        }
        if underRegisteredRoot { return true }

        let homePath = homeDirectory.path
        var ancestor = url.deletingLastPathComponent()
        for _ in 0..<projectRootEvidenceMaxAncestors {
            let ancestorPath = ancestor.path
            if ancestorPath == "/" || ancestorPath.isEmpty || ancestorPath == homePath { break }
            for marker in projectRootMarkerFileNames where fileExists(ancestorPath + "/" + marker) {
                return true
            }
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestorPath { break }
            ancestor = parent
        }
        return false
    }

    public static func matchesPersonaPath(_ url: URL, allowedMarkers: [String]) -> Bool {
        // Parity with isLowImpactPath (R1.6): search-index stores must never pass
        // the persona gate either — deleting them forces a costly reindex.
        if isSearchIndexSensitivePath(url) { return false }

        let path = url.path.lowercased()

        let isProtected = protectedPathMarkers.contains { path.contains($0) }
        if isProtected {
            let allowsProtectedPath = personaProtectedPathOverrides.contains { path.contains($0) }
            guard allowsProtectedPath else {
                return false
            }
        }

        let containsSensitiveDataMarker = sensitiveDataMarkers.contains { path.contains($0) }
        guard !containsSensitiveDataMarker else {
            return false
        }

        let containsAppStateSensitiveMarker = appStateSensitiveMarkers.contains { path.hasSuffix($0) || path.contains($0) }
        guard !containsAppStateSensitiveMarker else {
            return false
        }

        return allowedMarkers.contains { path.contains($0) }
    }

    public static func isLowImpactPath(_ url: URL) -> Bool {
        // Spotlight / Help / media-analysis indexes are never "low impact" to delete.
        if isSearchIndexSensitivePath(url) { return false }

        let path = url.path.lowercased()

        let isProtected = protectedPathMarkers.contains { path.contains($0) }
        guard !isProtected else {
            return false
        }

        let containsSensitiveDataMarker = sensitiveDataMarkers.contains { path.contains($0) }
        guard !containsSensitiveDataMarker else {
            return false
        }

        let containsAppStateSensitiveMarker = appStateSensitiveMarkers.contains { path.hasSuffix($0) || path.contains($0) }
        guard !containsAppStateSensitiveMarker else {
            return false
        }

        return lowImpactMarkers.contains { path.contains($0) }
    }

    /// Returns `true` for apps inside /System/Applications — SIP-protected and cannot be removed.
    public static func isSystemApp(_ url: URL) -> Bool {
        url.path.hasPrefix("/System/")
    }

    /// Returns `true` for paths inside ~/Library/Group Containers.
    /// These are shared across app suites and must never be auto-selected for deletion.
    public static func isGroupContainer(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
        return url.path.lowercased().hasPrefix("\(home)/library/group containers/")
    }
}

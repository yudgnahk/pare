import Foundation

// MARK: - Age thresholds and gates (R1.7 split)

extension ScanPolicy {

    public static let defaultCacheMinAgeSeconds: TimeInterval = 3 * 24 * 60 * 60

    /// Pure reconstructible download/extract caches (npx, npm cacache, Go/Cargo
    /// module caches, AI tool package caches, Homebrew bottles). No age gate —
    /// they rebuild on demand (same policy as common Mac cleaners).
    public static let reconstructibleCacheMinAgeSeconds: TimeInterval = 0

    // MARK: Named per-rule age thresholds (R1.5)
    // Single source of truth — rules must reference these, never inline literals.

    /// Older sibling backup of a device that has a newer backup.
    public static let deviceBackupStaleAgeSeconds: TimeInterval = 30 * 24 * 60 * 60
    /// The ONLY backup of a device — flag much later (180 days).
    public static let deviceBackupSingleStaleAgeSeconds: TimeInterval = 180 * 24 * 60 * 60
    /// Orphaned LaunchAgent plists — don't flag recently installed agents.
    public static let launchAgentOrphanMinAgeSeconds: TimeInterval = 30 * 24 * 60 * 60
    /// Browser review-required data (Local Storage, service workers…).
    public static let browserReviewDataMinAgeSeconds: TimeInterval = 30 * 24 * 60 * 60
    /// Superseded JetBrains IDE version data.
    public static let jetBrainsStaleVersionMinAgeSeconds: TimeInterval = 90 * 24 * 60 * 60
    /// Installer files — give users time to install before flagging.
    public static let installerFileMinAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// Age gate for cleanup re-checks. Reconstructible package caches use a short
    /// floor; other categories keep their default.
    public static func minimumAgeSeconds(forCleanupPath url: URL, category: ScanCategory) -> TimeInterval? {
        let path = url.path.lowercased()
        if reconstructibleCachePathMarkers.contains(where: { $0 != "/library/caches/" && path.contains($0) }) {
            return reconstructibleCacheMinAgeSeconds
        }
        return defaultMinimumAgeSeconds(for: category)
    }

    /// `true` when the URL's last activity is at least `minimumAgeSeconds` ago.
    /// Prefers **mtime** (updates when the cache is used); falls back to creation date.
    /// Fail-closed: unreadable attributes or missing dates BLOCK cleanup (return `false`)
    /// — never assume a file is old enough when we cannot prove it.
    /// `now` is injectable so tests can shift the reference clock instead of
    /// back-dating real files.
    public static func passesUnusedAge(for url: URL, minimumAgeSeconds: TimeInterval, now: Date = Date()) -> Bool {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        guard let lastUsed = values.contentModificationDate ?? values.creationDate else { return false }
        return now.timeIntervalSince(lastUsed) >= minimumAgeSeconds
    }

    public static func defaultMinimumAgeSeconds(for category: ScanCategory) -> TimeInterval? {
        switch category {
        case .userCaches, .temporaryFiles, .browserCaches, .developerPackageCaches,
             .developerSimulatorCaches, .designerCaches, .videoBuilderCaches, .aiToolCaches:
            return defaultCacheMinAgeSeconds  // 3 days
        case .logsAndCrashReports:
            return 24 * 60 * 60  // 1 day
        case .installerFiles:
            return installerFileMinAgeSeconds
        case .developerBuildArtifacts, .applications:
            return nil
        case .projectArtifacts:
            return 7 * 24 * 60 * 60  // 7 days — avoid flagging freshly created build dirs
        case .deviceBackups:
            return deviceBackupStaleAgeSeconds
        case .productivityCaches:
            return defaultCacheMinAgeSeconds  // 3 days
        case .launchAgents:
            return launchAgentOrphanMinAgeSeconds
        }
    }

    /// The effective reference date for age comparisons.
    /// For files: the modification date.
    /// For directories: the OLDER of creation date and modification date.
    /// Using the oldest date is intentional — it handles two opposing edge cases:
    ///   • App migration resets mtime to today on an old directory → creation date is older → use it.
    ///   • Backup/Migration Assistant resets birthtime to restore date → mtime from before restore is older → use it.
    /// Tests can back-date mtime via setAttributes; creation date defaults to "now" and is thus newer,
    /// so the min() still defers to the backdated mtime — which is what the test intends.
    public static func effectiveAgeDate(from values: URLResourceValues) -> Date? {
        guard values.isDirectory == true else { return values.contentModificationDate }
        let candidates = [values.creationDate, values.contentModificationDate].compactMap { $0 }
        return candidates.min()
    }

    /// Age reference for project artifacts. Hidden caches with a sibling manifest use the newest of their own
    /// date and their direct children's mtimes, because builds rewrite files inside (e.g. `.build/build.db`).
    /// Nil when that listing or any child date is unreadable, so age gates fail closed.
    public static func projectArtifactAgeDate(for url: URL, values: URLResourceValues) -> Date? {
        guard let own = effectiveAgeDate(from: values) else { return nil }
        guard projectArtifactRequiredSiblingMarkers[url.lastPathComponent.lowercased()] != nil else { return own }
        let key: URLResourceKey = .contentModificationDateKey
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [key]
        ) else { return nil }
        var newest = own
        for child in children {
            guard let date = try? child.resourceValues(forKeys: [key]).contentModificationDate else { return nil }
            newest = max(newest, date)
        }
        return newest
    }

    /// Fail-closed: when an age gate applies (`minimumAgeSeconds != nil`) and no date is
    /// available, the check FAILS — an unknowable age must never satisfy an age gate.
    /// `now` is injectable so tests can shift the reference clock instead of
    /// back-dating real files.
    public static func passesMinimumAge(for resourceValues: URLResourceValues, minimumAgeSeconds: TimeInterval?, now: Date = Date()) -> Bool {
        guard let minimumAgeSeconds else { return true }
        guard let date = effectiveAgeDate(from: resourceValues) else { return false }
        return now.timeIntervalSince(date) >= minimumAgeSeconds
    }
}

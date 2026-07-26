import Foundation

// MARK: - CleanupError

public enum CleanupError: Error, LocalizedError, Sendable {
    /// The file path failed the safety guardrail check.
    case unsafePath(String)
    /// The file is younger than the minimum-age threshold.
    case tooNew(String)
    /// The file is an ADVANCED-risk finding and must not be deleted directly.
    case advancedRiskBlocked(String)
    /// Docker VM disk / volume data — never delete as a filesystem path.
    case dockerNeverDelete(String)
    /// The file does not exist on disk when cleanup is attempted.
    case fileNotFound(String)
    /// The Trash move failed with an underlying system error.
    case trashFailed(String, Error)
    /// Undo failed because the Trash item no longer exists.
    case restoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "Unsafe path blocked: \(path)"
        case .tooNew(let path):
            return "File is too new to clean: \(path)"
        case .advancedRiskBlocked(let path):
            return "ADVANCED-risk file blocked from direct deletion: \(path). Use the app's native cleanup flow instead."
        case .dockerNeverDelete(let path):
            return "Docker VM disk/volume data blocked: \(path). Use docker system prune (never --volumes)."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .trashFailed(let path, let error):
            return "Failed to move to Trash: \(path) — \(error.localizedDescription)"
        case .restoreFailed(let path):
            return "Cannot restore — Trash item no longer exists: \(path)"
        }
    }
}

// MARK: - CleanupResult

/// Summary of a completed cleanup run.
public struct CleanupResult: Sendable {
    /// Successfully moved items (or dry-run candidates).
    public let succeeded: [CleanupItem]
    /// Items that were skipped because of a safety check failure, paired with the reason.
    public let skipped: [(path: String, reason: String)]
    /// The persisted transaction record (nil for dry-run that explicitly opts out of persistence).
    public let transaction: CleanupTransaction?

    public var totalBytesFreed: Int64 {
        succeeded.reduce(0) { $0 + $1.sizeBytes }
    }
}

// MARK: - CleanupEngine

/// Moves selected `ScanFinding` items to the Trash, records a `CleanupTransaction`,
/// and supports dry-run mode and undo/restore.
///
/// Safety rules applied to every finding before deletion:
/// 1. Docker VM disk paths (`Docker.raw` / `…/data/vms/…`) are always blocked — never Trash them;
///    they hold images, containers, **and volumes**. Reclaim only via Docker CLI without `--volumes`.
/// 2. `ADVANCED`-risk findings are always blocked — they require app-native prune flows.
/// 3. The path must pass `ScanPolicy.isLowImpactPath` OR persona markers —
///    whichever gate the matching rule used originally.  We re-verify here as a belt-and-suspenders check.
/// 4. The file must exist on disk.
/// 5. The minimum age threshold from `ScanPolicy.defaultMinimumAgeSeconds` must still be satisfied.
public actor CleanupEngine {
    private let store: CleanupTransactionStore
    /// Supplies the registered project scan roots (Spotlight-discovered + manual) used by
    /// the fail-closed project-artifact re-verification gate. Injectable for tests.
    private let projectRootsProvider: @Sendable () async -> [String]

    public init(
        store: CleanupTransactionStore = .shared,
        projectRootsProvider: (@Sendable () async -> [String])? = nil
    ) {
        self.store = store
        self.projectRootsProvider = projectRootsProvider ?? {
            let discovered = await ProjectRootDiscovery.shared.confirmedRoots().map(\.path)
            return discovered + ProjectScanPathStore.shared.paths
        }
    }

    // MARK: - Quick Clean (safe-risk only)

    /// Moves all `.safe`-risk findings to Trash. Skips `.review` and `.advanced` findings.
    /// Returns a `CleanupResult` and persists a `CleanupTransaction`.
    public func quickClean(
        findings: [ScanFinding],
        profileName: String,
        dryRun: Bool = false
    ) async throws -> CleanupResult {
        let safeFindings = findings.filter { $0.riskLevel == .safe }
        return try await clean(findings: safeFindings, profileName: profileName, dryRun: dryRun)
    }

    // MARK: - Deep Clean (safe + review-risk)

    /// Moves both `.safe` and `.review`-risk findings to Trash.
    /// `.advanced` findings are still always blocked.
    ///
    /// Callers **must** present an explicit user-facing warning before invoking this method
    /// — the `confirmed` parameter acts as an API-level assertion that the warning was shown.
    public func deepClean(
        findings: [ScanFinding],
        profileName: String,
        dryRun: Bool = false,
        confirmed: Bool
    ) async throws -> CleanupResult {
        guard confirmed else {
            return CleanupResult(succeeded: [], skipped: [], transaction: nil)
        }
        let candidates = findings.filter { $0.riskLevel == .safe || $0.riskLevel == .review }
        return try await clean(findings: candidates, profileName: profileName, dryRun: dryRun)
    }

    // MARK: - Full Clean

    /// Moves the given findings to Trash after applying all safety guards.
    /// - Parameters:
    ///   - findings: The findings to clean. `ADVANCED`-risk items are always skipped.
    ///   - profileName: Name of the scan profile (recorded in the transaction log).
    ///   - dryRun: When `true`, no files are moved but a transaction is still recorded.
    public func clean(
        findings: [ScanFinding],
        profileName: String,
        dryRun: Bool = false
    ) async throws -> CleanupResult {
        var succeeded: [CleanupItem] = []
        var skipped: [(path: String, reason: String)] = []

        // Resolved once per run — project-artifact re-verification needs the registered roots.
        let projectRootPaths = await projectRootsProvider()

        for finding in findings {
            let url = URL(fileURLWithPath: finding.path)

            // Path-level ban: Docker VM disk / volume data — independent of risk label.
            // Mis-tagged findings must still never trash Docker.raw or the vms tree.
            if ScanPolicy.isDockerNeverDeletePath(url) {
                skipped.append((
                    finding.path,
                    "Docker VM disk/volume data — never delete; use docker system prune without --volumes"
                ))
                continue
            }

            // Spotlight / Core Spotlight / Help / media analysis — deleting these
            // forces a costly reindex. Never trash even if a rule mis-reports them.
            if ScanPolicy.isSearchIndexSensitivePath(url) {
                skipped.append((
                    finding.path,
                    "Search-index path protected — cleaning would force Spotlight/media reindexing"
                ))
                continue
            }

            // ADVANCED findings must never be deleted directly.
            if finding.riskLevel == .advanced {
                skipped.append((finding.path, "ADVANCED-risk finding — use app-native cleanup"))
                continue
            }

            // Re-verify the path is still considered safe by policy. Fail-closed variants:
            // wrong-platform matches only inside the scanned trees; project artifacts only
            // with project-root evidence or under a registered project scan root.
            guard ScanPolicy.isLowImpactPath(url) || isPersonaPath(url)
                    || ScanPolicy.isCleanableWrongPlatformPath(url) || ScanPolicy.isInstallerFile(url)
                    || ScanPolicy.isReclaimableProjectArtifact(url, registeredRootPaths: projectRootPaths) else {
                skipped.append((finding.path, "Path no longer passes safety policy"))
                continue
            }

            // Verify the file still exists.
            guard FileManager.default.fileExists(atPath: finding.path) else {
                skipped.append((finding.path, "File no longer exists"))
                continue
            }

            // Re-verify minimum age for categories that require it.
            // Wrong-platform binaries/dirs are exempted: a Windows installer in ~/Downloads
            // or a win32/ native tree is inert on macOS from day zero — age is irrelevant.
            // Reconstructible package caches use a short floor (active download safety).
            if !ScanPolicy.isCleanableWrongPlatformPath(url),
               let minAge = ScanPolicy.minimumAgeSeconds(forCleanupPath: url, category: finding.category) {
                if ScanPolicy.isReconstructibleCachePath(url) {
                    // Reconstructible caches have no multi-day age gate (minAge may be 0).
                    if minAge > 0, !ScanPolicy.passesUnusedAge(for: url, minimumAgeSeconds: minAge) {
                        skipped.append((finding.path, "Cache too new"))
                        continue
                    }
                } else {
                    // Fail-closed: unreadable attributes / missing dates block cleanup —
                    // never assume the age gate is satisfied when age is unknowable.
                    let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey])
                    guard let date = res.flatMap(ScanPolicy.effectiveAgeDate(from:)) else {
                        skipped.append((finding.path, "File attributes unreadable — blocked for safety"))
                        continue
                    }
                    if Date().timeIntervalSince(date) < minAge {
                        skipped.append((finding.path, "File is too new (age < \(Int(minAge / 86400)) days)"))
                        continue
                    }
                }
            }

            if dryRun {
                succeeded.append(CleanupItem(
                    originalPath: finding.path,
                    trashedPath: nil,
                    sizeBytes: finding.sizeBytes,
                    reason: finding.reason,
                    riskLevel: finding.riskLevel
                ))
            } else {
                var trashURL: NSURL?
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
                    succeeded.append(CleanupItem(
                        originalPath: finding.path,
                        trashedPath: (trashURL as URL?)?.path,
                        sizeBytes: finding.sizeBytes,
                        reason: finding.reason,
                        riskLevel: finding.riskLevel
                    ))
                } catch {
                    skipped.append((finding.path, "Trash move failed: \(error.localizedDescription)"))
                }
            }
        }

        let transaction = CleanupTransaction(
            profileName: profileName,
            isDryRun: dryRun,
            items: succeeded
        )

        if !succeeded.isEmpty || dryRun {
            try store.save(transaction)
        }

        return CleanupResult(succeeded: succeeded, skipped: skipped, transaction: transaction)
    }

    // MARK: - Undo / Restore

    /// Restores all items from a previously recorded transaction by moving them
    /// out of the Trash back to their original locations.
    ///
    /// Items where the Trash path no longer exists are reported in `skipped`.
    public func restore(transaction: CleanupTransaction) async -> (restored: [String], skipped: [String]) {
        guard !transaction.isDryRun else {
            return ([], transaction.items.map(\.originalPath))
        }

        var restored: [String] = []
        var skipped: [String] = []

        for item in transaction.items {
            guard let trashedPath = item.trashedPath else {
                skipped.append(item.originalPath)
                continue
            }

            let trashURL = URL(fileURLWithPath: trashedPath)
            let destinationURL = URL(fileURLWithPath: item.originalPath)

            guard FileManager.default.fileExists(atPath: trashedPath) else {
                skipped.append(item.originalPath)
                continue
            }

            // Create parent directory if needed.
            let parentDir = destinationURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            do {
                try FileManager.default.moveItem(at: trashURL, to: destinationURL)
                restored.append(item.originalPath)
            } catch {
                skipped.append(item.originalPath)
            }
        }

        return (restored, skipped)
    }

    // MARK: - Single-item restore

    /// Restores one item from the Trash to its original path.
    /// Returns `true` when the move succeeded.
    public func restoreItem(_ item: CleanupItem) async -> Bool {
        guard let trashedPath = item.trashedPath else { return false }
        let trashURL = URL(fileURLWithPath: trashedPath)
        let destinationURL = URL(fileURLWithPath: item.originalPath)

        guard FileManager.default.fileExists(atPath: trashedPath) else { return false }

        let parentDir = destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        do {
            try FileManager.default.moveItem(at: trashURL, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private helpers

    /// A path passes persona policy if it matches any of the known persona marker sets.
    /// Docker advanced / VM disk markers are intentionally **not** included — those paths
    /// are hard-blocked via `isDockerNeverDeletePath` and must never become cleanable.
    private func isPersonaPath(_ url: URL) -> Bool {
        if ScanPolicy.isDockerNeverDeletePath(url) { return false }

        let allPersonaMarkers = ScanPolicy.designerSafePathMarkers
            + ScanPolicy.designerReviewPathMarkers
            + ScanPolicy.videoBuilderSafePathMarkers
            + ScanPolicy.videoBuilderReviewPathMarkers
            + ScanPolicy.developerSafePathMarkers
            + ScanPolicy.developerReviewPathMarkers
            + ScanPolicy.developerDockerReviewPathMarkers
            + ScanPolicy.developerDockerSafePathMarkers
            + ScanPolicy.developerPackageCacheMarkers
            + ScanPolicy.aiToolSafePathMarkers
            + ScanPolicy.browserExtendedSafePathMarkers
            + ScanPolicy.browserExtendedReviewPathMarkers
            + ScanPolicy.browserReviewDataPathMarkers
            + ScanPolicy.mobileSyncBackupPathMarkers
            + ScanPolicy.productivitySafePathMarkers
            + ScanPolicy.productivityReviewPathMarkers
            + ScanPolicy.launchAgentPathMarkers

        return ScanPolicy.matchesPersonaPath(url, allowedMarkers: allPersonaMarkers)
    }
}

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
    /// The path is excluded by the user's exclusion list.
    case excludedByUser(String)
    /// Search-index-sensitive path — cleaning would force Spotlight/media reindexing.
    case searchIndexProtected(String)
    /// File attributes could not be read — age gates fail closed.
    case attributesUnreadable(String)
    /// The undo transaction record could not be persisted before trashing.
    case undoRecordUnavailable(String)
    /// The file does not exist on disk when cleanup is attempted.
    case fileNotFound(String)
    /// The Trash move failed with an underlying system error.
    case trashFailed(String, Error)
    /// Undo failed — the associated value describes what went wrong.
    case restoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "Path no longer passes safety policy: \(path)"
        case .tooNew(let path):
            return "File is too new to clean: \(path)"
        case .advancedRiskBlocked(let path):
            return "ADVANCED-risk file blocked from direct deletion: \(path). Use the app's native cleanup flow instead."
        case .dockerNeverDelete(let path):
            return "Docker VM disk/volume data blocked: \(path). Use docker system prune (never --volumes)."
        case .excludedByUser(let path):
            return "Excluded by user: \(path)"
        case .searchIndexProtected(let path):
            return "Search-index path protected — cleaning would force Spotlight/media reindexing: \(path)"
        case .attributesUnreadable(let path):
            return "File attributes unreadable — blocked for safety: \(path)"
        case .undoRecordUnavailable(let detail):
            return "Could not persist undo record — cleanup aborted (\(detail))"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .trashFailed(let path, let error):
            return "Failed to move to Trash: \(path) — \(error.localizedDescription)"
        case .restoreFailed(let reason):
            return "Cannot restore — \(reason)"
        }
    }
}

/// One skipped cleanup item with its typed reason (R1.1).
public struct CleanupSkippedItem: Sendable {
    public let path: String
    public let error: CleanupError

    /// Human-readable reason — kept for presentation and log output.
    public var reason: String { error.localizedDescription }

    public init(path: String, error: CleanupError) {
        self.path = path
        self.error = error
    }
}

// MARK: - CleanupResult

/// Summary of a completed cleanup run.
public struct CleanupResult: Sendable {
    /// Successfully moved items (or dry-run candidates).
    public let succeeded: [CleanupItem]
    /// Items that were skipped because of a safety check failure, with typed reasons.
    public let skipped: [CleanupSkippedItem]
    /// The persisted transaction record (nil for dry-run that explicitly opts out of persistence).
    public let transaction: CleanupTransaction?
    /// Non-nil when the undo transaction could not be (fully) persisted to disk.
    /// Files may already have been moved to Trash — surfaced here instead of throwing.
    public let transactionSaveError: String?

    init(
        succeeded: [CleanupItem],
        skipped: [CleanupSkippedItem],
        transaction: CleanupTransaction?,
        transactionSaveError: String? = nil
    ) {
        self.succeeded = succeeded
        self.skipped = skipped
        self.transaction = transaction
        self.transactionSaveError = transactionSaveError
    }

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
    /// Supplies the user's exclusion list at cleanup time (scan-time filtering alone is
    /// not enough — exclusions added after a scan must still block cleanup). Injectable.
    private let exclusionsProvider: @Sendable () -> ExclusionList
    /// Injectable clock for age re-checks — tests shift this instead of
    /// back-dating real files. Defaults to the wall clock.
    private let now: @Sendable () -> Date

    /// Persist the undo record every N successful trash moves so a crash mid-cleanup
    /// loses at most this many items from the record.
    private static let incrementalSaveInterval = 20

    public init(
        store: CleanupTransactionStore = .shared,
        projectRootsProvider: (@Sendable () async -> [String])? = nil,
        exclusionsProvider: (@Sendable () -> ExclusionList)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.projectRootsProvider = projectRootsProvider ?? {
            let discovered = await ProjectRootDiscovery.shared.confirmedRoots().map(\.path)
            return discovered + ProjectScanPathStore.shared.paths
        }
        self.exclusionsProvider = exclusionsProvider ?? {
            (try? ExclusionStore.shared.load()) ?? .empty
        }
        self.now = now
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
        var skipped: [CleanupSkippedItem] = []

        // Resolved once per run — project-artifact re-verification needs the registered roots,
        // and exclusions must be honored at cleanup time (not only at scan time).
        let projectRootPaths = await projectRootsProvider()
        let exclusions = exclusionsProvider()

        // Durable-undo guarantee: for real runs, the transaction record is written
        // BEFORE anything is trashed and re-written incrementally during the loop.
        // If the initial record cannot be persisted, abort — never delete without
        // a durable undo record.
        let transactionID = UUID()
        let transactionTimestamp = Date()
        var transactionSaveError: String?

        func makeTransaction(_ items: [CleanupItem]) -> CleanupTransaction {
            CleanupTransaction(
                id: transactionID,
                timestamp: transactionTimestamp,
                profileName: profileName,
                isDryRun: dryRun,
                items: items
            )
        }

        if !dryRun, !findings.isEmpty {
            do {
                try store.save(makeTransaction([]))
            } catch {
                let detail = error.localizedDescription
                return CleanupResult(
                    succeeded: [],
                    skipped: findings.map {
                        CleanupSkippedItem(path: $0.path, error: .undoRecordUnavailable(detail))
                    },
                    transaction: nil,
                    transactionSaveError: detail
                )
            }
        }

        for finding in findings {
            let url = URL(fileURLWithPath: finding.path)

            // User exclusions always win — even if the finding predates the exclusion.
            if exclusions.isExcluded(finding.path) {
                skipped.append(CleanupSkippedItem(path: finding.path, error: .excludedByUser(finding.path)))
                continue
            }

            // Path-level ban: Docker VM disk / volume data — independent of risk label.
            // Mis-tagged findings must still never trash Docker.raw or the vms tree.
            if ScanPolicy.isDockerNeverDeletePath(url) {
                skipped.append(CleanupSkippedItem(path: finding.path, error: .dockerNeverDelete(finding.path)))
                continue
            }

            // Spotlight / Core Spotlight / Help / media analysis — deleting these
            // forces a costly reindex. Never trash even if a rule mis-reports them.
            if ScanPolicy.isSearchIndexSensitivePath(url) {
                skipped.append(CleanupSkippedItem(path: finding.path, error: .searchIndexProtected(finding.path)))
                continue
            }

            // ADVANCED findings must never be deleted directly.
            if finding.riskLevel == .advanced {
                skipped.append(CleanupSkippedItem(path: finding.path, error: .advancedRiskBlocked(finding.path)))
                continue
            }

            // Re-verify the path is still considered safe by policy. Fail-closed variants:
            // wrong-platform matches only inside the scanned trees; project artifacts only
            // with project-root evidence or under a registered project scan root.
            guard ScanPolicy.isLowImpactPath(url) || isPersonaPath(url)
                    || ScanPolicy.isCleanableWrongPlatformPath(url) || ScanPolicy.isInstallerFile(url)
                    || ScanPolicy.isReclaimableProjectArtifact(url, registeredRootPaths: projectRootPaths) else {
                skipped.append(CleanupSkippedItem(path: finding.path, error: .unsafePath(finding.path)))
                continue
            }

            // Verify the file still exists.
            guard FileManager.default.fileExists(atPath: finding.path) else {
                skipped.append(CleanupSkippedItem(path: finding.path, error: .fileNotFound(finding.path)))
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
                    if minAge > 0, !ScanPolicy.passesUnusedAge(for: url, minimumAgeSeconds: minAge, now: now()) {
                        skipped.append(CleanupSkippedItem(path: finding.path, error: .tooNew(finding.path)))
                        continue
                    }
                } else {
                    // Fail-closed: unreadable attributes / missing dates block cleanup —
                    // never assume the age gate is satisfied when age is unknowable.
                    let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey])
                    guard let date = res.flatMap(ScanPolicy.effectiveAgeDate(from:)) else {
                        skipped.append(CleanupSkippedItem(path: finding.path, error: .attributesUnreadable(finding.path)))
                        continue
                    }
                    if now().timeIntervalSince(date) < minAge {
                        skipped.append(CleanupSkippedItem(path: finding.path, error: .tooNew(finding.path)))
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
                    // Incremental persistence: bound how many trashed items a crash can
                    // drop from the undo record.
                    if succeeded.count % Self.incrementalSaveInterval == 0 {
                        do {
                            try store.save(makeTransaction(succeeded))
                        } catch {
                            transactionSaveError = error.localizedDescription
                        }
                    }
                } catch {
                    skipped.append(CleanupSkippedItem(path: finding.path, error: .trashFailed(finding.path, error)))
                }
            }
        }

        let transaction = makeTransaction(succeeded)

        var resultTransaction: CleanupTransaction? = transaction
        if dryRun {
            do {
                try store.save(transaction)
            } catch {
                transactionSaveError = error.localizedDescription
            }
        } else if succeeded.isEmpty {
            // Nothing was trashed — drop the empty placeholder record.
            try? store.delete(id: transactionID)
            resultTransaction = nil
        } else {
            do {
                try store.save(transaction)
                transactionSaveError = nil  // final save supersedes any incremental failure
            } catch {
                transactionSaveError = error.localizedDescription
            }
        }

        return CleanupResult(
            succeeded: succeeded,
            skipped: skipped,
            transaction: resultTransaction,
            transactionSaveError: transactionSaveError
        )
    }

    // MARK: - Undo / Restore

    /// Restores all items from a previously recorded transaction by moving them
    /// out of the Trash back to their original locations.
    ///
    /// Items that could not be restored are reported in `failed`, each with a reason
    /// (undo honesty — callers must not present a failed restore as success).
    public func restore(
        transaction: CleanupTransaction
    ) async -> (restored: [String], failed: [(path: String, reason: String)]) {
        guard !transaction.isDryRun else {
            return ([], transaction.items.map { ($0.originalPath, "Dry-run transaction — nothing was trashed") })
        }

        var restored: [String] = []
        var failed: [(path: String, reason: String)] = []

        for item in transaction.items {
            do {
                try restoreFromTrash(item)
                restored.append(item.originalPath)
            } catch {
                failed.append((item.originalPath, error.localizedDescription))
            }
        }

        return (restored, failed)
    }

    // MARK: - Single-item restore

    /// Restores one item from the Trash to its original path.
    /// Throws `CleanupError.restoreFailed` with the underlying reason on failure.
    public func restoreItem(_ item: CleanupItem) async throws {
        try restoreFromTrash(item)
    }

    /// Shared restore primitive — moves one trashed item back to its original path.
    private func restoreFromTrash(_ item: CleanupItem) throws {
        guard let trashedPath = item.trashedPath else {
            throw CleanupError.restoreFailed("No Trash location was recorded for \(item.originalPath)")
        }
        let trashURL = URL(fileURLWithPath: trashedPath)
        let destinationURL = URL(fileURLWithPath: item.originalPath)

        guard FileManager.default.fileExists(atPath: trashedPath) else {
            throw CleanupError.restoreFailed("Trash item no longer exists for \(item.originalPath)")
        }

        // Create parent directory if needed — a failure here surfaces via the move below.
        let parentDir = destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        do {
            try FileManager.default.moveItem(at: trashURL, to: destinationURL)
        } catch {
            throw CleanupError.restoreFailed("\(item.originalPath): \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    /// All persona marker sets, concatenated once (~250 elements). Built lazily on
    /// first use instead of per cleaned item — `clean` calls `isPersonaPath` for
    /// every candidate path.
    private static let allPersonaMarkers: [String] = ScanPolicy.designerSafePathMarkers
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

    /// A path passes persona policy if it matches any of the known persona marker sets.
    /// Docker advanced / VM disk markers are intentionally **not** included — those paths
    /// are hard-blocked via `isDockerNeverDeletePath` and must never become cleanable.
    private func isPersonaPath(_ url: URL) -> Bool {
        if ScanPolicy.isDockerNeverDeletePath(url) { return false }
        return ScanPolicy.matchesPersonaPath(url, allowedMarkers: Self.allPersonaMarkers)
    }
}

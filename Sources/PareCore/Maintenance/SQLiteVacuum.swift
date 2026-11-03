import Foundation

/// One database Pare may compact, and the app that must be quit first.
public struct SQLiteVacuumTarget: Sendable, Equatable {
    public let label: String
    public let path: String
    public let ownerBundleIdentifier: String?
    public let ownerName: String?

    public init(label: String, path: String, ownerBundleIdentifier: String?, ownerName: String?) {
        self.label = label
        self.path = path
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.ownerName = ownerName
    }
}

/// The `sqlite3` invocations for one database. In WAL mode VACUUM rewrites the whole file through
/// the `-wal` side file, so a TRUNCATE checkpoint on each side keeps it from staying database-sized.
public enum SQLiteVacuumPlan {
    static let quickCheck = "PRAGMA quick_check;"
    static let truncateCheckpoint = "PRAGMA wal_checkpoint(TRUNCATE);"
    static let vacuum = "VACUUM;"

    /// Argument lists for `sqlite3`; the first is the integrity check whose output must be `ok`.
    /// `-init /dev/null` stops a user's `~/.sqliterc` (e.g. `.headers on`) from changing the output parsed here.
    public static func steps(dbPath: String) -> [[String]] {
        [quickCheck, truncateCheckpoint, vacuum, truncateCheckpoint].map { [dbPath, "-init", "/dev/null", $0] }
    }

    /// `wal_checkpoint` prints `busy|log|checkpointed` and exits 0 even when a reader blocked it.
    static func checkpointWasBlocked(_ output: String) -> Bool {
        output.split(separator: "|").first?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }
}

/// Runs `SQLiteVacuumPlan` per database, skipping any that is corrupt, busy, owned by a running app,
/// or larger than half the free space. One failing database never stops the others.
public struct SQLiteVacuumRunner: Sendable {
    public static let defaultSQLite3Path = "/usr/bin/sqlite3"

    /// VACUUM needs room for a full copy of the database plus its WAL.
    static let requiredFreeSpaceMultiplier: Int64 = 2

    private let processRunner: any ProcessRunning
    private let freeSpace: any FreeSpaceProviding
    private let runningApps: any RunningAppChecking
    private let sqlite3Path: String

    public init(
        processRunner: any ProcessRunning,
        freeSpace: any FreeSpaceProviding = StatfsFreeSpace(),
        runningApps: any RunningAppChecking = WorkspaceRunningApps(),
        sqlite3Path: String = SQLiteVacuumRunner.defaultSQLite3Path
    ) {
        self.processRunner = processRunner
        self.freeSpace = freeSpace
        self.runningApps = runningApps
        self.sqlite3Path = sqlite3Path
    }

    public func vacuum(_ targets: [SQLiteVacuumTarget], log: @Sendable (String) -> Void) async {
        let volumePath = targets.first.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path }
        if let volumePath {
            log("Free space before: \(Self.formatted(freeSpace.availableBytes(atPath: volumePath)))")
        }
        for target in targets {
            log("→ Vacuuming \(target.label)…")
            if let reason = skipReason(for: target) {
                log("  ⚠ Skipped \(target.label): \(reason)")
                continue
            }
            await run(target, log: log)
        }
        if let volumePath {
            log("Free space after: \(Self.formatted(freeSpace.availableBytes(atPath: volumePath)))")
        }
    }

    // MARK: - Private

    private func skipReason(for target: SQLiteVacuumTarget) -> String? {
        if let owner = target.ownerBundleIdentifier, runningApps.isRunning(bundleIdentifier: owner) {
            return "quit \(target.ownerName ?? owner) first"
        }
        let needed = Self.requiredFreeSpaceMultiplier * (Self.fileSize(target.path) + Self.fileSize(target.path + "-wal"))
        let directory = URL(fileURLWithPath: target.path).deletingLastPathComponent().path
        guard let available = freeSpace.availableBytes(atPath: directory) else {
            return "free space could not be determined"
        }
        guard available >= needed else {
            return "needs \(Self.formatted(needed)) free, only \(Self.formatted(available)) available"
        }
        return nil
    }

    private func run(_ target: SQLiteVacuumTarget, log: @Sendable (String) -> Void) async {
        let sizeBefore = Self.fileSize(target.path)
        let steps = SQLiteVacuumPlan.steps(dbPath: target.path)
        do {
            let check = try await processRunner.run(executablePath: sqlite3Path, arguments: steps[0], environment: nil)
            guard check.exitCode == 0 else {
                log("  ⚠ Skipped \(target.label): \(Self.describe(check)) (busy or unreadable)")
                return
            }
            guard check.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
                log("  ⚠ Skipped \(target.label): integrity check failed")
                return
            }
            var walStillOpen = false
            for (index, step) in steps.enumerated().dropFirst() {
                let result = try await processRunner.run(executablePath: sqlite3Path, arguments: step, environment: nil)
                guard result.exitCode == 0 else {
                    log("  ⚠ \(target.label): \(Self.describe(result))")
                    return
                }
                guard step.last == SQLiteVacuumPlan.truncateCheckpoint,
                      SQLiteVacuumPlan.checkpointWasBlocked(result.standardOutput) else { continue }
                // Blocked before VACUUM: the rewrite would land in a WAL that cannot be truncated.
                if index < steps.count - 1 {
                    log("  ⚠ Skipped \(target.label): another process is reading it")
                    return
                }
                walStillOpen = true
            }
            let sizeAfter = Self.fileSize(target.path)
            if walStillOpen {
                log("  ⚠ \(target.label) compacted (\(Self.formatted(sizeBefore)) → \(Self.formatted(sizeAfter))), "
                    + "but another process kept its WAL open; it shrinks once that app closes the database.")
                return
            }
            log("  ✓ \(target.label) done (\(Self.formatted(sizeBefore)) → \(Self.formatted(sizeAfter))).")
        } catch {
            // Catch everything: one database that cannot be opened must not abort the rest.
            log("  ⚠ \(target.label): \(error.localizedDescription)")
        }
    }

    private static func describe(_ result: ProcessResult) -> String {
        let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "sqlite3 exited with code \(result.exitCode)" : message
    }

    private static func fileSize(_ path: String) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        return size ?? 0
    }

    private static func formatted(_ bytes: Int64?) -> String {
        guard let bytes else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

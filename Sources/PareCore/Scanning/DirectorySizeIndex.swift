import Foundation

/// Per-scan memoized directory-size index.
///
/// Many rules independently size overlapping directory trees (e.g. several rules
/// each walk subtrees of `~/Library/Caches`). Threading one index through
/// `ScanEnvironment` for the duration of a single `ScanRunner.run` means each
/// distinct directory is walked at most once per scan.
///
/// Implemented as a lock-guarded class (not an actor) so the synchronous rule
/// helpers that call it — deep inside `customScan` loops — don't all have to
/// become `async`. `ScanRunner` executes rules sequentially, so contention on
/// the lock is negligible; the lock is only held around dictionary access,
/// never during the filesystem walk itself.
public final class DirectorySizeIndex: @unchecked Sendable {
    /// Longest one directory may take to size before its finding is reported as "at least".
    public static let defaultPerDirectoryBudgetSeconds: TimeInterval = 10

    private let lock = NSLock()
    private var resultsByPath: [String: DirectorySizeResult] = [:]
    private let budgetSeconds: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        budgetSeconds: TimeInterval = DirectorySizeIndex.defaultPerDirectoryBudgetSeconds,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.budgetSeconds = budgetSeconds
        self.now = now
    }

    /// Returns the allocated size of the directory tree at `url`, computing it
    /// via `FileSystemUtils.directorySize` on first request and serving the
    /// memoized value on every subsequent request for the same path. Unbounded.
    public func directorySize(url: URL) -> Int64 {
        let key = url.standardizedFileURL.path
        if let cached = cached(key), cached.isComplete { return cached.bytes }
        let computed = DirectorySizeResult(bytes: FileSystemUtils.directorySize(url: url), isComplete: true)
        store(computed, for: key)
        return computed.bytes
    }

    /// Like `directorySize(url:)` but stops after `budgetSeconds`; an unfinished result is memoized as is.
    public func directorySizeResult(url: URL) -> DirectorySizeResult {
        let key = url.standardizedFileURL.path
        if let cached = cached(key) { return cached }
        let deadline = now().addingTimeInterval(budgetSeconds)
        let computed = FileSystemUtils.directorySize(at: url, deadline: deadline, now: now)
        store(computed, for: key)
        return computed
    }

    // The lock is only held around dictionary access, never during the walk.
    private func cached(_ key: String) -> DirectorySizeResult? {
        lock.lock()
        defer { lock.unlock() }
        return resultsByPath[key]
    }

    private func store(_ result: DirectorySizeResult, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        resultsByPath[key] = result
    }
}

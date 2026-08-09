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
    private let lock = NSLock()
    private var sizesByPath: [String: Int64] = [:]

    public init() {}

    /// Returns the allocated size of the directory tree at `url`, computing it
    /// via `FileSystemUtils.directorySize` on first request and serving the
    /// memoized value on every subsequent request for the same path.
    public func directorySize(url: URL) -> Int64 {
        let key = url.standardizedFileURL.path

        lock.lock()
        if let cached = sizesByPath[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let computed = FileSystemUtils.directorySize(url: url)

        lock.lock()
        sizesByPath[key] = computed
        lock.unlock()
        return computed
    }
}

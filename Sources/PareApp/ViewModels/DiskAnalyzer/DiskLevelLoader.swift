import Foundation
import PareCore

/// Loads one Disk Analyzer directory level off the main actor: sizes children with
/// `FileSystemUtils.directoryUsage`, reports progress, caps the visible rows to 200 plus a
/// folded remainder, and caches completed levels by standardized path for back/forward.
final class DiskLevelLoader: Sendable {

    struct Level: Sendable {
        let directory: URL
        let entries: [DiskEntry]
        let totalBytes: Int64
        let totalItemCount: Int
    }

    struct Progress: Sendable {
        let scanned: Int
        let total: Int
    }

    static let maxVisibleEntries = 200

    private let cache = DiskLevelCache()

    init() {}

    /// Returns the cached level for `directory` if present, otherwise walks it (cooperatively
    /// cancellable via the calling task) and stores the result before returning.
    func load(directory: URL, onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> Level {
        let key = DiskEntry.standardizedID(for: directory)
        if let cached = await cache.value(for: key) {
            return cached
        }
        let level = try Self.buildLevel(directory: directory, onProgress: onProgress)
        await cache.store(level, for: key)
        return level
    }

    /// Drops the cached level for `directory` (e.g. after a cleanup) so the next `load` re-walks it.
    func invalidate(directory: URL) async {
        await cache.remove(DiskEntry.standardizedID(for: directory))
    }

    func invalidateAll() async {
        await cache.removeAll()
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .contentModificationDateKey,
        .totalFileAllocatedSizeKey, .fileSizeKey,
    ]

    private static func buildLevel(
        directory: URL,
        onProgress: (@Sendable (Progress) -> Void)?
    ) throws -> Level {
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var entries: [DiskEntry] = []
        entries.reserveCapacity(children.count)
        for (index, childURL) in children.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            entries.append(makeEntry(url: childURL))
            onProgress?(Progress(scanned: index + 1, total: children.count))
        }

        // Largest first, so the 200-row cap keeps the entries that matter most.
        entries.sort { $0.sizeBytes > $1.sizeBytes }
        let totalBytes = entries.reduce(into: Int64(0)) { $0 += $1.sizeBytes }
        let totalItemCount = entries.reduce(into: 0) { $0 += $1.itemCount }

        guard entries.count > maxVisibleEntries else {
            return Level(directory: directory, entries: entries, totalBytes: totalBytes, totalItemCount: totalItemCount)
        }

        let visible = Array(entries.prefix(maxVisibleEntries))
        let folded = entries[maxVisibleEntries...]
        let remainder = DiskEntry.remainder(
            count: folded.count,
            sizeBytes: folded.reduce(into: Int64(0)) { $0 += $1.sizeBytes },
            in: directory
        )
        return Level(
            directory: directory,
            entries: visible + [remainder],
            totalBytes: totalBytes,
            totalItemCount: totalItemCount
        )
    }

    private static func makeEntry(url: URL) -> DiskEntry {
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let isDirectory = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        let ownModified = values?.contentModificationDate

        guard isDirectory else {
            return DiskEntry(
                id: DiskEntry.standardizedID(for: url),
                url: url,
                name: url.lastPathComponent,
                isDirectory: false,
                isPackage: false,
                sizeBytes: FileSystemUtils.fileSize(url: url),
                itemCount: 1,
                modified: ownModified,
                kind: DiskKind(isDirectory: false, isPackage: false, pathExtension: url.pathExtension)
            )
        }

        // A folder's own mtime only reflects its direct child list, not deep edits, so the
        // recursive `newestModification` is what "most recently touched" should mean here.
        let usage = FileSystemUtils.directoryUsage(url: url)
        return DiskEntry(
            id: DiskEntry.standardizedID(for: url),
            url: url,
            name: url.lastPathComponent,
            isDirectory: true,
            isPackage: isPackage,
            sizeBytes: usage.allocatedBytes,
            itemCount: usage.itemCount,
            modified: usage.newestModification ?? ownModified,
            kind: DiskKind(isDirectory: true, isPackage: isPackage, pathExtension: url.pathExtension)
        )
    }
}

/// Actor-isolated storage backing `DiskLevelLoader`'s path cache — the only mutable state, so
/// the loader class itself stays a plain `Sendable` value holder.
private actor DiskLevelCache {
    private var storage: [String: DiskLevelLoader.Level] = [:]

    func value(for key: String) -> DiskLevelLoader.Level? { storage[key] }
    func store(_ level: DiskLevelLoader.Level, for key: String) { storage[key] = level }
    func remove(_ key: String) { storage.removeValue(forKey: key) }
    func removeAll() { storage.removeAll() }
}

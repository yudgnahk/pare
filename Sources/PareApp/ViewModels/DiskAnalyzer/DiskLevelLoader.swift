import Foundation
import PareCore

/// Loads one Disk Analyzer directory level off the main actor: sizes children with
/// `FileSystemUtils.directoryUsage` (never crossing into other volumes), reports progress, and caches levels.
final class DiskLevelLoader: Sendable {

    struct Level: Sendable {
        let directory: URL
        let entries: [DiskEntry]
        let totalBytes: Int64
        let totalItemCount: Int
        let hasPartialSize: Bool
    }

    struct Progress: Sendable {
        let scanned: Int
        let total: Int
    }

    private let cache = DiskLevelCache()
    private let mountPoints: FileSystemUtils.MountPointCheck

    /// Production reads the prefetched `isVolume`; tests pass `isMountPoint` to fake a mount without mounting anything.
    init(isMountPoint: (@Sendable (URL) -> Bool)? = nil) {
        self.mountPoints = isMountPoint.map { .custom($0) } ?? .prefetchedVolumeFlag
    }

    /// Returns the cached level for `directory` if present, otherwise walks it (cooperatively
    /// cancellable via the calling task) and stores the result before returning.
    func load(directory: URL, onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> Level {
        let key = Self.cacheKey(for: directory)
        if let cached = await cache.value(for: key) {
            return cached
        }
        let level = try Self.buildLevel(directory: directory, mountPoints: mountPoints, onProgress: onProgress)
        try Task.checkCancellation()
        await cache.store(level, for: key)
        return level
    }

    /// Drops the cached level for `directory` (e.g. after a cleanup) so the next `load` re-walks it.
    func invalidate(directory: URL) async {
        await cache.remove(Self.cacheKey(for: directory))
    }

    /// Drops `directory` and every cached ancestor, whose rolled-up sizes include it.
    func invalidate(directoryAndAncestors directory: URL) async {
        var current = directory.standardizedFileURL
        while true {
            await invalidate(directory: current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { return }
            current = parent
        }
    }

    /// A folder and its symlinked spelling are the same level, so the key resolves every component.
    private static func cacheKey(for directory: URL) -> String {
        ScanPolicy.canonicalPathURL(directory.standardizedFileURL.resolvingSymlinksInPath(), normalizingFirmlinks: false).path
    }

    func invalidateAll() async {
        await cache.removeAll()
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .creationDateKey,
        .totalFileAllocatedSizeKey, .fileSizeKey, .isVolumeKey,
    ]

    private static func buildLevel(
        directory: URL,
        mountPoints: FileSystemUtils.MountPointCheck,
        onProgress: (@Sendable (Progress) -> Void)?
    ) throws -> Level {
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        var entries: [DiskEntry] = []
        entries.reserveCapacity(children.count)
        for (index, childURL) in children.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            entries.append(makeEntry(url: childURL, mountPoints: mountPoints))
            if Task.isCancelled { throw CancellationError() }
            onProgress?(Progress(scanned: index + 1, total: children.count))
        }

        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let totalBytes = entries.reduce(into: Int64(0)) { $0 += $1.sizeBytes }
        let totalItemCount = entries.reduce(into: 0) { $0 += $1.itemCount }
        return Level(
            directory: directory,
            entries: entries,
            totalBytes: totalBytes,
            totalItemCount: totalItemCount,
            hasPartialSize: entries.contains(where: \.hasPartialSize)
        )
    }

    private static func makeEntry(url: URL, mountPoints: FileSystemUtils.MountPointCheck) -> DiskEntry {
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let isDirectory = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        let ownModified = values?.contentModificationDate
        let creationDate = values?.creationDate

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
                kind: DiskKind(isDirectory: false, isPackage: false, pathExtension: url.pathExtension),
                creationDate: creationDate,
                hasPartialSize: values == nil
            )
        }

        // Walking another volume from here double-counts it and can hang on a slow mount.
        if isVolumeRoot(url, values: values, mountPoints: mountPoints) {
            return separateVolumeEntry(url: url, isPackage: isPackage, modified: ownModified, created: creationDate)
        }

        // A folder's own mtime only reflects its direct child list, not deep edits, so the
        // recursive `newestModification` is what "most recently touched" should mean here.
        let usage = FileSystemUtils.directoryUsage(url: url, mountPoints: mountPoints)
        return DiskEntry(
            id: DiskEntry.standardizedID(for: url),
            url: url,
            name: url.lastPathComponent,
            isDirectory: true,
            isPackage: isPackage,
            sizeBytes: usage.allocatedBytes,
            itemCount: usage.itemCount,
            modified: usage.newestModification ?? ownModified,
            kind: DiskKind(isDirectory: true, isPackage: isPackage, pathExtension: url.pathExtension),
            creationDate: creationDate,
            hasPartialSize: usage.isPartial || values == nil
        )
    }

    /// Uses the already-fetched `isVolume` unless a test override is set.
    private static func isVolumeRoot(
        _ url: URL,
        values: URLResourceValues?,
        mountPoints: FileSystemUtils.MountPointCheck
    ) -> Bool {
        if case .custom(let predicate) = mountPoints { return predicate(url) }
        return values?.isVolume == true
    }

    /// Row for a mounted volume: listed but not sized until the user opens it.
    private static func separateVolumeEntry(url: URL, isPackage: Bool, modified: Date?, created: Date?) -> DiskEntry {
        DiskEntry(
            id: DiskEntry.standardizedID(for: url),
            url: url,
            name: url.lastPathComponent,
            isDirectory: true,
            isPackage: isPackage,
            sizeBytes: 0,
            itemCount: 0,
            modified: modified,
            kind: DiskKind(isDirectory: true, isPackage: isPackage, pathExtension: url.pathExtension),
            creationDate: created,
            isSeparateVolume: true
        )
    }
}

/// Actor-isolated storage backing `DiskLevelLoader`'s path cache — the only mutable state, so
/// the loader class itself stays a plain `Sendable` value holder.
private actor DiskLevelCache {
    private let capacity = 8
    private var storage: [String: DiskLevelLoader.Level] = [:]
    private var recency: [String] = []

    func value(for key: String) -> DiskLevelLoader.Level? {
        guard let level = storage[key] else { return nil }
        recency.removeAll { $0 == key }
        recency.append(key)
        return level
    }

    func store(_ level: DiskLevelLoader.Level, for key: String) {
        storage[key] = level
        recency.removeAll { $0 == key }
        recency.append(key)
        while recency.count > capacity {
            storage.removeValue(forKey: recency.removeFirst())
        }
    }

    func remove(_ key: String) {
        storage.removeValue(forKey: key)
        recency.removeAll { $0 == key }
    }

    func removeAll() {
        storage.removeAll()
        recency.removeAll()
    }
}

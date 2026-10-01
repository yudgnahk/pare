import Foundation

/// Allocated bytes, regular-file count and newest modification date for a directory subtree.
public struct DirectoryUsage: Sendable {
    public let allocatedBytes: Int64
    public let itemCount: Int
    public let newestModification: Date?
    public let isPartial: Bool

    public init(allocatedBytes: Int64, itemCount: Int, newestModification: Date?, isPartial: Bool = false) {
        self.allocatedBytes = allocatedBytes
        self.itemCount = itemCount
        self.newestModification = newestModification
        self.isPartial = isPartial
    }
}

public enum FileSystemUtils {
    /// Compares two dot-separated version strings component-by-component.
    /// Non-numeric or missing components are treated as 0.
    public static func compareVersionStrings(_ a: String, _ b: String) -> ComparisonResult {
        compareVersionComponents(
            a.split(separator: ".").map { Int($0) ?? 0 },
            b.split(separator: ".").map { Int($0) ?? 0 }
        )
    }

    /// Compares numeric version component arrays; missing components are 0.
    /// The single comparison loop backing every version check (rules parse
    /// their own components, e.g. VS Code extension directory names).
    public static func compareVersionComponents(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        let count = max(a.count, b.count)
        for i in 0..<count {
            let va = i < a.count ? a[i] : 0
            let vb = i < b.count ? b[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func directorySize(url: URL) -> Int64 {
        measureDirectory(url: url, includeModificationDates: false).allocatedBytes
    }

    /// How a walk treats directories that are the root of another mounted volume.
    public enum MountPointCheck: Sendable {
        /// Walk into other volumes (scan-rule sizing).
        case none
        /// Skip nested volumes using the enumerator's prefetched `isVolume` value.
        case prefetchedVolumeFlag
        /// Test override: skip directories the closure flags as mount points.
        case custom(@Sendable (URL) -> Bool)

        fileprivate func isMountPoint(_ url: URL, _ vals: URLResourceValues) -> Bool {
            switch self {
            case .none: return false
            case .prefetchedVolumeFlag: return vals.isVolume == true
            case .custom(let predicate): return predicate(url)
            }
        }

        fileprivate var isActive: Bool {
            if case .none = self { return false }
            return true
        }
    }

    /// Allocated bytes, regular-file count and newest modification, in one enumerator pass
    /// (avoids walking large trees twice for the Disk Analyzer's size + item-count + date columns).
    /// Directories that `mountPoints` flags are skipped, so other volumes are never double-counted.
    public static func directoryUsage(url: URL, mountPoints: MountPointCheck = .none) -> DirectoryUsage {
        measureDirectory(url: url, includeModificationDates: true, mountPoints: mountPoints)
    }

    /// True when `url` is the root of a mounted volume (external, network, or an APFS sibling like `/System/Volumes/Data`).
    public static let isVolumeRoot: @Sendable (URL) -> Bool = { url in
        (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
    }

    private static func measureDirectory(
        url: URL,
        includeModificationDates: Bool,
        mountPoints: MountPointCheck = .none
    ) -> DirectoryUsage {
        var keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        if includeModificationDates { keys.append(.contentModificationDateKey) }
        let checksMountPoints = mountPoints.isActive
        if checksMountPoints { keys += [.isDirectoryKey, .isVolumeKey] }
        let keySet = Set(keys)
        var isPartial = false
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in
                isPartial = true
                return true
            }
        ) else {
            return DirectoryUsage(allocatedBytes: 0, itemCount: 0, newestModification: nil, isPartial: true)
        }
        var tally = UsageTally()
        for case let fileURL as URL in enumerator {
            // Checked on every entry so a cancelled walk of a huge tree stops promptly.
            if Task.isCancelled {
                break
            }
            guard let vals = try? fileURL.resourceValues(forKeys: keySet) else {
                isPartial = true
                continue
            }
            if checksMountPoints, vals.isDirectory == true, mountPoints.isMountPoint(fileURL, vals) {
                enumerator.skipDescendants()
                continue
            }
            guard vals.isRegularFile == true else {
                continue
            }
            tally.add(vals, includeModificationDates: includeModificationDates)
        }
        return DirectoryUsage(
            allocatedBytes: tally.total,
            itemCount: tally.itemCount,
            newestModification: tally.newest,
            isPartial: isPartial || Task.isCancelled
        )
    }

    /// Running totals for one `measureDirectory` walk; a local accumulator keeps the hot loop allocation-free.
    private struct UsageTally {
        var total: Int64 = 0
        var itemCount = 0
        var newest: Date?

        mutating func add(_ vals: URLResourceValues, includeModificationDates: Bool) {
            total += FileSystemUtils.allocatedBytes(from: vals)
            itemCount += 1
            if includeModificationDates,
               let modified = vals.contentModificationDate,
               modified > (newest ?? .distantPast) {
                newest = modified
            }
        }
    }

    /// Bytes actually allocated on disk for a file.
    /// Prefers `totalFileAllocatedSize` so sparse files (e.g. Docker.raw) report real usage,
    /// not the huge logical capacity. Matches `FileSystemTraversal` sizing.
    public static func fileSize(url: URL) -> Int64 {
        guard let vals = try? url.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        return allocatedBytes(from: vals)
    }

    /// Logical size (EOF) — may be much larger than disk usage for sparse files.
    public static func logicalFileSize(url: URL) -> Int64 {
        guard let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = vals.fileSize else { return 0 }
        return Int64(size)
    }

    fileprivate static func allocatedBytes(from values: URLResourceValues) -> Int64 {
        if let allocated = values.totalFileAllocatedSize {
            return Int64(allocated)
        }
        return Int64(values.fileSize ?? 0)
    }
}

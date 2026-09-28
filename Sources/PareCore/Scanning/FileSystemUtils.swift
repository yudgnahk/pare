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

    /// Entries between cooperative `Task.isCancelled` checks while sizing a directory.
    private static let cancellationCheckInterval = 1

    public static func directorySize(url: URL) -> Int64 {
        measureDirectory(url: url, includeModificationDates: false).allocatedBytes
    }

    /// Allocated bytes, regular-file count and newest modification, in one enumerator pass
    /// (avoids walking large trees twice for the Disk Analyzer's size + item-count + date columns).
    public static func directoryUsage(url: URL) -> DirectoryUsage {
        measureDirectory(url: url, includeModificationDates: true)
    }

    private static func measureDirectory(url: URL, includeModificationDates: Bool) -> DirectoryUsage {
        let fm = FileManager.default
        var keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        if includeModificationDates { keys.append(.contentModificationDateKey) }
        var isPartial = false
        guard let enumerator = fm.enumerator(
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
        var total: Int64 = 0
        var itemCount = 0
        var newest: Date?
        var checkedCount = 0
        for case let fileURL as URL in enumerator {
            checkedCount += 1
            if checkedCount % cancellationCheckInterval == 0, Task.isCancelled {
                break
            }
            guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                isPartial = true
                continue
            }
            guard vals.isRegularFile == true else {
                continue
            }
            total += allocatedBytes(from: vals)
            itemCount += 1
            if includeModificationDates,
               let modified = vals.contentModificationDate,
               modified > (newest ?? .distantPast) {
                newest = modified
            }
        }
        return DirectoryUsage(
            allocatedBytes: total,
            itemCount: itemCount,
            newestModification: newest,
            isPartial: isPartial || Task.isCancelled
        )
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

    private static func allocatedBytes(from values: URLResourceValues) -> Int64 {
        if let allocated = values.totalFileAllocatedSize {
            return Int64(allocated)
        }
        return Int64(values.fileSize ?? 0)
    }
}

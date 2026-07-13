import Foundation

public enum FileSystemUtils {
    /// Compares two dot-separated version strings component-by-component.
    /// Non-numeric or missing components are treated as 0.
    public static func compareVersionStrings(_ a: String, _ b: String) -> ComparisonResult {
        let partsA = a.split(separator: ".").map { Int($0) ?? 0 }
        let partsB = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
            ),
               vals.isRegularFile == true {
                total += allocatedBytes(from: vals)
            }
        }
        return total
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

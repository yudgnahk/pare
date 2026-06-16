import Foundation

public struct FileSystemTraversal: FileTraversing {
    public init() {}

    public func collectFiles(in directories: [URL]) async -> [ScannedFile] {
        await withTaskGroup(of: [ScannedFile].self) { group in
            for directory in directories {
                guard !Task.isCancelled else { break }
                group.addTask {
                    await self.collectFiles(in: directory)
                }
            }

            var allFiles: [ScannedFile] = []
            for await files in group {
                allFiles.append(contentsOf: files)
            }
            return allFiles
        }
    }

    private func collectFiles(in directory: URL) async -> [ScannedFile] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]

        // .skipsPackageDescendants prevents descending into .app/.framework/.bundle packages.
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }   // skip permission-denied entries silently
        ) else {
            return []
        }

        var files: [ScannedFile] = []
        var checkedCount = 0

        while let item = enumerator.nextObject() as? URL {
            // Check cancellation periodically to allow the scan to be aborted.
            checkedCount += 1
            if checkedCount % 200 == 0, Task.isCancelled {
                break
            }

            guard let values = try? item.resourceValues(forKeys: keys) else { continue }

            // Skip symlinks to avoid following potentially circular or out-of-scope links.
            if values.isSymbolicLink == true { continue }

            // Only include regular files (not directories or special files).
            guard values.isRegularFile == true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            let modified = values.contentModificationDate
            files.append(ScannedFile(url: item, sizeBytes: size, lastModified: modified))
        }
        return files
    }
}

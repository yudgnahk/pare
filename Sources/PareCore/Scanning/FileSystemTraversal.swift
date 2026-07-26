import Foundation

public struct FileSystemTraversal: FileTraversing {
    public init() {}

    public func collectFiles(in directories: [URL]) async -> [ScannedFile] {
        await collectFilesReportingErrors(in: directories).files
    }

    public func collectFilesReportingErrors(in directories: [URL]) async -> TraversalResult {
        await withTaskGroup(of: TraversalResult.self) { group in
            for directory in directories {
                guard !Task.isCancelled else { break }
                group.addTask {
                    await self.collect(in: directory)
                }
            }

            var allFiles: [ScannedFile] = []
            var unreadable: Set<String> = []
            for await result in group {
                allFiles.append(contentsOf: result.files)
                unreadable.formUnion(result.unreadablePaths)
            }
            return TraversalResult(files: allFiles, unreadablePaths: unreadable)
        }
    }

    /// Direct single-directory traversal — no task group involved.
    public func collectFiles(in directory: URL) async -> [ScannedFile] {
        await collect(in: directory).files
    }

    /// Direct single-directory error-reporting traversal — no task group involved.
    public func collectFilesReportingErrors(in directory: URL) async -> TraversalResult {
        await collect(in: directory)
    }

    /// Collects permission-error paths reported by the directory enumerator.
    /// The handler runs synchronously on the enumerating thread, so plain
    /// accumulation behind a reference box is safe.
    private final class UnreadablePathBox: @unchecked Sendable {
        var paths: Set<String> = []
    }

    private func collect(in directory: URL) async -> TraversalResult {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return TraversalResult(files: [])
        }

        // Existing-but-unreadable root (typical Full Disk Access gap) — report it
        // instead of silently returning nothing (R1.3).
        guard fileManager.isReadableFile(atPath: directory.path) else {
            return TraversalResult(files: [], unreadablePaths: [directory.path])
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]

        let unreadableBox = UnreadablePathBox()

        // .skipsPackageDescendants prevents descending into .app/.framework/.bundle packages.
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
                // Record permission-denied entries instead of dropping them silently (R1.3).
                unreadableBox.paths.insert(url.path)
                return true
            }
        ) else {
            return TraversalResult(files: [], unreadablePaths: [directory.path])
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
        return TraversalResult(files: files, unreadablePaths: unreadableBox.paths)
    }
}

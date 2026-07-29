import Foundation

/// Wraps any `FileTraversing` with per-directory mtime caching. On each scan, directories
/// whose `contentModificationDate` hasn't changed since the last scan are served from the
/// in-memory cache without re-traversal. Stale directories are re-traversed concurrently.
struct CachedFileTraversal: FileTraversing {
    let inner: any FileTraversing
    let cache: ScanMetadataCache

    func collectFiles(in directories: [URL]) async -> [ScannedFile] {
        await collectFilesReportingErrors(in: directories).files
    }

    func collectFilesReportingErrors(in directories: [URL]) async -> TraversalResult {
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

    func collectFiles(in directory: URL) async -> [ScannedFile] {
        await collect(in: directory).files
    }

    func collectFilesReportingErrors(in directory: URL) async -> TraversalResult {
        await collect(in: directory)
    }

    private func collect(in directory: URL) async -> TraversalResult {
        let mtime = directoryMtime(directory)
        if let mtime, await cache.isFresh(directory: directory, currentMtime: mtime),
           let cached = await cache.cachedFiles(for: directory) {
            // Cache hit — the directory was readable when cached.
            return TraversalResult(files: cached)
        }

        // Single-directory call keeps results per-directory without the inner
        // traversal spinning up a task group for exactly one child, while still
        // reporting unreadable paths (R1.3).
        let result = await inner.collectFilesReportingErrors(in: directory)

        // Only cache complete results — skip if the task was cancelled mid-traversal.
        if let mtime, !Task.isCancelled, result.unreadablePaths.isEmpty {
            await cache.store(directory: directory, mtime: mtime, files: result.files)
        }

        return result
    }

    private func directoryMtime(_ directory: URL) -> Date? {
        (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

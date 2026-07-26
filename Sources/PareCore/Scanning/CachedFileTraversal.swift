import Foundation

/// Wraps any `FileTraversing` with per-directory mtime caching. On each scan, directories
/// whose `contentModificationDate` hasn't changed since the last scan are served from the
/// in-memory cache without re-traversal. Stale directories are re-traversed concurrently.
struct CachedFileTraversal: FileTraversing {
    let inner: any FileTraversing
    let cache: ScanMetadataCache

    func collectFiles(in directories: [URL]) async -> [ScannedFile] {
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

    func collectFiles(in directory: URL) async -> [ScannedFile] {
        let mtime = directoryMtime(directory)
        if let mtime, await cache.isFresh(directory: directory, currentMtime: mtime),
           let cached = await cache.cachedFiles(for: directory) {
            return cached
        }

        // Single-directory call keeps results per-directory without the inner
        // traversal spinning up a task group for exactly one child.
        let files = await inner.collectFiles(in: directory)

        // Only cache complete results — skip if the task was cancelled mid-traversal.
        if let mtime, !Task.isCancelled {
            await cache.store(directory: directory, mtime: mtime, files: files)
        }

        return files
    }

    private func directoryMtime(_ directory: URL) -> Date? {
        (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

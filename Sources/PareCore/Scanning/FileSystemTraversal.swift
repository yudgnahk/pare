import Foundation

public struct FileSystemTraversal: FileTraversing {
    public init() {}

    public func collectFiles(in directories: [URL]) async -> [ScannedFile] {
        await withTaskGroup(of: [ScannedFile].self) { group in
            for directory in directories {
                group.addTask {
                    self.collectFiles(in: directory)
                }
            }

            var allFiles: [ScannedFile] = []
            for await files in group {
                allFiles.append(contentsOf: files)
            }
            return allFiles
        }
    }

    private func collectFiles(in directory: URL) -> [ScannedFile] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [ScannedFile] = []
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate
            files.append(ScannedFile(url: item, sizeBytes: size, lastModified: modified))
        }
        return files
    }
}

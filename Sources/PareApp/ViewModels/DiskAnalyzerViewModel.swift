import Foundation
import AppKit
import PareCore

@MainActor
final class DiskAnalyzerViewModel: ObservableObject {

    // MARK: - DiskNode

    struct DiskNode: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let sizeBytes: Int64
        let isDirectory: Bool
        let children: [DiskNode]
        /// Share of the parent node's total size (0.0–1.0).
        let shareOfParent: Double

        /// Non-nil triggers an expansion arrow in List(children:).
        var expandableChildren: [DiskNode]? {
            guard isDirectory, !children.isEmpty else { return nil }
            return children
        }
    }

    // MARK: - Published state

    @Published private(set) var rootURL: URL?
    @Published private(set) var rootNode: DiskNode?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    // MARK: - Public interface

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to analyze"
        panel.prompt = "Analyze"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startAnalysis(url: url)
    }

    func refresh() {
        guard let url = rootURL else { return }
        startAnalysis(url: url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }

    func moveToTrash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refresh()
        } catch {
            errorMessage = "Could not move to Trash: \(error.localizedDescription)"
        }
    }

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Private

    private func startAnalysis(url: URL) {
        rootURL = url
        isLoading = true
        rootNode = nil
        errorMessage = nil
        scanTask?.cancel()
        scanTask = Task {
            let node = await buildNode(url: url, depth: 0, shareOfParent: 1.0)
            guard !Task.isCancelled else { return }
            isLoading = false
            rootNode = node
        }
    }

    private func buildNode(url: URL, depth: Int, shareOfParent: Double) async -> DiskNode {
        let name = url.lastPathComponent

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else {
            let size = fileSizeBytes(url: url)
            return DiskNode(url: url, name: name, sizeBytes: size, isDirectory: false, children: [], shareOfParent: shareOfParent)
        }

        // Beyond depth 4, report directory size without recursing.
        guard depth < 4 else {
            let size = FileSystemUtils.directorySize(url: url)
            return DiskNode(url: url, name: name, sizeBytes: size, isDirectory: true, children: [], shareOfParent: shareOfParent)
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            let size = FileSystemUtils.directorySize(url: url)
            return DiskNode(url: url, name: name, sizeBytes: size, isDirectory: true, children: [], shareOfParent: shareOfParent)
        }

        // Build child nodes (size computed per child).
        var childNodes: [DiskNode] = []
        for childURL in contents {
            if Task.isCancelled { break }
            // Placeholder share; will be recalculated after we know all sizes.
            let child = await buildNode(url: childURL, depth: depth + 1, shareOfParent: 0)
            childNodes.append(child)
        }

        // Sort by size descending; keep top 50 to avoid overwhelming the UI.
        childNodes.sort { $0.sizeBytes > $1.sizeBytes }
        if childNodes.count > 50 {
            childNodes = Array(childNodes.prefix(50))
        }

        let totalSize = childNodes.reduce(0) { $0 + $1.sizeBytes }

        // Recompute shareOfParent for each child now that we know the total.
        if totalSize > 0 {
            childNodes = childNodes.map { child in
                DiskNode(
                    url: child.url,
                    name: child.name,
                    sizeBytes: child.sizeBytes,
                    isDirectory: child.isDirectory,
                    children: child.children,
                    shareOfParent: Double(child.sizeBytes) / Double(totalSize)
                )
            }
        }

        return DiskNode(url: url, name: name, sizeBytes: totalSize, isDirectory: true, children: childNodes, shareOfParent: shareOfParent)
    }

    private func fileSizeBytes(url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }
}

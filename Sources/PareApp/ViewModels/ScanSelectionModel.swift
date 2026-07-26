import Foundation
import PareCore

enum CategorySelectState: Equatable {
    case none, partial, all
}

/// Value-type selection domain for the scan dashboard: selected folder ids +
/// individual paths, cached totals, tri-state helpers, and browser expansion
/// state (absorbed from view-local `@State`).
///
/// Owned by `ScanDashboardViewModel` as a single `@Published` property so every
/// mutation publishes exactly once.
struct ScanSelectionModel {
    /// Folder-level selection (dozens of ids — never tens of thousands of file paths).
    private(set) var selectedFolderIds: Set<String> = []
    /// Optional individual paths (Largest items only — small, ≤ ~40).
    private(set) var selectedPaths: Set<String> = []
    /// Cached selection totals from folder meta + individual paths.
    private(set) var selectedCount: Int = 0
    private(set) var selectedBytes: Int64 = 0
    private(set) var selectedReviewCount: Int = 0

    /// Expanded categories in Browse by category (folder list only — no per-file children).
    var expandedCategories: Set<String> = []
    /// Expanded tool groups (e.g. Developer Package Caches → JetBrains).
    var expandedToolGroups: Set<String> = []

    /// Per-path size/risk for individual selections (rebuilt per scan).
    struct PathMeta: Sendable {
        let bytes: Int64
        let riskLevel: RiskLevel
    }

    // Aggregate-derived context (rebuilt per scan / exclusion).
    private var folderIdByPath: [String: String] = [:]
    private var metaByFolderId: [String: FolderMeta] = [:]
    private var safeFolderIds: Set<String> = []
    private var safeFolderIdsByCategory: [ScanCategory: Set<String>] = [:]
    private var pathMetaByPath: [String: PathMeta] = [:]

    // MARK: - Context lifecycle

    /// Swap in a fresh aggregate. When `resetToSafeSelection` is true the selection
    /// becomes "all SAFE folders" (post-scan default); otherwise the existing
    /// selection is intersected with the new context (post-exclusion rebuild).
    mutating func updateContext(
        aggregate: FolderAggregate,
        findingsByPath: [String: ScanFinding],
        resetToSafeSelection: Bool
    ) {
        folderIdByPath = aggregate.folderIdByPath
        metaByFolderId = aggregate.metaByFolderId
        safeFolderIds = aggregate.safeFolderIds
        safeFolderIdsByCategory = aggregate.safeFolderIdsByCategory
        pathMetaByPath = findingsByPath.mapValues {
            PathMeta(bytes: $0.sizeBytes, riskLevel: $0.riskLevel)
        }
        if resetToSafeSelection {
            // Default: all SAFE *folders* (dozens of ids) — never 25k file paths.
            selectedFolderIds = aggregate.safeFolderIds
            selectedPaths = []
        } else {
            selectedFolderIds = selectedFolderIds.intersection(Set(metaByFolderId.keys))
            selectedPaths = Set(selectedPaths.filter { pathMetaByPath[$0] != nil })
        }
        recomputeMetrics()
    }

    // MARK: - Queries

    func isSelected(path: String) -> Bool {
        if selectedPaths.contains(path) { return true }
        if let folderId = folderIdByPath[path], selectedFolderIds.contains(folderId) {
            return true
        }
        return false
    }

    func isSelectable(path: String) -> Bool {
        guard let meta = pathMetaByPath[path] else { return false }
        return meta.riskLevel != .advanced
    }

    func riskLevel(for path: String) -> RiskLevel? {
        pathMetaByPath[path]?.riskLevel
    }

    func folderSelectionState(_ row: CategoryFolderRow) -> CategorySelectState {
        guard row.isSelectable else { return .none }
        return selectedFolderIds.contains(row.id) ? .all : .none
    }

    /// Tri-state over an arbitrary folder-id set (tool group or category).
    func selectionState(of folderIds: Set<String>) -> CategorySelectState {
        guard !folderIds.isEmpty else { return .none }
        let hit = folderIds.intersection(selectedFolderIds).count
        if hit == 0 { return .none }
        if hit == folderIds.count { return .all }
        return .partial
    }

    func safeFolderIds(in category: ScanCategory) -> Set<String> {
        safeFolderIdsByCategory[category] ?? []
    }

    // MARK: - Mutations

    /// Largest-items path toggle. Never materializes folder children into `selectedPaths`.
    mutating func togglePath(_ path: String) {
        guard isSelectable(path: path) else { return }
        // If this path is covered by a selected folder, deselect the folder (O(1)).
        if let folderId = folderIdByPath[path], selectedFolderIds.contains(folderId) {
            selectedFolderIds.remove(folderId)
            recomputeMetrics()
            return
        }
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
        recomputeMetrics()
    }

    /// Toggle one rolled-up folder — O(1) set membership, no path expansion.
    mutating func toggleFolder(_ row: CategoryFolderRow) {
        guard row.isSelectable else { return }
        if selectedFolderIds.contains(row.id) {
            selectedFolderIds.remove(row.id)
        } else {
            selectedFolderIds.insert(row.id)
        }
        recomputeMetrics()
    }

    /// Toggle a whole folder-id set: all-selected → subtract, otherwise → union.
    mutating func toggleFolderIds(_ folderIds: Set<String>) {
        guard !folderIds.isEmpty else { return }
        if folderIds.isSubset(of: selectedFolderIds) {
            selectedFolderIds.subtract(folderIds)
        } else {
            selectedFolderIds.formUnion(folderIds)
        }
        recomputeMetrics()
    }

    mutating func selectAllSafe() {
        selectedFolderIds = safeFolderIds
        // Drop individual paths that are already covered by safe folders.
        selectedPaths = Set(selectedPaths.filter { path in
            guard let fid = folderIdByPath[path] else { return true }
            return !safeFolderIds.contains(fid)
        })
        recomputeMetrics()
    }

    mutating func clear() {
        selectedFolderIds = []
        selectedPaths = []
        selectedCount = 0
        selectedBytes = 0
        selectedReviewCount = 0
    }

    mutating func removePath(_ path: String) {
        selectedPaths.remove(path)
    }

    // MARK: - Private

    /// O(selected folders + individual paths) — never scans all findings.
    private mutating func recomputeMetrics() {
        var count = 0
        var bytes: Int64 = 0
        var review = 0
        for id in selectedFolderIds {
            guard let meta = metaByFolderId[id] else { continue }
            count += meta.itemCount
            bytes += meta.bytes
            review += meta.reviewCount
        }
        for path in selectedPaths {
            // Skip if already counted via its folder.
            if let fid = folderIdByPath[path], selectedFolderIds.contains(fid) { continue }
            guard let meta = pathMetaByPath[path], meta.riskLevel != .advanced else { continue }
            count += 1
            bytes += meta.bytes
            if meta.riskLevel == .review { review += 1 }
        }
        selectedCount = count
        selectedBytes = bytes
        selectedReviewCount = review
    }
}

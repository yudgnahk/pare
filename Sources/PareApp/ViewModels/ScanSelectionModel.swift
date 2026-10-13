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
    /// Selected paths that were written to recently, for the confirmation sheet.
    private(set) var selectedHotCount: Int = 0
    /// Paths labelled hot this scan: folder coverage and bulk actions skip them, only their own row ticks them.
    private(set) var hotPaths: Set<String> = []

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
    private var hotPathsByFolderId: [String: Set<String>] = [:]
    /// Rows the user clicked this scan; a label arriving later keeps their choice.
    private var touchedPaths: Set<String> = []
    private var touchedFolderIds: Set<String> = []

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
            hotPaths = []
            touchedPaths = []
            touchedFolderIds = []
        } else {
            selectedFolderIds = selectedFolderIds.intersection(Set(metaByFolderId.keys))
            selectedPaths = Set(selectedPaths.filter { pathMetaByPath[$0] != nil })
            hotPaths = hotPaths.filter { pathMetaByPath[$0] != nil }
            touchedPaths = touchedPaths.filter { pathMetaByPath[$0] != nil }
            touchedFolderIds = touchedFolderIds.intersection(Set(metaByFolderId.keys))
        }
        rebuildHotIndex()
        recomputeMetrics()
    }

    /// Unticks newly hot rows the user has not clicked; a clicked row keeps whatever the user chose.
    mutating func applyHotPaths(_ paths: Set<String>) {
        let known = paths.filter { pathMetaByPath[$0] != nil }
        for path in known.subtracting(hotPaths) {
            if isTouched(path), isSelected(path: path) {
                selectedPaths.insert(path)
            } else if !isTouched(path) {
                selectedPaths.remove(path)
            }
        }
        hotPaths.formUnion(known)
        rebuildHotIndex()
        recomputeMetrics()
    }

    // MARK: - Queries

    func isSelected(path: String) -> Bool {
        if selectedPaths.contains(path) { return true }
        if !hotPaths.contains(path), let folderId = folderIdByPath[path], selectedFolderIds.contains(folderId) {
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
        return folderState(row.id)
    }

    /// Tri-state over an arbitrary folder-id set (tool group or category); an unticked hot row keeps it below `.all`.
    func selectionState(of folderIds: Set<String>) -> CategorySelectState {
        let states = Set(folderIds.map(folderState))
        if states.isEmpty || states == [.none] { return .none }
        return states == [.all] ? .all : .partial
    }

    func safeFolderIds(in category: ScanCategory) -> Set<String> {
        safeFolderIdsByCategory[category] ?? []
    }

    // MARK: - Mutations

    /// Largest-items path toggle. Never materializes folder children into `selectedPaths`.
    mutating func togglePath(_ path: String) {
        guard isSelectable(path: path) else { return }
        touchedPaths.insert(path)
        // If this path is covered by a selected folder, deselect the folder (O(1)).
        if !hotPaths.contains(path), let folderId = folderIdByPath[path], selectedFolderIds.contains(folderId) {
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
    /// A row whose members are all hot is itself the hot row, so ticking it ticks them; otherwise hot members stay out.
    mutating func toggleFolder(_ row: CategoryFolderRow) {
        guard row.isSelectable else { return }
        touchedFolderIds.insert(row.id)
        let hot = hotPathsByFolderId[row.id] ?? []
        if isFullyHot(row.id) {
            if hot.isSubset(of: selectedPaths) {
                selectedPaths.subtract(hot)
            } else {
                selectedPaths.formUnion(hot)
            }
        } else if selectedFolderIds.contains(row.id) {
            selectedFolderIds.remove(row.id)
            selectedPaths.subtract(hot)
        } else {
            selectedFolderIds.insert(row.id)
        }
        recomputeMetrics()
    }

    /// Toggle a whole folder-id set: every non-hot folder ticked → subtract (hot too), otherwise → union; never ticks a hot path.
    mutating func toggleFolderIds(_ folderIds: Set<String>) {
        let bulk = bulkFolderIds(folderIds)
        if bulk.isSubset(of: selectedFolderIds) {
            selectedFolderIds.subtract(bulk)
            for id in folderIds { selectedPaths.subtract(hotPathsByFolderId[id] ?? []) }
        } else {
            selectedFolderIds.formUnion(bulk)
        }
        recomputeMetrics()
    }

    mutating func selectAllSafe() {
        selectedFolderIds = bulkFolderIds(safeFolderIds)
        // Drop individual paths that are already covered by safe folders.
        selectedPaths = Set(selectedPaths.filter { path in
            guard !hotPaths.contains(path), let fid = folderIdByPath[path] else { return true }
            return !selectedFolderIds.contains(fid)
        })
        recomputeMetrics()
    }

    /// Paths a clean of the current selection would touch; folders expand without their hot members.
    func selectedFindingPaths(pathsByFolderId: [String: [String]]) -> Set<String> {
        var paths = Set<String>()
        for id in selectedFolderIds {
            if let members = pathsByFolderId[id] { paths.formUnion(members) }
        }
        paths.subtract(hotPaths)
        return paths.union(selectedPaths)
    }

    mutating func clear() {
        selectedFolderIds = []
        selectedPaths = []
        selectedCount = 0
        selectedBytes = 0
        selectedReviewCount = 0
        selectedHotCount = 0
    }

    mutating func removePath(_ path: String) {
        selectedPaths.remove(path)
    }

    // MARK: - Private

    private func isTouched(_ path: String) -> Bool {
        if touchedPaths.contains(path) { return true }
        return folderIdByPath[path].map(touchedFolderIds.contains) ?? false
    }

    private func folderState(_ folderId: String) -> CategorySelectState {
        let hot = hotPathsByFolderId[folderId] ?? []
        let hotSelected = hot.intersection(selectedPaths).count
        if isFullyHot(folderId) {
            if hotSelected == 0 { return .none }
            return hotSelected == hot.count ? .all : .partial
        }
        if selectedFolderIds.contains(folderId) { return hotSelected == hot.count ? .all : .partial }
        return hotSelected > 0 ? .partial : .none
    }

    private func isFullyHot(_ folderId: String) -> Bool {
        guard let hot = hotPathsByFolderId[folderId], let meta = metaByFolderId[folderId] else { return false }
        return hot.count >= meta.itemCount
    }

    private func bulkFolderIds(_ folderIds: Set<String>) -> Set<String> {
        folderIds.filter { !isFullyHot($0) }
    }

    private mutating func rebuildHotIndex() {
        var byFolder: [String: Set<String>] = [:]
        for path in hotPaths {
            if let fid = folderIdByPath[path] { byFolder[fid, default: []].insert(path) }
        }
        hotPathsByFolderId = byFolder
        selectedFolderIds = bulkFolderIds(selectedFolderIds)
    }

    /// O(selected folders + individual paths + hot paths) — never scans all findings.
    private mutating func recomputeMetrics() {
        var count = 0
        var bytes: Int64 = 0
        var review = 0
        for id in selectedFolderIds {
            guard let meta = metaByFolderId[id] else { continue }
            count += meta.itemCount
            bytes += meta.bytes
            review += meta.reviewCount
            // Hot members are never covered by their folder.
            for path in hotPathsByFolderId[id] ?? [] {
                guard let hot = pathMetaByPath[path] else { continue }
                count -= 1
                bytes -= hot.bytes
                if hot.riskLevel == .review { review -= 1 }
            }
        }
        var hotCount = 0
        for path in selectedPaths {
            // Skip if already counted via its folder.
            if !hotPaths.contains(path), let fid = folderIdByPath[path], selectedFolderIds.contains(fid) { continue }
            guard let meta = pathMetaByPath[path], meta.riskLevel != .advanced else { continue }
            count += 1
            bytes += meta.bytes
            if meta.riskLevel == .review { review += 1 }
            if hotPaths.contains(path) { hotCount += 1 }
        }
        selectedCount = count
        selectedBytes = bytes
        selectedReviewCount = review
        selectedHotCount = hotCount
    }
}

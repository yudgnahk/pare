import Foundation
import SwiftUI
import AppKit
import PareCore

@MainActor
final class ScanDashboardViewModel: ObservableObject {
    enum ScanState: Equatable {
        case idle
        case scanning
        case success
    }

    struct SummaryItem: Identifiable {
        let id: String
        let category: ScanCategory
        let reclaimableBytes: Int64
        let fileCount: Int
        /// Aggregated folder rows shown in the browser (not raw file count).
        let folderCount: Int

        init(summary: ScanCategorySummary, folderCount: Int = 0) {
            self.id = summary.category.rawValue
            self.category = summary.category
            self.reclaimableBytes = summary.reclaimableBytes
            self.fileCount = summary.fileCount
            self.folderCount = folderCount
        }
    }

    struct FindingItem: Identifiable {
        let id: String
        let path: String
        let sizeBytes: Int64
        let category: ScanCategory
        let riskLevel: RiskLevel
        let reason: String
        let confidence: Double
        let lastUsed: Date?

        init(finding: ScanFinding) {
            self.id = "\(finding.path)-\(finding.sizeBytes)"
            self.path = finding.path
            self.sizeBytes = finding.sizeBytes
            self.category = finding.category
            self.riskLevel = finding.riskLevel
            self.reason = finding.reason
            self.confidence = finding.confidence
            self.lastUsed = finding.lastUsed
        }
    }

    struct CategoryLargeFiles: Identifiable {
        let id: String
        let category: ScanCategory
        let totalBytes: Int64
        let files: [FindingItem]
    }

    /// Lightweight folder row for the category browser.
    /// **No path lists** — underlying file paths stay private so SwiftUI never holds 10k+ strings per row.
    struct CategoryFolderRow: Identifiable, Equatable {
        let id: String
        /// Path used for Finder reveal (the rolled-up folder).
        let folderPath: String
        /// Full user-visible path (`~/…`).
        let displayPath: String
        let totalBytes: Int64
        /// Number of underlying scan findings rolled into this folder.
        let itemCount: Int
        /// Worst risk among members (safe < review < advanced).
        let riskLevel: RiskLevel
        let isSelectable: Bool
        /// Tool/app label (same as donut chart) for nested grouping.
        let toolName: String

        var isSafeFolder: Bool { riskLevel == .safe }
    }

    /// Intermediate browser level: category → **tool** (JetBrains, Package Managers, …) → folders.
    struct CategoryToolGroup: Identifiable, Equatable {
        let id: String
        let category: ScanCategory
        let toolName: String
        let totalBytes: Int64
        let folderCount: Int
        let itemCount: Int
        let riskLevel: RiskLevel
        /// Folder row ids in this tool group (for bulk select).
        let folderIds: Set<String>
        let isSelectable: Bool

        var isSafeGroup: Bool { riskLevel == .safe }
    }

    /// Precomputed size/count for a folder id (selection metrics without expanding paths).
    private struct FolderMeta {
        let itemCount: Int
        let bytes: Int64
        let reviewCount: Int
        let isSafe: Bool
    }

    /// Result of rolling findings into folder rows + private path maps.
    private struct FolderAggregate {
        var rowsByCategory: [ScanCategory: [CategoryFolderRow]] = [:]
        var toolGroupsByCategory: [ScanCategory: [CategoryToolGroup]] = [:]
        /// Private: folder id → finding paths (only used at clean time).
        var pathsByFolderId: [String: [String]] = [:]
        var folderIdByPath: [String: String] = [:]
        var metaByFolderId: [String: FolderMeta] = [:]
        var safeFolderIds: Set<String> = []
        var safeFolderIdsByCategory: [ScanCategory: Set<String>] = [:]
    }

    struct ToolRollupItem: Identifiable {
        let id: String
        let app: String
        let totalBytes: Int64
        let fileCount: Int
        let share: Double

        init(rollup: AppRollup, total: Int64) {
            self.id = rollup.app
            self.app = rollup.app
            self.totalBytes = rollup.totalBytes
            self.fileCount = rollup.fileCount
            self.share = total > 0 ? Double(rollup.totalBytes) / Double(total) : 0
        }
    }

    // MARK: - Cleanup state

    enum CleanupState: Equatable {
        case idle
        case confirming
        case cleaning
        case done(bytesFreed: Int64, skippedCount: Int)
        case undoing
        case undone(restoredCount: Int)
        case error(String)
    }

    @Published private(set) var state: ScanState = .idle
    @Published private(set) var totalReclaimableBytes: Int64 = 0
    @Published private(set) var summaries: [SummaryItem] = []
    @Published private(set) var topFindings: [FindingItem] = []
    @Published private(set) var largeFilesByCategory: [CategoryLargeFiles] = []
    @Published private(set) var perToolRollups: [ToolRollupItem] = []
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var revealFeedback: String?
    @Published var resultsVisible = false

    // Cleanup-specific state
    @Published private(set) var cleanupState: CleanupState = .idle
    @Published var showCleanConfirmation = false
    @Published var showDeepCleanConfirmation = false
    @Published var showSelectedCleanConfirmation = false
    /// Folder-level selection (dozens of ids — never tens of thousands of file paths).
    @Published private(set) var selectedFolderIds: Set<String> = []
    /// Optional individual paths (Largest items only — small, ≤ ~40).
    @Published private(set) var selectedPaths: Set<String> = []
    /// Cached selection totals from folder meta + individual paths.
    @Published private(set) var selectedCandidatesCount: Int = 0
    @Published private(set) var selectedCandidatesBytes: Int64 = 0
    @Published private(set) var selectedReviewCount: Int = 0
    /// Pre-aggregated **lightweight** folder rows per category (built once per scan).
    @Published private(set) var categoryFolderRows: [ScanCategory: [CategoryFolderRow]] = [:]
    /// Tool/app groups under a category (e.g. Developer Package Caches → JetBrains, Package Managers).
    @Published private(set) var categoryToolGroups: [ScanCategory: [CategoryToolGroup]] = [:]
    /// Scan progress for 3-step hero (1...3) and status line.
    @Published private(set) var scanStep: Int = 1
    @Published private(set) var scanStepTitle: String = ""
    @Published private(set) var scanRulesCompleted: Int = 0
    @Published private(set) var scanRulesTotal: Int = 0
    /// Heuristic Full Disk Access status for coaching banners.
    @Published private(set) var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    /// Show FDA coaching when access looks missing and the user has not dismissed the card.
    @Published private(set) var showFullDiskAccessBanner: Bool = false
    /// After a successful scan with ~0 reclaimable bytes, coach the user on next steps.
    @Published private(set) var showEmptyScanCoaching: Bool = false
    /// Most recent transaction, used to offer undo.
    private var lastTransaction: CleanupTransaction?
    private static let fdaBannerDismissedKey = "pare.fdaCoaching.dismissed"
    /// Raw findings kept after scan so cleanup can reference them.
    private var latestFindings: [ScanFinding] = []
    /// O(1) path → finding lookup (not published).
    private var findingsByPath: [String: ScanFinding] = [:]
    /// Private path expansion maps — never exposed to SwiftUI views.
    private var pathsByFolderId: [String: [String]] = [:]
    private var folderIdByPath: [String: String] = [:]
    private var folderMetaById: [String: FolderMeta] = [:]
    private var safeFolderIds: Set<String> = []
    private var safeFolderIdsByCategory: [ScanCategory: Set<String>] = [:]
    private let engine = CleanupEngine()
    private let scanCache = ScanMetadataCache()
    /// The running scan task — kept so we can cancel it on demand.
    private var scanTask: Task<Void, Never>?

    /// Hard cap on folder rows rendered per category (largest first).
    /// Higher than before so monorepos (many per-project `.next`/`target`) list as folders, not one root.
    static let maxFolderRowsPerCategory = 120

    var isScanning: Bool {
        state == .scanning
    }

    var isCleaning: Bool {
        if case .cleaning = cleanupState { return true }
        return false
    }

    var isUndoing: Bool {
        if case .undoing = cleanupState { return true }
        return false
    }

    var canUndo: Bool {
        if let tx = lastTransaction, !tx.isDryRun, !tx.items.isEmpty { return true }
        return false
    }

    /// Number of safe-risk findings from the last scan (Quick Clean candidates).
    var quickCleanCandidatesCount: Int {
        latestFindings.filter { $0.riskLevel == .safe }.count
    }

    var quickCleanCandidatesBytes: Int64 {
        latestFindings.filter { $0.riskLevel == .safe }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Deep Clean candidates: safe + review-risk findings.
    var deepCleanCandidatesCount: Int {
        latestFindings.filter { $0.riskLevel == .safe || $0.riskLevel == .review }.count
    }

    var deepCleanCandidatesBytes: Int64 {
        latestFindings.filter { $0.riskLevel == .safe || $0.riskLevel == .review }.reduce(0) { $0 + $1.sizeBytes }
    }

    var reviewRiskCandidatesCount: Int {
        latestFindings.filter { $0.riskLevel == .review }.count
    }

    /// True when a quick clean is large enough that Spotlight may busy-update for a while.
    var quickCleanMayTriggerSpotlightWork: Bool {
        ScanPolicy.shouldWarnAboutSpotlightIndexing(
            itemCount: quickCleanCandidatesCount,
            totalBytes: quickCleanCandidatesBytes
        )
    }

    var deepCleanMayTriggerSpotlightWork: Bool {
        ScanPolicy.shouldWarnAboutSpotlightIndexing(
            itemCount: deepCleanCandidatesCount,
            totalBytes: deepCleanCandidatesBytes
        )
    }

    var selectedCleanMayTriggerSpotlightWork: Bool {
        ScanPolicy.shouldWarnAboutSpotlightIndexing(
            itemCount: selectedCandidatesCount,
            totalBytes: selectedCandidatesBytes
        )
    }

    func isSelected(path: String) -> Bool {
        if selectedPaths.contains(path) { return true }
        if let folderId = folderIdByPath[path], selectedFolderIds.contains(folderId) {
            return true
        }
        return false
    }

    func isSelectable(path: String) -> Bool {
        guard let finding = findingsByPath[path] else { return false }
        return finding.riskLevel != .advanced
    }

    func riskLevel(for path: String) -> RiskLevel? {
        findingsByPath[path]?.riskLevel
    }

    /// Largest-items path toggle. Never materializes folder children into `selectedPaths`.
    func toggleSelection(path: String) {
        guard isSelectable(path: path) else { return }
        // If this path is covered by a selected folder, deselect the folder (O(1)).
        if let folderId = folderIdByPath[path], selectedFolderIds.contains(folderId) {
            var folders = selectedFolderIds
            folders.remove(folderId)
            selectedFolderIds = folders
            recomputeSelectionMetrics()
            return
        }
        var paths = selectedPaths
        if paths.contains(path) {
            paths.remove(path)
        } else {
            paths.insert(path)
        }
        selectedPaths = paths
        recomputeSelectionMetrics()
    }

    /// Toggle one rolled-up folder — O(1) set membership, no path expansion.
    func toggleFolder(_ row: CategoryFolderRow) {
        guard row.isSelectable else { return }
        // Reassign so `@Published` fires (in-place Set mutation does not).
        var next = selectedFolderIds
        if next.contains(row.id) {
            next.remove(row.id)
        } else {
            next.insert(row.id)
        }
        selectedFolderIds = next
        recomputeSelectionMetrics()
    }

    func folderSelectionState(_ row: CategoryFolderRow) -> CategorySelectState {
        guard row.isSelectable else { return .none }
        return selectedFolderIds.contains(row.id) ? .all : .none
    }

    /// Toggle every folder under a tool group (e.g. all JetBrains package-cache folders).
    func toggleToolGroup(_ group: CategoryToolGroup) {
        guard group.isSelectable, !group.folderIds.isEmpty else { return }
        var next = selectedFolderIds
        if group.folderIds.isSubset(of: next) {
            next.subtract(group.folderIds)
        } else {
            next.formUnion(group.folderIds)
        }
        selectedFolderIds = next
        recomputeSelectionMetrics()
    }

    func toolGroupSelectionState(_ group: CategoryToolGroup) -> CategorySelectState {
        guard !group.folderIds.isEmpty else { return .none }
        let hit = group.folderIds.intersection(selectedFolderIds).count
        if hit == 0 { return .none }
        if hit == group.folderIds.count { return .all }
        return .partial
    }

    func selectAllSafe() {
        selectedFolderIds = safeFolderIds
        // Drop individual paths that are already covered by safe folders.
        selectedPaths = Set(selectedPaths.filter { path in
            guard let fid = folderIdByPath[path] else { return true }
            return !safeFolderIds.contains(fid)
        })
        recomputeSelectionMetrics()
    }

    func clearSelection() {
        selectedFolderIds = []
        selectedPaths = []
        selectedCandidatesCount = 0
        selectedCandidatesBytes = 0
        selectedReviewCount = 0
    }

    func toggleCategory(_ category: ScanCategory, includeReview: Bool = false) {
        let folderIds: Set<String>
        if includeReview {
            folderIds = Set((categoryFolderRows[category] ?? []).filter(\.isSelectable).map(\.id))
        } else {
            folderIds = safeFolderIdsByCategory[category] ?? []
        }
        guard !folderIds.isEmpty else { return }
        var next = selectedFolderIds
        if folderIds.isSubset(of: next) {
            next.subtract(folderIds)
        } else {
            next.formUnion(folderIds)
        }
        selectedFolderIds = next
        recomputeSelectionMetrics()
    }

    func categorySelectionState(_ category: ScanCategory) -> CategorySelectState {
        let ids = safeFolderIdsByCategory[category] ?? []
        guard !ids.isEmpty else { return .none }
        let hit = ids.intersection(selectedFolderIds).count
        if hit == 0 { return .none }
        if hit == ids.count { return .all }
        return .partial
    }

    enum CategorySelectState: Equatable {
        case none, partial, all
    }

    /// O(selected folders + individual paths) — never scans all findings.
    private func recomputeSelectionMetrics() {
        var count = 0
        var bytes: Int64 = 0
        var review = 0
        for id in selectedFolderIds {
            guard let meta = folderMetaById[id] else { continue }
            count += meta.itemCount
            bytes += meta.bytes
            review += meta.reviewCount
        }
        for path in selectedPaths {
            // Skip if already counted via its folder.
            if let fid = folderIdByPath[path], selectedFolderIds.contains(fid) { continue }
            guard let finding = findingsByPath[path], finding.riskLevel != .advanced else { continue }
            count += 1
            bytes += finding.sizeBytes
            if finding.riskLevel == .review { review += 1 }
        }
        selectedCandidatesCount = count
        selectedCandidatesBytes = bytes
        selectedReviewCount = review
    }

    /// Expand folder ids → findings only when cleaning (not during scroll/UI).
    private func selectedFindingsForClean() -> [ScanFinding] {
        var pathSet = Set<String>()
        pathSet.reserveCapacity(min(selectedCandidatesCount, 65_536))
        for id in selectedFolderIds {
            if let paths = pathsByFolderId[id] {
                pathSet.formUnion(paths)
            }
        }
        pathSet.formUnion(selectedPaths)
        return pathSet.compactMap { findingsByPath[$0] }.filter { $0.riskLevel != .advanced }
    }

    // MARK: - Category browser (folder-only) + largest items

    func folderRows(for category: ScanCategory) -> [CategoryFolderRow] {
        categoryFolderRows[category] ?? []
    }

    func toolGroups(for category: ScanCategory) -> [CategoryToolGroup] {
        categoryToolGroups[category] ?? []
    }

    /// Categories that show tool children first (same labels as the donut chart).
    func usesToolGrouping(for category: ScanCategory) -> Bool {
        switch category {
        case .developerPackageCaches, .browserCaches, .aiToolCaches, .userCaches:
            return true
        default:
            // Use tool groups when we already built 2+ named tools for this category.
            return (categoryToolGroups[category]?.count ?? 0) >= 2
        }
    }

    func folderRows(for group: CategoryToolGroup) -> [CategoryFolderRow] {
        let rows = categoryFolderRows[group.category] ?? []
        return rows.filter { group.folderIds.contains($0.id) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Unique findings for the merged “Largest items” section (SAFE then REVIEW, by size).
    var largestItems: [FindingItem] {
        Array(topFindings.prefix(40))
    }

    /// SAFE items in largest list (for sectioned UI).
    var largestSafeItems: [FindingItem] {
        largestItems.filter { $0.riskLevel == .safe }
    }

    /// REVIEW items in largest list (for sectioned UI).
    var largestReviewItems: [FindingItem] {
        largestItems.filter { $0.riskLevel == .review }
    }

    /// Largest reclaimable findings by size, then ordered SAFE group → REVIEW group
    /// (each group still size-sorted) so both risk tiers appear when they make the cut.
    static func largestItemsSorted(from findings: [ScanFinding], limit: Int) -> [FindingItem] {
        let reclaimable = findings.filter { $0.riskLevel != .advanced }
        let top = reclaimable.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit)
        let safe = top.filter { $0.riskLevel == .safe }
        let review = top.filter { $0.riskLevel == .review }
        return (safe + review).map(FindingItem.init(finding:))
    }

    func abbreviatedPath(_ path: String) -> String {
        Self.abbreviatePath(path)
    }

    private static func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Collapse only **known deep caches** into one row (npm, browser, Library/Caches).
    ///
    /// Project trees are different: a monorepo root like
    /// `/Users/…/Projects/…/akzonobel` is **not** reclaimable as a whole just because
    /// a few child apps have `.next` / `target` / `.cache`. Those claimable folders
    /// must stay separate rows with their full paths — never merge into the monorepo root.
    static func rollupFolderPath(for path: String) -> String {
        let parts = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return path }

        // Package manager / tool cache roots — one row per root, not per blob.
        let singleSegmentRoots = [
            "_cacache", "_npx", "Yarn", "pnpm", "CocoaPods", "org.swift.swiftpm",
            "pip", "opencode", "Homebrew", "electron", "typescript",
        ]
        for root in singleSegmentRoots {
            if let i = parts.firstIndex(of: root) {
                return "/" + parts[0...i].joined(separator: "/")
            }
        }

        // Cargo / Gradle / Maven trees
        if let i = parts.firstIndex(of: "registry"), i > 0, parts[i - 1] == ".cargo" {
            return "/" + parts[0...i].joined(separator: "/")
        }
        if let i = parts.firstIndex(of: "git"), i > 0, parts[i - 1] == ".cargo" {
            return "/" + parts[0...i].joined(separator: "/")
        }
        if let i = parts.firstIndex(of: "caches"), i > 0, parts[i - 1] == ".gradle" {
            return "/" + parts[0...i].joined(separator: "/")
        }
        if let i = parts.firstIndex(of: "repository"), i > 0, parts[i - 1] == ".m2" {
            return "/" + parts[0...i].joined(separator: "/")
        }

        // ~/Library/Caches/<App> → stop at app name
        if let i = parts.firstIndex(of: "Caches"),
           i > 0, parts[i - 1] == "Library",
           i + 1 < parts.count {
            return "/" + parts[0...(i + 1)].joined(separator: "/")
        }

        // Browser Application Support profile trees — stop at profile (Default, Profile 1, …)
        let browserMarkers = [
            "Google", "Chromium", "BraveSoftware", "Microsoft Edge",
            "com.operasoftware.Opera", "Arc", "Firefox", "com.apple.Safari",
        ]
        for marker in browserMarkers {
            if let i = parts.firstIndex(of: marker) {
                if let def = parts.firstIndex(of: "Default"), def > i {
                    return "/" + parts[0...def].joined(separator: "/")
                }
                if let prof = parts.firstIndex(of: "Profiles"), prof + 1 < parts.count, prof > i {
                    return "/" + parts[0...(prof + 1)].joined(separator: "/")
                }
                let end = min(i + 2, parts.count - 1)
                return "/" + parts[0...end].joined(separator: "/")
            }
        }

        // Project-local reclaimable folders (.next, target, .cache, dist, …):
        // stop at the artifact segment so each project under a monorepo is its own row.
        // Example: …/akzonobel/app-a/.next  →  that path, NOT …/akzonobel
        let artifactNames = ScanPolicy.projectLocalArtifactDirectoryNames
        if let i = parts.lastIndex(where: { artifactNames.contains($0.lowercased()) }) {
            return "/" + parts[0...i].joined(separator: "/")
        }

        // Xcode / IDE style build products often appear as full directory findings.
        let buildProductNames: Set<String> = [
            "deriveddata", "archives", "ios device support", "watchos device support",
            "coresimulator", "modulecache.noindex", "documentationcache",
        ]
        if let i = parts.lastIndex(where: { buildProductNames.contains($0.lowercased()) }) {
            return "/" + parts[0...i].joined(separator: "/")
        }

        // Default: keep the finding path (or its parent if the leaf looks like a file).
        // Do **not** apply a shallow depth cap — that merges monorepo children into the root
        // and falsely presents a large tree as “6 items”.
        let last = parts[parts.count - 1]
        let lastLower = last.lowercased()
        let isArtifactLike = artifactNames.contains(lastLower) || last.hasPrefix(".")
        if !isArtifactLike, last.contains("."), parts.count > 1 {
            // e.g. …/Cache/f_000001 → parent folder
            return "/" + parts.dropLast().joined(separator: "/")
        }
        return "/" + parts.joined(separator: "/")
    }

    private static func buildFolderAggregate(from findings: [ScanFinding]) -> FolderAggregate {
        struct Acc {
            var bytes: Int64 = 0
            var count: Int = 0
            var reviewCount: Int = 0
            var paths: [String] = []
            var worstRisk: RiskLevel = .safe
        }

        var byCategory: [ScanCategory: [String: Acc]] = [:]

        for finding in findings {
            guard finding.riskLevel != .advanced else { continue }
            let folderPath = rollupFolderPath(for: finding.path)
            var catMap = byCategory[finding.category] ?? [:]
            var acc = catMap[folderPath] ?? Acc()
            acc.bytes += finding.sizeBytes
            acc.count += 1
            acc.paths.append(finding.path)
            if finding.riskLevel == .review {
                acc.reviewCount += 1
                acc.worstRisk = .review
            }
            catMap[folderPath] = acc
            byCategory[finding.category] = catMap
        }

        var aggregate = FolderAggregate()
        for (category, map) in byCategory {
            let sorted = map
                .map { folderPath, acc -> (String, Acc, String) in
                    let id = "\(category.rawValue)|\(folderPath)"
                    return (folderPath, acc, id)
                }
                .sorted { $0.1.bytes > $1.1.bytes }

            var rows: [CategoryFolderRow] = []
            rows.reserveCapacity(min(sorted.count, maxFolderRowsPerCategory))

            for (index, entry) in sorted.enumerated() {
                let (folderPath, acc, id) = entry
                // Keep path maps for every aggregate (needed for clean), but only publish top N rows.
                aggregate.pathsByFolderId[id] = acc.paths
                for p in acc.paths {
                    aggregate.folderIdByPath[p] = id
                }
                aggregate.metaByFolderId[id] = FolderMeta(
                    itemCount: acc.count,
                    bytes: acc.bytes,
                    reviewCount: acc.reviewCount,
                    isSafe: acc.worstRisk == .safe
                )
                if acc.worstRisk == .safe {
                    aggregate.safeFolderIds.insert(id)
                    aggregate.safeFolderIdsByCategory[category, default: []].insert(id)
                }
                // Majority tool among paths (same as donut chart attribution).
                let toolName = Self.dominantToolName(for: acc.paths)
                if index < maxFolderRowsPerCategory {
                    rows.append(
                        CategoryFolderRow(
                            id: id,
                            folderPath: folderPath,
                            displayPath: abbreviatePath(folderPath),
                            totalBytes: acc.bytes,
                            itemCount: acc.count,
                            riskLevel: acc.worstRisk,
                            isSelectable: !acc.paths.isEmpty,
                            toolName: toolName
                        )
                    )
                }
            }
            aggregate.rowsByCategory[category] = rows
            aggregate.toolGroupsByCategory[category] = Self.makeToolGroups(
                category: category,
                rows: rows
            )
        }
        return aggregate
    }

    private static func dominantToolName(for paths: [String]) -> String {
        guard !paths.isEmpty else { return "Other" }
        var counts: [String: Int] = [:]
        for path in paths {
            let tool = ScanReportAnnotator.sourceApp(forPath: path)
            counts[tool, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Other"
    }

    private static func makeToolGroups(
        category: ScanCategory,
        rows: [CategoryFolderRow]
    ) -> [CategoryToolGroup] {
        let grouped = Dictionary(grouping: rows, by: \.toolName)
        return grouped.map { toolName, toolRows in
            let folderIds = Set(toolRows.map(\.id))
            let totalBytes = toolRows.reduce(Int64(0)) { $0 + $1.totalBytes }
            let itemCount = toolRows.reduce(0) { $0 + $1.itemCount }
            let hasReview = toolRows.contains { $0.riskLevel == .review }
            let selectable = toolRows.contains(where: \.isSelectable)
            return CategoryToolGroup(
                id: "\(category.rawValue)|tool|\(toolName)",
                category: category,
                toolName: toolName,
                totalBytes: totalBytes,
                folderCount: toolRows.count,
                itemCount: itemCount,
                riskLevel: hasReview ? .review : .safe,
                folderIds: folderIds,
                isSelectable: selectable
            )
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    var deviceBackupFindings: [FindingItem] {
        latestFindings
            .filter { $0.category == .deviceBackups }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .map(FindingItem.init)
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        state = .idle
        resultsVisible = false
        scanRulesCompleted = 0
        scanRulesTotal = 0
        scanStepTitle = ""
        scanStep = 1
        showEmptyScanCoaching = false
        refreshPermissionCoaching()
    }

    /// Re-probe Full Disk Access and update coaching banners.
    func refreshPermissionCoaching() {
        let status = FullDiskAccessChecker.status()
        fullDiskAccessStatus = status

        if status == .granted {
            UserDefaults.standard.removeObject(forKey: Self.fdaBannerDismissedKey)
            showFullDiskAccessBanner = false
        } else if status == .denied {
            let dismissed = UserDefaults.standard.bool(forKey: Self.fdaBannerDismissedKey)
            showFullDiskAccessBanner = !dismissed
        } else {
            showFullDiskAccessBanner = false
        }

        showEmptyScanCoaching = state == .success && totalReclaimableBytes == 0
    }

    func dismissFullDiskAccessBanner() {
        UserDefaults.standard.set(true, forKey: Self.fdaBannerDismissedKey)
        showFullDiskAccessBanner = false
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access (best-effort).
    func openFullDiskAccessSettings() {
        for url in FullDiskAccessChecker.systemSettingsURLs {
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func runScan(forceRescan: Bool = false) {
        guard !isScanning else { return }

        state = .scanning
        showEmptyScanCoaching = false
        scanStep = 1
        scanStepTitle = "Scanning system & app caches…"
        scanRulesCompleted = 0
        scanRulesTotal = 0
        // Only hide results on the first scan; subsequent scans keep old results
        // visible so the screen doesn't go blank while scanning.
        if latestFindings.isEmpty {
            resultsVisible = false
        }
        let startedAt = Date()
        let cache = scanCache

        scanTask = Task(priority: .userInitiated) {
            let rules = RuleCatalog.all
            let exclusionList = (try? ExclusionStore.shared.load()) ?? .empty
            let runner = ScanRunner(exclusionList: exclusionList, cache: cache)
            let totalRules = rules.count
            await MainActor.run { self.scanRulesTotal = totalRules }

            let report = await runner.run(rules: rules, forceRescan: forceRescan) { completed, total, title in
                Task { @MainActor in
                    self.scanRulesCompleted = completed
                    self.scanRulesTotal = total
                    self.scanStepTitle = title
                    let fraction = Double(completed) / Double(max(total, 1))
                    if fraction < 0.34 {
                        self.scanStep = 1
                    } else if fraction < 0.67 {
                        self.scanStep = 2
                    } else {
                        self.scanStep = 3
                    }
                }
            }

            // If the task was cancelled, don't update UI with partial results.
            guard !Task.isCancelled else { return }

            // Heavy aggregation off the main actor so the UI doesn't freeze after scan.
            let findings = report.findings
            // Largest items: SAFE group then REVIEW group, each sorted by size.
            let sortedTopFindings = ScanDashboardViewModel.largestItemsSorted(from: findings, limit: 40)
            let largeFilesByCategory = Self.makeLargeFileGroups(from: findings)
            let toolRollups = Self.makeToolRollups(from: findings)
            let aggregate = Self.buildFolderAggregate(from: findings)
            let pathIndex = Dictionary(findings.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
            let summaries: [SummaryItem] = report.summaries.map { summary in
                SummaryItem(
                    summary: summary,
                    folderCount: aggregate.rowsByCategory[summary.category]?.count ?? 0
                )
            }
            let finishedAt = Date()

            await MainActor.run {
                scanTask = nil
                latestFindings = findings
                findingsByPath = pathIndex
                pathsByFolderId = aggregate.pathsByFolderId
                folderIdByPath = aggregate.folderIdByPath
                folderMetaById = aggregate.metaByFolderId
                safeFolderIds = aggregate.safeFolderIds
                safeFolderIdsByCategory = aggregate.safeFolderIdsByCategory
                categoryFolderRows = aggregate.rowsByCategory
                categoryToolGroups = aggregate.toolGroupsByCategory
                totalReclaimableBytes = report.totalReclaimableBytes
                self.summaries = summaries
                topFindings = sortedTopFindings
                self.largeFilesByCategory = largeFilesByCategory
                self.perToolRollups = toolRollups
                // Default: all SAFE *folders* (dozens of ids) — never 25k file paths.
                selectedFolderIds = aggregate.safeFolderIds
                selectedPaths = []
                recomputeSelectionMetrics()
                lastScanDate = finishedAt
                lastScanDuration = finishedAt.timeIntervalSince(startedAt)
                revealFeedback = nil
                cleanupState = .idle
                scanStep = 3
                scanStepTitle = "Scan complete"
                state = .success
                resultsVisible = true
                refreshPermissionCoaching()
            }
        }
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            revealFeedback = "File no longer exists: \(path)"
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        revealFeedback = nil
    }

    func canReveal(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Cleanup actions

    func requestQuickClean() {
        guard !latestFindings.isEmpty, state == .success else { return }
        showCleanConfirmation = true
        cleanupState = .confirming
    }

    func confirmQuickClean() {
        showCleanConfirmation = false
        guard state == .success else { return }
        cleanupState = .cleaning
        let findings = latestFindings

        Task(priority: .userInitiated) {
            do {
                let result = try await engine.quickClean(findings: findings, profileName: "all")
                await MainActor.run {
                    lastTransaction = result.transaction
                    cleanupState = .done(
                        bytesFreed: result.totalBytesFreed,
                        skippedCount: result.skipped.count
                    )
                    // Re-run scan to refresh results after cleanup.
                    runScan()
                }
            } catch {
                await MainActor.run {
                    cleanupState = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelCleanup() {
        showCleanConfirmation = false
        cleanupState = .idle
    }

    // MARK: - Deep Clean actions

    func requestDeepClean() {
        guard !latestFindings.isEmpty, state == .success else { return }
        showDeepCleanConfirmation = true
        cleanupState = .confirming
    }

    func confirmDeepClean() {
        showDeepCleanConfirmation = false
        guard state == .success else { return }
        cleanupState = .cleaning
        let findings = latestFindings

        Task(priority: .userInitiated) {
            do {
                let result = try await engine.deepClean(
                    findings: findings,
                    profileName: "all",
                    confirmed: true
                )
                await MainActor.run {
                    lastTransaction = result.transaction
                    cleanupState = .done(
                        bytesFreed: result.totalBytesFreed,
                        skippedCount: result.skipped.count
                    )
                    runScan()
                }
            } catch {
                await MainActor.run {
                    cleanupState = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelDeepClean() {
        showDeepCleanConfirmation = false
        cleanupState = .idle
    }

    // MARK: - Selected clean

    func requestCleanSelected() {
        guard selectedCandidatesCount > 0, state == .success else { return }
        showSelectedCleanConfirmation = true
        cleanupState = .confirming
    }

    func confirmCleanSelected() {
        showSelectedCleanConfirmation = false
        guard state == .success else { return }
        cleanupState = .cleaning
        // Expand folder ids → paths only here (background-friendly), not during UI scroll.
        let findings = selectedFindingsForClean()

        Task(priority: .userInitiated) {
            do {
                let result = try await engine.clean(findings: findings, profileName: "all")
                await MainActor.run {
                    lastTransaction = result.transaction
                    cleanupState = .done(
                        bytesFreed: result.totalBytesFreed,
                        skippedCount: result.skipped.count
                    )
                    runScan()
                }
            } catch {
                await MainActor.run {
                    cleanupState = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelSelectedClean() {
        showSelectedCleanConfirmation = false
        cleanupState = .idle
    }

    func undoLastCleanup() {
        guard let tx = lastTransaction, !tx.isDryRun else { return }
        cleanupState = .undoing

        Task(priority: .userInitiated) {
            let (restored, _) = await engine.restore(transaction: tx)
            await MainActor.run {
                lastTransaction = nil
                cleanupState = .undone(restoredCount: restored.count)
                runScan()
            }
        }
    }

    func dismissCleanupResult() {
        cleanupState = .idle
    }

    // MARK: - Exclusion

    func exclude(path: String) {
        let entry = ExclusionEntry(path: path)
        try? ExclusionStore.shared.addEntry(entry)
        latestFindings.removeAll { $0.path == path }
        findingsByPath.removeValue(forKey: path)
        topFindings.removeAll { $0.path == path }
        largeFilesByCategory = largeFilesByCategory.compactMap { group in
            let filtered = group.files.filter { $0.path != path }
            guard !filtered.isEmpty else { return nil }
            let total = filtered.reduce(0) { $0 + $1.sizeBytes }
            return CategoryLargeFiles(id: group.id, category: group.category, totalBytes: total, files: filtered)
        }
        // Rebuild private maps + lightweight rows (not on scroll hot path).
        let aggregate = Self.buildFolderAggregate(from: latestFindings)
        pathsByFolderId = aggregate.pathsByFolderId
        folderIdByPath = aggregate.folderIdByPath
        folderMetaById = aggregate.metaByFolderId
        safeFolderIds = aggregate.safeFolderIds
        safeFolderIdsByCategory = aggregate.safeFolderIdsByCategory
        categoryFolderRows = aggregate.rowsByCategory
        categoryToolGroups = aggregate.toolGroupsByCategory
        summaries = summaries.map { item in
            SummaryItem(
                summary: ScanCategorySummary(
                    category: item.category,
                    reclaimableBytes: item.reclaimableBytes,
                    fileCount: max(0, item.fileCount - 1)
                ),
                folderCount: categoryFolderRows[item.category]?.count ?? 0
            )
        }
        selectedPaths.remove(path)
        selectedFolderIds = selectedFolderIds.intersection(Set(folderMetaById.keys))
        recomputeSelectionMetrics()
        perToolRollups = Self.makeToolRollups(from: latestFindings)
    }

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func summaryShare(for bytes: Int64) -> Double {
        guard totalReclaimableBytes > 0 else { return 0 }
        return Double(bytes) / Double(totalReclaimableBytes)
    }

    static func makeToolRollups(from findings: [ScanFinding]) -> [ToolRollupItem] {
        // Chart is about reclaimable space — exclude advanced (e.g. Docker.raw attribution noise).
        let reclaimable = findings.filter { $0.riskLevel != .advanced }
        let rollups = ScanReportAnnotator.appRollups(from: reclaimable)
        let total = rollups.reduce(0) { $0 + $1.totalBytes }
        return rollups.map { ToolRollupItem(rollup: $0, total: total) }
    }

    private static func makeLargeFileGroups(from findings: [ScanFinding]) -> [CategoryLargeFiles] {
        let filtered = findings.filter { ScanPolicy.isLargeFile($0.sizeBytes) }
        let grouped = Dictionary(grouping: filtered, by: \.category)

        return grouped
            .map { category, files in
                let sorted = files.sorted { $0.sizeBytes > $1.sizeBytes }
                let total = sorted.reduce(0) { $0 + $1.sizeBytes }
                return CategoryLargeFiles(
                    id: category.rawValue,
                    category: category,
                    totalBytes: total,
                    files: sorted.map(FindingItem.init(finding:))
                )
            }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}

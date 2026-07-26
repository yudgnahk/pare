import Combine
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

    /// Fully prepared scan UI payload. Built off the main actor so large scans
    /// do not freeze the app at finalize (macOS “Not Responding”).
    private struct PreparedScanResults: Sendable {
        let findings: [ScanFinding]
        let findingsByPath: [String: ScanFinding]
        let aggregate: FolderAggregate
        let summaries: [SummaryItem]
        let sortedTopFindings: [FindingItem]
        let largeFilesByCategory: [CategoryLargeFiles]
        let toolRollups: [ToolRollup]
        let candidateStats: CandidateStats
        let totalReclaimableBytes: Int64
    }

    // MARK: - Published scan state

    @Published private(set) var state: ScanState = .idle
    @Published private(set) var totalReclaimableBytes: Int64 = 0
    @Published private(set) var summaries: [SummaryItem] = []
    @Published private(set) var topFindings: [FindingItem] = []
    @Published private(set) var largeFilesByCategory: [CategoryLargeFiles] = []
    @Published private(set) var perToolRollups: [ToolRollup] = []
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var revealFeedback: String?
    @Published var resultsVisible = false
    /// Selection domain: folder/path selection, cached totals, expansion state.
    @Published private(set) var selection = ScanSelectionModel()
    /// Pre-aggregated **lightweight** folder rows per category (built once per scan).
    @Published private(set) var categoryFolderRows: [ScanCategory: [CategoryFolderRow]] = [:]
    /// Tool/app groups under a category (e.g. Developer Package Caches → JetBrains, Package Managers).
    @Published private(set) var categoryToolGroups: [ScanCategory: [CategoryToolGroup]] = [:]
    /// Scan progress for 3-step hero (1...3) and status line.
    @Published private(set) var scanStep: Int = 1
    @Published private(set) var scanStepTitle: String = ""
    @Published private(set) var scanRulesCompleted: Int = 0
    @Published private(set) var scanRulesTotal: Int = 0
    /// After a successful scan with ~0 reclaimable bytes, coach the user on next steps.
    @Published private(set) var showEmptyScanCoaching: Bool = false
    /// Empty-scan card presentation when `showEmptyScanCoaching` is true.
    @Published private(set) var emptyScanCoachingStyle: EmptyScanCoachingStyle = .genuinelyEmpty

    /// Shared FDA state machine (also used by Settings).
    let permissions = PermissionCoachingModel()
    /// Cleanup lifecycle (pending sheet + engine calls + undo).
    let cleanup = CleanupCoordinator()

    /// Cached clean-candidate totals (recomputed per scan / exclusion — not per sheet render).
    private(set) var candidateStats = CandidateStats()

    /// Raw findings kept after scan so cleanup can reference them.
    private var latestFindings: [ScanFinding] = []
    /// O(1) path → finding lookup (not published).
    private var findingsByPath: [String: ScanFinding] = [:]
    /// Private path expansion map — never exposed to SwiftUI views.
    private var pathsByFolderId: [String: [String]] = [:]
    private let scanCache = ScanMetadataCache()
    /// The running scan task — kept so we can cancel it on demand.
    private var scanTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Child observable objects publish through the dashboard so existing
        // `@ObservedObject var viewModel` views keep re-rendering.
        permissions.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cleanup.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cleanup.onCleanupCompleted = { [weak self] in self?.runScan() }
    }

    // MARK: - Derived state

    var isScanning: Bool {
        state == .scanning
    }

    var cleanupState: CleanupCoordinator.CleanupState { cleanup.state }
    var isCleaning: Bool { cleanup.isCleaning }
    var isUndoing: Bool { cleanup.isUndoing }
    var canUndo: Bool { cleanup.canUndo }

    /// Drives the single cleanup confirmation sheet (`.sheet(item:)`).
    var pendingCleanup: PendingCleanup? {
        get { cleanup.pending }
        set { cleanup.pending = newValue }
    }

    /// Number of safe-risk findings from the last scan (Quick Clean candidates).
    var quickCleanCandidatesCount: Int { candidateStats.safeCount }
    var quickCleanCandidatesBytes: Int64 { candidateStats.safeBytes }

    /// Deep Clean candidates: safe + review-risk findings.
    var deepCleanCandidatesCount: Int { candidateStats.deepCount }
    var deepCleanCandidatesBytes: Int64 { candidateStats.deepBytes }

    var reviewRiskCandidatesCount: Int { candidateStats.reviewCount }

    var selectedCandidatesCount: Int { selection.selectedCount }
    var selectedCandidatesBytes: Int64 { selection.selectedBytes }
    var selectedReviewCount: Int { selection.selectedReviewCount }

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

    // MARK: - Selection (forwarded to ScanSelectionModel)

    func isSelected(path: String) -> Bool {
        selection.isSelected(path: path)
    }

    func isSelectable(path: String) -> Bool {
        selection.isSelectable(path: path)
    }

    func riskLevel(for path: String) -> RiskLevel? {
        selection.riskLevel(for: path)
    }

    func toggleSelection(path: String) {
        selection.togglePath(path)
    }

    func toggleFolder(_ row: CategoryFolderRow) {
        selection.toggleFolder(row)
    }

    func folderSelectionState(_ row: CategoryFolderRow) -> CategorySelectState {
        selection.folderSelectionState(row)
    }

    /// Toggle every folder under a tool group (e.g. all JetBrains package-cache folders).
    func toggleToolGroup(_ group: CategoryToolGroup) {
        guard group.isSelectable else { return }
        selection.toggleFolderIds(group.folderIds)
    }

    func toolGroupSelectionState(_ group: CategoryToolGroup) -> CategorySelectState {
        selection.selectionState(of: group.folderIds)
    }

    func selectAllSafe() {
        selection.selectAllSafe()
    }

    func clearSelection() {
        selection.clear()
    }

    func toggleCategory(_ category: ScanCategory, includeReview: Bool = false) {
        let folderIds: Set<String>
        if includeReview {
            folderIds = Set((categoryFolderRows[category] ?? []).filter(\.isSelectable).map(\.id))
        } else {
            folderIds = selection.safeFolderIds(in: category)
        }
        selection.toggleFolderIds(folderIds)
    }

    func categorySelectionState(_ category: ScanCategory) -> CategorySelectState {
        selection.selectionState(of: selection.safeFolderIds(in: category))
    }

    // MARK: - Browser expansion (absorbed from view-local @State)

    func isCategoryExpanded(_ category: ScanCategory) -> Bool {
        selection.expandedCategories.contains(category.rawValue)
    }

    func toggleCategoryExpanded(_ category: ScanCategory) {
        if !selection.expandedCategories.insert(category.rawValue).inserted {
            selection.expandedCategories.remove(category.rawValue)
        }
    }

    func isToolGroupExpanded(_ group: CategoryToolGroup) -> Bool {
        selection.expandedToolGroups.contains(group.id)
    }

    func toggleToolGroupExpanded(_ group: CategoryToolGroup) {
        if !selection.expandedToolGroups.insert(group.id).inserted {
            selection.expandedToolGroups.remove(group.id)
        }
    }

    /// Collapse all expanded browser sections (before Clear/All Safe re-diffs huge views).
    func collapseBrowserSections() {
        selection.expandedCategories.removeAll()
        selection.expandedToolGroups.removeAll()
    }

    /// Expand folder ids → findings only when cleaning (not during scroll/UI).
    private func selectedFindingsForClean() -> [ScanFinding] {
        var pathSet = Set<String>()
        pathSet.reserveCapacity(min(selectedCandidatesCount, 65_536))
        for id in selection.selectedFolderIds {
            if let paths = pathsByFolderId[id] {
                pathSet.formUnion(paths)
            }
        }
        pathSet.formUnion(selection.selectedPaths)
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

    func abbreviatedPath(_ path: String) -> String {
        FolderRollup.abbreviatePath(path)
    }

    var deviceBackupFindings: [FindingItem] {
        latestFindings
            .filter { $0.category == .deviceBackups }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .map(FindingItem.init)
    }

    // MARK: - Scan lifecycle

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
        emptyScanCoachingStyle = .genuinelyEmpty
        refreshPermissionCoaching()
    }

    /// Re-probe Full Disk Access and update coaching banners.
    /// Safe to call from any Smart Scan surface (hero or results) on activation/appear.
    func refreshPermissionCoaching() {
        permissions.refresh()
        updateEmptyScanCoaching()
    }

    var fullDiskAccessStatus: FullDiskAccessStatus { permissions.status }
    var showFullDiskAccessBanner: Bool { permissions.showBanner }

    func dismissFullDiskAccessBanner() {
        permissions.dismissBanner()
        // Empty-scan coaching may still apply once the primary banner is dismissed.
        updateEmptyScanCoaching()
    }

    func openFullDiskAccessSettings() {
        permissions.openSystemSettings()
    }

    /// Derive empty-scan coaching from live FDA status vs. the status at last scan finish.
    private func updateEmptyScanCoaching() {
        guard state == .success, totalReclaimableBytes == 0 else {
            showEmptyScanCoaching = false
            emptyScanCoachingStyle = .genuinelyEmpty
            return
        }

        // Primary FDA banner takes precedence while still visible.
        if permissions.showBanner {
            showEmptyScanCoaching = false
            return
        }

        showEmptyScanCoaching = true
        emptyScanCoachingStyle = permissions.emptyScanStyle()
    }

    func runScan(forceRescan: Bool = false) {
        guard !isScanning else { return }

        state = .scanning
        showEmptyScanCoaching = false
        emptyScanCoachingStyle = .genuinelyEmpty
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

            // `Task { }` on this @MainActor type inherits MainActor isolation.
            // Aggregation over large finding sets (path index, folder rollups, tool
            // attribution) must run in a detached task or the app beachballs with
            // “Not Responding” while still completing correctly afterward.
            let finishedAt = Date()
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.prepareScanResults(from: report)
            }.value

            guard !Task.isCancelled else { return }

            applyPreparedScanResults(prepared, startedAt: startedAt, finishedAt: finishedAt)
        }
    }

    /// Pure post-scan aggregation — safe to call from a background task.
    nonisolated private static func prepareScanResults(from report: ScanReport) -> PreparedScanResults {
        let findings = report.findings
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let pathIndex = Dictionary(findings.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        let summaries: [SummaryItem] = report.summaries.map { summary in
            SummaryItem(
                summary: summary,
                folderCount: aggregate.rowsByCategory[summary.category]?.count ?? 0
            )
        }
        return PreparedScanResults(
            findings: findings,
            findingsByPath: pathIndex,
            aggregate: aggregate,
            summaries: summaries,
            sortedTopFindings: ScanResultBuilders.largestItemsSorted(from: findings, limit: 40),
            largeFilesByCategory: ScanResultBuilders.makeLargeFileGroups(from: findings),
            toolRollups: FolderRollup.makeToolRollups(from: findings),
            candidateStats: CandidateStats.compute(from: findings),
            totalReclaimableBytes: report.totalReclaimableBytes
        )
    }

    private func applyPreparedScanResults(
        _ prepared: PreparedScanResults,
        startedAt: Date,
        finishedAt: Date
    ) {
        scanTask = nil
        latestFindings = prepared.findings
        findingsByPath = prepared.findingsByPath
        pathsByFolderId = prepared.aggregate.pathsByFolderId
        categoryFolderRows = prepared.aggregate.rowsByCategory
        categoryToolGroups = prepared.aggregate.toolGroupsByCategory
        totalReclaimableBytes = prepared.totalReclaimableBytes
        summaries = prepared.summaries
        topFindings = prepared.sortedTopFindings
        largeFilesByCategory = prepared.largeFilesByCategory
        perToolRollups = prepared.toolRollups
        candidateStats = prepared.candidateStats
        // Default: all SAFE *folders* (dozens of ids) — never 25k file paths.
        selection.updateContext(
            aggregate: prepared.aggregate,
            findingsByPath: prepared.findingsByPath,
            resetToSafeSelection: true
        )
        lastScanDate = finishedAt
        lastScanDuration = finishedAt.timeIntervalSince(startedAt)
        revealFeedback = nil
        cleanup.resetAfterScan()
        scanStep = 3
        scanStepTitle = "Scan complete"
        state = .success
        resultsVisible = true
        // Snapshot FDA at scan finish so later grants can show "rescan needed"
        // instead of a misleading clean-disk empty state.
        permissions.snapshotStatusAfterScan()
        refreshPermissionCoaching()
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
        cleanup.request(.quick)
    }

    func requestDeepClean() {
        guard !latestFindings.isEmpty, state == .success else { return }
        cleanup.request(.deep)
    }

    func requestCleanSelected() {
        guard selectedCandidatesCount > 0, state == .success else { return }
        cleanup.request(.selected)
    }

    /// One confirm path for all three cleanup kinds (was three duplicate bodies).
    func confirmPendingCleanup() {
        guard let kind = cleanup.pending else { return }
        guard state == .success else {
            cleanup.pending = nil
            return
        }
        let findings: [ScanFinding]
        switch kind {
        case .quick, .deep:
            findings = latestFindings
        case .selected:
            // Expand folder ids → paths only here (background-friendly), not during UI scroll.
            findings = selectedFindingsForClean()
        }
        cleanup.confirm(kind, findings: findings)
    }

    func cancelPendingCleanup() {
        cleanup.cancelPending()
    }

    func undoLastCleanup() {
        cleanup.undoLastCleanup()
    }

    func dismissCleanupResult() {
        cleanup.dismissResult()
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
        let aggregate = FolderRollup.buildAggregate(from: latestFindings)
        pathsByFolderId = aggregate.pathsByFolderId
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
        selection.removePath(path)
        selection.updateContext(
            aggregate: aggregate,
            findingsByPath: findingsByPath,
            resetToSafeSelection: false
        )
        candidateStats = CandidateStats.compute(from: latestFindings)
        perToolRollups = FolderRollup.makeToolRollups(from: latestFindings)
    }

    // MARK: - Formatting

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
}

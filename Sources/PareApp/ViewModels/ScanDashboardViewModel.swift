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

    // MARK: - Published scan state

    @Published private(set) var state: ScanState = .idle
    @Published private(set) var totalReclaimableBytes: Int64 = 0
    /// The total is "at least" this much: some folder sizes stopped at their deadline.
    @Published private(set) var isTotalSizePartial = false
    /// "Grew since last scan: …" for the results summary; nil on the first scan or when nothing grew.
    @Published private(set) var growthSinceLastScan: String?
    /// Non-empty when the last scan had rule failures or unreadable locations (R1.2/R1.3).
    @Published private(set) var scanWarnings: [String] = []
    /// Cache activity by finding path, filled after results appear; hot rows the user has not clicked get unticked.
    @Published private(set) var cacheActivity: [String: CacheActivityLabel] = [:]
    /// True from results appearing until the labels land; clean actions wait so no hot row slips through.
    @Published private(set) var isLabelingCacheActivity = false
    /// Newest-edit label per project root, filled with the cache labels; active projects' rows start unticked.
    @Published private(set) var projectActivity: [String: ProjectActivityLabel] = [:]
    /// Finding paths held out because their project was edited recently or its activity is unknown.
    private(set) var heldProjectPaths: Set<String> = []
    @Published private(set) var summaries: [SummaryItem] = []
    @Published private(set) var topFindings: [FindingItem] = []
    @Published private(set) var perToolRollups: [ToolRollup] = []
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var revealFeedback: String?
    /// Selection domain: folder/path selection, cached totals, expansion state.
    @Published private(set) var selection = ScanSelectionModel()
    /// Pre-aggregated **lightweight** folder rows per category (built once per scan).
    @Published private(set) var categoryFolderRows: [ScanCategory: [CategoryFolderRow]] = [:]
    /// Tool/app groups under a category (e.g. Developer Package Caches → JetBrains, Package Managers).
    @Published private(set) var categoryToolGroups: [ScanCategory: [CategoryToolGroup]] = [:]
    /// Every reclaimable folder grouped by owner; reuses the category rows' ids and selection.
    @Published private(set) var ownerSections: [OwnerSection] = []
    @Published private(set) var browseMode: BrowseMode
    /// Scan progress for 3-step hero (1...3) and status line.
    @Published private(set) var scanStep: Int = 1
    @Published private(set) var scanStepTitle: String = ""
    @Published private(set) var scanRulesCompleted: Int = 0
    @Published private(set) var scanRulesTotal: Int = 0
    /// True between the last rule finishing and results being applied.
    @Published private(set) var isFinalizingScan = false
    /// After a successful scan with ~0 reclaimable bytes, coach the user on next steps.
    @Published private(set) var showEmptyScanCoaching: Bool = false
    /// Empty-scan card presentation when `showEmptyScanCoaching` is true.
    @Published private(set) var emptyScanCoachingStyle: EmptyScanCoachingStyle = .genuinelyEmpty

    /// Shared FDA state machine (also used by Settings).
    let permissions = PermissionCoachingModel()
    /// Cleanup lifecycle (pending sheet + engine calls + undo), shared with the Disk Analyzer.
    let cleanup: CleanupCoordinator

    /// Cached clean-candidate totals (recomputed per scan / exclusion — not per sheet render).
    private(set) var candidateStats = CandidateStats()

    /// Raw findings kept after scan so cleanup can reference them.
    private var latestFindings: [ScanFinding] = []
    /// Read-only view of the latest scan's findings, for other view models (e.g. Disk Analyzer).
    var latestFindingsSnapshot: [ScanFinding] { latestFindings }
    /// O(1) path → finding lookup (not published).
    private var findingsByPath: [String: ScanFinding] = [:]
    /// Private path expansion map — never exposed to SwiftUI views.
    private var pathsByFolderId: [String: [String]] = [:]
    /// Owners resolved at scan finish, replayed when an exclusion rebuilds the groups.
    private var ownerByFolderPath: [String: FolderOwner] = [:]
    private let browseModes: BrowseModeStore
    private let exclusionStore: ExclusionStore
    /// Precomputed at scan finish (background pass) — see `revealabilityIndex`.
    private var revealablePaths: Set<String> = []
    private var folderFindingPaths: Set<String> = []
    private let scanCache = ScanMetadataCache()
    /// The running scan task — kept so we can cancel it on demand.
    private var scanTask: Task<Void, Never>?
    private let growthStore: GrowthSnapshotStore
    private let cacheActivityLabeler: @Sendable ([ScanFinding]) async -> [String: CacheActivityLabel]
    private let projectActivityLabeler: @Sendable ([String]) async -> [String: ProjectActivityLabel]
    /// Bumped per scan so growth lines or labels computed for an older scan cannot land after a newer one started.
    private var scanGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    init(
        cleanup: CleanupCoordinator = CleanupCoordinator(),
        growthStore: GrowthSnapshotStore = GrowthSnapshotStore(),
        cacheActivityLabeler: @escaping @Sendable ([ScanFinding]) async -> [String: CacheActivityLabel] = {
            CacheActivityLabeler.labels(for: $0)
        },
        projectActivityLabeler: @escaping @Sendable ([String]) async -> [String: ProjectActivityLabel] = {
            ProjectActivityLabeler.labels(
                forRoots: $0, homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        },
        browseModes: BrowseModeStore = BrowseModeStore(),
        exclusionStore: ExclusionStore = .shared
    ) {
        self.cleanup = cleanup
        self.growthStore = growthStore
        self.cacheActivityLabeler = cacheActivityLabeler
        self.projectActivityLabeler = projectActivityLabeler
        self.browseModes = browseModes
        self.exclusionStore = exclusionStore
        self.browseMode = SmartScanFeatures.ownerView ? browseModes.mode : .categories
        // Child observable objects publish through the dashboard so existing
        // `@ObservedObject var viewModel` views keep re-rendering.
        permissions.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cleanup.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cleanup.addCompletionHandler { [weak self] in self?.rescanAfterCleanup() }
    }

    // MARK: - Derived state

    var isScanning: Bool {
        state == .scanning
    }

    static let finalizingProgressCap = 0.95
    static let finalizingTitle = "Preparing results…"

    /// Rule-count progress scaled to the finalize cap so the ring never steps back.
    var scanProgress: Double {
        guard scanRulesTotal > 0 else { return 0 }
        return Double(scanRulesCompleted) / Double(scanRulesTotal) * Self.finalizingProgressCap
    }

    var cleanupState: CleanupCoordinator.CleanupState { cleanup.state }

    /// Whether clean actions may be requested; the request methods silently ignore clicks otherwise.
    var canRequestCleanup: Bool {
        Self.cleanupActionsEnabled(
            state: state, isCleaning: cleanup.isCleaning, isUndoing: cleanup.isUndoing,
            isLabelingCacheActivity: isLabelingCacheActivity
        )
    }

    /// Mirrors the guard in `requestQuickClean`/`requestDeepClean`/`requestCleanSelected`.
    static func cleanupActionsEnabled(
        state: ScanState, isCleaning: Bool, isUndoing: Bool, isLabelingCacheActivity: Bool
    ) -> Bool {
        state == .success && !isCleaning && !isUndoing && !isLabelingCacheActivity
    }
    var isCleaning: Bool { cleanup.isCleaning }
    var isUndoing: Bool { cleanup.isUndoing }
    var canUndo: Bool { cleanup.canUndo }

    /// Drives the single cleanup confirmation sheet (`.sheet(item:)`); hides Disk Analyzer requests.
    var pendingCleanup: PendingCleanup? {
        get { cleanup.pending.flatMap { $0.isSmartScan ? $0 : nil } }
        set {
            if let newValue {
                guard newValue.isSmartScan else { return }
                cleanup.pending = newValue
            } else if pendingCleanup != nil {
                // Escape nils the binding before onDismiss, so this path must reset state too.
                cleanup.cancelPending()
            }
        }
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

    /// Toggles the group's SAFE folders only; review rows stay one click each.
    func toggleToolGroup(_ group: CategoryToolGroup) {
        guard group.isSelectable else { return }
        selection.toggleFolderIds(group.safeFolderIds)
    }

    /// Same rule for owner groups: safe rows only, hot rows left to their own checkbox.
    func toggleOwnerGroup(_ group: OwnerGroup) {
        guard group.isSelectable else { return }
        selection.toggleFolderIds(group.safeFolderIds)
    }

    /// Changes only how results are grouped; selection and totals stay as they are.
    func setBrowseMode(_ mode: BrowseMode) {
        guard SmartScanFeatures.ownerView, mode != browseMode else { return }
        browseMode = mode
        browseModes.mode = mode
    }

    /// Reads the safe rows only, so a hand-ticked review row never flips the group checkbox.
    func toolGroupSelectionState(_ group: CategoryToolGroup) -> CategorySelectState {
        selection.selectionState(of: group.safeFolderIds)
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
        toggleExpandedGroup(group.id)
    }

    func toggleOwnerGroupExpanded(_ group: OwnerGroup) {
        toggleExpandedGroup(group.id)
    }

    private func toggleExpandedGroup(_ id: String) {
        if !selection.expandedToolGroups.insert(id).inserted {
            selection.expandedToolGroups.remove(id)
        }
    }

    /// Collapse all expanded browser sections (before Clear/All Safe re-diffs huge views).
    func collapseBrowserSections() {
        selection.expandedCategories.removeAll()
        selection.expandedToolGroups.removeAll()
    }

    /// Expand folder ids → findings only when cleaning (not during scroll/UI).
    private func selectedFindingsForClean() -> [ScanFinding] {
        selection.selectedFindingPaths(pathsByFolderId: pathsByFolderId)
            .compactMap { findingsByPath[$0] }
            .filter { $0.riskLevel != .advanced }
    }

    /// Quick and Deep Clean ignore the selection but still leave hot rows to their own checkbox.
    private var bulkCleanFindings: [ScanFinding] {
        latestFindings.filter { !selection.hotPaths.contains($0.path) }
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
    nonisolated static func largestItemsSorted(from findings: [ScanFinding], limit: Int) -> [FindingItem] {
        ScanReportPresenter.largestItems(from: findings, limit: limit)
            .map(FindingItem.init(finding:))
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
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        isLabelingCacheActivity = false
        state = .idle
        scanRulesCompleted = 0
        scanRulesTotal = 0
        scanStepTitle = ""
        scanStep = 1
        isFinalizingScan = false
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

    /// A scan in flight (e.g. during a Disk Analyzer clean) may still list what was just trashed.
    private func rescanAfterCleanup() {
        if isScanning { cancelScan() }
        runScan()
    }

    func runScan(forceRescan: Bool = false) {
        guard !isScanning else { return }

        scanGeneration += 1
        let generation = scanGeneration
        growthSinceLastScan = nil
        isLabelingCacheActivity = false
        state = .scanning
        showEmptyScanCoaching = false
        emptyScanCoachingStyle = .genuinelyEmpty
        scanStep = 1
        scanStepTitle = "Scanning system & app caches…"
        scanRulesCompleted = 0
        scanRulesTotal = 0
        isFinalizingScan = false
        let startedAt = Date()
        let cache = scanCache

        scanTask = Task(priority: .userInitiated) {
            if forceRescan {
                await ProjectRootDiscovery.shared.markStale()
            }
            let installedApps = SmartScanFeatures.ownerView ? Self.startInstalledAppsLoad() : nil
            defer { if Task.isCancelled { installedApps?.cancel() } }
            let rules = RuleCatalog.all
            let exclusionList = (try? exclusionStore.load()) ?? .empty
            let runner = ScanRunner(exclusionList: exclusionList, cache: cache, regrowth: RegrowthDetector())
            let totalRules = rules.count
            await MainActor.run { self.scanRulesTotal = totalRules }

            let report = await runner.run(rules: rules, forceRescan: forceRescan) { completed, total, title in
                Task { @MainActor in
                    self.applyRuleProgress(completed: completed, total: total, title: title)
                }
            }

            // If the task was cancelled, don't update UI with partial results.
            guard !Task.isCancelled else { return }

            // `Task { }` on this @MainActor type inherits MainActor isolation.
            // Aggregation over large finding sets (path index, folder rollups, tool
            // attribution) must run in a detached task or the app beachballs with
            // “Not Responding” while still completing correctly afterward.
            let finishedAt = Date()
            beginFinalizingScan()
            let owners = await Self.gatherOwnerInputs(installedApps)
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.prepareScanResults(from: report, owners: owners)
            }.value

            guard !Task.isCancelled else { return }

            applyPreparedScanResults(prepared, startedAt: startedAt, finishedAt: finishedAt)

            await publishPostScanDetails(report: report, generation: generation)
        }
    }

    /// Growth recording and cache and project labeling run side by side; each lands only while its scan is current.
    /// The clean hold lasts until both label sets are applied.
    func publishPostScanDetails(report: ScanReport, generation: Int) async {
        cacheActivity = [:]
        projectActivity = [:]
        isLabelingCacheActivity = true
        let store = growthStore
        // Only the rows "Largest items" shows can display a label.
        let shown = largestItems.compactMap { findingsByPath[$0.path] }
        let growthJob = Task.detached(priority: .utility) { Self.recordGrowth(report: report, store: store) }
        let labeler = cacheActivityLabeler
        let activityJob = Task.detached(priority: .utility) { await labeler(shown) }
        let projectLabeler = projectActivityLabeler
        let roots = projectRootsForActivity()
        let projectJob = Task.detached(priority: .utility) { await projectLabeler(roots) }

        let activity = await activityJob.value
        let projects = await projectJob.value
        if !Task.isCancelled {
            applyProjectActivity(projects, generation: generation)
            applyCacheActivity(activity, generation: generation)
        }
        if generation == scanGeneration { isLabelingCacheActivity = false }
        let growth = await growthJob.value
        if generation == scanGeneration, !Task.isCancelled { growthSinceLastScan = growth }
    }

    /// Labels from an older scan are dropped so they cannot change a newer scan's selection.
    func applyCacheActivity(_ labels: [String: CacheActivityLabel], generation: Int) {
        guard generation == scanGeneration else { return }
        isLabelingCacheActivity = false
        cacheActivity = labels
        selection.applyHotPaths(Set(labels.filter { $0.value.activity == .hot }.keys))
        candidateStats = CandidateStats.compute(from: bulkCleanFindings)
    }

    /// Unticks artifact rows of projects edited recently; a project with no label counts as active.
    func applyProjectActivity(_ labels: [String: ProjectActivityLabel], generation: Int, now: Date = Date()) {
        guard generation == scanGeneration else { return }
        projectActivity = labels
        var held: Set<String> = []
        for group in ownerSections.flatMap(\.groups) where group.owner.kind == .project {
            let isActive = group.owner.projectRoot.flatMap { labels[$0] }?.isActive(now: now) ?? true
            guard isActive else { continue }
            for id in group.folderIds {
                held.formUnion((pathsByFolderId[id] ?? []).filter { selection.isSelectable(path: $0) })
            }
        }
        heldProjectPaths = held
        selection.applyHotPaths(held)
        candidateStats = CandidateStats.compute(from: bulkCleanFindings)
    }

    var currentScanGeneration: Int { scanGeneration }

    func cacheActivityText(path: String) -> String? {
        cacheActivity[path]?.text(now: Date())
    }

    /// Compares with the last complete snapshot, saves this scan's, and returns the top growth as one line.
    nonisolated private static func recordGrowth(report: ScanReport, store: GrowthSnapshotStore) -> String? {
        let current = GrowthSnapshot(report: report)
        let previous = store.latestComplete()
        do {
            try store.save(current)
        } catch {
            NSLog("Saving growth snapshot failed: \(error.localizedDescription)")
        }
        guard let previous else { return nil }
        let delta = GrowthDelta.compute(previous: previous, current: current)
        let pathNames = Dictionary(
            report.findings.map { (GrowthSnapshot.key($0.path), URL(fileURLWithPath: $0.path).lastPathComponent) },
            uniquingKeysWith: { first, _ in first }
        )
        let top = (delta.paths.isEmpty ? delta.categories : delta.paths).prefix(5).map { entry in
            let size = ScanReportPresenter.formatBytes(entry.grewBy)
            return "\(pathNames[entry.key] ?? entry.key) " + (entry.isNew ? "new \(size)" : "+\(size)")
        }
        return top.isEmpty ? nil : "Grew since last scan: " + top.joined(separator: ", ")
    }

    /// Rule callbacks hop to the main actor unstructured, so one can land after finalize began; drop it.
    func applyRuleProgress(completed: Int, total: Int, title: String) {
        guard isScanning, !isFinalizingScan else { return }
        scanRulesCompleted = completed
        scanRulesTotal = total
        scanStepTitle = title
        let fraction = Double(completed) / Double(max(total, 1))
        if fraction < 0.34 {
            scanStep = 1
        } else if fraction < 0.67 {
            scanStep = 2
        } else {
            scanStep = 3
        }
    }

    func beginFinalizingScan() {
        guard isScanning else { return }
        isFinalizingScan = true
        scanStepTitle = Self.finalizingTitle
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
        revealablePaths = prepared.revealablePaths
        folderFindingPaths = prepared.folderFindingPaths
        categoryFolderRows = prepared.aggregate.rowsByCategory
        categoryToolGroups = prepared.aggregate.toolGroupsByCategory
        ownerSections = prepared.ownerSections
        ownerByFolderPath = prepared.ownerByFolderPath
        projectActivity = [:]
        heldProjectPaths = []
        totalReclaimableBytes = prepared.totalReclaimableBytes
        isTotalSizePartial = prepared.isTotalSizePartial
        scanWarnings = prepared.scanWarnings
        summaries = prepared.summaries
        topFindings = prepared.sortedTopFindings
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
        scanStep = 3
        scanStepTitle = "Scan complete"
        isFinalizingScan = false
        state = .success
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

    /// Set lookup against the scan-finish snapshot — called from SwiftUI row
    /// bodies, so it must never touch the filesystem. `revealInFinder` still
    /// re-checks existence live and surfaces feedback for stale entries.
    func canReveal(path: String) -> Bool {
        revealablePaths.contains(path)
    }

    /// Whether a top-finding path was a directory at scan finish (set lookup;
    /// same no-filesystem-in-body rule as `canReveal`).
    func isFolderFinding(path: String) -> Bool {
        folderFindingPaths.contains(path)
    }

    // MARK: - Cleanup actions

    func requestQuickClean() {
        guard !latestFindings.isEmpty, canRequestScanCleanup else { return }
        cleanup.request(.quick)
    }

    func requestDeepClean() {
        guard !latestFindings.isEmpty, canRequestScanCleanup else { return }
        cleanup.request(.deep)
    }

    func requestCleanSelected() {
        guard selectedCandidatesCount > 0, canRequestScanCleanup else { return }
        cleanup.request(.selected)
    }

    private var canRequestScanCleanup: Bool { state == .success && !isLabelingCacheActivity }

    /// One confirm path for all three cleanup kinds (was three duplicate bodies).
    func confirmPendingCleanup() {
        guard let kind = pendingCleanup else { return }
        guard state == .success else {
            cleanup.pending = nil
            return
        }
        guard let findings = findingsToClean(for: kind) else { return }
        cleanup.confirm(kind, findings: findings)
    }

    /// What `confirmPendingCleanup` sends the engine; nil while labels are pending, so no hot row is sent unlabeled.
    func findingsToClean(for kind: PendingCleanup) -> [ScanFinding]? {
        guard !isLabelingCacheActivity else { return nil }
        switch kind {
        case .quick, .deep:
            return bulkCleanFindings
        case .selected:
            // Expand folder ids → paths only here (background-friendly), not during UI scroll.
            return selectedFindingsForClean()
        case .diskReview:
            return nil
        }
    }

    func cancelPendingCleanup() {
        guard pendingCleanup != nil else { return }
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
        try? exclusionStore.addEntry(entry)
        // Capture the finding before removal so totals can be adjusted (R0.6).
        let excluded = findingsByPath[path] ?? latestFindings.first { $0.path == path }
        latestFindings.removeAll { $0.path == path }
        isTotalSizePartial = ScanReport.hasPartialSizes(in: latestFindings)
        findingsByPath.removeValue(forKey: path)
        topFindings.removeAll { $0.path == path }
        // Rebuild private maps + lightweight rows (not on scroll hot path).
        let resolver = SmartScanFeatures.ownerView ? CachedOwnerResolver(owners: ownerByFolderPath) : nil
        let owned = Self.ownerResults(
            aggregate: FolderRollup.buildAggregate(from: latestFindings), findings: latestFindings, resolver: resolver
        )
        let aggregate = owned.aggregate
        pathsByFolderId = aggregate.pathsByFolderId
        categoryFolderRows = aggregate.rowsByCategory
        categoryToolGroups = aggregate.toolGroupsByCategory
        ownerSections = owned.sections
        // Only the excluded finding's category loses bytes/count; `.advanced` findings
        // were never counted as reclaimable, so they don't reduce totals (R0.6).
        let excludedBytes = excluded?.sizeBytes ?? 0
        let countsAsReclaimable = excluded.map { $0.riskLevel != .advanced } ?? false
        if countsAsReclaimable {
            totalReclaimableBytes = max(0, totalReclaimableBytes - excludedBytes)
        }
        summaries = summaries.compactMap { item in
            var reclaimable = item.reclaimableBytes
            var fileCount = item.fileCount
            if item.category == excluded?.category {
                fileCount = max(0, fileCount - 1)
                if countsAsReclaimable {
                    reclaimable = max(0, reclaimable - excludedBytes)
                }
                guard fileCount > 0 else { return nil }
            }
            return SummaryItem(
                summary: ScanCategorySummary(
                    category: item.category,
                    reclaimableBytes: reclaimable,
                    fileCount: fileCount
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
        candidateStats = CandidateStats.compute(from: bulkCleanFindings)
        perToolRollups = owned.toolRollups
    }

    // MARK: - Formatting

    func formattedBytes(_ bytes: Int64) -> String {
        ScanReportPresenter.formatBytes(bytes)
    }

    /// "≥ X" or "size unknown" when a member finding's sizing stopped at its deadline.
    func formattedFolderSize(_ row: CategoryFolderRow) -> String {
        ScanReportPresenter.formatFindingSize(bytes: row.totalBytes, isComplete: !row.hasPartialSize)
    }

    /// "≥ X" or "size unknown" when the finding's sizing stopped at its deadline.
    func formattedFindingSize(_ finding: FindingItem) -> String {
        ScanReportPresenter.formatFindingSize(bytes: finding.sizeBytes, isComplete: finding.isSizeComplete)
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

#if DEBUG
// MARK: - Snapshot fixtures (DEBUG only)

extension ScanDashboardViewModel {
    /// Loads a canned report through the real results pipeline so snapshots show production layout.
    func applySnapshotResults(
        _ report: ScanReport,
        cacheActivity: [String: CacheActivityLabel] = [:],
        projectActivity: [String: ProjectActivityLabel] = [:],
        duration: TimeInterval = 14.2,
        owners: OwnerInputs = OwnerInputs()
    ) {
        let prepared = Self.prepareScanResults(from: report, owners: SmartScanFeatures.ownerView ? owners : nil)
        let finishedAt = Date()
        applyPreparedScanResults(prepared, startedAt: finishedAt.addingTimeInterval(-duration), finishedAt: finishedAt)
        if !projectActivity.isEmpty { applyProjectActivity(projectActivity, generation: scanGeneration) }
        if !cacheActivity.isEmpty { applyCacheActivity(cacheActivity, generation: scanGeneration) }
    }

    /// Holds results in the window between the scan finishing and its labels landing.
    func applySnapshotLabelingCacheActivity() {
        isLabelingCacheActivity = true
    }

    /// Freezes the hero in its finalize state (all rules done, results being prepared).
    func applySnapshotFinalizing(total: Int) {
        applySnapshotScanning(step: 3, completed: total, total: total, title: "")
        beginFinalizingScan()
    }

    /// Freezes the hero in its scanning state without starting a real scan.
    func applySnapshotScanning(step: Int, completed: Int, total: Int, title: String) {
        state = .scanning
        scanStep = step
        scanRulesCompleted = completed
        scanRulesTotal = total
        scanStepTitle = title
    }
}
#endif

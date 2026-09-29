import Foundation
import AppKit
import Combine
import PareCore

/// Drives one Disk Analyzer level at a time: breadcrumb navigation, the
/// filter/sort pipeline over `DiskEntry` rows, and a review tray that hands
/// off to `CleanupCoordinator` (never touches the filesystem directly).
@MainActor
final class DiskAnalyzerViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var rootURL: URL?
    @Published private(set) var currentURL: URL?
    @Published private(set) var crumbs: [DiskBreadcrumb.Crumb] = []
    @Published private(set) var level: DiskLevelLoader.Level?
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress: DiskLevelLoader.Progress?
    @Published var errorMessage: String?

    @Published var search = ""
    @Published var kindFilter: DiskKind?
    @Published var sizeFloor: DiskSizeFloor = .any
    @Published var sortOrder = DiskSortDescriptor.nameAscending
    @Published var selection: Set<String> = []

    /// Findings currently staged for cleanup, keyed by path so re-adding an
    /// already-covered entry never double-counts its bytes.
    @Published private(set) var reviewFindingsByPath: [String: ScanFinding] = [:]

    let coordinator: CleanupCoordinator

    private var breadcrumb: DiskBreadcrumb?
    private let findingsProvider: () -> [ScanFinding]
    private let levelLoader: DiskLevelLoader
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(
        findingsProvider: @escaping () -> [ScanFinding],
        levelLoader: DiskLevelLoader = DiskLevelLoader(),
        coordinator: CleanupCoordinator = CleanupCoordinator()
    ) {
        self.findingsProvider = findingsProvider
        self.levelLoader = levelLoader
        self.coordinator = coordinator
        coordinator.addCompletionHandler { [weak self] in
            self?.handleCleanupCompleted()
        }
        // Forward so the view's single @ObservedObject re-renders on sheet/state changes.
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Cleanup lifecycle (forwarded to `coordinator`)

    var cleanupState: CleanupCoordinator.CleanupState { coordinator.state }
    var canUndo: Bool { coordinator.canUndo }
    var cleanupIsBusy: Bool { coordinator.isCleaning || coordinator.isUndoing }
    var cleanupSkippedReasons: [String] { coordinator.lastResult?.skipped.map(\.reason) ?? [] }
    var transactionSaveError: String? { coordinator.transactionSaveError }

    /// Drives the single cleanup confirmation sheet (`.sheet(item:)`).
    var pendingCleanup: PendingCleanup? {
        get { coordinator.pending }
        set { coordinator.pending = newValue }
    }

    func cancelPendingCleanup() {
        coordinator.cancelPending()
    }

    func dismissCleanupResult() {
        coordinator.dismissResult()
    }

    func undoLastCleanup() {
        coordinator.undoLastCleanup()
    }

    // MARK: - Derived

    var visibleEntries: [DiskEntry] {
        DiskTableQuery.apply(
            entries: level?.entries ?? [],
            search: search,
            kind: kindFilter,
            sizeFloor: sizeFloor,
            sortOrder: sortOrder
        )
    }

    var reviewTrayFindings: [ScanFinding] { Array(reviewFindingsByPath.values) }
    var reviewTrayCount: Int { reviewFindingsByPath.count }
    var reviewTrayTotalBytes: Int64 { reviewFindingsByPath.values.reduce(0) { $0 + $1.sizeBytes } }
    var reviewTrayReviewRiskCount: Int {
        reviewFindingsByPath.values.filter { $0.riskLevel == .review }.count
    }

    // MARK: - Navigation

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to analyze"
        panel.prompt = "Analyze"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(root: url)
    }

    func open(root url: URL) {
        guard let crumb = DiskBreadcrumb(root: url, current: url) else { return }
        selection = []
        loadLevel(breadcrumb: crumb)
    }

    /// Drills into `entry` when it is a real directory inside the current level.
    func open(_ entry: DiskEntry) {
        guard entry.isDirectory,
              let breadcrumb, let next = breadcrumb.enter(entry.url) else { return }
        selection = []
        loadLevel(breadcrumb: next)
    }

    func goUp() {
        guard let breadcrumb, let previous = breadcrumb.up() else { return }
        selection = []
        loadLevel(breadcrumb: previous)
    }

    /// Jumps directly to a breadcrumb crumb (e.g. the user clicked an ancestor).
    func select(crumb: DiskBreadcrumb.Crumb) {
        guard let root = rootURL, let target = DiskBreadcrumb(root: root, current: crumb.url) else { return }
        selection = []
        loadLevel(breadcrumb: target)
    }

    func refresh() {
        guard let current = breadcrumb?.current else { return }
        selection = []
        Task {
            await levelLoader.invalidate(directoryAndAncestors: current)
            reloadCurrentLevel()
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }

    func formattedBytes(_ bytes: Int64) -> String {
        ScanReportPresenter.formatBytes(bytes)
    }

    // MARK: - Review tray

    /// Whether/why `entry` may be added to the review tray, without mutating state.
    func reviewResolution(for entry: DiskEntry) -> DiskReviewResolution {
        return DiskReviewResolver.resolve(entryPath: entry.url.path, findings: findingsProvider())
    }

    /// Adds the findings covering `entry` to the tray; `.notCandidate`/`.noScan` add nothing.
    @discardableResult
    func addToReview(_ entry: DiskEntry) -> DiskReviewResolution {
        let resolution = reviewResolution(for: entry)
        switch resolution {
        case .covered(let findings):
            merge(findings)
        case .insideFinding(let finding):
            merge([finding])
        case .notCandidate, .noScan:
            break
        }
        return resolution
    }

    func removeFromReview(path: String) {
        reviewFindingsByPath.removeValue(forKey: path)
    }

    func clearReview() {
        reviewFindingsByPath = [:]
    }

    /// Opens the confirmation sheet for the tray's contents.
    func requestReviewCleanup() {
        guard !reviewFindingsByPath.isEmpty, !cleanupIsBusy else { return }
        let latestByPath = Dictionary(findingsProvider().map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        reviewFindingsByPath = reviewFindingsByPath.compactMapValues { latestByPath[$0.path] }
        guard !reviewFindingsByPath.isEmpty else { return }
        coordinator.request(.selected)
    }

    /// Hands the coordinator exactly the tray's findings.
    func confirmReviewCleanup() {
        let latestByPath = Dictionary(findingsProvider().map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        let current = reviewTrayFindings.compactMap { latestByPath[$0.path] }
            .filter { $0.riskLevel != .advanced }
        reviewFindingsByPath = Dictionary(current.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        guard !current.isEmpty else {
            coordinator.cancelPending()
            return
        }
        coordinator.confirm(.selected, findings: current)
    }

    // MARK: - Private

    private func merge(_ findings: [ScanFinding]) {
        for finding in findings {
            if reviewFindingsByPath.keys.contains(where: { isAncestorOrSame($0, finding.path) }) {
                continue
            }
            reviewFindingsByPath = reviewFindingsByPath.filter { !isAncestorOrSame(finding.path, $0.key) }
            reviewFindingsByPath[finding.path] = finding
        }
    }

    private func isAncestorOrSame(_ ancestor: String, _ child: String) -> Bool {
        ScanPolicy.isCanonicallyEqualToOrDescendant(
            candidate: URL(fileURLWithPath: child),
            root: URL(fileURLWithPath: ancestor)
        )
    }

    private func loadLevel(breadcrumb: DiskBreadcrumb) {
        loadGeneration = UUID()
        let generation = loadGeneration
        self.breadcrumb = breadcrumb
        rootURL = breadcrumb.root
        currentURL = breadcrumb.current
        crumbs = breadcrumb.crumbs
        isLoading = true
        loadingProgress = nil
        errorMessage = nil

        loadTask?.cancel()
        loadTask = Task {
            do {
                let level = try await levelLoader.load(directory: breadcrumb.current) { progress in
                    Task { @MainActor in
                        guard self.loadGeneration == generation else { return }
                        self.loadingProgress = progress
                    }
                }
                guard !Task.isCancelled, generation == loadGeneration else { return }
                self.level = level
                isLoading = false
                loadingProgress = nil
            } catch is CancellationError {
                // Superseded by a newer navigation; drop silently.
            } catch {
                guard generation == loadGeneration else { return }
                isLoading = false
                loadingProgress = nil
                errorMessage = "Could not read \(breadcrumb.current.path): \(error.localizedDescription)"
            }
        }
    }

    /// Clears the tray and re-walks the current level so it reflects what cleanup just moved.
    private func handleCleanupCompleted() {
        selection = []
        let succeededPaths = Set(coordinator.lastResult?.succeeded.map(\.originalPath) ?? [])
        reviewFindingsByPath = reviewFindingsByPath.filter { !succeededPaths.contains($0.key) }
        let latestPaths = Set(findingsProvider().map(\.path))
        reviewFindingsByPath = reviewFindingsByPath.filter { latestPaths.contains($0.key) }
        Task {
            await levelLoader.invalidateAll()
            reloadCurrentLevel()
        }
    }

    /// Re-reads the location after an `await`, since the user may have navigated meanwhile.
    private func reloadCurrentLevel() {
        guard let breadcrumb else { return }
        loadLevel(breadcrumb: breadcrumb)
    }
}

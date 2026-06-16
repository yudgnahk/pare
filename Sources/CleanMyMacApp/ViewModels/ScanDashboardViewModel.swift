import Foundation
import SwiftUI
import AppKit
import CleanMyMacCore

@MainActor
final class ScanDashboardViewModel: ObservableObject {
    enum ScanState: Equatable {
        case idle
        case scanning
        case success
    }

    enum DashboardProfile: String, CaseIterable, Identifiable {
        case baseline = "Baseline"
        case developer = "Developer"
        case designer = "Designer"
        case videoBuilder = "Video Builder"

        var id: String { rawValue }

        var coreProfile: ScanProfile {
            switch self {
            case .baseline:
                return .baseline
            case .developer:
                return .developer
            case .designer:
                return .designer
            case .videoBuilder:
                return .videoBuilder
            }
        }
    }

    struct SummaryItem: Identifiable {
        let id: String
        let category: ScanCategory
        let reclaimableBytes: Int64
        let fileCount: Int

        init(summary: ScanCategorySummary) {
            self.id = summary.category.rawValue
            self.category = summary.category
            self.reclaimableBytes = summary.reclaimableBytes
            self.fileCount = summary.fileCount
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

    @Published var selectedProfile: DashboardProfile = .baseline
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
    /// Most recent transaction, used to offer undo.
    private var lastTransaction: CleanupTransaction?
    /// Raw findings kept after scan so cleanup can reference them.
    private var latestFindings: [ScanFinding] = []
    private let engine = CleanupEngine()
    private let scanCache = ScanMetadataCache()
    /// The running scan task — kept so we can cancel it on demand.
    private var scanTask: Task<Void, Never>?

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

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        state = .idle
        resultsVisible = false
    }

    func runScan(forceRescan: Bool = false) {
        guard !isScanning else { return }

        state = .scanning
        resultsVisible = false
        let startedAt = Date()
        let profile = selectedProfile.coreProfile
        let cache = scanCache

        scanTask = Task(priority: .userInitiated) {
            let rules = RuleCatalog.rules(for: profile)
            let runner = ScanRunner(cache: cache)
            let report = await runner.run(rules: rules, forceRescan: forceRescan)

            // If the task was cancelled, don't update UI with partial results.
            guard !Task.isCancelled else { return }

            let sortedTopFindings = report.findings
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .prefix(30)
                .map(FindingItem.init(finding:))
            let largeFilesByCategory = Self.makeLargeFileGroups(from: report.findings)
            let toolRollups = profile != .baseline
                ? Self.makeToolRollups(from: report.findings)
                : []
            let finishedAt = Date()

            await MainActor.run {
                scanTask = nil
                latestFindings = report.findings
                totalReclaimableBytes = report.totalReclaimableBytes
                summaries = report.summaries.map(SummaryItem.init(summary:))
                topFindings = sortedTopFindings
                self.largeFilesByCategory = largeFilesByCategory
                self.perToolRollups = toolRollups
                lastScanDate = finishedAt
                lastScanDuration = finishedAt.timeIntervalSince(startedAt)
                revealFeedback = nil
                cleanupState = .idle
                state = .success

                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    resultsVisible = true
                }
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
        let profileName = selectedProfile.coreProfile.rawValue

        Task(priority: .userInitiated) {
            do {
                let result = try await engine.quickClean(findings: findings, profileName: profileName)
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
        let profileName = selectedProfile.coreProfile.rawValue

        Task(priority: .userInitiated) {
            do {
                let result = try await engine.deepClean(
                    findings: findings,
                    profileName: profileName,
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
        let rollups = ScanReportAnnotator.appRollups(from: findings)
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

import Foundation
import SwiftUI
import AppKit
import App BCore

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
        let confidence: Double
        let lastUsed: Date?

        init(finding: ScanFinding) {
            self.id = "\(finding.path)-\(finding.sizeBytes)"
            self.path = finding.path
            self.sizeBytes = finding.sizeBytes
            self.category = finding.category
            self.riskLevel = finding.riskLevel
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

    @Published var selectedProfile: DashboardProfile = .baseline
    @Published private(set) var state: ScanState = .idle
    @Published private(set) var totalReclaimableBytes: Int64 = 0
    @Published private(set) var summaries: [SummaryItem] = []
    @Published private(set) var topFindings: [FindingItem] = []
    @Published private(set) var largeFilesByCategory: [CategoryLargeFiles] = []
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var revealFeedback: String?
    @Published var resultsVisible = false

    var isScanning: Bool {
        state == .scanning
    }

    func runScan() {
        guard !isScanning else { return }

        state = .scanning
        resultsVisible = false
        let startedAt = Date()
        let profile = selectedProfile.coreProfile

        Task(priority: .userInitiated) {
            let rules = RuleCatalog.rules(for: profile)
            let report = await ScanRunner().run(rules: rules)
            let sortedTopFindings = report.findings
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .prefix(30)
                .map(FindingItem.init(finding:))
            let largeFilesByCategory = Self.makeLargeFileGroups(from: report.findings)
            let finishedAt = Date()

            await MainActor.run {
                totalReclaimableBytes = report.totalReclaimableBytes
                summaries = report.summaries.map(SummaryItem.init(summary:))
                topFindings = sortedTopFindings
                self.largeFilesByCategory = largeFilesByCategory
                lastScanDate = finishedAt
                lastScanDuration = finishedAt.timeIntervalSince(startedAt)
                revealFeedback = nil
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

    func confidenceLabel(for confidence: Double) -> String {
        if confidence >= 0.9 { return "High" }
        if confidence >= 0.7 { return "Medium" }
        return "Review"
    }

    func summaryShare(for bytes: Int64) -> Double {
        guard totalReclaimableBytes > 0 else { return 0 }
        return Double(bytes) / Double(totalReclaimableBytes)
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

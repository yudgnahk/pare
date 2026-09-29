#if DEBUG
import Foundation
import PareCore

/// Deterministic, plausible scan data for DEBUG screenshots; paths are illustrative only.
enum SnapshotFixtures {
    private static let home = NSHomeDirectory()
    private static let gb: Int64 = 1_073_741_824
    private static let mb: Int64 = 1_048_576

    static var scanReport: ScanReport {
        let findings = rows.map { row in
            ScanFinding(
                category: row.category,
                riskLevel: row.risk,
                reason: "Snapshot fixture",
                path: home + row.path,
                sizeBytes: row.bytes,
                lastUsed: Date().addingTimeInterval(-86_400 * 21),
                confidence: 0.9
            )
        }
        let grouped = Dictionary(grouping: findings, by: \.category)
        let summaries = grouped.map { category, items in
            ScanCategorySummary(
                category: category,
                reclaimableBytes: items.filter { $0.riskLevel != .advanced }.reduce(0) { $0 + $1.sizeBytes },
                fileCount: items.count * 37
            )
        }
        .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        return ScanReport(findings: findings, summaries: summaries)
    }

    private struct Row {
        let category: ScanCategory
        let risk: RiskLevel
        let path: String
        let bytes: Int64
    }

    private static let rows: [Row] = [
        Row(category: .developerPackageCaches, risk: .safe, path: "/Library/Caches/JetBrains/IntelliJIdea2025.1", bytes: 3 * gb + 420 * mb),
        Row(category: .developerPackageCaches, risk: .safe, path: "/.npm/_cacache", bytes: 2 * gb + 180 * mb),
        Row(category: .developerPackageCaches, risk: .safe, path: "/Library/Caches/Homebrew", bytes: 1 * gb + 310 * mb),
        Row(category: .developerBuildArtifacts, risk: .safe, path: "/Library/Developer/Xcode/DerivedData", bytes: 6 * gb + 640 * mb),
        Row(category: .developerSimulatorCaches, risk: .safe, path: "/Library/Developer/CoreSimulator/Caches", bytes: 1 * gb + 900 * mb),
        Row(category: .browserCaches, risk: .safe, path: "/Library/Caches/Google/Chrome/Default/Cache", bytes: 1 * gb + 120 * mb),
        Row(category: .browserCaches, risk: .review, path: "/Library/Application Support/Google/Chrome/Default/Local Storage", bytes: 380 * mb),
        Row(category: .userCaches, risk: .safe, path: "/Library/Caches/com.spotify.client", bytes: 890 * mb),
        Row(category: .userCaches, risk: .safe, path: "/Library/Caches/com.tinyspeck.slackmacgap", bytes: 540 * mb),
        Row(category: .logsAndCrashReports, risk: .safe, path: "/Library/Logs/DiagnosticReports", bytes: 260 * mb),
        Row(category: .aiToolCaches, risk: .safe, path: "/.cache/huggingface/hub", bytes: 2 * gb + 50 * mb),
        Row(category: .installerFiles, risk: .review, path: "/Downloads/Xcode_16.dmg", bytes: 3 * gb + 700 * mb),
        Row(category: .temporaryFiles, risk: .safe, path: "/Library/Caches/TemporaryItems", bytes: 150 * mb)
    ]

    static func historyTransactions() -> [CleanupTransaction] {
        let day: TimeInterval = 86_400
        return [
            CleanupTransaction(
                timestamp: Date().addingTimeInterval(-day * 2),
                profileName: "all",
                isDryRun: false,
                items: [
                    CleanupItem(originalPath: home + "/Library/Developer/Xcode/DerivedData", trashedPath: "/tmp/x", sizeBytes: 5 * gb, reason: "Build artifacts", riskLevel: .safe),
                    CleanupItem(originalPath: home + "/.npm/_cacache", trashedPath: "/tmp/y", sizeBytes: 2 * gb, reason: "Package cache", riskLevel: .safe)
                ]
            ),
            CleanupTransaction(
                timestamp: Date().addingTimeInterval(-day * 9),
                profileName: "all",
                isDryRun: false,
                items: [
                    CleanupItem(originalPath: home + "/Library/Caches/com.spotify.client", trashedPath: "/tmp/z", sizeBytes: 700 * mb, reason: "App cache", riskLevel: .safe)
                ]
            )
        ]
    }
}
#endif

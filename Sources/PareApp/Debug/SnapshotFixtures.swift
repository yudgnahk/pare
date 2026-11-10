#if DEBUG
import Foundation
import PareCore

/// Deterministic, plausible scan data for DEBUG screenshots, rooted at a path that cannot exist.
enum SnapshotFixtures {
    static let root = "/nonexistent/pare-fixture"
    private static let home = root + "/home"
    static let projectsRoot = home + "/Code"
    private static let trash = root + "/Trash"
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

    /// One hot row (npm, written today) so results show it unticked, plus a cold and a warm label.
    static var cacheActivity: [String: CacheActivityLabel] {
        let now = Date()
        return [
            home + "/.npm/_cacache": CacheActivityLabel(activity: .hot, newestEntryDate: now.addingTimeInterval(-3_600)),
            home + "/Library/Caches/Homebrew": CacheActivityLabel(activity: .cold, newestEntryDate: now.addingTimeInterval(-86_400 * 58)),
            home + "/Library/Caches/com.spotify.client": CacheActivityLabel(activity: .warm, newestEntryDate: now.addingTimeInterval(-86_400 * 9)),
        ]
    }

    /// `shop` edited 4 hours ago (its builds start unticked), `blog` idle for 9 days; no real files are read.
    static var projectActivity: [String: ProjectActivityLabel] {
        let now = Date()
        let edits = [
            projectsRoot + "/shop": now.addingTimeInterval(-4 * 3_600),
            projectsRoot + "/blog": now.addingTimeInterval(-86_400 * 9),
        ]
        return ProjectActivityLabeler.labels(
            forRoots: Array(edits.keys), homeDirectory: URL(fileURLWithPath: home),
            now: { now }, probe: { root, _ in edits[root.path] }
        )
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
        Row(category: .aiToolCaches, risk: .safe, path: "/.cache/opencode", bytes: 2 * gb + 50 * mb),
        Row(category: .installerFiles, risk: .review, path: "/Downloads/Xcode_16.dmg", bytes: 3 * gb + 700 * mb),
        Row(category: .temporaryFiles, risk: .safe, path: "/Library/Caches/TemporaryItems", bytes: 150 * mb),
        Row(category: .projectArtifacts, risk: .safe, path: "/Code/shop/.next", bytes: 1 * gb + 420 * mb),
        Row(category: .projectArtifacts, risk: .review, path: "/Code/shop/node_modules", bytes: 910 * mb),
        Row(category: .projectArtifacts, risk: .safe, path: "/Code/blog/target", bytes: 2 * gb + 160 * mb),
        Row(category: .userCaches, risk: .safe, path: "/Library/Caches/com.acme.Whisper", bytes: 640 * mb),
        Row(category: .userCaches, risk: .safe, path: "/Library/Application Support/Code/Cache", bytes: 480 * mb),
        // Under the 50 MB fold threshold, so each group shows its small-items row.
        Row(category: .userCaches, risk: .safe, path: "/Library/Caches/com.apple.akd", bytes: 18 * mb),
        Row(category: .userCaches, risk: .safe, path: "/Library/Caches/com.acme.Notes", bytes: 9 * mb),
        Row(category: .projectArtifacts, risk: .safe, path: "/Code/blog/.cache", bytes: 31 * mb),
        // Working-set cache: listed under Size only, never cleaned.
        Row(category: .developerPackageCaches, risk: .advanced, path: "/go/pkg/mod", bytes: 4 * gb + 260 * mb)
    ]

    /// Owner context for the fake home: one installed app and two projects, found without touching disk.
    /// Whisper borrows a bundled system app's icon so the scene shows a real one; nothing is read from it.
    static var ownerInputs: OwnerInputs {
        OwnerInputs(
            homeDirectory: URL(fileURLWithPath: home),
            installedApps: InstalledAppIndex(
                namesByBundleID: ["com.acme.whisper": "Whisper"],
                appURLsByBundleID: ["com.acme.whisper": URL(fileURLWithPath: fixtureIconApp)]
            ),
            registeredRoots: [URL(fileURLWithPath: projectsRoot)],
            probe: FixtureProjectProbe(gitRoots: [projectsRoot + "/shop"], markerRoots: [projectsRoot + "/blog"])
        )
    }

    static let fixtureIconApp = "/System/Applications/VoiceMemos.app"

    /// Answers project-marker probes from fixed lists.
    struct FixtureProjectProbe: ProjectMarkerProbing {
        let gitRoots: Set<String>
        let markerRoots: Set<String>

        func probe(directory: String) -> (hasGit: Bool, hasMarker: Bool) {
            (gitRoots.contains(directory), markerRoots.contains(directory))
        }
    }

    /// Model store whose cleanup and history engines can never move, restore or record a real file.
    @MainActor
    static func makeModelStore() -> AppModelStore {
        let store = CleanupTransactionStore(directory: URL(fileURLWithPath: root + "/transactions"))
        return AppModelStore(
            cleanup: CleanupCoordinator(engine: inertEngine(store: store)),
            history: HistoryViewModel(store: store, engine: inertEngine(store: store))
        )
    }

    /// Engine with no project roots or exclusions and a Trash move that always refuses.
    static func inertEngine(store: CleanupTransactionStore) -> CleanupEngine {
        CleanupEngine(
            store: store,
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { _ in throw CocoaError(.featureUnsupported) }
        )
    }

    static func historyTransactions() -> [CleanupTransaction] {
        let day: TimeInterval = 86_400
        return [
            CleanupTransaction(
                timestamp: Date().addingTimeInterval(-day * 2),
                profileName: "all",
                isDryRun: false,
                items: [
                    CleanupItem(originalPath: home + "/Library/Developer/Xcode/DerivedData", trashedPath: trash + "/x", sizeBytes: 5 * gb, reason: "Build artifacts", riskLevel: .safe),
                    CleanupItem(originalPath: home + "/.npm/_cacache", trashedPath: trash + "/y", sizeBytes: 2 * gb, reason: "Package cache", riskLevel: .safe)
                ]
            ),
            CleanupTransaction(
                timestamp: Date().addingTimeInterval(-day * 9),
                profileName: "all",
                isDryRun: false,
                items: [
                    CleanupItem(originalPath: home + "/Library/Caches/com.spotify.client", trashedPath: trash + "/z", sizeBytes: 700 * mb, reason: "App cache", riskLevel: .safe)
                ]
            )
        ]
    }
}
#endif

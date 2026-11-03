import Foundation

/// Old upgrade/migration backups under `~` dot directories and `~/Library/Application Support/*`,
/// offered for review only once the app has written newer live data and a newer backup exists.
/// Every condition lives in `ScanPolicy.isReclaimableUpgradeBackup`, which `CleanupEngine` re-checks.
public struct StaleUpgradeBackupsRule: ScanRule {
    public let id = "stale-upgrade-backups"
    public let title = "Old Upgrade Backups"
    public let reason = "Old upgrade or migration backup the app has moved past"
    public let category: ScanCategory = .applications
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.8

    /// Levels below each root that are searched.
    static let maxDepth = 4
    /// Directory entries looked at per scan, across all roots.
    static let maxEntriesVisited = 20_000

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        var walk = Walk(sizeIndex: environment.sizeIndex, category: category, riskLevel: riskLevel, confidence: confidence)
        for root in Self.roots(home: environment.homeDirectory) {
            guard !Task.isCancelled, walk.budget > 0 else { break }
            let app = root.lastPathComponent.hasPrefix(".") ? String(root.lastPathComponent.dropFirst()) : root.lastPathComponent
            walk.visit(root, app: app, depth: 0)
        }
        return walk.findings
    }

    /// `~/.<name>` directories and `~/Library/Application Support/<app>` folders, minus excluded ones.
    static func roots(home: URL) -> [URL] {
        let dotDirectories = directories(in: home).filter {
            let name = $0.lastPathComponent
            return name.hasPrefix(".") && !ScanPolicy.upgradeBackupExcludedDotDirectories.contains(name.lowercased())
        }
        let appSupport = directories(in: home.appending(path: "Library/Application Support")).filter {
            let name = $0.lastPathComponent
            return !name.lowercased().hasPrefix("com.apple.")
                && !ScanPolicy.upgradeBackupExcludedApplicationSupportFolders.contains(name)
        }
        return dotDirectories + appSupport
    }

    private static func directories(in parent: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: keys)) ?? []
        return entries.filter {
            let values = try? $0.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }

    private struct Walk {
        let sizeIndex: DirectorySizeIndex
        let category: ScanCategory
        let riskLevel: RiskLevel
        let confidence: Double
        var budget = StaleUpgradeBackupsRule.maxEntriesVisited
        var findings: [ScanFinding] = []

        init(sizeIndex: DirectorySizeIndex, category: ScanCategory, riskLevel: RiskLevel, confidence: Double) {
            self.sizeIndex = sizeIndex
            self.category = category
            self.riskLevel = riskLevel
            self.confidence = confidence
        }

        mutating func visit(_ directory: URL, app: String, depth: Int) {
            guard depth < StaleUpgradeBackupsRule.maxDepth else { return }
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                            .contentModificationDateKey, .creationDateKey]
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys)
            ) else { return }
            for entry in entries {
                guard budget > 0 else { return }
                budget -= 1
                guard let values = try? entry.resourceValues(forKeys: keys), values.isSymbolicLink != true else { continue }
                let name = entry.lastPathComponent
                if ScanPolicy.hasUpgradeBackupSignal(name) {
                    if ScanPolicy.isReclaimableUpgradeBackup(entry) {
                        record(entry, values: values, app: app)
                    }
                    continue
                }
                if values.isDirectory == true, !ScanPolicy.isProjectDependencyDirectory(name),
                   !ScanPolicy.upgradeBackupExcludedDotDirectories.contains(name.lowercased()) {
                    visit(entry, app: app, depth: depth + 1)
                }
            }
        }

        private mutating func record(_ entry: URL, values: URLResourceValues, app: String) {
            let size = values.isDirectory == true
                ? sizeIndex.directorySize(url: entry)
                : Int64(values.fileSize ?? 0)
            guard size > 0 else { return }
            let date = ScanPolicy.effectiveAgeDate(from: values)
            let when = date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "an earlier version"
            findings.append(ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: "Old upgrade backup from \(when); \(app) has written newer data since — the newest backup is kept",
                path: entry.path,
                sizeBytes: size,
                lastUsed: values.contentModificationDate,
                confidence: confidence
            ))
        }
    }
}

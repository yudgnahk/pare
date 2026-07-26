import Foundation
import PareCore

@main
struct PareCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        let profile = parseProfile(from: args) ?? .baseline
        let top = parseTop(from: args) ?? 10

        let rules = RuleCatalog.rules(for: profile)
        let runner = ScanRunner()
        let report = await runner.run(rules: rules)

        print("Profile: \(profile.rawValue)")
        print("Rules: \(rules.count)")
        print("Total reclaimable: \(format(bytes: report.totalReclaimableBytes))")
        print("")
        print("By category:")

        for summary in report.summaries {
            print("- \(summary.category.rawValue): \(format(bytes: summary.reclaimableBytes)) (\(summary.fileCount) files)")
        }

        if !report.findings.isEmpty {
            print("")
            print("Largest items (SAFE then REVIEW):")
            let topFindings = ScanReportPresenter.largestItems(from: report.findings, limit: top)
            var lastRisk: RiskLevel?
            for finding in topFindings {
                if finding.riskLevel != lastRisk {
                    print("  — \(riskTag(finding.riskLevel).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) —")
                    lastRisk = finding.riskLevel
                }
                let riskLabel = riskTag(finding.riskLevel)
                print("- \(format(bytes: finding.sizeBytes)) \(riskLabel) \(finding.category.rawValue) — \(finding.reason)")
                print("  \(finding.path)")
            }
        }

        let largeFileGroups = ScanReportPresenter.largeFileGroups(from: report.findings)
        if !largeFileGroups.isEmpty {
            print("")
            print("Large files by category (> \(format(bytes: ScanPolicy.largeFileThresholdBytes))):")

            for group in largeFileGroups {
                print("- \(group.category.rawValue): \(format(bytes: group.totalBytes)) (\(group.files.count) files)")

                for finding in group.files.prefix(top) {
                    let riskLabel = riskTag(finding.riskLevel)
                    print("  \(riskLabel) \(format(bytes: finding.sizeBytes)) | \(finding.path)")
                }
            }
        }

        if profile != .baseline {
            let rollups = ScanReportAnnotator.appRollups(from: report.findings)
            if !rollups.isEmpty {
                let total = rollups.reduce(0) { $0 + $1.totalBytes }
                print("")
                print("── By Tool ─────────────────────────────────────────────────────────────")
                for rollup in rollups {
                    let pct = total > 0 ? Int(Double(rollup.totalBytes) / Double(total) * 100) : 0
                    print("  \(rollup.app.padding(toLength: 22, withPad: " ", startingAt: 0)) \(format(bytes: rollup.totalBytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(pct)%  (\(rollup.fileCount) files)")
                }
                print("────────────────────────────────────────────────────────────────────────")
            }
        }

        let advancedFindings = report.findings.filter { $0.riskLevel == .advanced }
        if !advancedFindings.isEmpty {
            print("")
            print("⚠️  ADVANCED findings detected — do NOT delete these files directly.")
            print("   Check each path and use the appropriate native tool to clean it.")
        }

        printDockerBuildCacheHint(profile: profile)
    }

    /// Emits a Docker reclaim advisory when running the developer profile and Docker
    /// Desktop is installed. Points users at docker-native prune (never --volumes).
    private static func printDockerBuildCacheHint(profile: ScanProfile) {
        guard profile == .developer else { return }

        let dockerDataDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.docker.docker/Data")
        guard FileManager.default.fileExists(atPath: dockerDataDir.path) else { return }

        print("")
        print("── Docker storage ──────────────────────────────────────────────────────")
        print("Docker Desktop keeps images, containers, build cache, and volumes inside")
        print("its VM. Pare never deletes that disk image or Docker volumes.")
        print("Safe reclaim options:")
        print("  docker builder prune --filter \"until=168h\"")
        print("    → build cache only; never touches volumes or databases")
        print("  docker system prune -f")
        print("    → unused images, stopped containers, networks, build cache")
        print("  Maintenance tab → Docker System Prune (same as system prune -f)")
        print("⚠️  Never add --volumes (destroys volume data e.g. Postgres).")
        print("────────────────────────────────────────────────────────────────────────")
    }

    private static func parseProfile(from args: ArraySlice<String>) -> ScanProfile? {
        guard let index = args.firstIndex(of: "--profile") else {
            return nil
        }
        let next = args.index(after: index)
        guard next < args.endIndex else {
            return nil
        }
        return ScanProfile(rawValue: args[next])
    }

    private static func parseTop(from args: ArraySlice<String>) -> Int? {
        guard let index = args.firstIndex(of: "--top") else {
            return nil
        }
        let next = args.index(after: index)
        guard next < args.endIndex, let value = Int(args[next]), value > 0 else {
            return nil
        }
        return value
    }

    private static func format(bytes: Int64) -> String {
        ScanReportPresenter.formatBytes(bytes)
    }

    private static func riskTag(_ level: RiskLevel) -> String {
        ScanReportPresenter.riskTag(level)
    }
}

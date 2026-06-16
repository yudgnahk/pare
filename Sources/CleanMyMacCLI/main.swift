import Foundation
import CleanMyMacCore

@main
struct CleanMyMacCLI {
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
            print("Top \(min(top, report.findings.count)) files:")
            let topFindings = report.findings.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(top)
            for finding in topFindings {
                let riskLabel = riskTag(finding.riskLevel)
                print("- \(format(bytes: finding.sizeBytes)) \(riskLabel) \(finding.category.rawValue) — \(finding.reason)")
                print("  \(finding.path)")
            }
        }

        let largeFileGroups = groupLargeFilesByCategory(findings: report.findings)
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

        let appRollups = groupBySourceApp(findings: report.findings)
        if !appRollups.isEmpty {
            print("")
            print("Top offenders by source app:")
            for rollup in appRollups {
                print("- \(rollup.app): \(format(bytes: rollup.totalBytes)) (\(rollup.fileCount) files)")
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

    /// Emits a Docker build-cache advisory when running the developer profile and Docker
    /// Desktop is installed. Docker stores build cache inside its VM disk (Docker.raw) —
    /// it cannot be scanned as regular files. This hint points to the correct CLI commands.
    private static func printDockerBuildCacheHint(profile: ScanProfile) {
        guard profile == .developer else { return }

        let dockerDataDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.docker.docker/Data")
        guard FileManager.default.fileExists(atPath: dockerDataDir.path) else { return }

        print("")
        print("── Docker build cache ──────────────────────────────────────────────────")
        print("Docker stores build cache inside its VM disk — not scannable as regular files.")
        print("To reclaim build cache older than 7 days, run:")
        print("  docker builder prune --filter \"until=168h\"")
        print("    → removes build cache only; never touches volumes or databases")
        print("  docker system prune  --filter \"until=168h\"")
        print("    → also removes unused images and stopped containers")
        print("⚠️  Never add --volumes unless you want to delete Docker volume data (e.g. databases).")
        print("────────────────────────────────────────────────────────────────────────")
    }

    private static func sourceApp(for finding: ScanFinding) -> String {
        let path = finding.path.lowercased()
        if path.contains("com.microsoft.vscode") || path.contains("/code/") || path.contains("/.vscode/") {
            return "VS Code"
        }
        if path.contains("jetbrains") {
            return "JetBrains"
        }
        if path.contains("com.docker.docker") || path.contains("/docker/") {
            return "Docker"
        }
        if path.contains("xcode") || path.contains("coresimulator") {
            return "Xcode"
        }
        if path.contains("com.apple.safari") || path.contains("/safari/") {
            return "Safari"
        }
        if path.contains("google/chrome") || path.contains("chromium") {
            return "Chrome"
        }
        if path.contains("firefox") {
            return "Firefox"
        }
        if path.contains("com.adobe") || path.contains("/adobe/") {
            return "Adobe"
        }
        if path.contains("com.figma") || path.contains("/figma/") {
            return "Figma"
        }
        if path.contains("com.blackmagicdesign") || path.contains("davinci resolve") {
            return "DaVinci Resolve"
        }
        if path.contains("finalcut") || path.contains("final cut pro") {
            return "Final Cut Pro"
        }
        if path.contains("homebrew") || path.contains("/npm/") || path.contains("node_modules") || path.contains("/.cargo/") || path.contains("/.gradle/") {
            return "Package Managers"
        }
        return "Other"
    }

    private static func groupBySourceApp(findings: [ScanFinding]) -> [(app: String, totalBytes: Int64, fileCount: Int)] {
        var grouped: [String: (bytes: Int64, count: Int)] = [:]
        for finding in findings {
            let app = sourceApp(for: finding)
            let current = grouped[app] ?? (0, 0)
            grouped[app] = (bytes: current.bytes + finding.sizeBytes, count: current.count + 1)
        }
        return grouped
            .map { app, value in (app: app, totalBytes: value.bytes, fileCount: value.count) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    private static func groupLargeFilesByCategory(findings: [ScanFinding]) -> [(category: ScanCategory, totalBytes: Int64, files: [ScanFinding])] {
        let largeFindings = findings.filter { ScanPolicy.isLargeFile($0.sizeBytes) }
        let grouped = Dictionary(grouping: largeFindings, by: \.category)

        return grouped
            .map { category, files in
                let sortedFiles = files.sorted { $0.sizeBytes > $1.sizeBytes }
                let totalBytes = sortedFiles.reduce(0) { $0 + $1.sizeBytes }
                return (category: category, totalBytes: totalBytes, files: sortedFiles)
            }
            .sorted { $0.totalBytes > $1.totalBytes }
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
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func riskTag(_ level: RiskLevel) -> String {
        switch level {
        case .safe:     return "[SAFE]"
        case .review:   return "[REVIEW]"
        case .advanced: return "[ADVANCED]"
        }
    }
}

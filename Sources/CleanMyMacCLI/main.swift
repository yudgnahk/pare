import Foundation
import App BCore

@main
struct App BCLI {
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
                print("- \(format(bytes: finding.sizeBytes)) | \(finding.category.rawValue) | \(finding.path)")
            }
        }

        let largeFileGroups = groupLargeFilesByCategory(findings: report.findings)
        if !largeFileGroups.isEmpty {
            print("")
            print("Large files by category (> \(format(bytes: ScanPolicy.largeFileThresholdBytes))):")

            for group in largeFileGroups {
                print("- \(group.category.rawValue): \(format(bytes: group.totalBytes)) (\(group.files.count) files)")

                for finding in group.files.prefix(top) {
                    print("  - \(format(bytes: finding.sizeBytes)) | \(finding.path)")
                }
            }
        }
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
}

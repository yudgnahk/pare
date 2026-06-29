import Foundation

/// Scans `~/Library/LaunchAgents/` for `.plist` files whose declared program binary
/// no longer exists on disk — left behind by apps that did not clean up on uninstall.
///
/// Skipped plists:
///   - Less than 30 days old (recently installed, binary may still be on its way)
///   - Program path contains `$` or starts with `~` (shell expansion required)
///   - No `Program` or `ProgramArguments` key present
public struct OrphanedLaunchAgentsRule: ScanRule {
    public let id = "orphaned-launch-agents"
    public let title = "Orphaned Launch Agents"
    public let reason = "Launch agent whose binary no longer exists on disk"
    public let category: ScanCategory = .launchAgents
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.85

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let agentsDir = environment.homeDirectory.appending(path: "Library/LaunchAgents")
        guard FileManager.default.fileExists(atPath: agentsDir.path) else { return [] }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        var findings: [ScanFinding] = []

        for plist in contents where plist.pathExtension.lowercased() == "plist" {
            let resourceValues = try? plist.resourceValues(forKeys: [
                .contentModificationDateKey, .creationDateKey, .fileSizeKey
            ])

            guard let effectiveDate = resourceValues.flatMap(ScanPolicy.effectiveAgeDate(from:)),
                  Date().timeIntervalSince(effectiveDate) >= thirtyDays else {
                continue
            }

            guard let programPath = extractProgramPath(from: plist) else { continue }

            // Skip paths that require shell expansion — can't resolve reliably
            guard !programPath.contains("$"), !programPath.hasPrefix("~") else { continue }

            guard !FileManager.default.fileExists(atPath: programPath) else { continue }

            let sizeBytes = Int64(resourceValues?.fileSize ?? 0)
            findings.append(ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: "Missing binary: \(programPath)",
                path: plist.path,
                sizeBytes: sizeBytes,
                lastUsed: effectiveDate,
                confidence: confidence
            ))
        }

        return findings.isEmpty ? nil : findings
    }

    // MARK: - Private

    private func extractProgramPath(from plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        if let program = obj["Program"] as? String, !program.isEmpty {
            return program
        }

        if let args = obj["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
            return first
        }

        return nil
    }
}

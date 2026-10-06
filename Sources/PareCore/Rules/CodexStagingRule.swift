import AppKit
import Foundation

/// Marketplace staging folders left behind by interrupted Codex installs and upgrades. One finding per
/// abandoned folder (rolled up to one row per root in the UI); nothing is reported while Codex or
/// ChatGPT runs. Every condition lives in `ScanPolicy.isReclaimableCodexStagingEntry`.
public struct CodexStagingRule: ScanRule {
    public let id = "codex-staging"
    public let title = "Codex Staging Leftovers"
    public let reason = "Abandoned Codex marketplace staging folder"
    public let category: ScanCategory = .aiToolCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.9

    private let isCodexRunning: @Sendable () async -> Bool

    public init(isCodexRunning: (@Sendable () async -> Bool)? = nil) {
        self.isCodexRunning = isCodexRunning ?? CodexActivity.system
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        guard !(await isCodexRunning()) else { return [] }
        let now = Date()
        var findings: [ScanFinding] = []
        for components in ScanPolicy.codexStagingRootComponents {
            let root = components.reduce(environment.homeDirectory) { $0.appending(path: $1) }
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            )) ?? []
            for entry in entries where ScanPolicy.isReclaimableCodexStagingEntry(entry, now: now) {
                findings.append(finding(for: entry, sizeIndex: environment.sizeIndex))
            }
        }
        return findings
    }

    /// Empty staging folders are still reported: they are leftovers even at 0 bytes.
    private func finding(for entry: URL, sizeIndex: DirectorySizeIndex) -> ScanFinding {
        let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let size = values?.isDirectory == true ? sizeIndex.directorySize(url: entry) : Int64(values?.fileSize ?? 0)
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(reason) — untouched for over 30 days",
            path: entry.path,
            sizeBytes: size,
            lastUsed: values?.contentModificationDate,
            confidence: confidence
        )
    }
}

/// Whether Codex or ChatGPT is running, from one process-name snapshot plus running app bundle ids.
public enum CodexActivity {
    static let bundleIdentifiers: Set<String> = ["com.openai.codex", "com.openai.chat"]
    /// Exact executable names, compared case-insensitively; substrings (e.g. third-party "CodexBar") never match.
    static let processNames: Set<String> = ["codex", "chatgpt"]

    /// Nil process output means the snapshot failed, which counts as running (fail closed).
    public static func isRunning(processNames output: String?, bundleIdentifiers running: [String]) -> Bool {
        guard let output else { return true }
        if running.contains(where: bundleIdentifiers.contains) { return true }
        return output.split(whereSeparator: \.isNewline).contains {
            processNames.contains($0.trimmingCharacters(in: .whitespaces).lowercased())
        }
    }

    public static let system: @Sendable () async -> Bool = {
        let processes = await ToolCommandRunner().capture(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axco", "comm="]
        )
        let bundles = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return isRunning(processNames: processes, bundleIdentifiers: bundles)
    }
}

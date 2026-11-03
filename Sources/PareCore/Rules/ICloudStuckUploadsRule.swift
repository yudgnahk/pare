import Foundation

/// iCloud Drive uploads stuck because iCloud storage is full, read from `brctl quota` and `brctl status`.
/// Explain-only: the pending bytes are not local space Pare can reclaim (the staged copy can be an APFS clone).
public struct ICloudStuckUploadsRule: ScanRule {
    public let id = "icloud-stuck-uploads"
    public let title = "iCloud Uploads Stuck"
    public let reason = "iCloud Drive cannot upload because iCloud storage is full"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.8

    /// `brctl status` is slow; uploads only stall on quota once the remaining space is nearly gone.
    public static let statusGateRemainingBytes: Int64 = 1_000_000_000
    /// Until the warning shows, files are silently not backed up, so three days is the most to wait.
    public static let minimumStuckHours: Double = 72
    public static let action = "iCloud storage is full: free some up, or turn off Desktop & Documents in iCloud Drive settings"
    static let brctlPath = "/usr/bin/brctl"
    static let quotaTimeoutSeconds: TimeInterval = 5
    static let statusTimeoutSeconds: TimeInterval = 45

    /// Returns `brctl <arguments>` output, or nil when it failed or timed out.
    public typealias Brctl = @Sendable ([String]) async -> String?

    private let brctl: Brctl

    public init(brctl: Brctl? = nil) {
        self.brctl = brctl ?? { arguments in
            let timeout = arguments == ["quota"] ? Self.quotaTimeoutSeconds : Self.statusTimeoutSeconds
            return await ToolCommandRunner(timeoutSeconds: timeout)
                .capture(executable: URL(fileURLWithPath: Self.brctlPath), arguments: arguments)
        }
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        guard let quota = await brctl(["quota"]),
              let remaining = ICloudUploadStatusParser.remainingQuotaBytes(fromQuotaOutput: quota),
              remaining < Self.statusGateRemainingBytes,
              !Task.isCancelled,
              let status = await brctl(["status"]),
              let backlog = ICloudUploadStatusParser.backlog(fromStatusOutput: status),
              backlog.itemCount > 0,
              backlog.oldestPendingHours >= Self.minimumStuckHours else { return [] }
        return [finding(for: backlog, home: environment.homeDirectory)]
    }

    private func finding(for backlog: ICloudUploadBacklog, home: URL) -> ScanFinding {
        let size = ByteCountFormatter.string(fromByteCount: backlog.totalBytes, countStyle: .file)
        let items = backlog.itemCount == 1 ? "1 item" : "\(backlog.itemCount) items"
        let days = Int(backlog.oldestPendingHours / 24)
        let folders = backlog.topLevelFolders
        let subject = "\(Self.joined(folders)) \(folders.count == 1 ? "isn't" : "aren't") backed up"
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(subject): iCloud hasn't uploaded \(size) (\(items)) for at least \(days) days — iCloud storage is full",
            path: home.appending(path: "Library/Application Support/CloudDocs").path,
            sizeBytes: 0,
            lastUsed: nil,
            confidence: confidence,
            annotations: [.explainOnly(action: Self.action)]
        )
    }

    private static func joined(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}

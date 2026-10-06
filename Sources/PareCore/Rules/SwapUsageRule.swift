import Foundation

/// Swap in use, from `sysctl vm.swapusage`. Explain-only: macOS frees swap itself once memory
/// pressure drops, and the swap files must never be deleted.
public struct SwapUsageRule: ScanRule {
    public let id = "swap-usage"
    public let title = "Swap In Use"
    public let reason = "Memory swapped to disk"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.9

    /// Below this, swap use is normal background behaviour and not worth a finding.
    public static let minimumReportedSwapBytes: Int64 = 1024 * 1024 * 1024
    /// Where macOS keeps swap files; root-owned, and diagnostics are blocked from cleanup anyway.
    public static let findingPath = "/private/var/vm"
    static let sysctlPath = "/usr/sbin/sysctl"

    /// Returns `sysctl vm.swapusage` output, or nil when it failed or timed out.
    public typealias Listing = @Sendable () async -> String?

    /// The real `sysctl vm.swapusage` reading, shared with other diagnostics.
    public static let systemListing: Listing = {
        await ToolCommandRunner().capture(
            executable: URL(fileURLWithPath: sysctlPath),
            arguments: ["vm.swapusage"]
        )
    }

    /// Swap currently in use, or nil when it could not be read.
    public static func currentUsedBytes() async -> Int64? {
        await systemListing().flatMap(usedBytes(fromSysctlOutput:))
    }

    private let listing: Listing

    public init(listing: Listing? = nil) {
        self.listing = listing ?? Self.systemListing
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        guard let output = await listing(),
              let used = Self.usedBytes(fromSysctlOutput: output),
              used > Self.minimumReportedSwapBytes else { return [] }
        let size = ByteCountFormatter.string(fromByteCount: used, countStyle: .memory)
        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(size) of swap in use — close memory-heavy apps or restart to release it",
            path: Self.findingPath,
            sizeBytes: used,
            lastUsed: nil,
            confidence: confidence,
            annotations: [.explainOnly(action: "Close memory-heavy apps or restart to release swap")]
        )]
    }

    /// Parses `used = 6794.44M` (units K, M, G, T in powers of 1024); nil when absent or malformed.
    static func usedBytes(fromSysctlOutput output: String) -> Int64? {
        guard let marker = output.range(of: "used = ") else { return nil }
        let token = output[marker.upperBound...].prefix { !$0.isWhitespace }
        guard let unit = token.last else { return nil }
        let multipliers: [Character: Double] = [
            "K": 1024,
            "M": 1024 * 1024,
            "G": 1024 * 1024 * 1024,
            "T": 1024 * 1024 * 1024 * 1024,
        ]
        guard let multiplier = multipliers[unit], let value = Double(token.dropLast()) else { return nil }
        return Int64(value * multiplier)
    }
}

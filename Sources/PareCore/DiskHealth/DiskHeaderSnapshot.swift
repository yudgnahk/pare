import Foundation

/// What sits behind the free-space number: purgeable space, swap in use and APFS local snapshots.
public struct DiskHeaderSnapshot: Sendable, Equatable {
    public let purgeableBytes: Int64?
    public let swapUsedBytes: Int64?
    public let localSnapshotCount: Int?

    /// Heavy swap on a nearly full disk: the system is short of both memory and room to page.
    public static let swapWarningBytes: Int64 = 4_000_000_000
    public static let lowFreeSpaceWarningBytes: Int64 = 10_000_000_000

    public init(purgeableBytes: Int64?, swapUsedBytes: Int64?, localSnapshotCount: Int?) {
        self.purgeableBytes = purgeableBytes
        self.swapUsedBytes = swapUsedBytes
        self.localSnapshotCount = localSnapshotCount
    }

    /// Space macOS reports as free "for important usage" beyond what is free right now; never negative.
    public static func purgeableBytes(importantUsage: Int64?, available: Int64?) -> Int64? {
        guard let importantUsage, let available else { return nil }
        return max(importantUsage - available, 0)
    }

    /// "Purgeable 3.2 GB · Swap 6.5 GB · 4 local snapshots", skipping unknown or zero parts.
    public var detailLine: String? {
        var parts: [String] = []
        if let purgeableBytes, purgeableBytes > 0 { parts.append("Purgeable \(Self.format(purgeableBytes))") }
        if let swapUsedBytes, swapUsedBytes > 0 { parts.append("Swap \(Self.format(swapUsedBytes))") }
        if let localSnapshotCount, localSnapshotCount > 0 {
            parts.append("\(localSnapshotCount) local snapshot\(localSnapshotCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public func warnsOfSwapPressure(freeBytes: Int64) -> Bool {
        guard let swapUsedBytes else { return false }
        return swapUsedBytes > Self.swapWarningBytes && freeBytes < Self.lowFreeSpaceWarningBytes
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Parses `sysctl vm.swapusage` (`total = 2048.00M  used = 1031.25M  free = 1016.75M  (encrypted)`).
public enum SwapUsageParser {
    private static let unitMultipliers: [Character: Double] = ["K": 1024, "M": 1024 * 1024, "G": 1024 * 1024 * 1024, "T": 1024 * 1024 * 1024 * 1024]

    public static func usedBytes(fromSysctlOutput output: String) -> Int64? {
        guard let range = output.range(of: #"used\s*=\s*[0-9]+([.,][0-9]+)?[A-Za-z]"#, options: .regularExpression) else {
            return nil
        }
        let field = output[range]
        guard let equals = field.firstIndex(of: "="), let unit = field.last,
              let multiplier = unitMultipliers[Character(unit.uppercased())] else { return nil }
        let number = field[field.index(after: equals)..<field.index(before: field.endIndex)]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")  // comma-decimal locales print `4908,88M`
        guard let value = Double(number) else { return nil }
        return Int64((value * multiplier).rounded())
    }
}

/// Counts snapshot names in `tmutil listlocalsnapshots <volume>` output; nil when the output is not a listing.
public enum LocalSnapshotParser {
    public static func count(fromTmutilOutput output: String) -> Int? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Headers include "Snapshots for disk /:" and "Snapshots for volume group containing disk /:";
        // names are single tokens, not only `com.apple.*` (backup tools add their own).
        let isHeader = { (line: String) in line.hasPrefix("Snapshots for ") || line.hasPrefix("No local snapshots") }
        let snapshots = lines.filter { !isHeader($0) && !$0.contains(" ") }
        let recognizedOtherwise = lines.allSatisfy { isHeader($0) || !$0.contains(" ") }
        return recognizedOtherwise ? snapshots.count : nil
    }
}
